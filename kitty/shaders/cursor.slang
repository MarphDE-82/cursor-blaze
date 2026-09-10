#language slang 2026
// Kitty port of "cursor.glsl" (hexagonal cursor trail, colored with the terminal's
// actual cursor color) from
// https://github.com/stephin-develops/linux-ricing/tree/main/ghostty
// Ghostty's iCurrentCursorColor maps to kitty's d.cursor_color.

import kitty_custom_shader_types;

static const float DURATION = 0.3;
static const float SATURATION_BOOST = 1.8;

struct Quad { float2 topLeft, topRight, bottomLeft, bottomRight; };

static Quad
makeQuad(float2 pos, float2 size) {
    Quad q;
    q.topLeft = pos;
    q.topRight = pos + float2(size.x, 0.0);
    q.bottomLeft = pos - float2(0.0, size.y);
    q.bottomRight = pos + float2(size.x, -size.y);
    return q;
}

// sel.x: 0=left,1=right  sel.y: 0=top,1=bottom -> 3 corners, counter-clockwise
static void
selectTrailCorners(Quad q, float2 sel, out float2 p1, out float2 p2, out float2 p3) {
    p1 = lerp(lerp(q.topRight, q.topLeft, sel.x), lerp(q.bottomRight, q.bottomLeft, sel.x), sel.y);
    p2 = lerp(lerp(q.topLeft, q.bottomLeft, sel.x), lerp(q.topRight, q.bottomRight, sel.x), sel.y);
    p3 = lerp(lerp(q.bottomRight, q.topRight, sel.x), lerp(q.bottomLeft, q.topLeft, sel.x), sel.y);
}

static void
selectCorners(Quad q, float2 sel, out float2 p1, out float2 p2, out float2 p3, out float2 p4) {
    selectTrailCorners(q, sel, p1, p2, p3);
    p4 = lerp(lerp(q.bottomLeft, q.bottomRight, sel.x), lerp(q.topLeft, q.topRight, sel.x), sel.y);
}

static float
easeClamped(float x) {
    float t = 1.0 - x;
    return 1.0 - t * t * t;
}

static float
sdRect(float2 p, float2 center, float2 halfSize) {
    float2 d = abs(p - center) - halfSize;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

static void
processEdge(float2 p, float2 a, float2 b, inout float minDist, inout float inside) {
    float2 edge = b - a;
    float2 pa = p - a;
    float invLenSq = 1.0 / dot(edge, edge);
    float t = clamp(dot(pa, edge) * invLenSq, 0.0, 1.0);
    float2 diff = pa - edge * t;
    minDist = min(minDist, dot(diff, diff));
    float cr = edge.x * pa.y - edge.y * pa.x;
    inside = min(inside, step(0.0, cr));
}

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

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float baseProgress = clamp((d.timestamp - d.cursor_trail_change_time) / DURATION, 0.0, 1.0);
    if (d.cursor_trail_state <= 0.0 || baseProgress >= 1.0) return color;

    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float invResY = 1.0 / pixelDims.y;
    float scale = 2.0 * invResY;
    float aaWidth = scale;
    float2 normOffset = pixelDims * invResY;

    // cursor_trail_edge is UV (origin bottom-left, y up), same convention as the
    // original algorithm's top-left-corner-minus-height math expects — no axis
    // flip, and both components must be scaled by pixelDims (not just x).
    float2 curPosPx = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.z) * pixelDims;
    float2 curSizePx = float2(d.cursor_trail_edge.y - d.cursor_trail_edge.x,
                               d.cursor_trail_edge.z - d.cursor_trail_edge.w) * pixelDims;
    float2 prevPosPx = float2(d.cursor_trail_prev_edge.x, d.cursor_trail_prev_edge.z) * pixelDims;
    float2 prevSizePx = float2(d.cursor_trail_prev_edge.y - d.cursor_trail_prev_edge.x,
                                d.cursor_trail_prev_edge.z - d.cursor_trail_prev_edge.w) * pixelDims;

    float2 currentPos = curPosPx * scale - normOffset;
    float2 previousPos = prevPosPx * scale - normOffset;
    float2 currentSize = curSizePx * scale;
    float2 previousSize = prevSizePx * scale;

    float2 deltaPos = currentPos - previousPos;
    Quad currentCursor = makeQuad(currentPos, currentSize);
    Quad previousCursor = makeQuad(previousPos, previousSize);
    float2 selector = step(float2(0.0), deltaPos);

    float2 currP1, currP2, currP3, currP4;
    float2 prevP1, prevP2, prevP3;
    selectCorners(currentCursor, selector, currP1, currP2, currP3, currP4);
    selectTrailCorners(previousCursor, selector, prevP1, prevP2, prevP3);

    float easedProgress = easeClamped(baseProgress);
    float stretchedProgress = min(baseProgress * 2.0, 1.0);
    float easedProgressDouble = easeClamped(stretchedProgress);

    float2 trailP1 = lerp(prevP1, currP1, easedProgress);
    float2 trailP2 = lerp(prevP2, currP2, easedProgressDouble);
    float2 trailP3 = lerp(prevP3, currP3, easedProgressDouble);

    float2 px = t.pos * pixelDims;
    float2 normCoord = px * scale - normOffset;

    float sdfHex = sdHexagon(normCoord, trailP1, trailP2, currP2, currP4, currP3, trailP3);
    float alpha = 1.0 - smoothstep(-aaWidth, aaWidth, sdfHex);

    float2 halfCurrentSize = currentSize * 0.5;
    float2 currentCenter = currentPos + float2(halfCurrentSize.x, -halfCurrentSize.y);
    float sdfCurrentCursor = sdRect(normCoord, currentCenter, halfCurrentSize);

    float4 cursorColor = d.cursor_color;
    float gray = dot(cursorColor.rgb, float3(0.299, 0.587, 0.114));
    float4 enhancedColor = clamp(lerp(float4(float3(gray, gray, gray), cursorColor.a), cursorColor, SATURATION_BOOST), 0.0, 1.0);

    float4 originalColor = color;
    float4 result = color;
    result.rgb = lerp(result.rgb, enhancedColor.rgb, alpha);
    result.rgb = lerp(result.rgb, originalColor.rgb, step(sdfCurrentCursor, 0.0));
    return result;
}
