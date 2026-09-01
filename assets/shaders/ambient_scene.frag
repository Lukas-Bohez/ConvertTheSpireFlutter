#version 300 es

#include <flutter/runtime_effect.glsl>

precision highp float;

// uRes         : viewport size in pixels                          (existing)
// uTime        : seconds since AmbientScene mounted                (existing)
// uDayPhase    : 0..1 local wall-clock day position                (new)
//                0 / 1 = midnight, 0.5 = noon
// uCloudAmount : 0..1 sky coverage, smoothly driven from Dart       (new)
// uRainAmount  : 0..1 rain + puddle intensity, smoothly driven      (new)
//
// See bitplayer_cinematic_view_v2_technical_reference.md for the
// reasoning behind every formula below — this file has short
// pointers only, not the full rationale.
uniform vec2 uRes;
uniform float uTime;
uniform float uDayPhase;
uniform float uCloudAmount;
uniform float uRainAmount;

out vec4 fragColor;

// ---------------------------------------------------------------------------
// hash() / noise() are unchanged from v1. fbm() and glowDisc() are new.
// ---------------------------------------------------------------------------
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

// 5-octave fractal Brownian motion, built from the noise() above.
// Used only for clouds; costs 5x noise() (20 hashes/pixel) so it's
// gated behind `uCloudAmount > 0.003` at the call site.
float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        sum += amp * noise(p);
        p *= 2.02; // slightly off 2.0 to avoid grid artifacts
        amp *= 0.5;
    }
    return sum;
}

