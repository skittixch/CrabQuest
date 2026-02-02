shader_type spatial;
render_mode blend_mix, depth_test_disabled, cull_front, unshaded, shadows_disabled;

// --- DIRECTIONAL X-RAY OVERLAY LAYER ---
// Re-implements the "2pt" directional logic for wall footprints.
// Lines only show if the face normal is pointing TOWARD the camera (backfacing relative to floor)

uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float atlas_size = 4.0;
uniform float xray_opacity = 0.0;

varying vec2 v_uv;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // We need the normal to check directional visibility
    world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_uv = UV;
}

void fragment() {
    // 1. DIRECTIONAL VISIBILITY CHECK
    // Calculate if this face is pointing towards the camera (relative to the camera's view vector)
    vec3 view_dir = normalize(world_pos - camera_pos);
    float dot_nv = dot(world_normal, view_dir);
    
    // IF dot(N, V) > 0.05, it's a "back-facing" wall surface relative to the view
    // Since we are CULL_FRONT, we are rendering the BACK FACES.
    // We want to see the lines on the FAR side of the wall (the "back" of the layout).
    float directional_mask = smoothstep(0.05, 0.25, dot_nv);
    
    // 2. OCCLUSION LOGIC
    float player_to_cam = length(player_pos.xz - camera_pos.xz);
    float frag_to_cam = length(world_pos.xz - camera_pos.xz);
    // Strict Check: Wall must be CLOSER to camera than player by at least 0.2m
    float occluder_mask = smoothstep(player_to_cam - 0.2, player_to_cam - 1.0, frag_to_cam);
    
    // 3. RADIUS MASK
    float dist_to_player = distance(world_pos.xz, player_pos.xz);
    float radial_mask = smoothstep(5.0, 3.0, dist_to_player);
    
    // Combined visibility
    float total_mask = directional_mask * occluder_mask * radial_mask;
    
    // 4. DRAW FOOTPRINT LINE (Based on World Y)
    // Map line to the absolute floor level (y=0 to y=0.04) -> 4cm thin line
    float height_above_floor = max(0.0, world_pos.y);
    float line_mask = smoothstep(0.04, 0.005, height_above_floor);
    
    // FINAL COMPOSITE
    ALBEDO = vec3(1.0); 
    ALPHA = line_mask * total_mask * 0.95 * xray_opacity;
}
