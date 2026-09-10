#language slang 2026
// Kitty port of "ghostty-slasher.glsl" (minty green/blue parallelogram cursor trail)
// from https://github.com/stephin-develops/linux-ricing/tree/main/ghostty
// Original used Ghostty's iCurrentCursor/iPreviousCursor/iTime/iFocus uniforms;
// this rewrites the same vertex-selection/SDF/compositing logic against kitty's
// KittyCustomShaderData (cursor_trail_edge/prev_edge, timestamp, cursor_trail_change_time).

import kitty_custom_shader_types;

static const float4 TRAIL_COLOR = float4(0.20, 0.90, 0.65, 1.0);        // Minty green-blue
static const float4 TRAIL_COLOR_ACCENT = float4(0.40, 1.0, 0.80, 1.0);  // Bright mint accent
static const float DURATION = 0.45;

static float
sdRect(float2 p, float2 center, float2 halfSize) {
    float2 d = abs(p - center) - halfSize;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

static float
seg(float2 p, float2 a, float2 b, inout float s, float d) {
    float2 e = b - a;
    float2 w = p - a;
    float2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(p - proj, p - proj));
    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    s *= lerp(1.0, -1.0, step(0.5, allCond + noneCond));
    return d;
}

static float
sdParallelogram(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);
    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);
    return s * sqrt(d);
}

// 0 for diagonal up-left/down-right movement, 1 otherwise — picks which corner
// of the parallelogram aligns with the direction of travel.
static float
startVertexFactor(float2 c, float2 p) {
    float cond1 = step(p.x, c.x) * step(c.y, p.y);
    float cond2 = step(c.x, p.x) * step(p.y, c.y);
    return 1.0 - max(cond1, cond2);
}

static float
isLess(float c, float p) { return 1.0 - step(p, c); }

static float
ease(float x) { return pow(1.0 - x, 3.0); }

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (d.cursor_trail_state <= 0.0) return color;

    // Work in pixel space so distances/antialiasing look right on any aspect ratio.
    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 px = t.pos * pixelDims;

    float2 curSize = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                             d.cursor_trail_edge.z - d.cursor_trail_edge.w) * pixelDims;
    float2 curPos = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.z) * pixelDims; // top-left, y-up (UV) convention
    float2 prevSize = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                              d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * pixelDims;
    float2 prevPos = float2(d.cursor_trail_prev_edge.x, d.cursor_trail_prev_edge.z) * pixelDims;

    // cursor_trail_edge is already in the same y-up, origin-bottom-left convention
    // the original shader's iCurrentCursor uses — no axis flip needed; subtracting
    // size.y below moves down towards the bottom, matching the original 1:1.
    float2 centerCC = float2(curPos.x + curSize.x * 0.5, curPos.y - curSize.y * 0.5);
    float2 centerCP = float2(prevPos.x + prevSize.x * 0.5, prevPos.y - prevSize.y * 0.5);

    float vf = startVertexFactor(curPos, prevPos);
    float ivf = 1.0 - vf;
    float xFactor = isLess(prevPos.x, curPos.x);
    float yFactor = isLess(curPos.y, prevPos.y);

    float2 v0 = float2(curPos.x + curSize.x * vf, curPos.y - curSize.y);
    float2 v1 = float2(curPos.x + curSize.x * xFactor, curPos.y - curSize.y * yFactor);
    float2 v2 = float2(curPos.x + curSize.x * ivf, curPos.y);
    float2 v3 = centerCP;

    float sdfCursor = sdRect(px, curPos + float2(curSize.x * 0.5, -curSize.y * 0.5), curSize * 0.5);
    float sdfTrail = sdParallelogram(px, v0, v1, v2, v3);

    float progress = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);
    float lineLength = length(centerCC - centerCP);

    float modTrail = 2.0; // pixel-space equivalent of the original's 0.007 in normalized space

    float4 trail = lerp(TRAIL_COLOR_ACCENT, color, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 2.0));
    trail = lerp(TRAIL_COLOR, trail, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 1.8));
    trail = lerp(trail, TRAIL_COLOR, step(sdfTrail + modTrail, 0.0));

    trail = lerp(TRAIL_COLOR_ACCENT, trail, 1.0 - smoothstep(0.0, sdfCursor + 1.0, 1.5));
    trail = lerp(TRAIL_COLOR, trail, 1.0 - smoothstep(0.0, sdfCursor + 1.0, 1.5));

    return lerp(trail, color, 1.0 - smoothstep(0.0, sdfCursor, easedProgress * lineLength));
}
