#version 300 es

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uRes;
uniform float uTime;

out vec4 fragColor;

// ============================================================
// TUNABLES -- safe to adjust without touching the logic below.
// ============================================================
const float CYCLE_LEN      = 180.0;  // seconds for one full day -> night -> day loop
const float SUN_ZENITH_Y   = 0.62;   // sun height at noon
const float SUN_PEEK_Y     = -0.20;  // sun never sinks below this -- always a horizon sliver
const float MOON_ZENITH_Y  = 0.56;   // moon height at the dead of night
const float MOON_PEEK_Y    = -0.18;  // moon never sinks below this
const float ORB_RADIUS     = 0.070;  // sun/moon disc radius
const float ORB_SWEEP      = 0.92;   // horizontal travel range (fraction of half-width)

const float RAIN_CYCLE_LEN = 540.0;  // a storm rolls through roughly every 9 minutes
const float RAIN_START     = 226.0;  // where in the weather cycle the rain begins
const float RAIN_DURATION  = 46.0;   // how long the rain itself lasts
const float RAIN_FADE      = 6.0;    // seconds to fade the rain in/out
const float PUDDLE_FILL    = 28.0;   // seconds for puddles to visibly fill once rain starts
const float PUDDLE_DRAIN   = 70.0;   // seconds for puddles to drain after rain ends

const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

