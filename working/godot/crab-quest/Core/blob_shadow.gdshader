shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

instance uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
instance uniform float softness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    float dist = distance(UV, vec2(0.5));
    // Use fwidth for a sharp but anti-aliased edge
    float edge = 0.5;
    float alpha = smoothstep(edge, edge - softness - 0.01, dist);
    
    ALBEDO = shadow_color.rgb;
    ALPHA = shadow_color.a * alpha;
}
