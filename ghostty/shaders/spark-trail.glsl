// Spark trail — procedural ember/spark burst along the cursor's movement path.
// Original effect for cursor-blaze (not a port), written to match the uniform
// conventions of the other shaders in this repo (iCurrentCursor/iPreviousCursor/
// iTime/iTimeCursorChange/iFocus).
//
// Each spark is reconstructed analytically every frame from its index and the
// time since the cursor last moved (fragment shaders have no persistent state,
// so there's no real particle buffer): a pseudo-random seed picks its spawn
// point along the previous->current cursor line, launch angle/speed, size and
// a small birth delay so they don't all pop/fade in lockstep. Gravity bends
// each spark's path into a falling arc. Each spark is rendered as a small hot
// core plus a longer glow streaked along its *instantaneous* velocity
// direction (so the streak itself bends through the arc, not just a straight
// line) — that streak plus a hot-core/cold-tail three-stop color ramp and a
// fast flicker is what sells "flying ember" instead of a soft floating dot.

vec2 getRectangleCenter(in vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.0), rectangle.y - (rectangle.w / 2.0));
}

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

const int NUM_SPARKS = 16;
const float DURATION = 0.65;
const float GRAVITY = 70.0;
const float MIN_SPEED = 40.0;
const float MAX_SPEED = 140.0;
const float MIN_SIZE = 0.9;
const float MAX_SIZE = 2.0;
const float MAX_DELAY_FRAC = 0.35; // fraction of DURATION a spark's birth can be staggered by
const float CORE_BRIGHTNESS = 3.0;
const float STREAK_BRIGHTNESS = 1.1;
const float INTENSITY = 1.35; // overall punch before clamping to LDR

vec3 emberColor(float t) {
    // white-hot -> yellow -> orange -> dark red as the spark ages (t: 0..1)
    vec3 c1 = vec3(1.0, 0.98, 0.92);
    vec3 c2 = vec3(1.0, 0.80, 0.25);
    vec3 c3 = vec3(1.0, 0.35, 0.05);
    vec3 c4 = vec3(0.35, 0.04, 0.01);
    vec3 col = mix(c1, c2, smoothstep(0.0, 0.28, t));
    col = mix(col, c3, smoothstep(0.28, 0.62, t));
    col = mix(col, c4, smoothstep(0.62, 1.0, t));
    return col;
}

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
        float r5 = hash(seed + 2.02);

        float delay = r4 * MAX_DELAY_FRAC;
        float localAge = (age - delay) / max(1.0 - delay, 0.001);
        if (localAge <= 0.0 || localAge >= 1.0) {
            continue;
        }

        vec2 basePos = mix(previousCenter, currentCenter, r0);

        float angle = r1 * 6.2831853;
        float speed = mix(MIN_SPEED, MAX_SPEED, r2);
        vec2 launchDir = vec2(cos(angle), sin(angle));

        // Position and instantaneous velocity (derivative of position wrt localAge)
        // under constant launch velocity plus downward gravity — this makes the
        // streak orientation itself curve through the falling arc.
        vec2 sparkPos = basePos + launchDir * speed * localAge + vec2(0.0, -GRAVITY * localAge * localAge);
        vec2 velocity = launchDir * speed + vec2(0.0, -2.0 * GRAVITY * localAge);
        float velLen = max(length(velocity), 0.001);
        vec2 tangent = velocity / velLen;
        vec2 normal = vec2(-tangent.y, tangent.x);

        float fade = (1.0 - localAge);
        float size = mix(MIN_SIZE, MAX_SIZE, r3) * fade;
        float speedNorm = (speed - MIN_SPEED) / max(MAX_SPEED - MIN_SPEED, 0.001);
        float streakLen = mix(4.0, 16.0, speedNorm) * fade;
        float flicker = 0.75 + 0.25 * sin(iTime * 40.0 + seed * 17.0);

        vec2 rel = px - sparkPos;
        float along = dot(rel, tangent);
        float across = dot(rel, normal);

        // Streak: stretched behind the direction of travel, tight ahead of it.
        float alongNorm = along < 0.0 ? (-along / streakLen) : (along / (size * 1.5));
        float acrossNorm = across / size;
        float streak = exp(-(alongNorm * alongNorm + acrossNorm * acrossNorm));

        // Small bright core exactly at the spark's current position.
        float core = exp(-(along * along + across * across) / (size * size));

        float glow = (core * CORE_BRIGHTNESS + streak * STREAK_BRIGHTNESS) * fade * flicker;
        vec3 sparkColor = emberColor(localAge);
        accumColor += sparkColor * glow * (0.6 + 0.4 * r5);
    }

    fragColor.rgb = clamp(fragColor.rgb + accumColor * INTENSITY, 0.0, 1.0);

    // Don't draw sparks over the cursor block itself.
    vec2 halfSize = iCurrentCursor.zw * 0.5;
    vec2 d = abs(px - currentCenter) - halfSize;
    float sdfCursor = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    fragColor.rgb = mix(fragColor.rgb, texture(iChannel0, fragCoord.xy / iResolution.xy).rgb, step(sdfCursor, 0.0));
}