// Soft circular glow: ~1.0 at `center`, falling off past `radius`
// over a band of width `soft`. Used for the sun/moon core + halo.
float glowDisc(vec2 p, vec2 center, float radius, float soft) {
    float d = length(p - center);
    return smoothstep(radius + soft, radius - soft, d);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    if (uRes.x < 1.0 || uRes.y < 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec2 uv = fragCoord / uRes;
    // Normalized centered coords. Sign convention follows the existing
    // ground/hill values below (negative = ground side); sun/moon and
    // clouds deliberately stay on the opposite (positive) side.
    vec2 p = (fragCoord - 0.5 * uRes) / uRes.y;

    // 0 at midnight, 1 at noon, smooth (cosine) across the transition.
    float daylight = 0.5 - 0.5 * cos(uDayPhase * 6.28318530718);

    // --- Sky gradient: night blue/purple <-> soft day blue ---
    vec3 nightBot = vec3(0.01, 0.015, 0.04);
    vec3 nightTop = vec3(0.04, 0.03, 0.08);
    vec3 dayBot   = vec3(0.58, 0.74, 0.90);
    vec3 dayTop   = vec3(0.18, 0.42, 0.74);
    vec3 skyBot = mix(nightBot, dayBot, daylight);
    vec3 skyTop = mix(nightTop, dayTop, daylight);
    vec3 col = mix(skyBot, skyTop, uv.y);

    // --- Slow aurora-like bands (unchanged shape from v1, fades with daylight) ---
    float band1 = sin(p.x * 2.5 + uTime * 0.15) * 0.5 + 0.5;
    float band2 = sin(p.x * 1.8 - uTime * 0.12 + 1.5) * 0.5 + 0.5;
    float band3 = sin(p.x * 3.2 + uTime * 0.08 + 3.0) * 0.5 + 0.5;

    vec3 aurora = vec3(0.0);
    aurora += vec3(0.08, 0.25, 0.12) * band1 * smoothstep(0.1, 0.5, uv.y) * smoothstep(0.9, 0.5, uv.y);
    aurora += vec3(0.15, 0.08, 0.20) * band2 * smoothstep(0.15, 0.55, uv.y) * smoothstep(0.85, 0.55, uv.y);
    aurora += vec3(0.05, 0.12, 0.22) * band3 * smoothstep(0.2, 0.6, uv.y) * smoothstep(0.8, 0.6, uv.y);
    col += aurora * 0.4 * (1.0 - daylight * 0.9);

    // --- Stars: same cell layout as v1, twinkle decorrelated (see tech ref §1) ---
    vec2 starUV = p * 35.0;
    vec2 starCell = floor(starUV);
    vec2 starFrac = fract(starUV);
    float starHash = hash(starCell + 100.0);
    if (starHash > 0.985) {
        vec2 starPos = vec2(hash(starCell + 1.0), hash(starCell + 2.0));
        float dist = length(starFrac - starPos);
        float brightness = smoothstep(0.18, 0.0, dist);

        float starFreq = mix(0.55, 2.3, hash(starCell + 7.0));
        float starPhase = starHash * 41.0;
        float twinkle = 0.5
            + 0.35 * sin(uTime * starFreq + starPhase)
            + 0.15 * sin(uTime * starFreq * 1.87 + starPhase * 1.7);
        twinkle = clamp(twinkle, 0.0, 1.0);

        col += vec3(0.9, 0.95, 1.0) * brightness * twinkle * 0.7 * (1.0 - daylight * 0.92);
    }

    // --- Shooting star (rare, unchanged from v1, dimmed by daylight) ---
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
            col += vec3(1.0, 0.95, 0.85) * trail * (1.0 - shootT / 1.2) * (1.0 - daylight * 0.9);
        }
    }

    // --- Sun & moon: full day arc, never fully absent (see tech ref §2) ---
    float ang = uDayPhase * 6.28318530718;

    vec2 sunPos = vec2(sin(ang), 0.38 - 0.16 * cos(ang));
    float sunCore = glowDisc(p, sunPos, 0.045, 0.015);
    float sunHalo = glowDisc(p, sunPos, 0.16, 0.16) * 0.4;
    float sunVisible = max(daylight, 0.15); // floor: always at least partly visible
    vec3 sunColor = mix(vec3(1.0, 0.62, 0.35), vec3(1.0, 0.93, 0.75), daylight);
    col += sunColor * (sunCore + sunHalo) * sunVisible;

    vec2 moonPos = vec2(-sin(ang), 0.38 + 0.16 * cos(ang));
    float moonCore = glowDisc(p, moonPos, 0.035, 0.012);
    float moonHalo = glowDisc(p, moonPos, 0.10, 0.10) * 0.3;
    float moonVisible = max(1.0 - daylight, 0.15); // floor
    col += vec3(0.85, 0.88, 0.97) * (moonCore + moonHalo) * moonVisible;
    // Faint offset crescent shading so the moon doesn't read as a flat disc.
    float crescent = glowDisc(p, moonPos + vec2(0.011, 0.005), 0.032, 0.01);
    col -= vec3(0.02, 0.02, 0.035) * crescent * moonVisible;

    // --- Clouds: fbm-driven, drifting, upper-sky band only (see tech ref §3) ---
    if (uCloudAmount > 0.003) {
        vec2 cloudUV = p * vec2(1.7, 2.4) + vec2(uTime * 0.015, uTime * 0.002);
        float cn = fbm(cloudUV + fbm(cloudUV * 0.5));
        float edge = mix(0.62, 0.30, uCloudAmount);
        float coverage = smoothstep(edge, edge + 0.28, cn);
        coverage *= smoothstep(-0.05, 0.22, p.y) * smoothstep(0.62, 0.32, p.y);
        vec3 cloudLit = mix(vec3(0.45, 0.47, 0.55), vec3(0.97, 0.97, 1.0), daylight);
        col = mix(col, cloudLit, coverage * uCloudAmount);
    }

    // --- Distant hills silhouette (unchanged from v1) ---
    float hill1 = -0.25 + noise(vec2(p.x * 2.0 + uTime * 0.02, 0.0)) * 0.08;
    float hill2 = -0.30 + noise(vec2(p.x * 3.5 + uTime * 0.015, 10.0)) * 0.06;
    if (p.y < hill2) {
        col = mix(col, vec3(0.005, 0.008, 0.015), 0.85);
    } else if (p.y < hill1) {
        col = mix(col, vec3(0.01, 0.015, 0.025), 0.7);
    }

    // --- Foreground ground: unchanged grass-tuft logic, plus a wet/puddle pass ---
    float ground = -0.38 + noise(vec2(p.x * 4.0 + uTime * 0.03, 20.0)) * 0.04;
    if (p.y < ground) {
        float depth = clamp((ground - p.y) / 0.25, 0.0, 1.0);
        vec3 soil = vec3(0.008, 0.012, 0.018);
        soil *= mix(1.0, 0.4, depth);

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
                soil += vec3(0.04, 0.10, 0.03);
            }
        }

        // Rain turns the ground into a puddle: mirror the sky for a
        // reflection tint, then add cell-seeded expanding ripple rings.
        // See tech ref §4 for the ripple technique.
        if (uRainAmount > 0.003) {
            vec2 mirrorP = vec2(p.x, 2.0 * ground - p.y);
            float mirrorUv = clamp(mirrorP.y + 0.5, 0.0, 1.0);
            vec3 reflSky = mix(skyBot, skyTop, mirrorUv);

            vec2 rippleUV = p * 9.0;
            vec2 rippleCell = floor(rippleUV);
            float rippleSeed = hash(rippleCell + 900.0);
            float ringT = fract(uTime * 0.3 + rippleSeed);
            float ringR = ringT * 0.4;
            float ringD = length(fract(rippleUV) - 0.5);
            float ring = smoothstep(ringR + 0.025, ringR, ringD)
                       - smoothstep(ringR, ringR - 0.025, ringD);

            vec3 puddle = mix(soil, reflSky * 0.65, 0.55 * uRainAmount);
            puddle += vec3(0.75, 0.8, 0.9) * ring * uRainAmount * 0.6;
            soil = mix(soil, puddle, uRainAmount);
        }

        col = soil;
    }

    // --- Rain streaks above the ground line (see tech ref §4) ---
    if (uRainAmount > 0.003 && p.y > ground) {
        vec2 rp = p * vec2(26.0, 7.0);
        rp.x += uTime * 0.4;
        rp.y -= uTime * 5.5;
        vec2 rCell = floor(rp);
        vec2 rFrac = fract(rp);
        float rHash = hash(rCell + 500.0);
        if (rHash < uRainAmount * 0.6) {
            float streak = smoothstep(0.06, 0.0, abs(rFrac.x - 0.5))
                          * smoothstep(1.0, 0.55, rFrac.y);
            col += vec3(0.65, 0.7, 0.8) * streak * 0.3;
        }
    }

    // --- Subtle vignette (unchanged from v1) ---
    float vignette = 1.0 - dot((uv - 0.5) * 1.4, (uv - 0.5) * 1.4);
    vignette = clamp(vignette, 0.0, 1.0);
    col *= vignette * 0.4 + 0.6;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
