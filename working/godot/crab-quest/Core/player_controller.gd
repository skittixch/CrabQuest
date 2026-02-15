extends CharacterBody3D
## Player Controller - Drives movement and weapon physics
## This script decouples the player logic from the main game scene.

signal took_damage(new_health, amount)

@export_group("References")
@export var input_layer: Control
@export var camera: Node3D
@export var weapon_ball: RigidBody3D
@export var chain: Node3D
@export var character_visuals: Node3D # Core/character.gd

@export_group("Movement")
@export var move_speed: float = 8.0
@export var knockback_decay: float = 20.0 # Faster recovery for high speed testing

@export_group("Weapon Physics")
@export var spring_strength: float = 300.0
@export var spring_damping: float = 15.0
@export var max_weapon_range: float = 4.0
@export var repulsion_strength: float = 1200.0
@export var repulsion_radius: float = 2.2
@export var visual_z_compensation: float = 1.3 # Stretch Z-axis to make swing look circular in skewed camera

# State
var knockback_velocity: Vector3 = Vector3.ZERO
var player_facing: Vector3 = Vector3.FORWARD
var weapon_target_pos: Vector3 = Vector3.ZERO
var current_max_range: float = 4.0

@export_group("Stats")
@export var max_health: float = 300.0
@export var iframe_duration: float = 1.0
@onready var health: float = max_health
var iframe_timer: float = 0.0

var _last_move_input: Vector2 = Vector2.ZERO
var _last_weapon_dir: Vector2 = Vector2.ZERO
var _last_weapon_mag: float = 0.0

var controls_enabled: bool = true # Default to true for testing in isolated scenes
func _ready() -> void:
	add_to_group("Player")
	
	if not camera:
		camera = get_viewport().get_camera_3d()
	
	# Initial Setup - Handled via late-binding in physics process for robustness
	_ensure_input_layer()
	_ensure_weapon_linkage()

	# Initial weapon target
	weapon_target_pos = global_position + Vector3(0, 0.5, 2)
	
	# Pass-through exception
	if is_instance_valid(weapon_ball):
		weapon_ball.add_collision_exception_with(self)
	
	# Connect Pickup Sensor
	var sensor = get_node_or_null("PickupSensor")
	if sensor:
		sensor.body_entered.connect(_on_pickup_entered)

func _on_pickup_entered(body: Node3D) -> void:
	if body.has_method("collect"):
		var recovered = body.collect()
		if recovered > 0:
			heal(recovered)
			if character_visuals:
				character_visuals.play_heal_effect()

func _on_movement_input(_velocity: Vector2) -> void:
	pass # Handled in physics process for continuous update

func _on_weapon_input(_direction: Vector2, _magnitude: float) -> void:
	pass # Handled in physics process

var _input_connected: bool = false
func _ensure_input_layer() -> bool:
	if _input_connected and is_instance_valid(input_layer):
		return true
		
	# Attempt resolution if it's currently null or invalid
	if not is_instance_valid(input_layer):
		input_layer = get_tree().get_first_node_in_group("InputLayer")
		if not input_layer and has_node("../InputLayer"):
			input_layer = get_node("../InputLayer")
	
	# If we found it now, connect
	if is_instance_valid(input_layer):
		print("PlayerController: Safely connecting to InputLayer: ", input_layer.name)
		_input_connected = true
		if input_layer.has_signal("movement_input"):
			input_layer.movement_input.connect(func(v): _last_move_input = v)
		if input_layer.has_signal("weapon_input"):
			input_layer.weapon_input.connect(func(d, m): 
				_last_weapon_dir = d
				_last_weapon_mag = m
			)
		return true
	return false

