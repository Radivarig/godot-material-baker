shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2DArray albedo_height_array : source_color;
uniform sampler2DArray normal_roughness_array : hint_normal;

uniform float height_scale : hint_range(0.0, 0.3) = 0.1;

varying flat int array_index;

void vertex() {
	array_index = int(INSTANCE_CUSTOM.r);
	vec4 albedo_height = texture(albedo_height_array, vec3(UV, float(array_index)));
	VERTEX += NORMAL * albedo_height.a * height_scale;
}

void fragment() {
	vec4 albedo_height = texture(albedo_height_array, vec3(UV, float(array_index)));
	vec4 normal_roughness = texture(normal_roughness_array, vec3(UV, float(array_index)));
	
	ALBEDO = albedo_height.rgb;
	NORMAL_MAP = normal_roughness.rgb;
	ROUGHNESS = normal_roughness.a;
}
