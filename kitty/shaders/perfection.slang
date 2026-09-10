#language slang 2026
// Kitty port of "perfection.glsl" (neon pink -> blue -> teal gradient cursor trail)
// from https://github.com/stephin-develops/linux-ricing/tree/main/ghostty
// Same parallelogram/SDF trail as ghostty-slasher.slang, but the fill color is an
// animated gradient based on how far along the trail (previous -> current cursor) a
// pixel sits, matching the original's getGradientColor().

import kitty_custom_shader_types;

static const float4 COLOR_PINK = float4(1.000, 0.000, 0.400, 1.0);
static const float4 COLOR_BLUE = float4(0.000, 0.400, 1.000, 1.0);
static const float4 COLOR_TEAL = float4(0.000, 1.000, 0.800, 1.0);
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

// pos 0.0 = trail head (previous cursor, pink) -> 1.0 = current cursor (teal)
static float4
gradientColor(float t) {
    float scaledT = t * 2.0;
    float4 col = lerp(COLOR_PINK, COLOR_BLUE, clamp(scaledT, 0.0, 1.0));
    col = lerp(col, COLOR_TEAL, clamp(scaledT - 1.0, 0.0, 1.0));
    return col;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (d.cursor_trail_state <= 0.0) return color;

    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 px = t.pos * pixelDims;

    float2 curSize = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                             d.cursor_trail_edge.z - d.cursor_trail_edge.w) * pixelDims;
    float2 curPos = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.z) * pixelDims;
    float2 prevSize = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                              d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * pixelDims;
    float2 prevPos = float2(d.cursor_trail_prev_edge.x, d.cursor_trail_prev_edge.z) * pixelDims;

    curPos.y = pixelDims.y - curPos.y;
    prevPos.y = pixelDims.y - prevPos.y;
    float2 pxFlipped = float2(px.x, pixelDims.y - px.y);

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

    // Project this pixel onto the trail line to find its 0..1 gradient position.
    float lineDistSq = dot(centerCC - centerCP, centerCC - centerCP);
    float tGrad = 1.0;
    if (lineDistSq > 0.0001) {
        float2 dir = centerCC - centerCP;
        float2 w = pxFlipped - centerCP;
        tGrad = clamp(dot(w, dir) / lineDistSq, 0.0, 1.0);
    }
    float4 dynTrail = gradientColor(tGrad);
    float4 dynAccent = lerp(dynTrail, float4(1.0), 0.5);

    float sdfCursor = sdRect(pxFlipped, curPos + float2(curSize.x * 0.5, -curSize.y * 0.5), curSize * 0.5);
    float sdfTrail = sdParallelogram(pxFlipped, v0, v1, v2, v3);

    float progress = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);
    float lineLength = length(centerCC - centerCP);

    float modTrail = 2.0;

    float4 trail = lerp(dynAccent, color, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 2.0));
    trail = lerp(dynTrail, trail, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 1.8));
    trail = lerp(trail, dynTrail, step(sdfTrail + modTrail, 0.0));

    trail = lerp(dynAccent, trail, 1.0 - smoothstep(0.0, sdfCursor + 1.0, 1.5));
    trail = lerp(dynTrail, trail, 1.0 - smoothstep(0.0, sdfCursor + 1.0, 1.5));

    return lerp(trail, color, 1.0 - smoothstep(0.0, sdfCursor, easedProgress * lineLength));
}
