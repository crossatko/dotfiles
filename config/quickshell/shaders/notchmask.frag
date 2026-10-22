#version 440
// Notched card (NotchMask.qml, a `layer.effect`): draws the card's layer (fill, border, hover glow, content) as is,
// except inside up to 4 round notches (the link buttons of MonitorCardRow), which are cut out with an antialiased
// edge, and a border of the card's colour and width along each cut, so the outline follows the notch. The border
// band is clipped to the card's rounded rect, so a notch over a corner keeps the corner shape. Sizes in item px.
// Build: /usr/lib/qt6/bin/qsb --qt6 -o notchmask.frag.qsb notchmask.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;       // card corner radius
    float borderWidth;
    vec4 borderRgba;    // straight (not premultiplied) rgba
    vec4 n0;            // notch: xy = centre, z = radius (0 = none)
    vec4 n1;
    vec4 n2;
    vec4 n3;
};
layout(binding = 1) uniform sampler2D source;

float hole(vec2 p, vec4 n) { return n.z > 0.0 ? length(p - n.xy) - n.z : 1e6; }

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    // AA: smoothstep over +-1 device px around each edge (keeps the stroke's total coverage). Qt's own AA'd rounded
    // border at the card corners spreads ~2 px per row and carries ~1.3x the ink of its straight 1 px edge, so the cut
    // stroke gets the same: width borderWidth + 0.3 px. A 1 px linear ramp on an exact 1 px stroke was crisp on some
    // rows and split over two pixels on others: visibly stepped (2026-10-22, live screenshot + nested 8x crops).
    float w = max(fwidth(p.x), 1e-4);
    float dc = min(min(hole(p, n0), hole(p, n1)), min(hole(p, n2), hole(p, n3)));   // > 0 = outside every notch
    vec2 h = itemSize * 0.5;
    float r = min(radius, min(h.x, h.y));
    vec2 q = abs(p - h) - (h - r);
    float dr = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;                     // < 0 = inside the card
    float card = clamp(0.5 - dr / w, 0.0, 1.0);                                       // pixel-aligned like the Rectangle's edge
    float hw = (borderWidth + 0.3) * 0.5;
    float band = smoothstep(-w, w, hw - abs(dc - hw)) * card;                         // stroke centred on dc = hw
    float keep = smoothstep(-w, w, dc - 2.0 * hw);                                    // beyond it: the card as drawn
    vec4 bc = vec4(borderRgba.rgb * borderRgba.a, borderRgba.a);
    fragColor = (texture(source, qt_TexCoord0) * keep + bc * band) * qt_Opacity;
}
