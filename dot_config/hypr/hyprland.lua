-- Hyprland Lua config converted from hyprland.conf.
-- Docs referenced while converting:
-- https://wiki.hypr.land/Configuring/Start/
-- https://wiki.hypr.land/Configuring/Basics/Monitors/
-- https://wiki.hypr.land/Configuring/Basics/Variables/
-- https://wiki.hypr.land/Configuring/Basics/Binds/
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

local terminal = "ghostty +new-window || kitty || alacritty"
local file_manager = "nautilus || dolphin || thunar"
local menu = "rofi -show combi"
local browser = "zen-browser || firefox || chromium"
local main_mod = "SUPER"

-- Keep window rule effects out of Lua LSP's stricter generated stubs; the wiki
-- documents these fields but the current stubs only type the match/name shell.
local function window_rule(spec)
	hl.window_rule(spec)
end

----------------
-- Monitors
----------------

hl.monitor({
	output = "desc:AOC CQ27G2S 1EKQ5JA001846",
	mode = "2560x1440@165.00",
	position = "0x0",
	scale = "1",
})

hl.monitor({
	output = "desc:Acer Technologies ED270U P TKYEE0013W01",
	mode = "2560x1440@165.00",
	position = "auto-right",
	scale = "1",
})

hl.config({
	quirks = {
		prefer_hdr = 2,
	},
})

----------------
-- Autostart
----------------

hl.on("hyprland.start", function()
	hl.exec_cmd("systemctl --user start hyprland-session.target")
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
	hl.exec_cmd("udiskie --smart-tray")
	hl.exec_cmd(
		"dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_MENU_PREFIX XDG_DATA_DIRS"
	)
	hl.exec_cmd([[hyprctl plugin load "$HYPR_PLUGIN_DIR/lib/libhyprexpo.so"]])
	hl.exec_cmd("systemctl --user start hypridle.service")
	hl.exec_cmd("systemctl --user start waybar.service")
	hl.exec_cmd("systemctl --user start hyprsunset.service")
	hl.exec_cmd(terminal)
end)

----------------
-- Environment
----------------

hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XDG_MENU_PREFIX", "plasma-")
hl.env(
	"XDG_DATA_DIRS",
	"/home/misti/.local/share-hyprland:/home/misti/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
)
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_QPA_PLATFORM", "xcb;wayland")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")

----------------
-- Permissions
----------------

hl.config({
	ecosystem = {
		enforce_permissions = false,
		no_donation_nag = true,
	},
})

hl.permission({ binary = "/usr/(bin|local/bin)/grim", type = "screencopy", mode = "allow" })
hl.permission({
	binary = "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland",
	type = "screencopy",
	mode = "allow",
})

----------------
-- Look And Feel
----------------

hl.layer_rule({ match = { namespace = "waybar" }, blur = true })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, no_screen_share = true })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, no_screen_share = true })
window_rule({ match = { class = "^(swaync)$" }, no_initial_focus = true })

hl.config({
	general = {
		gaps_in = 6,
		gaps_out = 6,
		border_size = 2,
		col = {
			active_border = { colors = { "rgba(b4befeee)", "rgba(cba6f7ee)" }, angle = 45 },
		},
		resize_on_border = false,
		allow_tearing = false,
		layout = "dwindle",
	},
	decoration = {
		rounding = 8,
		rounding_power = 3,
		active_opacity = 1.0,
		inactive_opacity = 0.85,
		shadow = {
			enabled = false,
			range = 4,
			render_power = 2,
			color = "rgba(1a1a1aee)",
		},
		blur = {
			enabled = true,
			size = 5,
			passes = 3,
			special = true,
			vibrancy = 0.1696,
		},
	},
	animations = {
		enabled = true,
	},
	dwindle = {
		preserve_split = true,
	},
	master = {
		new_status = "master",
	},
	misc = {
		force_default_wallpaper = -1,
		disable_hyprland_logo = false,
		middle_click_paste = false,
		mouse_move_enables_dpms = false,
		key_press_enables_dpms = true,
	},
	cursor = {
		warp_on_change_workspace = 1,
		inactive_timeout = 10,
		default_monitor = "DP-3",
	},
	debug = {
		full_cm_proto = true,
	},
	render = {
		direct_scanout = 1,
	},
	input = {
		kb_layout = "de",
		kb_variant = "nodeadkeys",
		kb_model = "",
		kb_options = "fkeys:basic_13-24",
		kb_rules = "",
		follow_mouse = 1,
		sensitivity = 0,
		accel_profile = "flat",
		touchpad = {
			natural_scroll = false,
		},
	},
	binds = {
		hide_special_on_workspace_change = false,
	},
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

----------------
-- Workspaces
----------------

for i = 1, 8 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "DP-3", default = i == 1, persistent = true })
end

for i = 11, 18 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "DP-2", default = i == 11, persistent = true })
end

----------------
-- Keybindings
----------------

