//
//  Scenes.metal
//  Wlprz · Wlprz
//
//  Original procedural wallpaper scenes, used as SwiftUI colorEffect shaders.
//
//  Every scene shares one signature after the implicit (position, color) pair:
//    size    – view size in points
//    time    – seconds since the scene started
//    pointer – pointer position in view points (top-left origin)
//    press   – 0…1, eased mouse-button pressure, used for ripples and bursts
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Helpers

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

static float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

static float stars(float2 uv, float density, float time) {
    float2 cell = floor(uv * density);
    float2 local = fract(uv * density) - 0.5;
    float h = hash21(cell);
    float2 offset = float2(hash21(cell + 3.1), hash21(cell + 7.7)) - 0.5;
    float d = length(local - offset * 0.7);
    float twinkle = 0.6 + 0.4 * sin(time * (1.0 + h * 3.0) + h * 40.0);
    return step(0.92, h) * smoothstep(0.06, 0.0, d) * twinkle;
}

// MARK: - Aurora

[[ stitchable ]] half4 aurora(float2 position, half4 color, float2 size, float time, float2 pointer, float press) {
    float2 uv = position / size;
    float aspect = size.x / size.y;
    float2 p = float2(uv.x * aspect, uv.y);
    float2 m = float2(pointer.x / size.y, pointer.y / size.y);

    float3 sky = mix(float3(0.01, 0.02, 0.06), float3(0.02, 0.07, 0.12), uv.y);
    sky += stars(p, 70.0, time) * (1.0 - uv.y) * 0.9;

    float3 col = sky;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float lean = 0.06 * exp(-6.0 * abs(p.x - m.x)) * (1.0 + press);
        float curtain = 0.32 + fi * 0.07
            + 0.08 * sin(p.x * (1.4 + fi * 0.5) + time * (0.10 + fi * 0.04))
            + 0.05 * fbm(float2(p.x * 2.0 + time * 0.05, fi))
            - lean;
        float dist = uv.y - curtain;
        float band = exp(-pow(max(dist, 0.0) * 9.0, 1.3)) * smoothstep(-0.02, 0.01, dist);
        float rays = 0.55 + 0.45 * fbm(float2(p.x * 9.0 + fi * 3.0, time * 0.15));
        float3 tint = mix(float3(0.10, 0.95, 0.55), float3(0.55, 0.30, 0.95), fi / 2.0 + 0.3 * uv.y);
        col += tint * band * rays * (0.55 - fi * 0.12);
    }
    // Faint reflection on a calm horizon.
    col = mix(col, col * 0.35 + float3(0.0, 0.03, 0.05), smoothstep(0.82, 0.86, uv.y));
    return half4(half3(col), 1.0);
}

// MARK: - Nebula Drift

[[ stitchable ]] half4 nebula(float2 position, half4 color, float2 size, float time, float2 pointer, float press) {
    float2 p = (position - 0.5 * size) / size.y;
    float2 m = (pointer - 0.5 * size) / size.y;
    float t = time * 0.03;

    float2 toward = p - m;
    p += toward * (0.08 + 0.1 * press) * exp(-4.0 * dot(toward, toward));

    float2 q = float2(fbm(p * 1.6 + t), fbm(p * 1.6 + float2(5.2, 1.3) - t));
    float2 r = float2(fbm(p * 1.6 + 3.0 * q + float2(1.7, 9.2) + t * 1.5),
                      fbm(p * 1.6 + 3.0 * q + float2(8.3, 2.8) - t));
    float f = fbm(p * 1.6 + 3.0 * r);

    float3 col = palette(f + 0.2 * r.x, float3(0.25, 0.12, 0.35), float3(0.35, 0.25, 0.40),
                         float3(1.0, 1.0, 1.0), float3(0.80, 0.90, 0.30));
    col *= smoothstep(0.15, 0.9, f) * 1.4;
    col += float3(0.9, 0.55, 0.85) * pow(f, 6.0) * 2.0;
    col += stars(p + 3.0, 60.0, time) * 0.8;
    col *= 1.0 - 0.35 * length(p);
    return half4(half3(clamp(col, 0.0, 1.0)), 1.0);
}

// MARK: - Liquid Orbs

