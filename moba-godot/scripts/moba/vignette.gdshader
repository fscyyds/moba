shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 danger_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(0.35, 0.75, dist);
	COLOR = vec4(danger_color.rgb, vignette * intensity * 0.35);
}