hl.bind(main_mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(main_mod .. " + W", hl.dsp.window.close())
hl.bind(main_mod .. " + SHIFT + W", hl.dsp.window.kill())
hl.bind(main_mod .. " + E", hl.dsp.exec_cmd(file_manager))
hl.bind(main_mod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(main_mod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(main_mod .. " + G", hl.dsp.exec_cmd(browser))
hl.bind(main_mod .. " + ALT + T", hl.dsp.exec_cmd("~/.config/hypr/thunderbird-toggle.sh"))
hl.bind(main_mod .. " + P", hl.dsp.exec_cmd("$HOME/.cargo/bin/wp next"))
hl.bind(main_mod .. " + SHIFT + M", hl.dsp.exec_cmd("uwsm stop"))
hl.bind(main_mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main_mod .. " + SHIFT + V", hl.dsp.window.pseudo())

hl.bind(main_mod .. " + left", hl.dsp.window.cycle_next({ next = false }))
hl.bind(main_mod .. " + right", hl.dsp.window.cycle_next({}))
hl.bind(main_mod .. " + up", hl.dsp.window.cycle_next({ next = false }))
hl.bind(main_mod .. " + down", hl.dsp.window.cycle_next({}))

local key_to_workspace = {
	{ "1", 1 },
	{ "2", 2 },
	{ "3", 3 },
	{ "4", 4 },
	{ "5", 5 },
	{ "6", 11 },
	{ "7", 12 },
	{ "8", 13 },
	{ "9", 14 },
	{ "0", 15 },
}

for _, bind in ipairs(key_to_workspace) do
	local key, workspace = bind[1], bind[2]
	hl.bind(main_mod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
	hl.bind(main_mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

hl.bind(main_mod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(main_mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(main_mod .. " + mouse_down", hl.dsp.window.cycle_next({}))
hl.bind(main_mod .. " + mouse_up", hl.dsp.window.cycle_next({ next = false }))
hl.bind(main_mod .. " + f", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(main_mod .. " + ALT + f", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

---@type any
local mouse_bind = { mouse = true }
hl.bind(main_mod .. " + mouse:272", hl.dsp.window.drag(), mouse_bind)
hl.bind(main_mod .. " + mouse:273", hl.dsp.window.resize(), mouse_bind)

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind("Print", hl.dsp.exec_cmd("bash ~/.config/hypr/screenshot.sh"))
hl.bind(main_mod .. " + x", hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind("F14", hl.dsp.pass({ window = "class:vesktop" }))
hl.bind("F14", hl.dsp.pass({ window = "class:discord" }))
hl.bind("F18", hl.dsp.exec_cmd("/usr/bin/python3 ~/source/MySuperWhisper/remote_control.py --start"))
hl.bind("F18", hl.dsp.exec_cmd("/usr/bin/python3 ~/source/MySuperWhisper/remote_control.py --stop"), { release = true })

----------------
-- Windows And Workspaces
----------------

hl.workspace_rule({ workspace = "w[tv1]s[false]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]s[false]", gaps_out = 0, gaps_in = 0 })
window_rule({ match = { workspace = "w[tv1]s[false]", float = false }, border_size = 0 })
window_rule({ match = { workspace = "w[tv1]s[false]", float = false }, rounding = 0 })
window_rule({ match = { workspace = "f[1]s[false]", float = false }, border_size = 0 })
window_rule({ match = { workspace = "f[1]s[false]", float = false }, rounding = 0 })

hl.workspace_rule({ workspace = "special:magic", gaps_out = 32, no_shadow = true, on_created_empty = terminal })
window_rule({ match = { workspace = "special:magic", float = false }, rounding = 12 })
window_rule({ match = { class = "scrcpy" }, workspace = "special:magic silent" })
window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
window_rule({
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- Converted from windowrules.conf, which was sourced by hyprland.conf.
window_rule({ match = { title = ".*- YouTube.*" }, opaque = true })
window_rule({ match = { title = ".*- Twitch.*" }, opaque = true })
window_rule({ match = { class = ".*cord" }, opaque = true })
window_rule({ match = { title = ".*HiAnime\\.to.*" }, opaque = true })
window_rule({ match = { title = ".*n\\.eko.*" }, opaque = true })
window_rule({ match = { title = ".*Watch2Gether.*" }, opaque = true })
window_rule({ match = { class = "jellyfin-desktop" }, opaque = true })
window_rule({ match = { class = "cafe\\.avery\\.Delfin" }, opaque = true })
window_rule({ match = { class = "Jellyfin Media Player" }, opaque = true })
window_rule({ match = { class = "affinity.exe" }, opaque = true })
window_rule({ match = { class = "darktable" }, opaque = true })
window_rule({ match = { class = "jellyfin-desktop" }, idle_inhibit = "focus" })
window_rule({ match = { class = "cafe\\.avery\\.Delfin" }, idle_inhibit = "focus" })
window_rule({ match = { class = "Jellyfin Media Player" }, idle_inhibit = "focus" })
window_rule({ match = { fullscreen = true }, idle_inhibit = "focus" })
window_rule({ match = { class = "(firefox|zen|chromium)" }, focus_on_activate = true })
window_rule({ match = { class = "(Element)" }, focus_on_activate = true })
window_rule({ match = { class = "(discord|vesktop)" }, workspace = "11 silent" })
window_rule({ match = { class = "(discord|vesktop)" }, no_screen_share = true })
window_rule({ match = { class = "com.gabm.satty" }, float = true })
window_rule({ match = { class = "Emulator" }, float = true })
