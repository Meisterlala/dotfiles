const FILE_NAME = "safety-watch.json"

export function statePath(directory) {
  return `${directory}/${FILE_NAME}`
}

export async function readState(path) {
  try {
    const value = await Bun.file(path).json()
    return {
      sessions: value.sessions && typeof value.sessions === "object" ? value.sessions : {},
      pending: value.pending && typeof value.pending === "object" ? value.pending : {},
    }
  } catch (error) {
    if (error?.code === "ENOENT") return { sessions: {}, pending: {} }
    throw error
  }
}

export async function writeState(path, value) {
  await Bun.write(path, JSON.stringify(value))
}

export function layerEnabled(state, sessionID, layer, fallback) {
  const session = state.sessions[sessionID] ?? state.pending
  return typeof session?.[layer] === "boolean" ? session[layer] : fallback
}
