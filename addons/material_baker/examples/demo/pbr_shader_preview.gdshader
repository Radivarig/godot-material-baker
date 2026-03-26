shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_height : source_color;
uniform sampler2D normal_roughness : hint_normal;

uniform float height_scale : hint_range(0.0, 0.3) = 0.1;

void vertex() {
	vec4 ah = texture(albedo_height, UV);
	VERTEX += NORMAL * ah.a * height_scale;
}

void fragment() {
	vec4 ah = texture(albedo_height, UV);
	vec4 nr = texture(normal_roughness, UV);

	ALBEDO = ah.rgb;
	NORMAL_MAP = nr.rgb;
	ROUGHNESS = nr.a;
}
