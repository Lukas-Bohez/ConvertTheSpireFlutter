#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uRes;
uniform float uTime;

out vec4 fragColor;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

// ---------- HASH / NOISE ----------
float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise1(float x) {
    float i = floor(x);
    float f = fract(x);
    float a = hash11(i);
    float b = hash11(i + 1.0);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u);
}

float fbm1(float x) {
    float v = 0.0;
    v += noise1(x) * 0.6;
    v += noise1(x * 2.13) * 0.3;
    v += noise1(x * 4.71) * 0.1;
    return v;
}

// ---------- SDF HELPERS ----------
float sdCircle(vec2 p, vec2 c, float r) {
    return length(p - c) - r;
}

float sdEllipse(vec2 p, vec2 c, vec2 r) {
    vec2 d = (p - c) / r;
    return (length(d) - 1.0) * min(r.x, r.y);
}

// ---------- GROUND HEIGHT (world-space x) ----------
float groundYAt(float x, float base, float amp, float freq) {
    float n = fbm1(x * freq);
    return base + (n - 0.5) * amp;
}

// ---------- CYCLIC 4-STOP RAIN PALETTE ----------
vec3 rainPalette(float t) {
    vec3 c0 = vec3(0.75, 0.85, 1.00); // pale blue
    vec3 c1 = vec3(0.85, 0.78, 1.00); // pale lavender
    vec3 c2 = vec3(0.78, 0.95, 0.88); // pale mint
    vec3 c3 = vec3(1.00, 0.88, 0.72); // pale gold
    float seg = fract(t) * 4.0;
    float i = floor(seg);
    float f = smoothstep(0.0, 1.0, fract(seg));
    if (i < 0.5) return mix(c0, c1, f);
    if (i < 1.5) return mix(c1, c2, f);
    if (i < 2.5) return mix(c2, c3, f);
    return mix(c3, c0, f);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    // Flutter's coordinate system has Y=0 at the top; flip so the shader's
    // "y up" logic renders correctly.
    fragCoord.y = uRes.y - fragCoord.y;
    vec2 uv = fragCoord / uRes.xy;
    vec2 p = (fragCoord - 0.5 * uRes.xy) / uRes.y; // aspect-correct, centered, y up

    // ---------- TIME OF DAY ----------
    float dayCycle = 240.0;
    float tod = fract(uTime / dayCycle);
    float sunAngle = tod * TAU;
    float sunHeight = sin(sunAngle);
    float sunXn = cos(sunAngle);
    float daylight = smoothstep(-0.25, 0.25, sunHeight);

    // ---------- SKY ----------
    vec3 nightSky = vec3(0.035, 0.04, 0.09);
    vec3 daySky   = vec3(0.42, 0.70, 0.93);
    vec3 duskSky  = vec3(0.86, 0.46, 0.32);

    vec3 sky = mix(nightSky, daySky, daylight);
    float horizonGlow = pow(clamp(1.0 - abs(sunHeight) * 1.6, 0.0, 1.0), 4.0);
    sky = mix(sky, duskSky, horizonGlow * 0.55);
    sky *= mix(0.85, 1.12, clamp(uv.y, 0.0, 1.0));

    if (daylight < 0.6) {
        vec2 starUV = p * 26.0;
        vec2 gid = floor(starUV);
        vec2 gf = fract(starUV);
        float sh = hash12(gid + 91.7);
        if (sh > 0.985) {
            vec2 starPos = vec2(hash12(gid + 3.1), hash12(gid + 7.7));
            float d = length(gf - starPos);
            float dot = smoothstep(0.22, 0.0, d);
            float tw = 0.5 + 0.5 * sin(uTime * 2.4 + sh * 80.0);
            sky += vec3(dot * tw * (1.0 - daylight) * 0.9);
        }
    }

    vec2 sunPos = vec2(sunXn * 0.85, sunHeight * 0.42 + 0.30);
    float sunDist = length(p - sunPos);
    vec3 sunColor = mix(vec3(0.75, 0.80, 0.92), vec3(1.0, 0.86, 0.55), daylight);
    float sunDisc = smoothstep(0.075, 0.06, sunDist);
    float sunGlow = pow(clamp(1.0 - sunDist / 0.32, 0.0, 1.0), 3.0) * 0.5;
    sky += sunColor * sunGlow;
    sky = mix(sky, sunColor, sunDisc);

    vec3 col = sky;

    // ---------- BACKGROUND RIDGES (parallax) ----------
    float camBG1 = mod(uTime * 0.012, 100000.0);
    float camBG2 = mod(uTime * 0.024, 100000.0);

    vec3 ridgeFar  = mix(vec3(0.10, 0.13, 0.20), vec3(0.55, 0.62, 0.66), daylight);
    vec3 ridgeNear = mix(vec3(0.06, 0.08, 0.14), vec3(0.36, 0.46, 0.42), daylight);

    float ry1 = -0.30 + fbm1((p.x + camBG1) * 1.6) * 0.16;
    float ry2 = -0.35 + fbm1((p.x + camBG2) * 2.4) * 0.15;

    if (p.y < ry1) col = mix(col, ridgeFar, 0.9);
    if (p.y < ry2) col = ridgeNear;

    // ---------- FOREGROUND GROUND ----------
    float camFG = mod(uTime * 0.05, 100000.0);
    float groundBase = -0.40;
    float groundAmp = 0.06;
    float groundFreq = 1.1;
    float grassBand = 0.10;

    float gy = groundYAt(p.x + camFG, groundBase, groundAmp, groundFreq);

    if (p.y < gy + grassBand) {
        vec3 soil = mix(vec3(0.05, 0.07, 0.05), vec3(0.30, 0.20, 0.12), daylight * 0.7 + 0.3);
        float depth = clamp((gy - p.y) / 0.3, 0.0, 1.0);
        soil *= mix(1.0, 0.55, depth);

        vec2 soilCell = floor(vec2((p.x + camFG) * 130.0, p.y * 130.0));
        float n = (hash12(soilCell) - 0.5) * 0.05;
        soil += vec3(n);

        vec3 grass = mix(vec3(0.05, 0.10, 0.05), vec3(0.20, 0.42, 0.18), daylight * 0.8 + 0.2);
        float withinGrass = smoothstep(gy, gy + grassBand * 0.4, p.y);

        float tuftW = 0.026;
        float tileX = floor((p.x + camFG) / tuftW);
        float rnd = hash11(tileX * 57.1);
        if (rnd < 0.55) {
            float cxWorld = (tileX + 0.5) * tuftW;
            float cxScreen = cxWorld - camFG;
            float sway = sin(uTime * 1.3 + tileX) * 0.006;
            float lean = (hash11(tileX * 13.3) - 0.5) * 0.03 + sway;
            float tuftHeight = 0.05 + hash11(tileX * 4.4) * 0.045;
            float txs = (p.x - cxScreen) + (p.y - gy) * lean;
            float tys = (p.y - gy);
            float w = 0.003;
            float blade = step(0.0, tys) * step(tys, tuftHeight) *
                          step(abs(txs), mix(w, 0.0005, clamp(tys / tuftHeight, 0.0, 1.0)));
            grass += vec3(0.08, 0.16, 0.06) * blade;
        }

        float rim = 1.0 - smoothstep(0.0, 0.004, abs(gy - p.y));
        grass += vec3(0.10, 0.11, 0.04) * rim * daylight;

        col = mix(soil, grass, withinGrass);
    }

    // ---------- RAIN (comes and goes, drifts in hue) ----------
    float rainCycle = fbm1(uTime * 0.045 + 12.0);
    float rainIntensity = smoothstep(0.55, 0.82, rainCycle);

    if (rainIntensity > 0.001) {
        vec2 rp = p * vec2(34.0, 9.0);
        rp.x += p.y * 2.4;
        rp.y += uTime * 2.6;
        vec2 rid = floor(rp);
        vec2 rf = fract(rp);
        float rh = hash12(rid);
        float streak = smoothstep(0.94, 1.0, rh) * smoothstep(0.0, 0.15, rf.x) * smoothstep(1.0, 0.7, rf.x);

        vec3 rainTint = rainPalette(uTime * 0.02);

        col += rainTint * streak * rainIntensity * 0.55;
        col *= mix(1.0, 0.82, rainIntensity * 0.6);

        float boltTick = floor(uTime * 1.7);
        float boltGate = step(0.985, hash11(boltTick));
        float bolt = boltGate * pow(hash11(boltTick + 3.3), 6.0) * step(0.7, rainIntensity);
        col += vec3(bolt) * 0.6;
    }

    // ---------- HOP CHARACTER (crosses the screen every so often) ----------
    float hopPeriod = 52.0;
    float hopCycle = floor(uTime / hopPeriod);
    float hopSeed = hash11(hopCycle * 7.13);
    if (hopSeed > 0.45) {
        float hopStart = hash11(hopCycle * 3.7) * (hopPeriod * 0.5);
        float hopDur = 5.5;
        float ht = uTime - hopCycle * hopPeriod - hopStart;
        float phase = clamp(ht / hopDur, 0.0, 1.0);
        if (ht > 0.0 && phase < 1.0) {
            float dir = hopSeed > 0.72 ? 1.0 : -1.0;
            float charScreenX = mix(-dir * 0.95, dir * 0.95, phase);

            float hopsCount = 5.0;
            float bounce = abs(sin(phase * PI * hopsCount));
            float squash = 1.0 - 0.35 * pow(1.0 - bounce, 6.0) + 0.10 * pow(bounce, 8.0);

            float charGY = groundYAt(charScreenX + camFG, groundBase, groundAmp, groundFreq);
            float cy = charGY + bounce * 0.05;

            vec2 cp;
            cp.x = (p.x - charScreenX) * dir;
            cp.y = (p.y - cy);
            cp.y /= squash;
            cp.x *= squash;

            float body = sdEllipse(cp, vec2(0.0, 0.013), vec2(0.019, 0.014));
            float head = sdCircle(cp, vec2(0.008, 0.030), 0.014);
            float ear1 = sdEllipse(cp, vec2(0.001, 0.046), vec2(0.0032, 0.013));
            float ear2 = sdEllipse(cp, vec2(0.013, 0.047), vec2(0.0032, 0.013));
            float d = min(min(body, head), min(ear1, ear2));

            float mask = smoothstep(0.0015, -0.0015, d);
            vec3 critterCol = mix(vec3(0.55, 0.40, 0.30), vec3(0.95, 0.85, 0.72), daylight * 0.6 + 0.2);
            float shade = 1.0 - clamp(-d * 6.0, 0.0, 0.3);
            col = mix(col, critterCol * shade, mask);
        }
    }

    fragColor = vec4(col, 1.0);
}
