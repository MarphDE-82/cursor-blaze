#language slang 2026
// Kitty port of spark-trail.glsl (procedural ember/spark burst) — original
// effect for cursor-blaze, see ghostty/shaders/spark-trail.glsl for the full
// design writeup. Same per-spark reconstruction, ported to kitty's
// KittyCustomShaderData (cursor_trail_edge/prev_edge, timestamp,
// cursor_trail_change_time) instead of Ghostty's iCurrentCursor/iPreviousCursor.

import kitty_custom_shader_types;

static const int NUM_SPARKS = 14;
static const float DURATION = 0.6;
static const float GRAVITY = 60.0;
static const float MIN_SPEED = 25.0;
static const float MAX_SPEED = 110.0;
static const float MIN_SIZE = 1.4;
static const float MAX_SIZE = 3.6;
static const float MAX_DELAY_FRAC = 0.35;
static const float3 COLOR_HOT = float3(1.0, 0.95, 0.72);
static const float3 COLOR_COLD = float3(1.0, 0.22, 0.04);

static float
hash(float n) { return frac(sin(n) * 43758.5453123); }

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (d.cursor_trail_state <= 0.0) return color;

    float age = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);
    if (age >= 1.0) return color;

    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 px = t.pos * pixelDims;
    // Flip to the same y-down/top-left convention used by the other ports in this
    // repo, so the geometry (and the gravity direction) reads the same way.
    float2 pxFlipped = float2(px.x, pixelDims.y - px.y);

    float2 curSize = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                             d.cursor_trail_edge.z - d.cursor_trail_edge.w) * pixelDims;
    float2 curPos = float2(d.cursor_trail_edge.x * pixelDims.x, pixelDims.y - d.cursor_trail_edge.z * pixelDims.y);
    float2 prevSize = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                              d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * pixelDims;
    float2 prevPos = float2(d.cursor_trail_prev_edge.x * pixelDims.x, pixelDims.y - d.cursor_trail_prev_edge.z * pixelDims.y);

    float2 currentCenter = float2(curPos.x + curSize.x * 0.5, curPos.y - curSize.y * 0.5);
    float2 previousCenter = float2(prevPos.x + prevSize.x * 0.5, prevPos.y - prevSize.y * 0.5);

    float eventSeed = frac(d.cursor_trail_change_time * 13.37) * 1000.0;

    float3 accumColor = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < NUM_SPARKS; i++) {
        float seed = eventSeed + float(i) * 7.919;
        float r0 = hash(seed);
        float r1 = hash(seed + 0.37);
        float r2 = hash(seed + 0.71);
        float r3 = hash(seed + 1.13);
        float r4 = hash(seed + 1.53);

        float delay = r4 * MAX_DELAY_FRAC;
        float localAge = (age - delay) / max(1.0 - delay, 0.001);
        if (localAge <= 0.0 || localAge >= 1.0) {
            continue;
        }

        float2 basePos = lerp(previousCenter, currentCenter, r0);

        float angle = r1 * 6.2831853;
        float speed = lerp(MIN_SPEED, MAX_SPEED, r2);
        float2 dir = float2(cos(angle), sin(angle));
        float2 offset = dir * speed * localAge;
        offset.y -= GRAVITY * localAge * localAge;

        float2 sparkPos = basePos + offset;
        float size = lerp(MIN_SIZE, MAX_SIZE, r3) * (1.0 - localAge);

        float dist = length(pxFlipped - sparkPos);
        float glow = exp(-(dist * dist) / (2.0 * size * size)) * (1.0 - localAge);

        float3 sparkColor = lerp(COLOR_HOT, COLOR_COLD, localAge);
        accumColor += sparkColor * glow;
    }

    float4 result = color;
    result.rgb = clamp(result.rgb + accumColor, float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0));

    float2 halfSize = curSize * 0.5;
    float2 dd = abs(pxFlipped - currentCenter) - halfSize;
    float sdfCursor = length(max(dd, float2(0.0))) + min(max(dd.x, dd.y), 0.0);
    result.rgb = lerp(result.rgb, color.rgb, step(sdfCursor, 0.0));

    return result;
}
