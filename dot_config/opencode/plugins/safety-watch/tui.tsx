/** @jsxImportSource @opentui/solid */
import { createSignal } from "solid-js"
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"
import { layerEnabled, readState, statePath, writeState } from "./state.js"

type Status = { dcg: boolean; aiReview: boolean; showStatus: boolean }

const tui: TuiPlugin = async (api, options) => {
  const defaultShowStatus = options?.["show-status"] !== false
  const [defaults, setDefaults] = createSignal<Status>({ dcg: false, aiReview: false, showStatus: defaultShowStatus })
  const [status, setStatus] = createSignal<Status>(defaults())
  const [reviewing, setReviewing] = createSignal(false)
  const [spinner, setSpinner] = createSignal("⠋")
  const sessionID = () => api.route.current.name === "session" ? api.route.current.params.sessionID : undefined
  const file = () => statePath(api.state.path.state)

  async function loadDefaults() {
    const response = await api.client.config.get()
    const config = response.data ?? {}
    const entry = config.plugin?.find((item) =>
      Array.isArray(item) && String(item[0]).includes("plugins/safety-watch/index.js"),
    )
    const options = Array.isArray(entry) && entry[1] && typeof entry[1] === "object" ? entry[1] : {}
    setDefaults({
      dcg: options.dcg === true,
      aiReview: options["ai-review"] !== false,
      showStatus: defaultShowStatus,
    })
  }

  async function refresh() {
    const state = await readState(file())
    const id = sessionID()
    const key = id ?? ""
    const configured = defaults()
    const next = {
      dcg: layerEnabled(state, key, "dcg", configured.dcg),
      aiReview: layerEnabled(state, key, "aiReview", configured.aiReview),
      showStatus: layerEnabled(state, key, "showStatus", configured.showStatus),
    }
    setStatus((current) =>
      current.dcg === next.dcg &&
      current.aiReview === next.aiReview &&
      current.showStatus === next.showStatus
        ? current
        : next,
    )
    setReviewing(state.reviewing[key] === true)
  }

  async function toggle(layer: "dcg" | "aiReview" | "showStatus") {
    const id = sessionID()
    const state = await readState(file())
    const configured = defaults()
    const fallback = layer === "dcg"
      ? configured.dcg
      : layer === "aiReview"
        ? configured.aiReview
        : configured.showStatus
    const active = layerEnabled(state, id ?? "", layer, fallback)
    const target = id
      ? (state.sessions[id] ??= {})
      : state.pending
    target[layer] = !active
    await writeState(file(), state)
    await refresh()
    api.ui.toast({
      variant: !active ? "success" : "warning",
      title: "Safety Watch",
      message: `${layer === "dcg" ? "DCG" : layer === "aiReview" ? "AI review" : "Show status"} is ${!active ? "ON" : "OFF"}${id ? " for this session" : " for the next session"}.`,
    })
  }

  function openMenu() {
    const DialogSelect = api.ui.DialogSelect
    const value = status()
    api.ui.dialog.setSize("medium")
    api.ui.dialog.replace(() => (
      <DialogSelect
        title="Configure Automatic Tool-Call Review"
        skipFilter
        flat
        options={[
          {
            title: `DCG: ${value.dcg ? "ON" : "OFF"}`,
            value: "dcg",
            description: "A deterministic tool review",
          },
          {
            title: `AI review: ${value.aiReview ? "ON" : "OFF"}`,
            value: "aiReview",
            description: "Sends the tool call to a different model for review",
          },
          {
            title: `Show status: ${value.showStatus ? "ON" : "OFF"}`,
            value: "showStatus",
            description: "Show the current Safety Watch status",
          },
        ]}
        onSelect={(item) => {
          void toggle(item.value).then(openMenu)
        }}
      />
    ))
  }

  api.command.register(() => [{
    title: "Configure Automatic Tool-Call Review",
    value: "safety-watch.menu",
    description: "Configure automatic tool-call review",
    category: "Safety Watch",
    slash: { name: "safety-watch" },
    onSelect: openMenu,
  }])

  api.slots.register({
    slots: {
      home_prompt_right() {
        const value = status()
        if (!value.showStatus) return null
        const active = [value.dcg ? "DCG" : undefined, value.aiReview ? "AI" : undefined]
          .filter(Boolean)
          .join("+")
        return <text fg={active === "DCG+AI" ? "#7fd88f" : active ? "#f5c542" : "#f26d6d"}>{reviewing() ? `${spinner()} ` : ""}{active || "Safety OFF"}</text>
      },
      session_prompt_right() {
        const value = status()
        if (!value.showStatus) return null
        const active = [value.dcg ? "DCG" : undefined, value.aiReview ? "AI" : undefined]
          .filter(Boolean)
          .join("+")
        return <text fg={active === "DCG+AI" ? "#7fd88f" : active ? "#f5c542" : "#f26d6d"}>{reviewing() ? `${spinner()} ` : ""}{active || "Safety OFF"}</text>
      },
    },
  })

  await loadDefaults()
  await refresh()
  const refreshTimer = setInterval(() => void refresh().catch(() => {}), 200)
  const spinnerTimer = setInterval(() => {
    if (!reviewing()) return
    const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    setSpinner((current) => frames[(frames.indexOf(current) + 1) % frames.length])
  }, 120)
  api.lifecycle.onDispose(() => {
    clearInterval(refreshTimer)
    clearInterval(spinnerTimer)
  })
}

const plugin: TuiPluginModule & { id: string } = { id: "safety-watch", tui }

export default plugin
