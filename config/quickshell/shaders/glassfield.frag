#version 440
// Shape field of the glass shapes (GlassShape.qml), rendered once per mask into a float (RGBA16F) layer:
//   r = coverage: the mask with rounded corners (a small blur at the outline level, anti-aliased, inside the mask)
//   g = height: the mask blurred at three radii (0.5 / 0.8 / 1.1 x the half stroke), averaged; glasstext.frag clips it
//       to the coverage. A blurred mask is smooth, so there is no ridge on the stroke's centreline and no steps; the
//       clip keeps close strokes from bridging (each glyph is its own GlassShape, so neighbours never add up)
//   b = the mask blurred wide (2.2 x): the shadow / caustic
//   a = the small-blur mask value whose 0.5 level is the outline: an implicit shape glasstext.frag can morph between two
//       fields (written raw: the layer is drawn without blending)
// Blurs: Gaussian-weighted Vogel-disc samples of the (2x, mipmapped) mask, read from a mip level matching the sample
// spacing, so they come out smooth with 64 taps each. Cost: once per mask change, never per frame.
// Build: /usr/lib/qt6/bin/qsb --qt6 -o glassfield.frag.qsb glassfield.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;       // px, half stroke width
    float level;        // coverage threshold of the rounded mask (0.5 = the outline; lower inflates)
    float maskScale;    // mask texels per item px (the mask's supersampling)
};
layout(binding = 1) uniform sampler2D mask;

const int TAPS = 64;

float blurred(vec2 uv, float r) {
    vec2 px = 1.0 / itemSize;
    float spacing = r * 2.0 * maskScale / sqrt(float(TAPS));
    float lod = log2(max(spacing, 1.0));
    float sum = 0.0, wsum = 0.0;
    for (int i = 0; i < TAPS; i++) {
        float f = (float(i) + 0.5) / float(TAPS);
        float d = sqrt(f);
        float a = float(i) * 2.3999632;
        float w = exp(-2.0 * d * d);
        sum += w * textureLod(mask, uv + vec2(cos(a), sin(a)) * d * r * px, lod).a;
        wsum += w;
    }
    return sum / wsum;
}

void main() {
    vec2 uv = qt_TexCoord0;
    // coverage: the outline itself (level 0.5: no growth), corners rounded by a small blur, and never outside the mask
    float c0 = blurred(uv, max(radius * 0.2, 1.0)) - level;
    float w = max(fwidth(c0), 1e-4);
    float cov = clamp(0.5 + c0 / w, 0.0, 1.0) * smoothstep(0.0, 0.5, textureLod(mask, uv, 0.0).a);
    // height: blurs bounded by the half stroke (glasstext.frag clips it to the coverage: no bridges to other strokes)
    float h = (blurred(uv, radius * 0.5) + blurred(uv, radius * 0.8) + blurred(uv, radius * 1.1)) / 3.0;
    float wide = blurred(uv, radius * 2.2);
    fragColor = vec4(cov, h, wide, c0 + level);
}
