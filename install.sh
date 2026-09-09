#!/usr/bin/env bash
# Installs the shader files into both terminals' config directories (additive,
# does not touch your existing kitty.conf / ghostty config — see the printed
# instructions at the end for the one line to add for whichever variant you want).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Ghostty shaders to ~/.config/ghostty/shaders/"
mkdir -p ~/.config/ghostty/shaders
cp "$ROOT"/ghostty/shaders/*.glsl ~/.config/ghostty/shaders/

echo "==> Installing kitty shaders to ~/.config/kitty/shaders/"
mkdir -p ~/.config/kitty/shaders
cp "$ROOT"/kitty/shaders/*.slang "$ROOT"/kitty/shaders/*.pipeline ~/.config/kitty/shaders/

cat <<'EOF'

==> Done. Enable ONE variant per terminal:

Ghostty (~/.config/ghostty/config), pick one:
    custom-shader = shaders/ghostty-slasher.glsl   # minty
    custom-shader = shaders/perfection.glsl        # neon gradient
    custom-shader = shaders/cursor.glsl             # hexagon, dynamic cursor color
    custom-shader-animation = always

kitty (~/.config/kitty/kitty.conf), needs kitty >= 0.49.0 (kitty-git from AUR today):
    cursor_trail 1
    custom_shaders cursor-trail-mint       # minty
    custom_shaders cursor-trail-neon       # neon gradient
    custom_shaders cursor-trail-hexagon    # hexagon, dynamic cursor color
EOF
