#language slang 2026
// Fresh, literal kitty Slang port of "cursor.glsl" (hexagonal cursor trail,
// colored with the terminal's actual cursor color) from
// https://github.com/stephin-develops/linux-ricing — unmodified upstream copy
// kept at ghostty/shaders/cursor.glsl in this repo. Translated function-for-
// function and line-for-line from that file, working in the same normalized
// (divide-by-viewport-height) coordinate space the original uses.
// Ghostty's iCurrentCursorColor maps to kitty's d.cursor_color.

import kitty_custom_shader_types;

static const float DURATION = 0.3;

// Process each edge: compute distance and determine if point is inside
static void
processEdge(float2 p, float2 a, float2 b, inout float minDist, inout float inside) {
    float2 edge = b - a;
    float2 pa = p - a;
    float lenSq = dot(edge, edge);
    float invLenSq = 1.0 / lenSq;

    float t = clamp(dot(pa, edge) * invLenSq, 0.0, 1.0);
    float2 diff = pa - edge * t;
    minDist = min(minDist, dot(diff, diff));

    float cr = edge.x * pa.y - edge.y * pa.x;
    inside = min(inside, step(0.0, cr));
}

// Signed distance field for hexagon (negative inside, positive outside)
// Vertices must be in counter-clockwise order
static float
sdHexagon(float2 p, float2 v0, float2 v1, float2 v2, float2 v3, float2 v4, float2 v5) {
    float minDist = 1e20;
    float inside = 1.0;

    processEdge(p, v0, v1, minDist, inside);
    processEdge(p, v1, v2, minDist, inside);
    processEdge(p, v2, v3, minDist, inside);
    processEdge(p, v3, v4, minDist, inside);
    processEdge(p, v4, v5, minDist, inside);
    processEdge(p, v5, v0, minDist, inside);

    float dist = sqrt(max(minDist, 0.0));
    return lerp(dist, -dist, inside);
}