var _weapon_linked: bool = false
func _ensure_weapon_linkage() -> bool:
	if _weapon_linked: return true
	
	# Resolve references if null (NodePath conversion)
	if not chain: chain = get_node_or_null("../Chain")
	if not weapon_ball: weapon_ball = get_node_or_null("../MorningstarPhysics")
	
	if chain and weapon_ball:
		var handle = get_node_or_null("Handle")
		if handle:
			print("PlayerController: Linking Chain and Ball to Handle.")
			chain.setup(handle, weapon_ball, self)
			if "player" in weapon_ball: weapon_ball.player = self
			if "chain_node" in weapon_ball: weapon_ball.chain_node = chain
			weapon_ball.add_collision_exception_with(self)
			_weapon_linked = true
			return true
	return false

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		# Still update visuals if needed, but skip physics/input
		if character_visuals and character_visuals.has_method("update_state"):
			character_visuals.update_state(Vector3.ZERO, (weapon_ball.global_position - global_position) if weapon_ball else Vector3.ZERO)
		return

	_ensure_input_layer()
	_ensure_weapon_linkage()

	var move_input := _last_move_input
	var weapon_dir_vec2 := _last_weapon_dir
	var weapon_mag := _last_weapon_mag
	
	# Polling fallback if signals didn't update OR signals connected late
	if is_instance_valid(input_layer) and input_layer.get("touch_active"):
		var current_touch = input_layer.get("current_touch")
		var start_anchor = input_layer.get("start_anchor")
		var drift_anchor = input_layer.get("drift_anchor")
		var max_r = input_layer.get("max_movement_radius")
		
		if current_touch != null and start_anchor != null:
			# Direct calculation for robustness
			var m_vec = current_touch - start_anchor
			move_input = m_vec / (max_r if max_r > 0 else 100.0)
			if move_input.length() > 1.0:
				move_input = move_input.normalized()
				
			var w_vec = current_touch - drift_anchor
			weapon_dir_vec2 = w_vec.normalized()
			weapon_mag = w_vec.length()

	# 1. Movement Calculations
	var move_velocity: Vector3 = Vector3.ZERO
	var relative_weapon_dir := Vector3.ZERO
	
	if camera:
		var cam_basis = camera.global_transform.basis
		var forward = Vector3(cam_basis.z.x, 0, cam_basis.z.z).normalized()
		var right = Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
		
		
		var relative_move_dir = (right * move_input.x) + (forward * move_input.y)
		move_velocity = relative_move_dir * move_speed
		
		# Apply Z-compensation to weapon input to counteract perspective foreshortening
		relative_weapon_dir = (right * weapon_dir_vec2.x) + (forward * (weapon_dir_vec2.y * visual_z_compensation))
	else:
		move_velocity = Vector3(move_input.x, 0, move_input.y) * move_speed
		# Fallback for no camera (rarely used but good for safety)
		relative_weapon_dir = Vector3(weapon_dir_vec2.x, 0, weapon_dir_vec2.y * visual_z_compensation)

	# Apply Gravity
	var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	velocity.x = move_velocity.x + knockback_velocity.x
	velocity.z = move_velocity.z + knockback_velocity.z
	
	move_and_slide()
	
	# Decay knockback
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, delta * knockback_decay)
	if knockback_velocity.length() < 0.1:
		knockback_velocity = Vector3.ZERO
		
	# Update i-frame timer and visuals
	if iframe_timer > 0:
		iframe_timer -= delta
		if character_visuals:
			character_visuals.visible = (int(Time.get_ticks_msec() / 50.0) % 2 == 0)
	elif character_visuals and not character_visuals.visible:
		character_visuals.visible = true
		
	# Update facing
	if move_velocity.length() > 0.1:
		player_facing = move_velocity.normalized()
		var target_basis = Basis.looking_at(player_facing, Vector3.UP)
		global_basis = global_basis.orthonormalized().slerp(target_basis, delta * 12.0).orthonormalized()

	# 2. Weapon Physics Logic
	if weapon_ball:
		if weapon_mag > 10.0:
			# ACTIVE
			var target_dist: float = clamp(weapon_mag / 40.0, 1.0, max_weapon_range)
			weapon_target_pos = global_position + (relative_weapon_dir * target_dist) + Vector3(0, 0.5, 0)
		else:
			# IDLE
			var home_dist: float = 2.0
			weapon_target_pos = global_position + (player_facing * home_dist) + Vector3(0, 0.3, 0)


		# Apply forces to ball
		var to_target: Vector3 = weapon_target_pos - weapon_ball.global_position
		var active_spring_strength = spring_strength if weapon_mag > 10.0 else 150.0
		var spring_force: Vector3 = (to_target * active_spring_strength).limit_length(5000.0) # Cap force
		var damp_force: Vector3 = -weapon_ball.linear_velocity * spring_damping
		
		# Repulsion
		var repulsion_force := Vector3.ZERO
		var dist_player_ball = global_position.distance_to(weapon_ball.global_position)
		if dist_player_ball < repulsion_radius:
			var r_dir = (weapon_ball.global_position - global_position).normalized()
			var r_factor = pow(1.0 - (dist_player_ball / repulsion_radius), 2)
			repulsion_force = r_dir * repulsion_strength * r_factor
			
		weapon_ball.apply_central_force(spring_force + damp_force + repulsion_force)

	# 3. Update Visuals & Camera
	if character_visuals and character_visuals.has_method("update_state"):
		character_visuals.update_state(move_velocity, (weapon_ball.global_position - global_position) if weapon_ball else Vector3.ZERO)

	if camera and "look_at_target" in camera:
		camera.set("look_at_target", global_position)

	# Update handle rotation
	var handle = get_node_or_null("Handle")
	if handle and weapon_ball:
		var target_look = weapon_ball.global_position
		if (target_look - handle.global_position).length() > 0.1:
			handle.look_at(target_look, Vector3.UP)

func enable_controls() -> void:
	controls_enabled = true
	if is_instance_valid(weapon_ball):
		weapon_ball.freeze = false

func disable_controls() -> void:
	controls_enabled = false
	velocity = Vector3.ZERO
	if is_instance_valid(weapon_ball):
		weapon_ball.freeze = true

func take_damage(amount: float) -> void:
	if iframe_timer > 0:
		return
		
	health = max(0.0, health - amount)
	iframe_timer = iframe_duration
	took_damage.emit(health, amount)
	
	if health <= 0:
		_die()

## receive_hit
## The central entry point for all combat damage. 
## Handles iframes and feedback.
func receive_hit(attacker_pos: Vector3, damage_amount: float = 25.0) -> bool:
	if iframe_timer > 0:
		return false # ABSOLUTELY NO damage or feedback during iframes
		
	# 1. FEEDBACK
	# Vibration (Haptics)
	Input.vibrate_handheld(200) # Moderate buzz for damage
	
	# Screen Shake
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.5)
			
	# Sound (Tick)
	if get_tree().root.has_node("ProceduralAudio"):
		get_tree().root.get_node("ProceduralAudio").call("play_tick", 1, 800.0)
		
	# Knockback
	var push_dir = (global_position - attacker_pos).normalized()
	push_dir.y = 0
	knockback_velocity = push_dir * 12.0
	
	# 2. APPLY
	take_damage(damage_amount)
	return true

func heal(amount: float) -> void:
	health = min(max_health, health + amount)
	# Emit signal with negative damage_amount (0) to trigger a non-splash sync
	took_damage.emit(health, 0)

func _die() -> void:
	# Basic death logic - can be expanded
	disable_controls()
	print("Player DIED!")
	
	# Delay for animation/drama
	await get_tree().create_timer(2.0).timeout
	
	# Reload Scene
	get_tree().reload_current_scene()
