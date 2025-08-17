shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 rim_color : hint_color = vec4(0.04, 0.04, 0.05, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.2;
uniform float vignette : hint_range(0.0, 2.0) = 0.35;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float rim = smoothstep(0.2, 1.0, dist);
	float v = smoothstep(1.0, vignette, dist);
	vec4 base = texture(TEXTURE, UV);
	COLOR = mix(base, base + rim_color * rim_strength, rim * 0.35) * (1.0 - v * 0.15);
}
