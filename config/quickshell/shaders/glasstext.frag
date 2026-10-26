#version 440
// Glass shapes (GlassShape.qml: the lock clock's digits, the password beads) as clear glass tubes in front of the lock
// screen's backdrop. Shape: `field` (glassfield.frag, once per mask) = coverage + tube height over the distance to the
// outline; `shape` = that height blurred, so the surface is smooth with no ridge on the stroke's centreline. The normal
// comes from its gradient: flat on top, tilting towards the outline, following every curve.
// Optics: refraction of the SHARP scene (clear glass: no frost / clarity, only bent, more towards the rim, with a
// chromatic split), a broad soft highlight along each stroke where it faces the light plus a weaker back reflection,
// fresnel towards the rim, an inner glow, a darker band where the glass is steep, and behind it a soft shadow with a
// faint caustic; `glow` fills it with a state colour. Driven by Settings > Glass (GlassTuneCtl.effective), mapped for
// small glass: tint / darkening only tint the body faintly, aberration and the light have floors, and the body is kept
// a little brighter than dark surroundings, so it never vanishes or goes black. Shell sRGB pixels, sizes in item px.
// Build: /usr/lib/qt6/bin/qsb --qt6 -o glasstext.frag.qsb glasstext.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // glyph item incl. padding
    vec2 origin;        // item's top-left in backdrop px
    vec2 backdropSize;  // backdrop texture size, px
    float radius;       // half stroke width, px (the tube radius)
    float heightScale;  // px of surface height per unit of field height (how steep the rim is)
    float refraction;   // px          (solid_glass:refraction x depth, scaled to the glyph size)
    float edgeCurve;    //             (solid_glass:edge_curve)
    float aberration;   //             (solid_glass:aberration)
    vec2 lightDir;      // y down      (solid_glass:light_angle)
    float specular;     //             (solid_glass:specular_intensity)
    float specPower;    //             (solid_glass:specular_power)
    float sheen;        //             (solid_glass:sheen)
    float saturation;   //             (solid_glass:saturation)
    float darkening;    //             (solid_glass:darkening)
    vec4 tint;          // rgb + alpha = absorption (solid_glass:tint)
    float shade;        // shadow alpha
    float sharpInset;   // px the sharp backdrop extends past the blurred one on every side
    vec4 glow;          // rgb + strength: a coloured light inside the glass (state feedback, e.g. an error)
    float morph;        // 0 = `field`, 1 = `field2`: the glass flows from one shape to the other
    float dim;          // subtracted from the sharp scene, as the blurred backdrop's MultiEffect brightness (Theme.lockDim)
};
layout(binding = 1) uniform sampler2D backdrop;   // blurred
layout(binding = 2) uniform sampler2D sharp;      // unblurred
layout(binding = 3) uniform sampler2D field;      // glassfield.frag: r = coverage, g = smooth height, b = wide blur, a = implicit
layout(binding = 4) uniform sampler2D field2;     // the shape it morphs into (= field when not morphing)

vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }
vec2 buv(vec2 p) { return clamp((origin + p) / backdropSize, vec2(0.0), vec2(1.0)); }
vec2 suv(vec2 p) { return clamp((origin + p + sharpInset) / (backdropSize + 2.0 * sharpInset), vec2(0.0), vec2(1.0)); }
vec3 seen(vec2 p) { return max(texture(sharp, suv(p)).rgb - dim, 0.0); }   // clear glass: the unblurred scene (dimmed like the backdrop), only bent
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
// the (morphed) field at uv: coverage from an interpolated implicit shape, anti-aliased by its screen derivative (aa),
// height clipped to it, wide blur. The implicit is the crisp outline field (a) at the ends of a morph and, towards the
// middle, the smooth height field (g, also 0.5 on a straight outline): the outline then travels gradually across the
// glass instead of flipping at once
float sm(float t) { return t * t * (3.0 - 2.0 * t); }
float implicitAt(vec4 a, vec4 b) {
    float s = sm(morph);
    return mix(mix(a.a, b.a, s), mix(a.g, b.g, s), sin(3.14159265 * morph));
}
vec4 fieldAt(vec2 uv, float aa) {
    vec4 a = texture(field, uv);
    if (morph <= 0.0005) return vec4(a.r, a.g * a.r, a.b, a.a);
    vec4 b = texture(field2, uv);
    float s = sm(morph);
    float cov = clamp(0.5 + (implicitAt(a, b) - 0.5) / aa, 0.0, 1.0);
    return vec4(cov, mix(a.g, b.g, s) * cov, mix(a.b, b.b, s), 0.0);
}
float aaw = 1.0;
float height(vec2 uv) { return fieldAt(uv, aaw).g; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5; }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * itemSize;
    vec2 px = 1.0 / itemSize;
    float imp = implicitAt(texture(field, uv), texture(field2, uv));
    aaw = max(fwidth(imp), 1e-4);
    vec4 f = fieldAt(uv, aaw);
    float cov = f.r;

    vec3 around = texture(backdrop, buv(p)).rgb;          // the surroundings (no glass)
    float L0 = luma(around);
    float lightBg = smoothstep(0.3, 0.75, L0);
    vec2 L = normalize(lightDir + vec2(1e-5, 0.0));

    // behind the glass, away from the light: a soft shadow, and a faint caustic (light focused by the tubes, in the
    // colour of what they refract) a little further out
    vec2 away = -L * radius;
    float sh = fieldAt(uv - away * 0.35 * px, aaw).b;
    float ca = fieldAt(uv - away * 0.9 * px, aaw).b;
    float outside = 1.0 - cov;
    float shadowA = shade * mix(0.5, 0.4, lightBg) * smoothstep(0.0, 0.8, sh) * outside;
    float caustic = 0.12 * smoothstep(0.15, 0.6, ca) * (1.0 - smoothstep(0.1, 0.7, sh)) * outside;
    vec3 causticC = clamp(around * 2.2 + 0.05, 0.0, 1.0);
    vec4 behind = over(vec4(causticC * caustic, caustic), vec4(0.0, 0.0, 0.0, shadowA));
    if (cov <= 0.002) {
        fragColor = vec4(behind.rgb + hash(gl_FragCoord.xy) / 255.0 * behind.a, behind.a) * qt_Opacity;
        return;
    }

    // surface normal from the smooth height field (glassfield.frag): flat on top, tilting towards the outline, no ridge
    float k = 1.5;
    vec2 gr = vec2(height(uv + vec2(k * px.x, 0.0)) - height(uv - vec2(k * px.x, 0.0)),
                   height(uv + vec2(0.0, k * px.y)) - height(uv - vec2(0.0, k * px.y))) * heightScale / (2.0 * k);
    float slope = length(gr);
    vec2 outward = slope > 1e-5 ? -gr / slope : vec2(0.0);
    float t = slope / sqrt(1.0 + slope * slope);                      // sine of the tilt: 0 on top, -> 1 at the rim
    t = min(pow(t, 1.0 / max(edgeCurve, 0.2)), 0.995);
    vec3 N = vec3(outward * t, sqrt(1.0 - t * t));                    // outward-facing surface normal (z = viewer)

    // refraction: what lies behind is seen bent outwards along the normal (more near the rim), split by colour
    vec2 disp = N.xy * refraction;
    vec2 sp = p + disp;
    vec3 col = seen(sp);
    float ab = max(aberration, 0.08) * 2.0;
    col.r = seen(sp + disp * ab).r;
    col.b = seen(sp - disp * ab).b;

    // material, light-handed: saturation, a thin tint (denser where the glass is steep), a little darkening
    col = mix(vec3(luma(col)), col, clamp(saturation, 0.0, 3.0));
    float transmission = exp(-tint.a * 0.15 * mix(0.6, 1.0, t));
    col = col * transmission + tint.rgb * (1.0 - transmission);
    col *= 1.0 - 0.12 * clamp(darkening, 0.0, 1.0);

    // steep glass bends light away: a darker band towards the rim (stronger on light backdrops)
    float steep = smoothstep(0.45, 0.92, t);
    col *= 1.0 - steep * (0.18 + 0.3 * lightBg);

    // state colour (glow), under the light
    col = mix(col, glow.rgb * (0.75 + 0.5 * (1.0 - t)), glow.a);

    // reflection (fresnel: ~4 % face on, all of it at grazing angles) of a soft studio: a broad light from
    // light_angle and a dim sky above. Clear glass on a black backdrop reads by this and the highlights alone
    vec3 L3 = normalize(vec3(L, 0.75));
    vec3 R = vec3(2.0 * N.z * N.xy, 2.0 * N.z * N.z - 1.0);
    float env = 1.25 * smoothstep(0.0, 0.95, dot(R, normalize(vec3(L, 0.35)))) + 0.15 * smoothstep(0.1, -0.9, R.y);
    float F = 0.02 + 0.98 * pow(t, 7.0);   // by tilt, steep: only the rim mirrors, the body stays clear
    col += vec3(env * F) * (1.0 - 0.5 * lightBg);
    // inner glow: light carried along inside the tube, on its far wall
    float back = max(dot(N, normalize(vec3(-L, 0.6))), 0.0);
    col += vec3(1.0) * pow(back, 3.0) * smoothstep(0.3, 0.9, t) * 0.08 * (1.0 - 0.5 * lightBg);
    // highlights, kept soft: a broad lobe along each stroke where it faces the light, a gentle core, a weak back
    // reflection on the far side (specular_intensity / power raise them; never below a small floor)
    vec3 H = normalize(L3 + vec3(0.0, 0.0, 1.0));
    float ndh = max(dot(N, H), 0.0);
    float shin = clamp(specPower, 8.0, 200.0);
    float hiAmt = 0.16 + 0.22 * clamp(specular, 0.0, 3.0);
    float hi = pow(ndh, shin * 0.6) * 0.45 + pow(ndh, shin * 2.0) * 0.35;
    vec3 H2 = normalize(vec3(-L, 0.75) + vec3(0.0, 0.0, 1.0));
    float hi2 = pow(max(dot(N, H2), 0.0), shin * 1.0) * 0.12;
    col += vec3(1.0) * (hi + hi2) * hiAmt;
    col += vec3(1.0) * sheen * 0.2 * max(dot(N, L3), 0.0) * (1.0 - t);
    // over light backdrops the very outline turns dark (the bent edge), as glass reads on a bright ground
    float outline = smoothstep(0.9, 0.99, t);
    col = mix(col, around * 0.4, outline * lightBg * 0.5);

    vec4 body = vec4(clamp(col, 0.0, 1.0) * cov, cov);
    vec4 outc = over(body, behind);
    // dither +-0.5 LSB: no banding in the soft shadow / glow gradients
    outc.rgb += hash(gl_FragCoord.xy) / 255.0 * outc.a;
    fragColor = outc * qt_Opacity;
}
