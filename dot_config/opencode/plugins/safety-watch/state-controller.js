import { layerEnabled, readState, statePath, writeState } from "./state.js";
import { unwrap } from "./utils.js";

export function createStateController({
  client,
  directory,
  dcgEnabled,
  aiReviewEnabled,
}) {
  let path;

  async function getPath() {
    if (!path) {
      const paths = unwrap(
        await client.path.get({ query: { directory } }),
        "resolving Safety Watch state path",
      );
      path = statePath(paths.state);
    }
    return path;
  }

  async function load() {
    return readState(await getPath());
  }

  return {
    async activeLayers(sessionID) {
      const state = await load();
      return {
        dcg: layerEnabled(state, sessionID, "dcg", dcgEnabled),
        aiReview: layerEnabled(state, sessionID, "aiReview", aiReviewEnabled),
      };
    },
    async applyPendingSettings(sessionID) {
      const state = await load();
      if (
        !Object.values(state.pending).some(
          (value) => typeof value === "boolean",
        )
      )
        return;
      state.sessions[sessionID] = {
        ...state.pending,
        ...state.sessions[sessionID],
      };
      state.pending = {};
      await writeState(await getPath(), state);
    },
    async setReviewing(sessionID, reviewing) {
      const state = await load();
      state.reviewing[sessionID] = reviewing;
      await writeState(await getPath(), state);
    },
    async reviewerID(parentID) {
      return (await load()).reviewers[parentID];
    },
    async saveReviewer(parentID, reviewerID) {
      const state = await load();
      if (reviewerID) state.reviewers[parentID] = reviewerID;
      else delete state.reviewers[parentID];
      await writeState(await getPath(), state);
    },
  };
}