// ============================================================
// Noise utilities
// ============================================================
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {
        v += amp * noise(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return v;
}

// ============================================================
// Weather: deterministic rain + puddle envelope, a pure function
// of time so no extra uniforms are needed from the Dart side.
// Returns (rainIntensity, puddleLevel), both 0..1.
// ============================================================
vec2 weatherEnvelope(float t) {
    float cyclePos = mod(t, RAIN_CYCLE_LEN);

    float rainIn  = smoothstep(RAIN_START, RAIN_START + RAIN_FADE, cyclePos);
    float rainOut = 1.0 - smoothstep(RAIN_START + RAIN_DURATION - RAIN_FADE, RAIN_START + RAIN_DURATION, cyclePos);
    float rain = clamp(rainIn * rainOut, 0.0, 1.0);

    float puddleIn  = smoothstep(RAIN_START, RAIN_START + PUDDLE_FILL, cyclePos);
    float puddleOut = 1.0 - smoothstep(RAIN_START + RAIN_DURATION, RAIN_START + RAIN_DURATION + PUDDLE_DRAIN, cyclePos);
    float puddle = clamp(puddleIn * puddleOut, 0.0, 1.0);

    return vec2(rain, puddle);
}

// ============================================================
// A glowing celestial disc (used for both the sun and the moon)
// ============================================================
vec3 orbGlow(vec2 p, vec2 pos, float radius, vec3 core, vec3 glow, float glowSize) {
    float d = length(p - pos);
    float disc = smoothstep(radius, radius * 0.85, d);
    float halo = exp(-d * (1.0 / glowSize));
    return core * disc + glow * halo * (1.0 - disc);
}

// ============================================================
// A soft, drifting cloud layer
// ============================================================
float cloudLayer(vec2 p, float drift, float scale, float coverage) {
    vec2 cp = vec2(p.x + drift, p.y * 1.6);
    float n = fbm(cp * scale);
    float mask = smoothstep(coverage, coverage + 0.30, n);
    float band = smoothstep(-0.05, 0.15, p.y) * (1.0 - smoothstep(0.55, 0.75, p.y));
    return mask * band;
}

// ============================================================
// A single layer of falling, wind-slanted rain streaks
// ============================================================
float rainLayer(vec2 p, float speed, float density, float slant) {
    vec2 rp = p;
    rp.y += uTime * speed;
    rp.x += rp.y * slant;
    vec2 cell = floor(rp * density);
    vec2 f = fract(rp * density);
    float h = hash(cell + 500.0);
    if (h < 0.55) return 0.0;
    float cx = hash(cell + 5.0);
    float line = smoothstep(0.06, 0.0, abs(f.x - cx));
    float vert = smoothstep(0.0, 0.08, f.y) * smoothstep(1.0, 0.55, f.y);
    return line * vert;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Guard against zero resolution
    if (uRes.x < 1.0 || uRes.y < 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec2 uv = fragCoord / uRes;
    // Normalized centered coords, Y up
    vec2 p = (fragCoord - 0.5 * uRes) / uRes.y;

    // --- Day / night cycle -------------------------------------------
    float phase = mod(uTime, CYCLE_LEN) / CYCLE_LEN * TAU;
    float daylight = sin(phase) * 0.5 + 0.5;   // 0 = deepest night, 1 = noon
    float nightAmt = 1.0 - daylight;
    float goldenHour = clamp(1.0 - abs(daylight - 0.3) / 0.22, 0.0, 1.0);

    // --- Weather --------------------------------------------------------
    vec2 weather = weatherEnvelope(uTime);
    float rainAmt   = weather.x;
    float puddleAmt = weather.y;

    // --- Sky gradient: night blue-purple <-> day blue ------------------
    vec3 nightSkyBot = vec3(0.010, 0.015, 0.040);
    vec3 nightSkyTop = vec3(0.040, 0.030, 0.080);
    vec3 daySkyBot   = vec3(0.55, 0.72, 0.88);
    vec3 daySkyTop   = vec3(0.16, 0.40, 0.78);
    vec3 skyBot = mix(nightSkyBot, daySkyBot, daylight);
    vec3 skyTop = mix(nightSkyTop, daySkyTop, daylight);
    vec3 col = mix(skyBot, skyTop, uv.y);

    // Golden-hour tint low on the horizon, twice a cycle (dawn + dusk)
    col = mix(col, vec3(1.0, 0.55, 0.22), goldenHour * 0.30 * (1.0 - clamp(uv.y * 1.4, 0.0, 1.0)));

    // Storms dim and desaturate everything
    col *= mix(1.0, 0.68, rainAmt * 0.75);
    float grayAmt = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(grayAmt), rainAmt * 0.20);

    // --- Slow aurora-like bands (night only) ----------------------------
    float band1 = sin(p.x * 2.5 + uTime * 0.15) * 0.5 + 0.5;
    float band2 = sin(p.x * 1.8 - uTime * 0.12 + 1.5) * 0.5 + 0.5;
    float band3 = sin(p.x * 3.2 + uTime * 0.08 + 3.0) * 0.5 + 0.5;
    vec3 aurora = vec3(0.0);
    aurora += vec3(0.08, 0.25, 0.12) * band1 * smoothstep(0.1, 0.5, uv.y) * (1.0 - smoothstep(0.5, 0.9, uv.y));
    aurora += vec3(0.15, 0.08, 0.20) * band2 * smoothstep(0.15, 0.55, uv.y) * (1.0 - smoothstep(0.55, 0.85, uv.y));
    aurora += vec3(0.05, 0.12, 0.22) * band3 * smoothstep(0.2, 0.6, uv.y) * (1.0 - smoothstep(0.6, 0.8, uv.y));
    col += aurora * 0.4 * pow(nightAmt, 1.2) * (1.0 - rainAmt * 0.8);

    // --- Stars: each one wakes up on its own random schedule ------------
    // (Previously every star pulsed on the same continuous sine wave, which
    // reads as one predictable, synchronized heartbeat across the whole
    // sky. Now each star gets its own multi-second cycle length, its own
    // phase offset, and its own "on" duration, so they light up one by one
    // at irregular, unsynchronized moments instead of pulsing in lockstep.)
    vec2 starUV = p * 35.0;
    vec2 starCell = floor(starUV);
    vec2 starFrac = fract(starUV);
    float starHash = hash(starCell + 100.0);
    if (starHash > 0.985) {
        vec2 starPos = vec2(hash(starCell + 1.0), hash(starCell + 2.0));
        float dist = length(starFrac - starPos);
        float brightness = smoothstep(0.18, 0.0, dist);

        float cycleLen = 3.0 + hash(starCell + 50.0) * 5.0;               // 3-8s personal cycle
        float localT = mod(uTime + hash(starCell + 60.0) * 97.0, cycleLen);
        float onDur = 0.4 + hash(starCell + 70.0) * 1.2;                  // 0.4-1.6s "on" pulse
        float flicker = smoothstep(0.0, 0.15, localT) * (1.0 - smoothstep(onDur, onDur + 0.5, localT));
        float shimmer = 0.85 + 0.15 * sin(uTime * 9.0 + starHash * 40.0);

        col += vec3(0.9, 0.95, 1.0) * brightness * flicker * shimmer * nightAmt;
    }

    // Shooting star (rare, night only)
    float shootCycle = floor(uTime * 0.08);
    float shootSeed = hash(vec2(shootCycle, 0.0));
    if (shootSeed > 0.75) {
        float shootStart = shootSeed * 4.0;
        float shootT = uTime - shootCycle * 12.5 - shootStart;
        if (shootT > 0.0 && shootT < 1.2) {
            float sx = mix(-0.8, 0.6, shootT / 1.2);
            float sy = mix(0.4, 0.1, shootT / 1.2);
            float d = length(p - vec2(sx, sy));
            float trail = smoothstep(0.02, 0.0, d);
            col += vec3(1.0, 0.95, 0.85) * trail * (1.0 - shootT / 1.2) * nightAmt;
        }
    }

    // --- Sun: clamped orbit, never fully leaves the screen --------------
    float sunX = cos(phase) * ORB_SWEEP;
    float sunY = mix(SUN_PEEK_Y, SUN_ZENITH_Y, daylight);
    vec3 sunCore = mix(vec3(1.0, 0.96, 0.85), vec3(1.0, 0.55, 0.25), nightAmt * 0.7);
    vec3 sunGlowCol = vec3(1.0, 0.75, 0.35);
    float sunStrength = mix(0.35, 1.0, daylight);
    col += orbGlow(p, vec2(sunX, sunY), ORB_RADIUS, sunCore, sunGlowCol, 0.55) * sunStrength * (1.0 - rainAmt * 0.6);

    // --- Moon: opposite phase of the same orbit, same clamp -------------
    float moonX = -sunX;
    float moonY = mix(MOON_PEEK_Y, MOON_ZENITH_Y, nightAmt);
    vec3 moonCore = vec3(0.88, 0.90, 0.98);
    float moonTexture = noise((p - vec2(moonX, moonY)) * 9.0) * 0.06;
    moonCore -= vec3(moonTexture);
    vec3 moonGlowCol = vec3(0.55, 0.62, 0.85);
    float moonStrength = mix(0.35, 0.9, nightAmt);
    col += orbGlow(p, vec2(moonX, moonY), ORB_RADIUS * 0.92, moonCore, moonGlowCol, 0.42) * moonStrength * (1.0 - rainAmt * 0.5);

    // --- Clouds -----------------------------------------------------------
    float c1 = cloudLayer(p, uTime * 0.015, 1.7, mix(0.44, 0.30, rainAmt));
    float c2 = cloudLayer(p, uTime * 0.026 + 40.0, 2.6, mix(0.34, 0.22, rainAmt));
    vec3 cloudLitDay   = vec3(0.97, 0.97, 1.0);
    vec3 cloudShadeDay = vec3(0.55, 0.60, 0.74);
    vec3 cloudNight    = vec3(0.22, 0.25, 0.36);
    vec3 cloudStorm    = vec3(0.14, 0.14, 0.18);
    vec3 cloudColor = mix(mix(cloudNight, mix(cloudShadeDay, cloudLitDay, 0.6), daylight), cloudStorm, rainAmt);
    cloudColor = mix(cloudColor, vec3(1.0, 0.6, 0.3), goldenHour * 0.35);
    col = mix(col, cloudColor, clamp(c1 * 0.55 + c2 * 0.35, 0.0, 0.85));

    // --- Distant hills silhouette (tinted by daylight) -------------------
    float hill1 = -0.25 + noise(vec2(p.x * 2.0 + uTime * 0.02, 0.0)) * 0.08;
    float hill2 = -0.30 + noise(vec2(p.x * 3.5 + uTime * 0.015, 10.0)) * 0.06;
    vec3 hillFar  = mix(vec3(0.005, 0.008, 0.015), vec3(0.09, 0.14, 0.10), daylight);
    vec3 hillNear = mix(vec3(0.010, 0.015, 0.025), vec3(0.13, 0.19, 0.13), daylight);
    if (p.y < hill2) {
        col = mix(col, hillFar, 0.85);
    } else if (p.y < hill1) {
        col = mix(col, hillNear, 0.7);
    }

    // --- Foreground ground, grass, and rain puddles ----------------------
    float ground = -0.38 + noise(vec2(p.x * 4.0 + uTime * 0.03, 20.0)) * 0.04;
    if (p.y < ground) {
        float depth = clamp((ground - p.y) / 0.25, 0.0, 1.0);
        vec3 soil = mix(vec3(0.008, 0.012, 0.018), vec3(0.10, 0.09, 0.06), daylight);
        soil *= mix(1.0, 0.4, depth);

        // Grass tufts
        float tuftX = floor((p.x + uTime * 0.03) * 40.0);
        float tuftR = hash(vec2(tuftX, 30.0));
        if (tuftR < 0.5 && p.y > ground - 0.04) {
            float tx = (tuftX + 0.5) / 40.0 - uTime * 0.03;
            float sway = sin(uTime * 1.2 + tuftX) * 0.008;
            float bladeX = (p.x - tx) + (p.y - ground) * ((tuftR - 0.5) * 0.8 + sway);
            float bladeY = p.y - ground;
            float bladeH = 0.04 + tuftR * 0.03;
            float w = 0.003;
            if (bladeY > 0.0 && bladeY < bladeH && abs(bladeX) < w * (1.0 - bladeY / bladeH)) {
                soil += mix(vec3(0.04, 0.10, 0.03), vec3(0.10, 0.24, 0.07), daylight);
            }
        }

        // Puddle: spreads across the ground while it rains, drains after.
        // (puddleLine sits at `ground` when dry and creeps further down --
        // deeper into frame -- as puddleAmt rises, so coverage visibly grows.)
        float puddleLine = ground - 0.12 * puddleAmt;
        if (p.y > puddleLine) {
            vec2 rp = p * vec2(3.0, 10.0);
            float ripple = noise(rp + uTime * 0.4) - 0.5;
            vec3 reflection = mix(skyBot, skyTop, 0.25) * 1.15;
            vec3 puddleColor = mix(reflection * 0.55, vec3(0.03, 0.05, 0.07), 0.55) + ripple * 0.025;

            // Raindrop impact ripples on the puddle surface
            vec2 rippleCell = floor(p * 5.0);
            float rippleGen = floor(uTime * 1.1);
            float rippleSeed = hash(rippleCell + rippleGen * 3.7);
            if (rippleSeed > 0.72 && rainAmt > 0.05) {
                vec2 center = (rippleCell + 0.5) / 5.0;
                float d = length(p - center);
                float ringT = fract(uTime * 1.1 + rippleSeed * 12.0);
                float ring = smoothstep(0.025, 0.0, abs(d - ringT * 0.09)) * (1.0 - ringT);
                puddleColor += vec3(0.6, 0.7, 0.8) * ring * rainAmt;
            }

            soil = mix(soil, puddleColor, puddleAmt);
        }

        col = soil;
    }

    // --- Rain streak overlay ---------------------------------------------
    if (rainAmt > 0.01) {
        float r1 = rainLayer(p, 2.2, 14.0, 0.35) * 0.5;
        float r2 = rainLayer(p, 3.1, 22.0, 0.30) * 0.35;
        float rainMask = clamp(r1 + r2, 0.0, 1.0);
        col += vec3(0.75, 0.85, 0.95) * rainMask * rainAmt * 0.5;
    }

    // --- Subtle vignette ---------------------------------------------------
    float vignette = 1.0 - dot((uv - 0.5) * 1.4, (uv - 0.5) * 1.4);
    vignette = clamp(vignette, 0.0, 1.0);
    col *= vignette * 0.4 + 0.6;

    fragColor = vec4(col, 1.0);
}
