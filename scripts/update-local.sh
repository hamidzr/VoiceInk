#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
install_path=${VOICEINK_INSTALL_PATH:-/Applications/VoiceInk.app}
build_path="$HOME/Downloads/VoiceInk.app"
bundle_id=com.prakashjoshipax.VoiceInk
app_binary="$install_path/Contents/MacOS/VoiceInk"

designated_requirement() {
  codesign -d -r- "$1" 2>/dev/null | sed -n 's/^designated => //p' || true
}

quit_app() {
  osascript -e 'tell application "VoiceInk" to quit' 2>/dev/null || true
  for _ in {1..20}; do
    pgrep -f "$app_binary" >/dev/null || return 0
    sleep 0.5
  done
  echo "Error: VoiceInk did not quit" >&2
  exit 1
}

# the shortcut event tap is only installed at launch, so check it after each start
launch_and_check_shortcuts() {
  local started_at failures
  started_at=$(date '+%Y-%m-%d %H:%M:%S')
  open "$install_path"
  sleep 5
  failures=$(/usr/bin/log show --start "$started_at" --style compact \
    --predicate 'process == "VoiceInk" AND eventMessage CONTAINS "Failed to install global shortcut event tap"' \
    2>/dev/null || true)
  [[ $failures != *"event tap"* ]]
}

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

old_requirement=$(designated_requirement "$install_path")

make local

new_requirement=$(designated_requirement "$build_path")
if [[ $new_requirement == cdhash* ]]; then
  echo "Warning: ad-hoc signed build; macOS privacy grants will reset on every rebuild" >&2
fi

printf 'Installing %s...\n' "$install_path"
quit_app
rm -rf "$install_path"
ditto "$build_path" "$install_path"
codesign --verify --deep --strict "$install_path"

# grants are bound to the old signature; toggling them in System Settings does not
# rebind them, only removing the entry does
if [[ -n $old_requirement && $old_requirement != "$new_requirement" ]]; then
  echo "Code signature changed; clearing stale privacy grants..."
  for service in Accessibility Microphone ScreenCapture; do
    tccutil reset "$service" "$bundle_id" >/dev/null
  done
fi

if ! launch_and_check_shortcuts; then
  cat >&2 <<'MSG'
VoiceInk could not install its shortcut event tap: Accessibility is not granted.
In System Settings > Privacy & Security > Accessibility, remove VoiceInk with "-"
if listed, add /Applications/VoiceInk.app with "+", and enable it. Toggling an
existing entry is not enough.
MSG
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  if [[ -t 0 ]]; then
    read -r -p "Press Enter after granting Accessibility to restart VoiceInk..."
    quit_app
    if ! launch_and_check_shortcuts; then
      echo "Error: shortcuts still unavailable; check the Accessibility entry" >&2
      exit 1
    fi
  else
    echo "Restart VoiceInk after granting Accessibility." >&2
    exit 1
  fi
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$install_path/Contents/Info.plist")
printf 'VoiceInk %s installed and launched.\n' "$version"
