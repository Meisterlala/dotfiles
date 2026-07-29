import { DEFAULT_TEXT_LIMIT, DEFAULT_TIMEOUT_MS, REVIEWER_AGENT, REVIEWER_PROMPT } from "./constants.js";
import { createReviewer } from "./reviewer.js";
import { createStateController } from "./state-controller.js";
import { commandText, matchesTool } from "./utils.js";

/** @type {import('@opencode-ai/plugin').Plugin} */
export async function SafetyWatch({ client, directory }, options = {}) {
  const dcgEnabled = options.dcg === true;
  const aiReviewEnabled = options["ai-review"] !== false;
  if (!dcgEnabled && !aiReviewEnabled) return {};

  const { checkDcg } = await import("../dcg-guard/index.js");
  let reviewerModel = typeof options.model === "string" ? options.model : undefined;
  let reviewerContextTokens;
  const timeoutMs = Number.isFinite(options.timeoutMs) ? options.timeoutMs : DEFAULT_TIMEOUT_MS;
  const textLimit = Number.isFinite(options.textLimit) ? options.textLimit : DEFAULT_TEXT_LIMIT;
  const guardedTools = Array.isArray(options.tools) ? options.tools : ["bash", "*.bash"];
  const state = createStateController({ client, directory, dcgEnabled, aiReviewEnabled });
  let reviewer;

  function getReviewer() {
    reviewer ??= createReviewer({
      client, directory, state, model: () => reviewerModel, contextTokens: () => reviewerContextTokens, timeoutMs,
    });
    return reviewer;
  }

  return {
    config: async (config) => {
      reviewerModel ??= config.small_model;
      const [providerID, modelID] = reviewerModel.split("/");
      const configuredContext = config.provider?.[providerID]?.models?.[modelID]?.limit?.context;
      if (Number.isFinite(configuredContext)) reviewerContextTokens = configuredContext;
      config.agent ??= {};
      config.agent[REVIEWER_AGENT] = {
        description: "Internal text-only classifier for Safety Watch.",
        mode: "subagent",
        model: reviewerModel,
        hidden: true,
        maxSteps: 1,
        tools: { "*": false },
        permission: { "*": "deny", edit: "deny", bash: "deny", webfetch: "deny", external_directory: "deny" },
        prompt: REVIEWER_PROMPT,
      };
    },

    event: async ({ event }) => {
      if (event?.type === "session.created") {
        await state.applyPendingSettings(event.properties.info.id);
        return;
      }
      if (event?.type === "session.idle" || (event?.type === "session.status" && event.properties.status.type === "idle")) {
        await getReviewer().cancelReview(event.properties.sessionID);
        return;
      }
      if (event?.type === "session.deleted") await getReviewer().handleDeleted(event.properties.sessionID);
    },

    "tool.execute.before": async (input, output) => {
      const reviews = getReviewer();
      if (reviews.isReviewer(input.sessionID)) return;
      reviews.clearIdleCompaction(input.sessionID);
      if (!matchesTool(input.tool, guardedTools)) return;
      const layers = await state.activeLayers(input.sessionID);
      if (layers.dcg) await checkDcg(output.args?.command, { required: true });
      if (!layers.aiReview) return;
      let decision;
      try {
        decision = await reviews.queueReview(input.sessionID, () => reviews.review(input.sessionID, commandText(input.tool, output.args, textLimit)));
      } catch (error) {
        throw new Error(`Safety Watch failed closed: ${error?.message ?? String(error)}`);
      }
      if (!decision.allow) {
        throw new Error(`Safety Watch blocked this tool call. It was not run. Reason: ${decision.reason.trim()} Revise the approach instead of retrying the same call.`);
      }
    },

    "tool.execute.after": async (input) => {
      const reviews = getReviewer();
      if (!reviews.isReviewer(input.sessionID)) reviews.scheduleIdleCompaction(input.sessionID);
    },
  };
}

export default SafetyWatch;
