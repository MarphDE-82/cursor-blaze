// Spark trail — procedural ember/spark burst along the cursor's movement path.
// Original effect for cursor-blaze (not a port), written to match the uniform
// conventions of the other shaders in this repo (iCurrentCursor/iPreviousCursor/
// iTime/iTimeCursorChange/iFocus).
//
// Fragment shaders have no persistent state, so there's no real particle buffer —
// each of NUM_SPARKS "sparks" is instead reconstructed analytically every frame
// from its index and the time since the cursor last moved: a pseudo-random seed
// picks its spawn point along the previous->current cursor line, its outward
// launch angle/speed, its size, and a small per-spark start delay so they don't
// all pop and fade in lockstep. A slight downward "gravity" term bends each
// spark's path into a small falling arc as it flies out and fades.

vec2 getRectangleCenter(in vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.0), rectangle.y - (rectangle.w / 2.0));
}

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

const int NUM_SPARKS = 14;
const float DURATION = 0.6;
const float GRAVITY = 60.0;
const float MIN_SPEED = 25.0;
const float MAX_SPEED = 110.0;
const float MIN_SIZE = 1.4;
const float MAX_SIZE = 3.6;
const float MAX_DELAY_FRAC = 0.35; // fraction of DURATION a spark's birth can be staggered by
const vec3 COLOR_HOT = vec3(1.0, 0.95, 0.72);   // white-yellow, freshly launched
const vec3 COLOR_COLD = vec3(1.0, 0.22, 0.04);  // ember orange-red, about to die

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);

    if (iFocus == 0) {
        return;
    }

    float age = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    if (age >= 1.0) {
        return;
    }

    vec2 px = fragCoord.xy;
    vec2 currentCenter = getRectangleCenter(iCurrentCursor);
    vec2 previousCenter = getRectangleCenter(iPreviousCursor);

    // Distinct seed base per cursor-move event so repeated jumps don't look identical.
    float eventSeed = fract(iTimeCursorChange * 13.37) * 1000.0;

    vec3 accumColor = vec3(0.0);

    for (int i = 0; i < NUM_SPARKS; i++) {
        float seed = eventSeed + float(i) * 7.919;
        float r0 = hash(seed);
        float r1 = hash(seed + 0.37);
        float r2 = hash(seed + 0.71);
        float r3 = hash(seed + 1.13);
        float r4 = hash(seed + 1.53);

        // When this spark is born, relative to the overall trail age.
        float delay = r4 * MAX_DELAY_FRAC;
        float localAge = (age - delay) / max(1.0 - delay, 0.001);
        if (localAge <= 0.0 || localAge >= 1.0) {
            continue;
        }

        // Spawn point: somewhere along the path the cursor just travelled.
        vec2 basePos = mix(previousCenter, currentCenter, r0);

        // Outward scatter in a random direction, with a falling arc over its life.
        float angle = r1 * 6.2831853;
        float speed = mix(MIN_SPEED, MAX_SPEED, r2);
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 offset = dir * speed * localAge;
        offset.y -= GRAVITY * localAge * localAge;

        vec2 sparkPos = basePos + offset;
        float size = mix(MIN_SIZE, MAX_SIZE, r3) * (1.0 - localAge);

        float dist = length(px - sparkPos);
        float glow = exp(-(dist * dist) / (2.0 * size * size)) * (1.0 - localAge);

        vec3 sparkColor = mix(COLOR_HOT, COLOR_COLD, localAge);
        accumColor += sparkColor * glow;
    }

    fragColor.rgb = clamp(fragColor.rgb + accumColor, 0.0, 1.0);

    // Don't draw sparks over the cursor block itself.
    vec2 halfSize = iCurrentCursor.zw * 0.5;
    vec2 d = abs(px - currentCenter) - halfSize;
    float sdfCursor = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    fragColor.rgb = mix(fragColor.rgb, texture(iChannel0, fragCoord.xy / iResolution.xy).rgb, step(sdfCursor, 0.0));
}