// Signed distance field for rectangle (negative inside, positive outside)
static float
sdRectangle(float2 p, float2 center, float2 halfSize) {
    float2 d = abs(p - center) - halfSize;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

// Represents cursor as a quad with four corners
struct Quad {
    float2 topLeft;
    float2 topRight;
    float2 bottomLeft;
    float2 bottomRight;
};

// Construct quad from top-left position and size
static Quad
getQuad(float2 pos, float2 size) {
    Quad q;
    q.topLeft = pos;
    q.topRight = pos + float2(size.x, 0.0);
    q.bottomLeft = pos - float2(0.0, size.y);
    q.bottomRight = pos + float2(size.x, -size.y);
    return q;
}

// Select 3 corners from quad based on movement direction
// sel.x: 0=left, 1=right | sel.y: 0=top, 1=bottom
// Returns corners in counter-clockwise order for hexagon construction
static void
selectTrailCorners(Quad q, float2 sel, out float2 p1, out float2 p2, out float2 p3) {
    p1 = lerp(lerp(q.topRight, q.topLeft, sel.x),
              lerp(q.bottomRight, q.bottomLeft, sel.x),
              sel.y);

    p2 = lerp(lerp(q.topLeft, q.bottomLeft, sel.x),
              lerp(q.topRight, q.bottomRight, sel.x),
              sel.y);
    p3 = lerp(lerp(q.bottomRight, q.topRight, sel.x),
              lerp(q.bottomLeft, q.topLeft, sel.x),
              sel.y);
}

// Select 4 corners from quad based on movement direction
static void
selectCorners(Quad q, float2 sel, out float2 p1, out float2 p2, out float2 p3, out float2 p4) {
    selectTrailCorners(q, sel, p1, p2, p3);

    p4 = lerp(lerp(q.bottomLeft, q.bottomRight, sel.x),
              lerp(q.topLeft, q.topRight, sel.x),
              sel.y);
}

// Cubic ease-out function for smooth animation (expects clamped input)
static float
easeClamped(float x) {
    float t = 1.0 - x;
    return 1.0 - t * t * t;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // Calculate animation progress with easing
    float baseProgress = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);

    // No 1:1 equivalent of the original's iFocus check exists in
    // KittyCustomShaderData; cursor_trail_state covers kitty's own "is the trail
    // actually animating" gate instead.
    if (d.cursor_trail_state <= 0.0 || baseProgress >= 1.0) {
        return color;
    }

    float2 res = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 fragCoord = t.pos * res;

    // Precompute reused values
    float invResY = 1.0 / res.y;
    float scale = 2.0 * invResY;
    float aaWidth = scale;
    float2 normOffset = res * invResY;

    // cursor_trail_edge/_prev_edge: .x=left, .y=right, .z=top, .w=bottom, UV
    // (origin bottom-left, y up) — the same axis convention the original's
    // iCurrentCursor/iPreviousCursor pixel coordinates use, so build the
    // equivalent (left, top, width, height) pixel vector before normalizing.
    float2 curXY = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.z) * res;
    float2 curZW = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                           d.cursor_trail_edge.z - d.cursor_trail_edge.w) * res;
    float2 prevXY = float2(d.cursor_trail_prev_edge.x, d.cursor_trail_prev_edge.z) * res;
    float2 prevZW = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                            d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * res;

    // Normalize cursor positions and sizes to screen-independent coordinates
    float2 currentPos = curXY * scale - normOffset;
    float2 previousPos = prevXY * scale - normOffset;
    float2 currentSize = curZW * scale;
    float2 previousSize = prevZW * scale;

    // Determine movement direction and construct cursor quads
    float2 deltaPos = currentPos - previousPos;
    Quad currentCursor = getQuad(currentPos, currentSize);
    Quad previousCursor = getQuad(previousPos, previousSize);
    float2 selector = step(float2(0.0), deltaPos);

    // Select corners based on movement direction
    float2 currP1, currP2, currP3, currP4;
    float2 prevP1, prevP2, prevP3;
    selectCorners(currentCursor, selector, currP1, currP2, currP3, currP4);
    selectTrailCorners(previousCursor, selector, prevP1, prevP2, prevP3);

    float easedProgress = easeClamped(baseProgress);
    float stretchedProgress = min(baseProgress * 2.0, 1.0);
    float easedProgressDouble = easeClamped(stretchedProgress);

    // Create trailing effect by moving diagonal point slower
    float2 trailP1 = lerp(prevP1, currP1, easedProgress);
    float2 trailP2 = lerp(prevP2, currP2, easedProgressDouble);
    float2 trailP3 = lerp(prevP3, currP3, easedProgressDouble);

    // Compute hexagon SDF and convert to alpha with antialiasing
    float2 normCoord = fragCoord * scale - normOffset;
    float sdfHex = sdHexagon(normCoord, trailP1, trailP2, currP2, currP4, currP3, trailP3);
    float alpha = 1.0 - smoothstep(-aaWidth, aaWidth, sdfHex);

    // Compute current cursor SDF
    float2 halfCurrentSize = currentSize * 0.5;
    float2 currentCenter = currentPos + float2(halfCurrentSize.x, -halfCurrentSize.y);
    float sdfCurrentCursor = sdRectangle(normCoord, currentCenter, halfCurrentSize);

    // Enhance color saturation for more vibrant trail effect
    float4 cursorColor = d.cursor_color;
    float gray = dot(cursorColor.rgb, float3(0.299, 0.587, 0.114));
    static const float saturationBoost = 1.8;
    float4 enhancedColor = clamp(
        lerp(float4(float3(gray, gray, gray), cursorColor.a), cursorColor, saturationBoost),
        0.0, 1.0
    );

    // Blend trail color with background
    float4 originalColor = color;
    float4 result = color;
    result.rgb = lerp(result.rgb, enhancedColor.rgb, alpha);

    // Remove trail where it overlaps with current cursor
    result.rgb = lerp(result.rgb, originalColor.rgb, step(sdfCurrentCursor, 0.0));

    return result;
}
