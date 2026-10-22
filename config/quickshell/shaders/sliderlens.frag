#version 440
// Slider lens (Slider.qml): draws a captured card (ShaderEffectSource of the whole card, hidden while this runs) as is,
// except inside a small round lens (squircle / circle, 1:1), where it is refracted with the optics of the compositor's
// solid_glass (Hyprland fork, solidglassfinish.frag) and the SAME Settings > Glass values, so the lens matches the
// popup glass: bend (refraction, bulb, depth, edge_curve), chromatic split (aberration), frost / clarity, specular
// rim / counter rim / sheen / inner shadow (light_angle, specular_intensity, specular_power, sheen).
// Not applied: tint, darkening, saturation. Those act on the BACKDROP, and the lens sits inside the card's own
// compositor glass region, which already applies them to the wallpaper behind the card; the shell content is drawn
// on top of that glass untinted, so the lens keeps it untinted too (applying them again would double them, and the
// absorption of a dark tint would black out the slider).
// Differences to the compositor: the shell's own premultiplied sRGB pixels, not linear light; the bend of a bead is
// refraction * depth * (bulb share) capped at 0.75 x the bulb (the compositor's sqrt share and 1.5 x cap pull the
// track to the rim of a 28 px lens), plus a centre magnification from depth. Plus a soft drop shadow. Sizes in item px.
// Build: /usr/lib/qt6/bin/qsb --qt6 -o sliderlens.frag.qsb sliderlens.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // effect (= card + margin) size
    vec2 lensCenter;
    float lensHalf;     // half size (the lens is square: 1:1)
    float radius;       // corner radius (lensHalf = fully round)
    float power;        // corner shape: 2 = circular, 4 = squircle
    float amount;       // 0 = pass-through, 1 = full lens
    float refraction;   // px          (solid_glass:refraction)
    float bulb;         // px          (solid_glass:bulb)
    float depth;        //             (solid_glass:depth)
    float edgeCurve;    //             (solid_glass:edge_curve)
    float aberration;   //             (solid_glass:aberration)
    vec2 lightDir;      // y down      (solid_glass:light_angle)
    float specular;     //             (solid_glass:specular_intensity)
    float specPower;    //             (solid_glass:specular_power)
    float sheen;        //             (solid_glass:sheen)
    float frost;        // px          (solid_glass:frost, plus clarity)
    float mag;          // centre magnification of a bead, 1 + 0.35 x depth
    float shade;        // drop shadow alpha
};
layout(binding = 1) uniform sampler2D source;

float slen(vec2 v, float p) {
    v = abs(v);
    float s = max(max(v.x, v.y), 1.0);
    v /= s;
    return pow(pow(v.x, p) + pow(v.y, p), 1.0 / p) * s;
}
// rounded box with superellipse corners (as solid_glass roundedBoxSDF)
float sdBox(vec2 p, float h, float r, float pw) {
    r = clamp(r, 0.0, h);
    vec2 o = abs(p) - vec2(h - r);
    return slen(max(o, 0.0), pw) + min(max(o.x, o.y), 0.0) - r;
}
vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }
vec4 tap(vec2 p) { return texture(source, p / itemSize); }

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 q = p - lensCenter;
    float sd = sdBox(q, lensHalf, radius, power);
    vec4 base = tap(p);

    // soft drop shadow (outside the lens only)
    float ssd = sdBox(q - vec2(0.0, 1.5), lensHalf, radius, power);
    float sh = shade * amount * (1.0 - smoothstep(-1.5, 4.0, ssd));
    vec4 outside = over(vec4(0.0, 0.0, 0.0, sh), base);
    if (sd > 1.0 || amount <= 0.0) {
        fragColor = outside * qt_Opacity;
        return;
    }

    vec2 e = vec2(0.5, 0.0);
    vec2 n = vec2(sdBox(q + e.xy, lensHalf, radius, power) - sdBox(q - e.xy, lensHalf, radius, power),
                  sdBox(q + e.yx, lensHalf, radius, power) - sdBox(q - e.yx, lensHalf, radius, power));
    n = length(n) > 1e-4 ? normalize(n) : vec2(0.0, -1.0);
    float d = max(0.0, -sd);

    // solid_glass optics: convex profile over the bulb, rim samples pulled in from further inside
    float sb = clamp(bulb, 1.0, max(lensHalf, 1.0));
    float edge = 1.0 - clamp(d / sb, 0.0, 1.0);
    float lens = pow(1.0 - sqrt(max(1.0 - edge * edge, 0.0)), edgeCurve);
    float thin = clamp(sb / max(bulb, 1.0), 0.0, 1.0);
    float bend = min(refraction * depth * thin, sb * 0.75) * lens * amount;
    vec2 disp = -n * bend;

    // frost: 13 taps on two hex rings (frost px), the centre tap kept for the chromatic split
    // a bead also magnifies its middle (no rim jump: it fades in over the bulb)
    vec2 sp = lensCenter + mix(q, q / mag, amount * smoothstep(0.0, 1.0, d / sb)) + disp;
    vec4 centre = tap(sp);
    vec4 glass = centre;
    if (frost > 0.05) {
        glass *= 2.0;
        for (int i = 0; i < 6; i++) {
            float a = float(i) * 1.0471976 + 0.5235988;
            vec2 dir = vec2(cos(a), sin(a));
            glass += tap(sp + dir * frost * 0.5) + tap(sp + dir * frost) * 0.5;
        }
        glass /= 11.0;
    }
    if (aberration > 0.0001 && dot(disp, disp) > 0.0025) {
        glass.r += tap(sp + disp * aberration).r - centre.r;
        glass.b += tap(sp - disp * aberration).b - centre.b;
        glass = max(glass, vec4(0.0));
    }

    // lighting (scaled by specular_intensity, nothing without it): thin rim lit from lightDir, softer counter rim,
    // sheen on the lit side, inner edge shadow
    if (specular > 0.0) {
        vec2 L = normalize(lightDir + vec2(0.00001, 0.0));
        float facing = dot(n, L);
        float rimW = clamp(sb * 0.04, 1.2, 3.0);
        float rim = exp(-d / rimW);
        float soft = exp(-d / max(sb * 0.3, 1.0));
        float ex = max(specPower / 24.0, 0.5);
        float key = pow(max(facing, 0.0), ex);
        float counter = pow(max(-facing, 0.0), ex);
        float hl = rim * (0.25 + 1.6 * key + 0.7 * counter) + soft * (0.16 * key + 0.06 * counter);
        hl += sheen * soft * smoothstep(-0.2, 0.9, facing) * 1.5;
        float shadow = soft * (1.0 - rim) * (0.12 + 0.12 * max(-facing, 0.0));
        glass.rgb *= 1.0 - shadow * specular * amount;
        float a = clamp(hl * specular * amount, 0.0, 1.0);
        glass = over(vec4(vec3(a), a), glass);
    }

    float cov = clamp(0.5 - sd, 0.0, 1.0);
    fragColor = mix(outside, glass, cov) * qt_Opacity;
}
