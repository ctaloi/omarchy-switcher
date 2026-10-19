-- macOS-style switching.
--
--   SUPER + TAB          Hold SUPER, tap TAB to step through apps (most recent
--                        first), release SUPER to switch. A quick tap flips to
--                        the previous app. SHIFT steps backwards.
--   SUPER + GRAVE (`/~)  Cycle windows of the focused app. SHIFT reverses.
--                        While the app strip is up, steps it backwards.
--
-- The app strip is drawn by the chris.switcher shell plugin
-- (~/.config/omarchy/plugins/chris.switcher); this file owns all the state and
-- pushes it there over IPC.

local POLL_MS = 15 -- how often to check whether SUPER is still held
local HUD_DELAY_MS = 110 -- quick taps switch without flashing the strip

-- Survive `hyprctl reload`: stop a timer left running by the previous load.
if _G.chris_switcher and _G.chris_switcher.timer then
  _G.chris_switcher.timer:set_enabled(false)
end
-- Seeded from the clock so a fresh Hyprland never reuses a number the
-- long-running shell has already seen closed.
local seq = (_G.chris_switcher and _G.chris_switcher.seq) or os.time()
_G.chris_switcher = { seq = seq }
local state = _G.chris_switcher

local function json(value)
  local kind = type(value)
  if kind == "table" then
    local parts = {}
    if #value > 0 or next(value) == nil then
      for _, item in ipairs(value) do
        table.insert(parts, json(item))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
      table.insert(parts, json(tostring(key)) .. ":" .. json(item))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif kind == "string" then
    return '"' .. value:gsub('[%c"\\]', function(c)
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif kind == "boolean" or kind == "number" then
    return tostring(value)
  end
  return "null"
end

local function switchable(window)
  return window.mapped
    and not window.hidden
    and window.class ~= ""
    and window.workspace ~= nil
    and not window.workspace.special
end

-- One entry per app, ordered by its most recently focused window.
local function app_list()
  local by_class, apps = {}, {}
  for _, window in ipairs(hl.get_windows()) do
    if switchable(window) then
      local app = by_class[window.class]
      if not app then
        app = { class = window.class, window = window, count = 0 }
        by_class[window.class] = app
        table.insert(apps, app)
      end
      app.count = app.count + 1
      if window.focus_history_id < app.window.focus_history_id then
        app.window = window
      end
    end
  end
  table.sort(apps, function(a, b)
    return a.window.focus_history_id < b.window.focus_history_id
  end)
  return apps
end

local function super_held()
  return hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
end

local function push_hud()
  local items = {}
  for _, app in ipairs(state.apps) do
    table.insert(items, { class = app.class, title = app.window.title, count = app.count })
  end
  hl.exec_cmd("omarchy-shell -q switcher show " .. o.shell_quote(json({ seq = state.seq, selected = state.index - 1, items = items })))
end

local function finish(commit)
  if state.timer then
    state.timer:set_enabled(false)
    state.timer = nil
  end
  if state.hud_shown then
    hl.exec_cmd("omarchy-shell -q switcher close " .. state.seq)
  end

  local target = commit and state.apps and state.apps[state.index]
  state.apps, state.index, state.hud_shown = nil, nil, false

  if target then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. target.window.address }))
    hl.dispatch(hl.dsp.window.bring_to_top())
  end
end

local function step(delta)
  if not state.apps then
    local apps = app_list()
    if #apps < 2 then
      return
    end
    state.apps = apps
    -- Each IPC push is its own process, so a late show could land after the
    -- close; the strip drops anything from a session it already closed.
    state.seq = state.seq + 1
    -- Start on the current app so the first step lands on the previous one.
    state.index = 1
    state.started = 0
    state.timer = hl.timer(function()
      state.started = state.started + POLL_MS
      if not super_held() then
        finish(true)
      elseif not state.hud_shown and state.started >= HUD_DELAY_MS then
        state.hud_shown = true
        push_hud()
      end
    end, { timeout = POLL_MS, type = "repeat" })
  end

  state.index = (state.index - 1 + delta) % #state.apps + 1
  if state.hud_shown then
    push_hud()
  end
end

-- Windows of the focused app in a fixed order, so repeated presses walk through
-- all of them instead of bouncing between the two most recent.
local function cycle_app_windows(delta)
  local active = hl.get_active_window()
  if not active then
    return
  end

  local windows = {}
  for _, window in ipairs(hl.get_windows()) do
    if window.class == active.class and switchable(window) then
      table.insert(windows, window)
    end
  end
  if #windows < 2 then
    return
  end
  table.sort(windows, function(a, b)
    return a.stable_id < b.stable_id
  end)

  for i, window in ipairs(windows) do
    if window.address == active.address then
      local target = windows[(i - 1 + delta) % #windows + 1]
      hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
      hl.dispatch(hl.dsp.window.bring_to_top())
      return
    end
  end
end

-- Was: SUPER+TAB next workspace, SUPER+SHIFT+TAB previous workspace.
-- SUPER+CTRL+TAB (former workspace), SUPER+scroll and the 3-finger swipe still
-- move between workspaces.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")

o.bind("SUPER + TAB", "Switch app", function() step(1) end)
o.bind("SUPER + SHIFT + TAB", "Switch app backwards", function() step(-1) end)
-- While the app strip is up, ` steps it backwards (as on macOS); otherwise it
-- cycles the focused app's windows.
o.bind("SUPER + code:49", "Next window of this app", function()
  if state.apps then step(-1) else cycle_app_windows(1) end
end)
o.bind("SUPER + SHIFT + code:49", "Previous window of this app", function()
  if state.apps then step(1) else cycle_app_windows(-1) end
end)

-- Exposed for testing from `hyprctl eval`.
state.step = step
state.finish = finish
state.cycle = cycle_app_windows
state.app_list = app_list
