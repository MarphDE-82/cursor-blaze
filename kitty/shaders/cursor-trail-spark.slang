#language slang 2026
// Kitty port of spark-trail.glsl (procedural ember/spark burst with streaked,
// arc-following motion trails) — original effect for cursor-blaze, see
// ghostty/shaders/spark-trail.glsl for the full design writeup. Same per-spark
// reconstruction, ported to kitty's KittyCustomShaderData (cursor_trail_edge/
// prev_edge, timestamp, cursor_trail_change_time) instead of Ghostty's
// iCurrentCursor/iPreviousCursor.

import kitty_custom_shader_types;

static const int NUM_SPARKS = 16;
static const float DURATION = 0.65;
static const float GRAVITY = 70.0;
static const float MIN_SPEED = 40.0;
static const float MAX_SPEED = 140.0;
static const float MIN_SIZE = 0.9;
static const float MAX_SIZE = 2.0;
static const float MAX_DELAY_FRAC = 0.35;
static const float CORE_BRIGHTNESS = 3.0;
static const float STREAK_BRIGHTNESS = 1.1;
static const float INTENSITY = 1.35;

static float
hash(float n) { return frac(sin(n) * 43758.5453123); }

static float3
emberColor(float t) {
    float3 c1 = float3(1.0, 0.98, 0.92);
    float3 c2 = float3(1.0, 0.80, 0.25);
    float3 c3 = float3(1.0, 0.35, 0.05);
    float3 c4 = float3(0.35, 0.04, 0.01);
    float3 col = lerp(c1, c2, smoothstep(0.0, 0.28, t));
    col = lerp(col, c3, smoothstep(0.28, 0.62, t));
    col = lerp(col, c4, smoothstep(0.62, 1.0, t));
    return col;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (d.cursor_trail_state <= 0.0) return color;

    float age = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);
    if (age >= 1.0) return color;

    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 px = t.pos * pixelDims;

    // cursor_trail_edge is UV (origin bottom-left, y up) — keep that convention
    // throughout, no axis flip; subtracting size.y below moves towards the bottom.
    float2 curSize = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                             d.cursor_trail_edge.z - d.cursor_trail_edge.w) * pixelDims;
    float2 curPos = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.z) * pixelDims;
    float2 prevSize = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                              d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * pixelDims;
    float2 prevPos = float2(d.cursor_trail_prev_edge.x, d.cursor_trail_prev_edge.z) * pixelDims;

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
        float r5 = hash(seed + 2.02);

        float delay = r4 * MAX_DELAY_FRAC;
        float localAge = (age - delay) / max(1.0 - delay, 0.001);
        if (localAge <= 0.0 || localAge >= 1.0) {
            continue;
        }

        float2 basePos = lerp(previousCenter, currentCenter, r0);

        float angle = r1 * 6.2831853;
        float speed = lerp(MIN_SPEED, MAX_SPEED, r2);
        float2 launchDir = float2(cos(angle), sin(angle));

        float2 sparkPos = basePos + launchDir * speed * localAge + float2(0.0, -GRAVITY * localAge * localAge);
        float2 velocity = launchDir * speed + float2(0.0, -2.0 * GRAVITY * localAge);
        float velLen = max(length(velocity), 0.001);
        float2 tangent = velocity / velLen;
        float2 normal = float2(-tangent.y, tangent.x);

        float fade = (1.0 - localAge);
        float size = lerp(MIN_SIZE, MAX_SIZE, r3) * fade;
        float speedNorm = (speed - MIN_SPEED) / max(MAX_SPEED - MIN_SPEED, 0.001);
        float streakLen = lerp(4.0, 16.0, speedNorm) * fade;
        float flicker = 0.75 + 0.25 * sin(d.timestamp * 40.0 + seed * 17.0);

        float2 rel = px - sparkPos;
        float along = dot(rel, tangent);
        float across = dot(rel, normal);

        float alongNorm = along < 0.0 ? (-along / streakLen) : (along / (size * 1.5));
        float acrossNorm = across / size;
        float streak = exp(-(alongNorm * alongNorm + acrossNorm * acrossNorm));

        float core = exp(-(along * along + across * across) / (size * size));

        float glow = (core * CORE_BRIGHTNESS + streak * STREAK_BRIGHTNESS) * fade * flicker;
        float3 sparkColor = emberColor(localAge);
        accumColor += sparkColor * glow * (0.6 + 0.4 * r5);
    }

    float4 result = color;
    result.rgb = clamp(result.rgb + accumColor * INTENSITY, float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0));

    float2 halfSize = curSize * 0.5;
    float2 dd = abs(px - currentCenter) - halfSize;
    float sdfCursor = length(max(dd, float2(0.0))) + min(max(dd.x, dd.y), 0.0);
    result.rgb = lerp(result.rgb, color.rgb, step(sdfCursor, 0.0));

    return result;
}
