-- Custom Hyprland configuration.
--
-- Stowed from dot/arch/.config/omarchy/custom-hyprland.lua into ~/.config/omarchy/, so
-- it is version-controlled AND omarchy template refreshes never touch it. The
-- post-update hook re-adds the require line if a future update strips it.
--
-- Required LAST from ~/.config/hypr/hyprland.lua -- after default/hypr/* and after
-- ~/.config/hypr/bindings.lua -- which is why this file can override anything.
--
-- Two API facts this file depends on:
--   * hl.bind() APPENDS, it does not replace. Re-binding an occupied chord makes BOTH
--     dispatchers fire. Always hl.unbind() first.
--   * hl.unbind() on an unbound chord is a silent no-op, so it is safe to call blindly.

-- ---------------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------------

-- US and Russian keyboard layouts, switch with Caps Lock; natural scroll on touchpad.
hl.config({
  input = {
    kb_layout = "us,ru",
    kb_options = "grp:caps_toggle",
    touchpad = {
      natural_scroll = true,
    },
  },
})

-- ---------------------------------------------------------------------------------
-- Letter workspaces -- one muscle memory with AeroSpace on macOS
-- ---------------------------------------------------------------------------------
-- The mirrored layer is on ALT, not SUPER. One external keyboard now serves both
-- machines, and it sends the same LeftAlt keycode to each, so AeroSpace's `alt-t` and
-- this `ALT+T` are the same physical key -- not merely the same position on two
-- different boards, which is what the SUPER version relied on. Named workspaces keep
-- the letter as the workspace's real identity, so there is no letter->digit table to
-- drift out of sync with mac/.config/aerospace/aerospace.toml.
--
-- ALT+<letter> was free: nothing in omarchy binds a bare ALT letter chord. So unlike
-- the SUPER version this layer displaces nothing, and the workarounds that existed
-- only to rehouse displaced SUPER verbs are gone -- SUPER+C/F/G/O/P/S/T and the
-- SUPER+SHIFT+<letter> launchers are omarchy's again.
--
-- Named workspaces get negative ids, so they are a disjoint set from SUPER+1..0. Those
-- stay bound to numeric workspaces and cannot collide with this layer.
--
-- No workspace_rule persistence on purpose: a letter workspace is created by its chord
-- and evaporates when the last window leaves, which is how AeroSpace behaves too.

-- Keep this list in step with [workspace-to-monitor-force-assignment], the alt-<letter>
-- bindings and the [[on-window-detected]] rules in mac/.config/aerospace/aerospace.toml.
local WORKSPACES = {
  { letter = "E", note = "scratch / main empty" },
  { letter = "T", note = "Telegram", classes = { [[^(org\.telegram\.desktop)$]] } },
  { letter = "F", note = "Firefox", classes = { [[^([fF]irefox)$]] } },
  { letter = "G", note = "terminals", classes = { [[^(com\.mitchellh\.ghostty)$]], [[^(Alacritty)$]] } },
  { letter = "Z", note = "Zed", classes = { [[^(dev\.zed\.Zed)$]] } },
  { letter = "C", note = "Chrome (work)", classes = { [[^([gG]oogle-chrome)$]] } },
  { letter = "S", note = "Slack", classes = { [[^([sS]lack)$]] } },
  { letter = "I", note = "IntelliJ IDEA", classes = { [[^(jetbrains-idea)$]] } },
  { letter = "O", note = "CLion", classes = { [[^(jetbrains-clion)$]] } },
  { letter = "P", note = "PyCharm", classes = { [[^(jetbrains-pycharm)$]] } },
  { letter = "B", note = "empty built-in display" },
}

for _, ws in ipairs(WORKSPACES) do
  local letter = ws.letter
  local name = "name:" .. letter

  -- Nothing binds these today, so both calls are no-ops. Kept because hl.bind appends:
  -- if omarchy ever ships an ALT letter chord, binding over it would double-fire.
  hl.unbind("ALT + " .. letter)
  hl.unbind("ALT + SHIFT + " .. letter)

  o.bind("ALT + " .. letter, "Workspace " .. letter .. " -- " .. ws.note,
    hl.dsp.focus({ workspace = name }))
  o.bind("ALT + SHIFT + " .. letter, "Move window to workspace " .. letter,
    hl.dsp.window.move({ workspace = name }))

  for _, class in ipairs(ws.classes or {}) do
    o.window(class, { workspace = name })
  end
end

-- ---------------------------------------------------------------------------------
-- The rest of the mirrored layer
-- ---------------------------------------------------------------------------------
-- omarchy's SUPER equivalents stay bound. ALT and SUPER are distinct chords, so these
-- are second routes to the same verb rather than competitors.

o.bind("ALT + M", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- code:20 / code:21 are minus / equal. Direction follows AeroSpace's `alt-minus` /
-- `alt-equal` (shrink / grow), which is the reverse of how omarchy labels the same two
-- keycodes on SUPER.
o.bind("ALT + code:20", "Shrink window", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
o.bind("ALT + code:21", "Grow window", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))

-- SUPER, not ALT: macOS locks on ctrl-cmd-q, and SUPER is the key that sends Command
-- there. omarchy's SUPER+CTRL+L stays bound as a second route.
o.bind("SUPER + CTRL + Q", "Lock system", "omarchy-system-lock")

-- ---------------------------------------------------------------------------------
-- TAB -- the one deliberate exception to the mirror
-- ---------------------------------------------------------------------------------
-- AeroSpace puts workspace-back-and-forth and move-to-next-monitor on alt-tab and
-- alt-shift-tab. Here those two chords are the conventional window switcher, which
-- macOS has no counterpart to (it switches on cmd-tab), so mirroring would cost a
-- switcher and buy nothing. Both verbs stay on SUPER instead.
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Former workspace (back and forth)",
  hl.dsp.focus({ workspace = "previous" }))

-- Displaces omarchy's "previous workspace", which matters little now that workspaces
-- are addressed by letter.
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + SHIFT + TAB", "Move workspace to next monitor",
  hl.dsp.workspace.move({ monitor = "+1" }))

-- Window mode, mirroring AeroSpace's `service` mode, which it enters with
-- alt-shift-semicolon -- the same chord, with the same inner letters wherever a verb
-- exists on both.
hl.define_submap("window", function()
  o.bind("ESCAPE", "Exit window mode", hl.dsp.submap("reset"))

  -- Shared with AeroSpace service mode.
  o.bind("F", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
  o.bind("R", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")

  -- Linux-only verbs, no AeroSpace counterpart.
  o.bind("G", "Toggle window grouping", hl.dsp.group.toggle())
  o.bind("O", "Pop window out (float & pin)", "omarchy-hyprland-window-pop")
  o.bind("P", "Pseudo window", hl.dsp.window.pseudo())
end)

o.bind("ALT + SHIFT + SEMICOLON", "Window mode", hl.dsp.submap("window"))

-- ---------------------------------------------------------------------------------
-- App launcher mode
-- ---------------------------------------------------------------------------------
-- Every launcher in ~/.config/hypr/bindings.lua gathered under one uniform path, each
-- keeping its mnemonic letter. This began as a rescue for the eight launchers the old
-- SUPER+SHIFT+<letter> workspace layer displaced (B C E F G O P S); the layer moved to
-- ALT and gave them back, so nothing depends on this mode any more. Kept because a
-- single alphabet of launchers is easier to hold than fifteen scattered chords.
hl.define_submap("apps", function()
  o.bind("ESCAPE", "Exit app mode", hl.dsp.submap("reset"))

  o.bind("B", "Browser", { omarchy = "browser" })
  o.bind("C", "Calendar", { webapp = "https://app.hey.com/calendar/weeks/" })
  o.bind("E", "Email", { webapp = "https://app.hey.com" })
  o.bind("F", "File manager", { omarchy = "nautilus" })
  o.bind("G", "Signal", { launch = "signal-desktop", focus = "^signal$" })
  o.bind("O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
  o.bind("P", "Google Photos", { webapp = "https://photos.google.com/", focus = true })
  o.bind("S", "Google Maps", { webapp = "https://maps.google.com/", focus = true })

  o.bind("A", "ChatGPT", { webapp = "https://chatgpt.com" })
  o.bind("D", "Docker", { tui = "lazydocker" })
  o.bind("M", "Music", { omarchy = "or-focus spotify" })
  o.bind("N", "Editor", { omarchy = "editor" })
  o.bind("W", "Typora", { launch = "typora --enable-wayland-ime" })
  o.bind("X", "X", { webapp = "https://x.com/" })
  o.bind("Y", "YouTube", { webapp = "https://youtube.com/" })
  o.bind("SLASH", "Passwords", { launch = "1password" })

  -- Modified variants, using the same modifiers they use outside the mode.
  o.bind("ALT + A", "Grok", { webapp = "https://grok.com" })
  o.bind("ALT + B", "Browser (private)", { omarchy = "browser --private" })
  o.bind("ALT + F", "File manager (cwd)", { omarchy = "nautilus-cwd" })
  o.bind("ALT + G", "WhatsApp", { webapp = "https://web.whatsapp.com/", focus = true })
  o.bind("ALT + M", "Music TUI", { tui = "cliamp", focus = true })
  o.bind("ALT + X", "X Post", { webapp = "https://x.com/compose/post" })
  o.bind("CTRL + G", "Google Messages",
    { webapp = "https://messages.google.com/web/conversations", focus = true })
end)

o.bind("SUPER + A", "App mode", hl.dsp.submap("apps"))

-- Lost in the .conf -> .lua migration: bindings.conf.bak.1779450719 had
-- `SUPER SHIFT CTRL, A, opencode, exec, omarchy-launch-opencode`. That launcher script no
-- longer ships, but opencode is still installed, so restore the binding on its original
-- chord using the current TUI launcher.
o.bind("SUPER + SHIFT + CTRL + A", "opencode", { tui = "opencode" })
