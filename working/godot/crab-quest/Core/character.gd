extends Node3D

@onready var model_root: Node3D = $CharacterGLB 

# Animation Parameters
@export var bounce_freq: float = 10.0
@export var bounce_amp: float = 0.15
@export var step_rate: float = 0.1 

# Runtime State
var time_passed: float = 0.0
var current_velocity: Vector3 = Vector3.ZERO
var weapon_pull_dir: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Add shadow
	var shadow_scene = load("res://Core/shadow.tscn")
	if shadow_scene:
		var shadow = shadow_scene.instantiate()
		add_child(shadow)
		shadow.base_scale = 0.75
		
	# Try to find the model if it's named differently
	if not model_root:
		for child in get_children():
			if child is Node3D and child.name != "Shadow":
				model_root = child
				break
	
	# Standard Material setup - Unshaded for pure vertex colors
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	set_skin_material(mat)

func _physics_process(delta: float) -> void:
	if current_velocity.length() > 0.1:
		time_passed += delta * 1.5 
	else:
		time_passed = move_toward(time_passed, 0.0, delta * 2.0)
	
	_animate_clipped(delta)

func _animate_clipped(_delta: float) -> void:
	if not model_root: return
	
	var snapped_time = snapped(time_passed, step_rate)
	
	# 1. Vertical Bounce (Stepped)
	var bounce = sin(snapped_time * bounce_freq) * bounce_amp
	model_root.position.y = max(0.0, bounce) 
	
	# 2. Rotation
	if current_velocity.length() > 0.1:
		var target_rot = atan2(current_velocity.x, current_velocity.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 0.2)

	# 3. Squash and Stretch (Stepped)
	var speed_factor = clamp(current_velocity.length() / 10.0, 0.0, 1.0)
	var squash = 1.0 + (bounce * 0.5 * speed_factor)
	model_root.scale.y = snapped(squash, 0.05) 
	model_root.scale.x = snapped(2.0 - squash, 0.05)
	model_root.scale.z = model_root.scale.y

func update_state(vel: Vector3, weapon_dir: Vector3) -> void:
	current_velocity = vel
	weapon_pull_dir = weapon_dir

func set_skin_material(mat: Material) -> void:
	if model_root:
		_apply_material_recursive(model_root, mat)

func _apply_material_recursive(node: Node, mat: Material):
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)

func cough() -> void:
	if model_root:
		var tween = create_tween()
		tween.tween_property(model_root, "scale", Vector3(1.5, 1.5, 1.5), 0.05).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(model_root, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_BOUNCE)
