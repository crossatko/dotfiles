#version 440
// Unlock transition of the lock screen (LockReveal.qml): a glass ring expands from `centre` and reveals the desktop
// snapshot behind it. Inside the ring: the snapshot; outside: the lock scene; across the ring (`band` px): a glass tube
// that bends both with a chromatic split, catches a soft highlight from `lightDir` and blends one into the other.
// progress 0 = all lock, 1 = all snapshot (the ring has passed every corner).
// Build: /usr/lib/qt6/bin/qsb --qt6 -o lockreveal.frag.qsb lockreveal.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 centre;        // px
    float maxRadius;    // px: distance from centre to the farthest corner
    float band;         // px: width of the glass ring
    float progress;
    vec2 lightDir;      // y down
};
layout(binding = 1) uniform sampler2D lockScene;
layout(binding = 2) uniform sampler2D snapshot;

vec3 tap(sampler2D t, vec2 p) { return texture(t, clamp(p / itemSize, vec2(0.0), vec2(1.0))).rgb; }

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 d = p - centre;
    float dist = length(d);
    vec2 dir = dist > 1e-3 ? d / dist : vec2(0.0, -1.0);
    float r = progress * (maxRadius + 2.0 * band) - band;          // ring centre line
    float u = clamp((dist - r) / band, -1.0, 1.0);                  // -1 inner edge .. 1 outer edge of the ring
    float inRing = 1.0 - smoothstep(0.85, 1.0, abs(u));
    float slope = u / sqrt(max(1.0 - u * u, 0.02));                 // round tube cross-section
    vec2 bend = dir * clamp(slope, -3.0, 3.0) * band * 0.35 * inRing;
    float mixAt = smoothstep(0.6, -0.6, u);                         // 1 inside (snapshot) .. 0 outside (lock)
    vec3 snapC = vec3(tap(snapshot, p - bend * 1.06).r, tap(snapshot, p - bend).g, tap(snapshot, p - bend * 0.94).b);
    vec3 lockC = vec3(tap(lockScene, p + bend * 1.06).r, tap(lockScene, p + bend).g, tap(lockScene, p + bend * 0.94).b);
    vec3 col = mix(lockC, snapC, mixAt);
    // the tube catches light: a soft highlight where its side faces the light, a faint rim
    float h = sqrt(max(1.0 - u * u, 0.0));
    vec3 N = normalize(vec3(dir * u, h + 0.05));
    vec3 H = normalize(normalize(vec3(lightDir, 0.75)) + vec3(0.0, 0.0, 1.0));
    float hi = pow(max(dot(N, H), 0.0), 24.0) * 0.35 + pow(abs(u), 6.0) * 0.08;
    col += vec3(hi) * inRing * (1.0 - smoothstep(0.9, 1.0, progress));
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    fragColor = vec4(col + n / 255.0, 1.0) * qt_Opacity;
}
