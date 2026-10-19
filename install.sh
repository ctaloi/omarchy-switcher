#!/bin/bash
# Wire the switcher into Hyprland and the Omarchy shell from this repo.
# Safe to re-run: links are refreshed and the require line is added once.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
hypr=~/.config/hypr
plugin=~/.config/omarchy/plugins/chris.switcher

link() {
  local src=$1 dest=$2
  if [[ -e $dest && ! -L $dest ]]; then
    mv "$dest" "$dest.bak.$(date +%s)"
  fi
  ln -sfn "$src" "$dest"
}

link "$repo/hypr/switcher.lua" "$hypr/switcher.lua"

mkdir -p "$plugin"
link "$repo/plugin/manifest.json" "$plugin/manifest.json"
link "$repo/plugin/Switcher.qml" "$plugin/Switcher.qml"

if ! grep -q 'require("hypr.switcher")' "$hypr/bindings.lua"; then
  printf '\n-- macOS-style SUPER+TAB app switcher and SUPER+` window cycling.\nrequire("hypr.switcher")\n' >> "$hypr/bindings.lua"
fi

omarchy-shell -q shell rescanPlugins
omarchy-shell -q shell setPluginEnabled chris.switcher true
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  echo "$errors" >&2
  exit 1
fi
echo "switcher installed"
