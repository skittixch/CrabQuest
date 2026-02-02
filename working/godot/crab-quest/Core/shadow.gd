extends MeshInstance3D

@export var max_dist: float = 5.0
@export var base_scale: float = 1.0

static var shared_shadow_mat: ShaderMaterial = null

func _ready() -> void:
	add_to_group("BlobShadow")
	
	if not shared_shadow_mat:
		var shadow_scene = load("res://Core/shadow.tscn")
		if shadow_scene:
			var temp = shadow_scene.instantiate()
			shared_shadow_mat = temp.get_active_material(0)
	
	material_override = shared_shadow_mat
	
	# Register with DebugMode if it exists for immediate visibility syncing
	var debug = get_tree().root.find_child("DebugMode", true, false)
	if debug and "layers_visible" in debug:
		visible = debug.layers_visible.get("shadows", true)
	
	# Make it independent of parent rotation if we want, but usually for blob shadows
	# they just follow the parent position.
	set_as_top_level(true)

func _physics_process(_delta: float) -> void:
	if not get_parent(): return
	
	var parent_pos = get_parent().global_position
	
	# Raycast down to find the floor accurately
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(parent_pos, parent_pos + Vector3.DOWN * 5.0)
		query.collision_mask = 1 # World/Floor layer
		var result = space_state.intersect_ray(query)
		
		if result:
			global_position = result.position + Vector3(0, 0.01, 0)
		else:
			# Fallback to a safe Y height if no floor hit
			global_position = Vector3(parent_pos.x, 0.06, parent_pos.z)
	else:
		global_position = Vector3(parent_pos.x, 0.06, parent_pos.z)
	
	# Scale shadow based on height
	var height = parent_pos.y
	var scale_factor = clamp(1.0 - (height / max_dist), 0.2, 1.0)
	scale = Vector3.ONE * base_scale * scale_factor
	
	# Shared uniform for height base alpha (using instance uniform for batching)
	var alpha = clamp(0.4 * scale_factor, 0.0, 0.4)
	set_instance_shader_parameter("shadow_color", Color(0, 0, 0, alpha))
