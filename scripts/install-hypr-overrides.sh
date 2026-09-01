#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$HOME/.config/hypr"
file="bindings.lua"

mkdir -p "$target"

if [[ -f "$target/$file" ]]; then
  cp -a "$target/$file" "$target/$file.bak.$(date +%Y%m%d-%H%M%S)"
fi

cp "$repo_dir/hypr/$file" "$target/$file"

echo "Installed MacBook brightness bindings into $target/$file"
echo "No Caps-to-Escape remap is installed; the working Touch Bar provides a real Escape key."
echo "Log out/in if your Omarchy release does not auto-reload this file."
