#!/usr/bin/env bash
# Re-apply the wallpapers so a theme change updates the generated ACO background.
# A wallpaper chosen by the user stays as it is.
set -euo pipefail
[[ -n ${WAYLAND_DISPLAY:-} ]] || exit 0
bash "${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper/wallpaper.sh" apply --quiet
