#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$HOME/.config/hypr"

mkdir -p "$target"

for file in bindings.lua input.lua; do
  if [[ -f "$target/$file" ]]; then
    cp -a "$target/$file" "$target/$file.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  cp "$repo_dir/hypr/$file" "$target/$file"
done

echo "Installed Hyprland overrides into $target"
echo "Log out/in if your Omarchy release does not auto-reload these files."
