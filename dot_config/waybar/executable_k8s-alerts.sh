#!/usr/bin/env bash
set -u

KUBECTL_TIMEOUT="${K8S_ALERTS_TIMEOUT:-8s}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
NAMESPACE_CACHE_FILE="$CACHE_DIR/alertmanager-namespace"
ICON_OK="󰄬"
ICON_ALERT=""
ICON_ERROR=""

json_escape() {
  jq -Rs . <<<"$1"
}

emit_json() {
  local text="$1"
  local tooltip="$2"
  local class_name="$3"
  local text_json tooltip_json

  text_json="$(json_escape "$text")"
  tooltip_json="$(json_escape "$tooltip")"
  printf '{"text":%s,"tooltip":%s,"class":"%s"}\n' "$text_json" "$tooltip_json" "$class_name"
}

error_out() {
  local message="$1"
  emit_json "$ICON_ERROR err" "$message" "error"
  exit 0
}

for cmd in kubectl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error_out "Missing dependency: $cmd"
  fi
done

if ! mkdir -p "$CACHE_DIR" 2>/dev/null; then
  CACHE_DIR="/tmp"
  NAMESPACE_CACHE_FILE="$CACHE_DIR/waybar-alertmanager-namespace-${UID:-0}"
fi

context="$(kubectl config current-context 2>/dev/null || true)"
if [[ -z "$context" ]]; then
  error_out "No current Kubernetes context configured."
fi

discover_namespace() {
  kubectl --request-timeout="$KUBECTL_TIMEOUT" get svc -A -o json 2>/dev/null \
    | jq -r '[.items[] | select(.metadata.name == "alertmanager-operated") | .metadata.namespace][0] // empty'
}

get_namespace() {
  local ns="${ALERTMANAGER_NAMESPACE:-}"
  if [[ -n "$ns" ]]; then
    printf '%s\n' "$ns"
    return 0
  fi

  if [[ -r "$NAMESPACE_CACHE_FILE" ]]; then
    ns="$(<"$NAMESPACE_CACHE_FILE")"
    if [[ -n "$ns" ]]; then
      printf '%s\n' "$ns"
      return 0
    fi
  fi

  ns="$(discover_namespace)"
  if [[ -n "$ns" ]]; then
    printf '%s\n' "$ns" >"$NAMESPACE_CACHE_FILE" 2>/dev/null || true
    printf '%s\n' "$ns"
    return 0
  fi

  return 1
}

fetch_alerts() {
  local ns="$1"
  kubectl --request-timeout="$KUBECTL_TIMEOUT" get --raw "/api/v1/namespaces/${ns}/services/http:alertmanager-operated:9093/proxy/api/v2/alerts" 2>/dev/null
}

namespace="$(get_namespace || true)"
if [[ -z "$namespace" ]]; then
  error_out "Cannot find Alertmanager service (alertmanager-operated)."
fi

alerts_json="$(fetch_alerts "$namespace" || true)"
if [[ -z "$alerts_json" ]]; then
  refreshed_namespace="$(discover_namespace || true)"
  if [[ -n "$refreshed_namespace" && "$refreshed_namespace" != "$namespace" ]]; then
    namespace="$refreshed_namespace"
    printf '%s\n' "$namespace" >"$NAMESPACE_CACHE_FILE" 2>/dev/null || true
    alerts_json="$(fetch_alerts "$namespace" || true)"
  fi
fi

if [[ -z "$alerts_json" ]]; then
  error_out "Cannot connect to cluster or Alertmanager API (context: $context)."
fi

if ! jq -e . >/dev/null 2>&1 <<<"$alerts_json"; then
  error_out "Invalid JSON returned by Alertmanager API."
fi

read -r active_count watchdog_running <<<"$(jq -r '
  [.[] | select(.status.state == "active")] as $active
  | ($active | map(select((.labels.alertname // "") != "Watchdog" and (.labels.alertname // "") != "InfoInhibitor")) | length) as $visible
  | ($active | map(select((.labels.alertname // "") == "Watchdog")) | length > 0) as $watchdog
  | "\($visible) \($watchdog)"
' <<<"$alerts_json")"

tooltip_lines="$(jq -r '
  [.[]
   | select(.status.state == "active" and (.labels.alertname // "") != "Watchdog" and (.labels.alertname // "") != "InfoInhibitor")
   | {
       sev: (.labels.severity // "unknown"),
       name: (.labels.alertname // "unknown"),
       ns: (.labels.namespace // "-"),
       msg: ((.annotations.summary // .annotations.description // .annotations.message // "") | gsub("\\n"; " "))
     }
  ]
  | sort_by(.sev, .name, .ns)
  | if length == 0 then
      "No active alerts"
    else
      .[] | "- [\(.sev)] \(.name) (\(.ns))\(if .msg == "" then "" else ": \(.msg)" end)"
    end
' <<<"$alerts_json")"

timestamp="$(date +"%H:%M")"
base_tooltip="context: $context\nnamespace: $namespace\nupdated: $timestamp"

if [[ "$watchdog_running" != "true" ]]; then
  emit_json "$ICON_ERROR wd" "Watchdog alert is missing.\n$base_tooltip\n\n$tooltip_lines" "error"
  exit 0
fi

if [[ "$active_count" -gt 0 ]]; then
  emit_json "$ICON_ALERT $active_count" "$base_tooltip\n\n$tooltip_lines" "warning"
  exit 0
fi

emit_json "$ICON_OK 0" "$base_tooltip\n\n$tooltip_lines" "ok"
