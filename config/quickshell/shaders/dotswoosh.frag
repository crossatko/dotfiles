#version 440
// Dot swoosh (DotSwoosh.qml): a flowing two-strand ribbon drawn as an ordered-dithered (4x4 Bayer) dot grid, with
// optional dot-matrix labels at its left / right end drawn in the SAME grid (one glyph pixel = one cell), and an
// error look (one flat dotted line). Everything is computed per fragment from a handful of uniforms: no texture,
// no per-frame work on the CPU besides `time` / `level`.
// Grid: cols x rows cells of `pitch` px, centred in the item; a dot = a square of pitch * dotFrac in its cell's
// centre, anti-aliased by its pixel coverage (fwidth), so it stays crisp at any output scale.
// Ribbon: per column u in 0..1 between the labels, envelope sin(pi u)^0.7,
// strand k = 0 (alpha 1) and k = 1 (alpha strand2Alpha, drawn over it); centre line = two sines that flow with
// `time`, amplitude (idleAmp at level 0, 1 at level 1) and thickness follow the level (the `hist` samples across u when histN > 0, else `level`);
// a cell is lit when pow(coverage, 1.1) exceeds its Bayer threshold. Colour = colA -> colB over the middle of the ribbon.
// Labels: up to 16 columns each, 5 rows; column c = bits 5*(c%4).. of component c/4 of labL / labR (bit 0 = top row).
// Build: /usr/lib/qt6/bin/qsb --qt6 -o dotswoosh.frag.qsb dotswoosh.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pitch;        // px per grid cell
    float dotFrac;      // dot size / pitch
    float time;         // s, flow phase
    float level;        // 0..1 (used when histN == 0)
    float histN;        // number of valid hist samples (0..16), oldest first
    vec4 hist0;
    vec4 hist1;
    vec4 hist2;
    vec4 hist3;
    vec4 colA;          // left end colour (and the left label)
    vec4 colB;          // right end colour (and the right label)
    vec4 errCol;
    float error;        // 1 = the flat error line, no labels
    vec4 labL;
    float labLW;        // columns of the left label (0 = none)
    vec4 labR;
    float labRW;
    float labAlpha;
    float strand2Alpha;
    float idleAmp;      // swing at level 0 (fraction of the swing at level 1)
};

const float bayer[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
float thresh(vec2 g) {
    int i = int(mod(g.y, 4.0)) * 4 + int(mod(g.x, 4.0));
    return (bayer[i] + 0.5) / 16.0;
}

float histAt(int i) {
    vec4 v = i < 4 ? hist0 : i < 8 ? hist1 : i < 12 ? hist2 : hist3;
    int j = i - (i / 4) * 4;
    return j == 0 ? v.x : j == 1 ? v.y : j == 2 ? v.z : v.w;
}
float levelAt(float u) {
    if (histN < 1.0) return level;
    float f = clamp(u, 0.0, 1.0) * (histN - 1.0);
    int i0 = int(floor(f));
    int i1 = min(i0 + 1, int(histN) - 1);
    return mix(histAt(i0), histAt(i1), f - float(i0));
}

// one bit of a label: column c, row r
bool labelBit(vec4 lab, float w, float c, float r) {
    if (c < 0.0 || c >= w || r < 0.0 || r >= 5.0) return false;
    int ci = int(c);
    int q = ci / 4;
    float comp = q == 0 ? lab.x : q == 1 ? lab.y : q == 2 ? lab.z : lab.w;
    int bits = (int(comp + 0.5) >> (5 * (ci - q * 4))) & 31;
    return ((bits >> int(r)) & 1) == 1;
}

// colour (straight alpha) of cell g
vec4 cellColor(vec2 g, float cols, float rows) {
    if (error > 0.5) {
        float cy = floor(rows / 2.0);
        return (g.y == cy && thresh(g) < 0.9) ? errCol : vec4(0.0);
    }
    float y0 = floor((rows - 5.0) / 2.0);
    if (labLW > 0.0 && g.x < labLW)
        return labelBit(labL, labLW, g.x, g.y - y0) ? vec4(colA.rgb, labAlpha) : vec4(0.0);
    if (labRW > 0.0 && g.x >= cols - labRW)
        return labelBit(labR, labRW, g.x - (cols - labRW), g.y - y0) ? vec4(colB.rgb, labAlpha) : vec4(0.0);
    float l0 = labLW > 0.0 ? labLW + 2.0 : 0.0;
    float r0 = labRW > 0.0 ? labRW + 2.0 : 0.0;
    float n = cols - l0 - r0;
    if (g.x < l0 || g.x >= cols - r0 || n < 2.0) return vec4(0.0);
    float u = (g.x - l0) / (n - 1.0);
    float env = pow(max(0.0, sin(3.14159265 * u)), 0.7);
    float l = clamp(levelAt(u), 0.0, 1.0);
    float th0 = thresh(g);
    // left colour -> right colour over the middle part (a long linear blend of two contrasting accents reads as grey)
    vec3 c = mix(colA.rgb, colB.rgb, smoothstep(0.3, 0.7, u));
    vec4 outc = vec4(0.0);
    for (int k = 0; k < 2; k++) {
        float kf = float(k);
        float amp = (idleAmp + (1.0 - idleAmp) * l) * (k == 1 ? 0.8 : 1.0);
        float cy = rows / 2.0
                 + sin(u * 6.2831853 * (1.2 + kf * 0.5) + time * (2.0 + kf * 1.2) + kf * 1.7) * amp * rows * 0.34 * env
                 + sin(u * 3.14159265 * 5.0 + time * 3.1) * amp * rows * 0.06 * env;
        float th = rows * (0.12 + 0.4 * l) * env * (k == 1 ? 0.6 : 1.0) + 0.35;
        float cov = max(0.0, 1.0 - abs(g.y - cy) / th);
        if (pow(cov, 1.1) > th0) {
            float a = k == 1 ? strand2Alpha : 1.0;
            // straight-alpha "over"
            float ao = a + outc.a * (1.0 - a);
            outc = vec4((c * a + outc.rgb * outc.a * (1.0 - a)) / max(ao, 1e-4), ao);
        }
    }
    return outc;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 px = max(fwidth(p), vec2(1e-3));         // one output pixel in item px
    float cols = floor(itemSize.x / pitch);
    float rows = floor(itemSize.y / pitch);
    vec2 o = (itemSize - vec2(cols, rows) * pitch) / 2.0;
    float s = pitch * dotFrac;
    vec4 acc = vec4(0.0);                          // premultiplied
    // the (at most 2 x 2) cells whose dots this pixel can touch
    vec2 g0 = floor((p - px * 0.5 - o) / pitch);
    vec2 g1 = floor((p + px * 0.5 - o) / pitch);
    for (float gy = g0.y; gy <= g1.y; gy += 1.0) {
        for (float gx = g0.x; gx <= g1.x; gx += 1.0) {
            vec2 g = vec2(gx, gy);
            if (gx < 0.0 || gy < 0.0 || gx >= cols || gy >= rows) continue;
            vec2 c = o + (g + 0.5) * pitch;
            vec2 ov = clamp(min(p + px * 0.5, c + s * 0.5) - max(p - px * 0.5, c - s * 0.5), vec2(0.0), px) / px;
            float cover = ov.x * ov.y;
            if (cover <= 0.0) continue;
            vec4 col = cellColor(g, cols, rows);
            acc += vec4(col.rgb * col.a, col.a) * cover;
        }
    }
    fragColor = min(acc, vec4(1.0)) * qt_Opacity;
}
