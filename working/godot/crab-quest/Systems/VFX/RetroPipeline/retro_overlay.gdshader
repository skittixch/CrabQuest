shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform int pixel_size : hint_range(1, 16) = 4;
uniform float color_levels : hint_range(2.0, 32.0) = 8.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Godot 4 standard for getting viewport resolution in spatial shaders
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	
	// Snap UV to lower resolution grid
	vec2 grid_uv = floor(uv * screen_size / float(pixel_size)) / (screen_size / float(pixel_size));
	
	// Sample color at the snapped UV
	vec3 col = texture(screen_texture, grid_uv).rgb;
	
	// Posterization (Simulate limited color palette)
	col = floor(col * color_levels) / color_levels;
	
	ALBEDO = col;
}
