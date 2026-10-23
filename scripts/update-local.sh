#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
install_path=${VOICEINK_INSTALL_PATH:-/Applications/VoiceInk.app}
build_path="$HOME/Downloads/VoiceInk.app"

cd "$repo_dir"

if [[ -n $(git status --porcelain) ]]; then
  echo "Error: working tree has uncommitted changes" >&2
  exit 1
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/Beingpax/VoiceInk.git
fi

current_branch=$(git branch --show-current)
if [[ -z $current_branch ]]; then
  echo "Error: detached HEAD; check out your fork branch first" >&2
  exit 1
fi

printf 'Updating %s from upstream...\n' "$current_branch"
git fetch origin "$current_branch"
git merge --ff-only "origin/$current_branch"
git fetch upstream main
git merge --no-edit upstream/main

if ! xcrun metal --version >/dev/null 2>&1; then
  echo "Installing required Xcode Metal toolchain..."
  xcodebuild -downloadComponent MetalToolchain
fi

make local

printf 'Installing %s...\n' "$install_path"
osascript -e 'tell application "VoiceInk" to quit' 2>/dev/null || true
rm -rf "$install_path"
ditto "$build_path" "$install_path"
codesign --verify --deep --strict "$install_path"
open "$install_path"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$install_path/Contents/Info.plist")
printf 'VoiceInk %s installed and launched.\n' "$version"
