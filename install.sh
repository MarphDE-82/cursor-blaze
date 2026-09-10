#!/usr/bin/env bash
# Installs the shader files into whichever supported terminal(s) are actually
# installed (additive — does not touch your existing kitty.conf / ghostty
# config, see the printed instructions at the end for the one line to add).
#
# Pure POSIX-ish file operations (mkdir/cp) only, no package manager calls,
# so this works on any Linux distro (or macOS) — the only requirement is bash
# itself and, obviously, kitty and/or Ghostty already installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

installed_any=0

# --- Ghostty ---------------------------------------------------------------
if command -v ghostty >/dev/null 2>&1; then
    echo "==> Ghostty detected — installing shaders to $CONFIG_HOME/ghostty/shaders/"
    mkdir -p "$CONFIG_HOME/ghostty/shaders"
    cp "$ROOT"/ghostty/shaders/*.glsl "$CONFIG_HOME/ghostty/shaders/"
    installed_any=1
else
    echo "==> Ghostty not found on PATH — skipping (nothing to enable in your config)"
fi

# --- kitty -------------------------------------------------------------
if command -v kitty >/dev/null 2>&1; then
    # kitty-git builds don't bump the reported version string, so checking
    # `kitty --version` can't tell a custom_shaders-capable build from stable
    # 0.48.x. Ask kitty's own option schema at runtime instead.
    if kitty +runpy 'from kitty.options.types import Options; import sys; sys.exit(0 if hasattr(Options, "custom_shaders") else 1)' >/dev/null 2>&1; then
        echo "==> kitty detected with custom_shaders support — installing shaders to $CONFIG_HOME/kitty/shaders/"
        mkdir -p "$CONFIG_HOME/kitty/shaders"
        cp "$ROOT"/kitty/shaders/*.slang "$ROOT"/kitty/shaders/*.pipeline "$CONFIG_HOME/kitty/shaders/"
        installed_any=1
    else
        echo "==> kitty detected, but this build has no custom_shaders support (needs kitty >= 0.49.0)."
        echo "    Install kitty-git from the AUR (Arch) or build from master, then re-run this script."
    fi
else
    echo "==> kitty not found on PATH — skipping (nothing to enable in your config)"
fi

if [ "$installed_any" -eq 0 ]; then
    echo
    echo "Neither Ghostty nor a custom_shaders-capable kitty was found — nothing installed."
    echo "See the README for Alacritty/Konsole (not supported, and why)."
    exit 1
fi

cat <<'EOF'

==> Done. Enable ONE variant per terminal:

Ghostty (~/.config/ghostty/config or $XDG_CONFIG_HOME/ghostty/config), pick one:
    custom-shader = shaders/ghostty-slasher.glsl   # minty
    custom-shader = shaders/perfection.glsl        # neon gradient
    custom-shader = shaders/cursor.glsl             # hexagon, dynamic cursor color
    custom-shader = shaders/spark-trail.glsl        # ember/spark burst
    custom-shader-animation = always

kitty (~/.config/kitty/kitty.conf or $XDG_CONFIG_HOME/kitty/kitty.conf):
    cursor_trail 1
    custom_shaders ghostty-slasher         # minty
    custom_shaders perfection              # neon gradient
    custom_shaders cursor                  # hexagon, dynamic cursor color
    custom_shaders cursor-trail-spark      # ember/spark burst
EOF
