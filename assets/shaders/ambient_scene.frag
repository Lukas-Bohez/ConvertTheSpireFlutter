#version 300 es

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uRes;
uniform float uTime;

out vec4 fragColor;

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

    // --- Sky gradient: deep night blue → purple-black ---
    vec3 skyBot = vec3(0.01, 0.015, 0.04);
    vec3 skyTop = vec3(0.04, 0.03, 0.08);
    vec3 col = mix(skyBot, skyTop, uv.y);

    // --- Slow aurora-like bands ---
    float band1 = sin(p.x * 2.5 + uTime * 0.15) * 0.5 + 0.5;
    float band2 = sin(p.x * 1.8 - uTime * 0.12 + 1.5) * 0.5 + 0.5;
    float band3 = sin(p.x * 3.2 + uTime * 0.08 + 3.0) * 0.5 + 0.5;

    vec3 aurora = vec3(0.0);
    aurora += vec3(0.08, 0.25, 0.12) * band1 * smoothstep(0.1, 0.5, uv.y) * smoothstep(0.9, 0.5, uv.y);
    aurora += vec3(0.15, 0.08, 0.20) * band2 * smoothstep(0.15, 0.55, uv.y) * smoothstep(0.85, 0.55, uv.y);
    aurora += vec3(0.05, 0.12, 0.22) * band3 * smoothstep(0.2, 0.6, uv.y) * smoothstep(0.8, 0.6, uv.y);
    col += aurora * 0.4;

    // --- Stars ---
    vec2 starUV = p * 35.0;
    vec2 starCell = floor(starUV);
    vec2 starFrac = fract(starUV);
    float starHash = hash(starCell + 100.0);
    if (starHash > 0.985) {
        vec2 starPos = vec2(hash(starCell + 1.0), hash(starCell + 2.0));
        float dist = length(starFrac - starPos);
        float brightness = smoothstep(0.18, 0.0, dist);
        float twinkle = 0.5 + 0.5 * sin(uTime * 2.5 + starHash * 50.0);
        col += vec3(0.9, 0.95, 1.0) * brightness * twinkle * 0.7;
    }

    // --- Shooting star (rare) ---
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
            col += vec3(1.0, 0.95, 0.85) * trail * (1.0 - shootT / 1.2);
        }
    }

    // --- Distant hills silhouette ---
    float hill1 = -0.25 + noise(vec2(p.x * 2.0 + uTime * 0.02, 0.0)) * 0.08;
    float hill2 = -0.30 + noise(vec2(p.x * 3.5 + uTime * 0.015, 10.0)) * 0.06;
    if (p.y < hill2) {
        col = mix(col, vec3(0.005, 0.008, 0.015), 0.85);
    } else if (p.y < hill1) {
        col = mix(col, vec3(0.01, 0.015, 0.025), 0.7);
    }

    // --- Foreground ground ---
    float ground = -0.38 + noise(vec2(p.x * 4.0 + uTime * 0.03, 20.0)) * 0.04;
    if (p.y < ground) {
        float depth = clamp((ground - p.y) / 0.25, 0.0, 1.0);
        vec3 soil = vec3(0.008, 0.012, 0.018);
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
                soil += vec3(0.04, 0.10, 0.03);
            }
        }
        col = soil;
    }

    // --- Subtle vignette ---
    float vignette = 1.0 - dot((uv - 0.5) * 1.4, (uv - 0.5) * 1.4);
    vignette = clamp(vignette, 0.0, 1.0);
    col *= vignette * 0.4 + 0.6;

    fragColor = vec4(col, 1.0);
}
