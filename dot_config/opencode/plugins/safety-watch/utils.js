export function compact(value, limit) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  if (!text) return "";
  return text.length <= limit ? text : `${text.slice(0, limit)}... [truncated]`;
}

export function commandText(tool, args, limit) {
  return tool === "bash" && typeof args?.command === "string"
    ? compact(args.command, limit)
    : compact(args, limit);
}

export function unwrap(response, operation) {
  if (response?.error) throw new Error(`${operation} failed: ${compact(response.error, 500)}`);
  if (!response?.data) throw new Error(`${operation} returned no data`);
  return response.data;
}

export function parseDecision(text) {
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("reviewer returned no JSON decision");
  const decision = JSON.parse(match[0]);
  if (typeof decision.allow !== "boolean" || typeof decision.reason !== "string" || !decision.reason.trim()) {
    throw new Error("reviewer returned an invalid decision");
  }
  return decision;
}

export function matchesTool(toolName, patterns) {
  return patterns.some((pattern) => pattern === "*" ||
    (pattern.startsWith("*.") && toolName.endsWith(pattern.slice(1))) || toolName === pattern);
}
