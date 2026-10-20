# omarchy-switcher

macOS-style app switching for Omarchy (Hyprland 0.56+, Lua config).

| Keys | Does |
|---|---|
| `SUPER + TAB` | Tap: flip to the previous app. Hold SUPER and tap TAB to step through apps (most recent first), release to switch. |
| `SUPER + SHIFT + TAB` | Step the strip backwards. |
| `SUPER + `` ` `` | Strip open: step backwards. Otherwise: next window of the focused app. |
| `SUPER + SHIFT + `` ` `` | Strip open: step forwards. Otherwise: previous window of the focused app. |

Replaces Omarchy's default `SUPER + TAB` / `SUPER + SHIFT + TAB` (next/previous
workspace). `SUPER + CTRL + TAB`, `SUPER` + scroll and the 3-finger swipe still
move between workspaces.

## Layout

- `hypr/switcher.lua`: all state and key handling. Polls whether SUPER is still
  held, then focuses the chosen app's most recent window.
- `plugin/`: the `chris.switcher` Omarchy shell plugin that draws the strip.
  It only renders what the Lua side pushes over `omarchy-shell switcher show|close`.

## Install

```bash
./install.sh
```

Symlinks `hypr/switcher.lua` into `~/.config/hypr/` and the plugin files into
`~/.config/omarchy/plugins/chris.switcher/`, adds `require("hypr.switcher")` to
`~/.config/hypr/bindings.lua`, enables the plugin, and validates the Hyprland
config. Re-run it after `omarchy refresh hyprland`, which resets `bindings.lua`.

Edits in this repo are live: Hyprland reloads the Lua on save. The plugin is
`keepLoaded`, so QML changes need `omarchy restart shell`.

## Uninstall

Delete the `require("hypr.switcher")` line from `~/.config/hypr/bindings.lua`,
then `omarchy-shell shell setPluginEnabled chris.switcher false`.

## Debugging

```bash
hyprctl eval 'chris_switcher.step(1)'   # one tap of SUPER+TAB
omarchy-shell switcher show '{"seq":1,"selected":0,"items":[{"class":"foot","title":"","count":2}]}'
omarchy-shell switcher close 1
```

## License

MIT.
