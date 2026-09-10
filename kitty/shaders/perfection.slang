#language slang 2026
// Fresh, literal kitty Slang port of "perfection.glsl" (neon pink -> blue -> teal
// gradient cursor trail) from https://github.com/stephin-develops/linux-ricing
// — unmodified upstream copy kept at ghostty/shaders/perfection.glsl in this repo.
// Translated function-for-function and line-for-line from that file, working in
// the same normalized (divide-by-viewport-height) coordinate space the original
// uses via its norm() helper, instead of re-derived pixel-space constants — so
// DURATION/modTrail etc. below are the original's literal values, unchanged.

import kitty_custom_shader_types;

static const float4 COLOR_PINK = float4(1.000, 0.000, 0.400, 1.0);
static const float4 COLOR_BLUE = float4(0.000, 0.400, 1.000, 1.0);
static const float4 COLOR_TEAL = float4(0.000, 1.000, 0.800, 1.0);
static const float DURATION = 0.45;

static float
getSdfRectangle(float2 p, float2 xy, float2 b) {
    float2 d = abs(p - xy) - b;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

// Distance function for a line segment, optimized for branchless execution
static float
seg(float2 p, float2 a, float2 b, inout float s, float d) {
    float2 e = b - a;
    float2 w = p - a;
    float2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);

    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);

    float flip = lerp(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;

    return d;
}

static float
getSdfParallelogram(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

// Normalizes coordinates to a -1 to 1 space
static float2
norm(float2 value, float isPosition, float2 res) {
    return (value * 2.0 - res * isPosition) / res.y;
}

static float
determineStartVertexFactor(float2 c, float2 p) {
    float condition1 = step(p.x, c.x) * step(c.y, p.y); // c.x <= p.x && c.y >= p.y
    float condition2 = step(c.x, p.x) * step(p.y, c.y); // c.x >= p.x && c.y <= p.y
    return 1.0 - max(condition1, condition2);
}

static float
isLess(float c, float p) { return 1.0 - step(p, c); }

static float2
getRectangleCenter(float4 rectangle) {
    return float2(rectangle.x + rectangle.z / 2.0, rectangle.y - rectangle.w / 2.0);
}

static float
ease(float x) { return pow(1.0 - x, 3.0); }

// Calculates the color based on the position 't' (0.0 to 1.0) along the trail
static float4
getGradientColor(float t) {
    float scaledT = t * 2.0;
    float4 col = lerp(COLOR_PINK, COLOR_BLUE, clamp(scaledT, 0.0, 1.0));
    col = lerp(col, COLOR_TEAL, clamp(scaledT - 1.0, 0.0, 1.0));
    return col;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // No 1:1 equivalent of the original's iFocus check exists in
    // KittyCustomShaderData; cursor_trail_state covers kitty's own "is the trail
    // actually animating" gate instead.
    if (d.cursor_trail_state <= 0.0) return color;

    float2 res = float2(d.viewport_size_pixels) * t.viewport.zw;

    // fragCoord equivalent: t.pos is UV (origin bottom-left, y up), same axis
    // convention as GLSL's fragCoord, so scaling by res is a direct match.
    float2 fragCoord = t.pos * res;
    float2 vu = norm(fragCoord, 1.0, res);
    float2 offsetFactor = float2(-0.5, 0.5);

    // cursor_trail_edge/_prev_edge: .x=left, .y=right, .z=top, .w=bottom, UV
    // (origin bottom-left, y up) — the same axis convention the original's
    // iCurrentCursor/iPreviousCursor pixel coordinates use, so build the
    // equivalent (left, top, width, height) pixel vector and normalize with
    // the same norm() the original applies to iCurrentCursor/iPreviousCursor.
    float2 curXY = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.z) * res;
    float2 curZW = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                           d.cursor_trail_edge.z - d.cursor_trail_edge.w) * res;
    float2 prevXY = float2(d.cursor_trail_prev_edge.x, d.cursor_trail_prev_edge.z) * res;
    float2 prevZW = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                            d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * res;

    float4 currentCursor = float4(norm(curXY, 1.0, res), norm(curZW, 0.0, res));
    float4 previousCursor = float4(norm(prevXY, 1.0, res), norm(prevZW, 0.0, res));

    float2 centerCC = getRectangleCenter(currentCursor);
    float2 centerCP = getRectangleCenter(previousCursor);

    // Determine parallelogram vertices
    float vertexFactor = determineStartVertexFactor(currentCursor.xy, previousCursor.xy);
    float invertedVertexFactor = 1.0 - vertexFactor;

    float xFactor = isLess(previousCursor.x, currentCursor.x);
    float yFactor = isLess(currentCursor.y, previousCursor.y);

    float2 v0 = float2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    float2 v1 = float2(currentCursor.x + currentCursor.z * xFactor, currentCursor.y - currentCursor.w * yFactor);
    float2 v2 = float2(currentCursor.x + currentCursor.z * invertedVertexFactor, currentCursor.y);
    float2 v3 = centerCP;

    // --- GRADIENT CALCULATION ---
    // Project the current pixel onto the trail line to find its 0.0->1.0 location
    float lineDistSq = dot(centerCC - centerCP, centerCC - centerCP);
    float tGrad = 1.0; // Default to head color (Teal) if stationary

    if (lineDistSq > 0.0001) {
        float2 dir = centerCC - centerCP;
        float2 w = vu - centerCP;
        tGrad = clamp(dot(w, dir) / lineDistSq, 0.0, 1.0);
    }

    // Fetch gradient color for this specific pixel and calculate accent
    float4 dynamicTrailColor = getGradientColor(tGrad);
    float4 dynamicAccentColor = lerp(dynamicTrailColor, float4(1.0), 0.5); // Brightened core

    // Calculate Signed Distance Fields
    float sdfCurrentCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
    float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

    // Calculate animations
    float progress = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);
    float lineLength = distance(centerCC, centerCP);

    // Compositing the trail and cursor blaze using our dynamic gradient colors
    float modTrail = 0.007;

    // Trail blaze
    float4 trail = lerp(dynamicAccentColor, color, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 0.007));
    trail = lerp(dynamicTrailColor, trail, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 0.006));
    trail = lerp(trail, dynamicTrailColor, step(sdfTrail + modTrail, 0.0));

    // Cursor blaze
    trail = lerp(dynamicAccentColor, trail, 1.0 - smoothstep(0.0, sdfCurrentCursor + 0.002, 0.004));
    trail = lerp(dynamicTrailColor, trail, 1.0 - smoothstep(0.0, sdfCurrentCursor + 0.002, 0.004));

    // Final composite onto base terminal texture
    return lerp(trail, color, 1.0 - smoothstep(0.0, sdfCurrentCursor, easedProgress * lineLength));
}