[[ stitchable ]] half4 orbs(float2 position, half4 color, float2 size, float time, float2 pointer, float press) {
    float2 p = (position - 0.5 * size) / size.y;
    float2 m = (pointer - 0.5 * size) / size.y;

    float field = 0.0;
    float3 tint = float3(0.0);
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float2 c = 0.45 * float2(sin(time * (0.11 + fi * 0.023) + fi * 1.7) * 1.4,
                                 cos(time * (0.09 + fi * 0.031) + fi * 2.3));
        float w = (0.035 + 0.01 * fi) / (dot(p - c, p - c) + 1e-4);
        field += w;
        tint += w * palette(fi / 6.0 + time * 0.01, float3(0.5), float3(0.5),
                            float3(1.0), float3(0.0, 0.33, 0.67));
    }
    float wp = (0.03 + 0.05 * press) / (dot(p - m, p - m) + 1e-4);
    field += wp;
    tint += wp * float3(1.0, 0.95, 0.9);

    tint /= max(field, 1e-4);
    float surface = smoothstep(0.9, 1.1, field);
    float rim = smoothstep(0.85, 1.0, field) - smoothstep(1.0, 1.4, field);
    float3 bg = mix(float3(0.05, 0.04, 0.09), float3(0.09, 0.06, 0.14), position.y / size.y);
    float3 col = mix(bg, tint * (0.7 + 0.3 * smoothstep(1.0, 4.0, field)), surface);
    col += rim * 0.25;
    return half4(half3(col), 1.0);
}

// MARK: - Constellation

[[ stitchable ]] half4 constellation(float2 position, half4 color, float2 size, float time, float2 pointer, float press) {
    float2 p = position / size.y;
    float2 m = pointer / size.y;
    float3 col = mix(float3(0.01, 0.01, 0.03), float3(0.03, 0.03, 0.08), position.y / size.y);

    float scale = 9.0;
    float2 g = p * scale;
    float2 cell = floor(g);
    float3 glow = float3(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 c = cell + float2(x, y);
            float2 jitter = float2(hash21(c), hash21(c + 11.3));
            float2 star = c + 0.5 + 0.4 * sin(time * 0.08 + jitter * 6.28);
            float d = length(g - star);
            float near = exp(-5.0 * length(star / scale - m));
            float twinkle = 0.5 + 0.5 * sin(time * (0.7 + jitter.x) + jitter.y * 30.0);
            glow += float3(0.7, 0.8, 1.0) * (0.004 + 0.02 * near) / (d * d + 0.002) * (0.4 + 0.6 * twinkle) * 0.08;

            // Threads between neighbouring stars light up near the pointer.
            float2 c2 = c + float2(1.0, 0.0);
            float2 j2 = float2(hash21(c2), hash21(c2 + 11.3));
            float2 star2 = c2 + 0.5 + 0.4 * sin(time * 0.08 + j2 * 6.28);
            float2 pa = g - star, ba = star2 - star;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float line = smoothstep(0.03, 0.0, length(pa - ba * h));
            glow += float3(0.4, 0.6, 1.0) * line * near * 0.6;
        }
    }
    // Click ripple.
    float ring = abs(length(p - m) - fract(time * 0.6) * 0.6);
    glow += float3(0.5, 0.7, 1.0) * press * smoothstep(0.02, 0.0, ring) * 0.5;
    col += glow;
    return half4(half3(clamp(col, 0.0, 1.0)), 1.0);
}

// MARK: - Dusk Waves

[[ stitchable ]] half4 duskWaves(float2 position, half4 color, float2 size, float time, float2 pointer, float press) {
    float2 uv = position / size;
    float aspect = size.x / size.y;
    float tilt = (pointer.x / size.x - 0.5) * 0.04;

    float3 top = float3(0.18, 0.10, 0.32), mid = float3(0.95, 0.42, 0.30), low = float3(1.0, 0.78, 0.45);
    float3 col = mix(top, mid, smoothstep(0.0, 0.5, uv.y));
    col = mix(col, low, smoothstep(0.45, 0.6, uv.y));

    float2 sunPos = float2(0.5 + tilt * 3.0, 0.52);
    float sun = length((uv - sunPos) * float2(aspect, 1.0));
    col += float3(1.0, 0.85, 0.6) * smoothstep(0.09, 0.08, sun);
    col += float3(1.0, 0.5, 0.3) * 0.25 * exp(-sun * 6.0);

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float depth = fi / 4.0;
        float speed = 0.15 + depth * 0.25;
        float x = uv.x * aspect * (2.0 + depth * 3.0);
        float h = 0.56 + depth * 0.09 + tilt * (1.0 + depth * 2.0)
            + 0.012 * (1.0 + depth) * sin(x + time * speed + fi * 1.3)
            + 0.006 * (1.0 + depth) * sin(x * 2.3 - time * speed * 1.4 + fi);
        float3 water = mix(float3(0.55, 0.25, 0.35), float3(0.08, 0.05, 0.16), depth);
        float glint = pow(max(0.0, sin(x * 6.0 + time * 0.8 + fi)), 30.0) * (1.0 - depth) * 0.4;
        float edge = smoothstep(h, h + 0.002, uv.y);
        col = mix(col, water + float3(1.0, 0.7, 0.5) * glint, edge);
    }
    return half4(half3(col), 1.0);
}
