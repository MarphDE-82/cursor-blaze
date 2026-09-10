# cursor-blaze

Animated cursor-trail shaders for your terminal — works in **both Ghostty and kitty**,
with the exact same visuals in each. Four variants: a neon pink→blue→teal gradient
trail, a minty parallelogram trail, a hexagonal trail colored with your actual cursor
color, and a procedural ember/spark burst.

<!-- Add a screenshot or GIF of the trail in action here -->

## Why this exists

Ghostty added custom-shader support a while back, and a few nice cursor-trail shaders
exist for it (see [Credits](#credits)). kitty just landed its own custom-shader system
([RFC](https://github.com/kovidgoyal/kitty/discussions/10344), kitty ≥ 0.49.0) — but
it's a different shading language (**Slang**, not GLSL) with a completely different
uniform/pipeline model, so nothing written for Ghostty runs in kitty as-is.

This repo ports the same three effects to kitty's Slang system, matching the original
Ghostty visuals — geometry, easing, and color logic — 1:1, so you get the identical
look in both terminals instead of settling for kitty's differently-styled built-in
`cursor-trail-blaze`.

## Variants

| Variant | Shader name | Effect |
|---|---|---|
| Neon gradient | `perfection` | Pink → blue → teal gradient trail |
| Mint blaze | `ghostty-slasher` | Minty green/blue parallelogram trail |
| Hexagon | `cursor` | Hexagonal trail using your actual cursor color |
| Spark | `spark-trail` / `cursor-trail-spark` | Procedural ember/spark burst with a falling arc — original effect, not a Ghostty port |

## Install

Run `./install.sh` — it detects which of Ghostty / kitty you actually have installed
(and, for kitty, whether that build actually supports `custom_shaders` — kitty-git
builds don't bump their version string, so it checks kitty's own option schema at
runtime rather than trusting `kitty --version`) and only installs shaders for those.
Pure `mkdir`/`cp`, no package manager calls, so it runs on any Linux distro. It does
**not** touch your existing config files; add one of the lines below yourself.

### Ghostty

```
# ~/.config/ghostty/config
custom-shader = shaders/perfection.glsl        # neon gradient
# custom-shader = shaders/ghostty-slasher.glsl # mint
# custom-shader = shaders/cursor.glsl          # hexagon
# custom-shader = shaders/spark-trail.glsl     # ember/spark burst
custom-shader-animation = always
```

### kitty

Requires kitty ≥ 0.49.0 (not yet in a stable release as of writing — use
[`kitty-git`](https://aur.archlinux.org/packages/kitty-git) from the AUR, or build
from `master`).

```
# ~/.config/kitty/kitty.conf
cursor_trail 1
custom_shaders perfection              # neon gradient
# custom_shaders ghostty-slasher       # mint
# custom_shaders cursor                # hexagon
# custom_shaders cursor-trail-spark    # ember/spark burst
```

## How the kitty port works

Ghostty shaders are plain GLSL fragment shaders (Shadertoy-style `mainImage()`,
uniforms like `iCurrentCursor`/`iPreviousCursor`/`iTime`/`iFocus`). kitty's shaders
are Slang (`fragment_main(color, textures, data)`), reading cursor state from a
`KittyCustomShaderData` struct (`cursor_trail_edge`/`cursor_trail_prev_edge` for the
current/previous cursor rect, `cursor_color` for the live cursor color, `timestamp`/
`cursor_trail_change_time` for animation progress). The kitty shaders in this repo
reimplement each effect's SDF geometry, vertex selection, easing curve and color
logic against those kitty types rather than reusing kitty's own built-in blaze
shader, so the look matches the Ghostty originals rather than kitty's own style.

## Other terminals

**Alacritty**: no native shader support. The third-party [CRTty](https://github.com/kosa12/CRTty)
(`LD_PRELOAD`) can run generic post-processing GLSL on Alacritty (CRT, scanlines,
vignette, bloom), but it only exposes time/resolution to the shader — no cursor
position — so it can't drive a cursor trail. These effects need real cursor-position
data every frame, which nothing currently plumbs into Alacritty's renderer.

**KDE Konsole**: no shader path at all, native or third-party. Konsole doesn't render
through a GLSL fragment-shader pipeline the way kitty/Ghostty/Alacritty do (it's
Qt/QPainter-based), and no known project bridges that gap. The closest thing KDE has
is [kwin-effect-shaders](https://github.com/kevinlekiller/kwin-effect-shaders) at the
*compositor* level — but that applies to the whole desktop, not a specific terminal
window, and has no concept of "where's the terminal cursor" either.

The spark variant (`spark-trail.glsl` / `cursor-trail-spark.slang`) is an original
addition, not a Ghostty port — written for this repo. It reconstructs a burst of
"sparks" analytically every frame (no persistent particle state is possible in a
stateless fragment shader): each spark's spawn point along the cursor's travel path,
launch angle/speed, size and birth delay come from a per-spark pseudo-random hash
seeded by the time of the last cursor move, so every jump throws a differently
shaped burst. A small downward "gravity" term bends each spark into a falling arc,
and color ages from white-yellow to ember orange-red as it fades.

## Credits

Original Ghostty shaders (perfection/ghostty-slasher/cursor) by [stephin-develops](https://github.com/stephin-develops)
([linux-ricing](https://github.com/stephin-develops/linux-ricing/tree/main/ghostty),
u/IntellegientTrash2669 on Reddit). Spark variant, kitty ports, and this repo by
[MarphDE](https://github.com/snafus-io).

## License

MIT — see [LICENSE](LICENSE). Please keep the credits above if you fork this.
