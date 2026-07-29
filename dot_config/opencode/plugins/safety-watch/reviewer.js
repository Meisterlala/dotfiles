import {
  DEFAULT_TIMEOUT_MS,
  IMMEDIATE_COMPACTION_RATIO,
  LONG_IDLE_COMPACTION_RATIO,
  LONG_IDLE_MS,
  RESPONSE_SHAPE,
  REVIEWER_AGENT,
  REVIEWER_PROMPT,
  SHORT_IDLE_COMPACTION_RATIO,
  SHORT_IDLE_MS,
} from "./constants.js";
import { parseDecision, unwrap } from "./utils.js";

export function createReviewer({
  client,
  directory,
  state,
  model,
  contextTokens,
  timeoutMs = DEFAULT_TIMEOUT_MS,
}) {
  const sessions = new Map();
  const owners = new Map();
  const queues = new Map();
  const generations = new Map();
  const compactions = new Map();
  const usage = new Map();
  const timers = new Map();

  function clearIdleCompaction(sessionID) {
    const pending = timers.get(sessionID);
    if (!pending) return;
    clearTimeout(pending.short);
    clearTimeout(pending.long);
    timers.delete(sessionID);
  }

  function scheduleCompaction(sessionID, threshold) {
    const current = usage.get(sessionID);
    const limit = contextTokens();
    if (
      !current ||
      !Number.isFinite(limit) ||
      current.inputTokens < limit * threshold ||
      compactions.has(sessionID)
    )
      return;
    clearIdleCompaction(sessionID);
    const compacting = client.session
      .summarize({
        path: { id: current.reviewerID },
        query: { directory },
        body: { ...current.model, auto: true },
      })
      .catch(() => {})
      .finally(() => {
        compactions.delete(sessionID);
        usage.delete(sessionID);
        clearIdleCompaction(sessionID);
      });
    compactions.set(sessionID, compacting);
  }

  function scheduleIdleCompaction(sessionID) {
    clearIdleCompaction(sessionID);
    timers.set(sessionID, {
      short: setTimeout(
        () => scheduleCompaction(sessionID, SHORT_IDLE_COMPACTION_RATIO),
        SHORT_IDLE_MS,
      ),
      long: setTimeout(
        () => scheduleCompaction(sessionID, LONG_IDLE_COMPACTION_RATIO),
        LONG_IDLE_MS,
      ),
    });
  }

  async function reviewerSession(parentID) {
    const existing = sessions.get(parentID);
    if (existing) return existing;
    const persisted = await state.reviewerID(parentID);
    if (typeof persisted === "string") {
      const response = await client.session.get({
        path: { id: persisted },
        query: { directory },
      });
      if (response?.data) {
        sessions.set(parentID, persisted);
        owners.set(persisted, parentID);
        return persisted;
      }
      await state.saveReviewer(parentID);
    }
    const created = unwrap(
      await client.session.create({
        body: { parentID, title: "[internal] Safety Watch reviewer" },
        query: { directory },
      }),
      "creating reviewer session",
    );
    sessions.set(parentID, created.id);
    owners.set(created.id, parentID);
    await state.saveReviewer(parentID, created.id);
    return created.id;
  }

  async function queueReview(sessionID, task) {
    const generation = generations.get(sessionID) ?? 0;
    const previous = queues.get(sessionID) ?? Promise.resolve();
    let release;
    const current = new Promise((resolve) => {
      release = resolve;
    });
    queues.set(sessionID, current);
    await previous;
    await compactions.get(sessionID);
    if ((generations.get(sessionID) ?? 0) !== generation)
      throw new Error("Safety Watch review was canceled");
    await state.setReviewing(sessionID, true).catch(() => {});
    try {
      return await task();
    } finally {
      release();
      if (queues.get(sessionID) === current) {
        queues.delete(sessionID);
        await state.setReviewing(sessionID, false).catch(() => {});
      }
    }
  }

  async function review(sessionID, args) {
    const reviewerID = await reviewerSession(sessionID);
    const toolIDs = unwrap(
      await client.tool.ids({ query: { directory } }),
      "listing reviewer tools",
    );
    const tools = Object.fromEntries(toolIDs.map((id) => [id, false]));
    const selectedModel = model();
    const reviewerModel = selectedModel
      ? {
          providerID: selectedModel.split("/")[0],
          modelID: selectedModel.split("/").slice(1).join("/"),
        }
      : undefined;
    const deadline = Date.now() + timeoutMs;
    async function prompt(text) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) return;
      let timeout;
      return Promise.race([
        client.session.prompt({
          path: { id: reviewerID },
          query: { directory },
          body: {
            agent: REVIEWER_AGENT,
            model: reviewerModel,
            tools,
            system: REVIEWER_PROMPT,
            parts: [{ type: "text", text }],
          },
        }),
        new Promise((resolve) => {
          timeout = setTimeout(() => resolve(), remaining);
        }),
      ]).finally(() => clearTimeout(timeout));
    }
    async function decide(text, schedule = true) {
      const response = await prompt(text);
      if (!response) {
        await client.session
          .abort({ path: { id: reviewerID }, query: { directory } })
          .catch(() => {});
        return;
      }
      const message = unwrap(response, "reviewing tool call");
      const decision = parseDecision(
        message.parts
          .filter((part) => part.type === "text")
          .map((part) => part.text)
          .join("\n"),
      );
      if (schedule) {
        usage.set(sessionID, {
          reviewerID,
          model: reviewerModel,
          inputTokens: message.info?.tokens?.input ?? 0,
        });
        scheduleCompaction(sessionID, IMMEDIATE_COMPACTION_RATIO);
        if (!compactions.has(sessionID)) scheduleIdleCompaction(sessionID);
      }
      return decision;
    }
    try {
      const decision = await decide(
        `# Determine if this is safe to run:\n${args}`,
      );
      if (decision) return decision;
    } catch {
      const decision = await decide(
        `Answer with this shape only and no other text:\n${RESPONSE_SHAPE}`,
        false,
      );
      if (decision) return decision;
    }
    return { allow: true, reason: "AI review timed out; allowed by fallback." };
  }

  async function cancelReview(sessionID) {
    if (!queues.has(sessionID)) return;
    clearIdleCompaction(sessionID);
    usage.delete(sessionID);
    generations.set(sessionID, (generations.get(sessionID) ?? 0) + 1);
    queues.delete(sessionID);
    await state.setReviewing(sessionID, false).catch(() => {});
    const reviewerID = sessions.get(sessionID);
    if (reviewerID)
      await client.session
        .abort({ path: { id: reviewerID }, query: { directory } })
        .catch(() => {});
  }

  async function handleDeleted(sessionID) {
    const parentID = owners.get(sessionID);
    if (parentID) {
      owners.delete(sessionID);
      sessions.delete(parentID);
      await state.saveReviewer(parentID).catch(() => {});
      return;
    }
    const reviewerID = sessions.get(sessionID);
    if (!reviewerID) return;
    sessions.delete(sessionID);
    queues.delete(sessionID);
    clearIdleCompaction(sessionID);
    usage.delete(sessionID);
    await state.setReviewing(sessionID, false).catch(() => {});
    owners.delete(reviewerID);
    await state.saveReviewer(sessionID).catch(() => {});
    await client.session
      .abort({ path: { id: reviewerID }, query: { directory } })
      .catch(() => {});
    await client.session
      .delete({ path: { id: reviewerID }, query: { directory } })
      .catch(() => {});
  }

  return {
    isReviewer: (sessionID) => owners.has(sessionID),
    clearIdleCompaction,
    scheduleIdleCompaction,
    queueReview,
    review,
    cancelReview,
    handleDeleted,
  };
}
