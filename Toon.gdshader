shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec3 albedo : source_color = vec3(1.0);
uniform sampler2D texture_albedo : source_color;
uniform float specular = 0.5;
uniform float roughness : hint_range(0,1) = 0.5;

uniform float cuts : hint_range(1, 8) = 3.0;
uniform float wrap : hint_range(0, 1) = 0.0;
uniform float steepness : hint_range(1, 20) = 1.0;

uniform float sway_speed : hint_range(0.0, 5.0) = 1.0;
uniform float sway_strength : hint_range(0.0, 1.0) = 0.1;

void vertex() {
	// Simple procedural sway based on world position and time
	float sway = sin(TIME * sway_speed + VERTEX.x * 2.0) * sway_strength;
	VERTEX.x += sway * VERTEX.y * 0.1; // Sway stronger at the top
}

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo * albedo_tex.rgb;
	SPECULAR = specular;
	ROUGHNESS = roughness;
}

void light() {
	float dot_product = dot(NORMAL, LIGHT);
	float diffuse_amount = clamp((dot_product + wrap) / (1.0 + wrap), 0.0, 1.0);
	float toon_diffuse = floor(diffuse_amount * cuts) / (cuts - 0.5);
	
	// Add some smoothness to the edges of the cuts
	toon_diffuse = clamp(toon_diffuse * steepness, 0.0, 1.0);
	
	DIFFUSE_LIGHT += toon_diffuse * ATTENUATION * LIGHT_COLOR * ALBEDO;
}
