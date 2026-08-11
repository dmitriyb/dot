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
-- `option` on a Mac keyboard and `SUPER` here occupy the same physical position, so
-- AeroSpace's `alt-t` and this `SUPER+T` are one chord under the same finger; only the
-- keycap differs. Named workspaces keep the letter as the workspace's real identity, so
-- there is no letter->digit table to drift out of sync with
-- mac/.config/aerospace/aerospace.toml.
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

  -- Displaces omarchy defaults on C F G O P S T, and this machine's app launchers on
  -- B C E F G O P S. A silent no-op on the letters that were already free.
  hl.unbind("SUPER + " .. letter)
  hl.unbind("SUPER + SHIFT + " .. letter)

  o.bind("SUPER + " .. letter, "Workspace " .. letter .. " -- " .. ws.note,
    hl.dsp.focus({ workspace = name }))
  o.bind("SUPER + SHIFT + " .. letter, "Move window to workspace " .. letter,
    hl.dsp.window.move({ workspace = name }))

  for _, class in ipairs(ws.classes or {}) do
    o.window(class, { workspace = name })
  end
end

-- ---------------------------------------------------------------------------------
-- New homes for the window verbs the letter layer displaced
-- ---------------------------------------------------------------------------------

-- Work around Hyprland send_shortcut sometimes leaving synthetic key state stuck.
-- Lifted from default/hypr/bindings/clipboard.lua, where it is a file-local function.
-- https://github.com/hyprwm/Hyprland/discussions/14099
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down", window = "activewindow" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up", window = "activewindow" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

-- High-frequency verbs stay one keystroke away, on letters the workspace layer left free.
o.bind("SUPER + M", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" })) -- was SUPER+F
o.bind("SUPER + D", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad")) -- was SUPER+S
o.bind("SUPER + INSERT", "Universal copy", send_shortcut_once("CTRL", "Insert"))       -- was SUPER+C
-- SUPER+V paste and SUPER+X cut are untouched: V and X are not workspace letters.

-- AeroSpace's alt-tab is `workspace-back-and-forth`, but omarchy points SUPER+TAB at
-- "next workspace". Align the chord that actually gets used, on the side not hand-picked:
-- next/prev workspace matters little now that workspaces are addressed by letter, and
-- SUPER+SHIFT+TAB / SUPER+CTRL+TAB still cover prev and former.
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Former workspace (back and forth)",
  hl.dsp.focus({ workspace = "previous" }))

-- Window mode, mirroring AeroSpace's `service` mode. AeroSpace already enters that with
-- alt-shift-semicolon, so the same physical chord now opens the same kind of mode on both
-- machines, with the same inner letters wherever a verb exists on both.
hl.define_submap("window", function()
  o.bind("ESCAPE", "Exit window mode", hl.dsp.submap("reset"))

  -- Shared with AeroSpace service mode.
  o.bind("F", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" })) -- was SUPER+T
  o.bind("R", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")

  -- Linux-only verbs, no AeroSpace counterpart.
  o.bind("G", "Toggle window grouping", hl.dsp.group.toggle())                -- was SUPER+G
  o.bind("O", "Pop window out (float & pin)", "omarchy-hyprland-window-pop")  -- was SUPER+O
  o.bind("P", "Pseudo window", hl.dsp.window.pseudo())                        -- was SUPER+P
end)

o.bind("SUPER + SHIFT + SEMICOLON", "Window mode", hl.dsp.submap("window"))

-- ---------------------------------------------------------------------------------
-- App launcher mode
-- ---------------------------------------------------------------------------------
-- SUPER+SHIFT+<letter> now means "move window to workspace <letter>", which displaced
-- eight app launchers from ~/.config/hypr/bindings.lua (B C E F G O P S). Rather than
-- scatter them across arbitrary free chords, every app gets one uniform path here and
-- keeps its original mnemonic letter. Nothing is lost.
--
-- The seven launchers that did NOT collide (A D M N W X Y) are deliberately left in place
-- in bindings.lua as well, so no relearning is forced -- they simply also work from here.
hl.define_submap("apps", function()
  o.bind("ESCAPE", "Exit app mode", hl.dsp.submap("reset"))

  -- Displaced by the workspace layer -- now reachable only here.
  o.bind("B", "Browser", { omarchy = "browser" })
  o.bind("C", "Calendar", { webapp = "https://app.hey.com/calendar/weeks/" })
  o.bind("E", "Email", { webapp = "https://app.hey.com" })
  o.bind("F", "File manager", { omarchy = "nautilus" })
  o.bind("G", "Signal", { launch = "signal-desktop", focus = "^signal$" })
  o.bind("O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
  o.bind("P", "Google Photos", { webapp = "https://photos.google.com/", focus = true })
  o.bind("S", "Google Maps", { webapp = "https://maps.google.com/", focus = true })

  -- Still on SUPER+SHIFT+<letter> too; mirrored here so the mode is complete.
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
