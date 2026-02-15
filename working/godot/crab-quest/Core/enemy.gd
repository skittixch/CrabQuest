extends RigidBody3D

const ExplosionFX = preload("res://Core/explosion_fx.tscn")
# Mocks for missing assets
var ACID_PUDDLE_SCENE: PackedScene = null 
var CRAB_MEAT_SCENE: PackedScene = null 

@onready var mesh: CSGSphere3D = $Body
var base_scale: Vector3 = Vector3.ONE
var health: int = 3
var max_health: int = 3
var hit_cooldown: float = 0.0
var health_bar_timer: float = 0.0
var detect_range: float = 12.0 # Increased range since no fog

# UI References
var hp_sprite: Sprite3D

# AI Settings
var chase_speed: float = 4.0
var acceleration: float = 20.0
var target_player: Node3D = null

# Movement variety
var strafe_offset: float = 0.0 # Current strafe direction
var strafe_timer: float = 0.0
var strafe_change_interval: float = 0.8 # How often to change strafe direction
var wobble_time: float = 0.0

# Aggressive state
@export var is_aggressive: bool = true # Default to true now
var is_alert: bool = true # Always alert now

# New States
var is_hungry: bool = false
var target_meat: Node3D = null
var is_zombie: bool = false
var eating_timer: float = 0.0
var meat_detection_radius: float = 12.0
var enemy_type: String = "Crab"

# Token Stealing
var stolen_tokens: int = 0
var steal_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("Enemy")
	base_scale = mesh.scale
	max_health = health
	
	# Randomly decide if this crab is hungry (50% chance)
	is_hungry = randf() < 0.5
	
	# SCALING: Randomize base size slightly
	var rand_scale = randf_range(0.9, 1.2)
	mesh.scale = base_scale * rand_scale
	base_scale = mesh.scale
	
	# Register with Main for cached access
	var main = get_tree().get_first_node_in_group("Main")
	if main:
		if main.has_method("register_enemy"):
			main.register_enemy(self)
		if "is_endgame_active" in main and main.is_endgame_active:
			_stomach_spawn_effect()
	
	# Add shadow
	var shadow_scene = load("res://Core/shadow.tscn")
	if shadow_scene:
		var shadow = shadow_scene.instantiate()
		add_child(shadow)
		if "base_scale" in shadow: shadow.base_scale = 0.7 
		
	# Physics for "boppable" feel
	collision_layer = 2
	collision_mask = 1 | 8 | 128 # World, Player, Weapon
	continuous_cd = true
	
	_setup_health_bar()
	
	# Auto-find player in the scene
	target_player = get_tree().get_first_node_in_group("Player")
	if not target_player:
		target_player = get_parent().get_node_or_null("PlayerBody")
	
	# Physics for "boppable" feel
	mass = 2.0 
	linear_damp = 0.5 
	angular_damp = 5.0
	
	contact_monitor = true
	max_contacts_reported = 8 
	sleeping = false
	can_sleep = false
	body_entered.connect(_on_body_entered)
	
	axis_lock_angular_z = true

	# ENSURE VISIBLE (Fog bypass)
	if mesh: mesh.visible = true

func set_aggressive(val: bool) -> void:
	is_aggressive = val
	is_alert = val

func _setup_health_bar() -> void:
	hp_sprite = Sprite3D.new()
	hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_sprite.position = Vector3(0, 1.2, 0)
	hp_sprite.modulate.a = 0.0
	hp_sprite.no_depth_test = true
	hp_sprite.fixed_size = false
	hp_sprite.pixel_size = 0.01
	
	# Generate a simple texture
	var grad = GradientTexture2D.new()
	grad.width = 64
	grad.height = 8
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(1, 0) 
	grad.gradient = Gradient.new()
	grad.gradient.interpolation_mode = 1 
	grad.gradient.set_color(0, Color(0.2, 0.9, 0.3)) # Green
	grad.gradient.set_color(1, Color(0.1, 0.1, 0.1)) # Dark
	grad.gradient.add_point(1.0, Color(0.1, 0.1, 0.1)) 
	
	hp_sprite.texture = grad
	add_child(hp_sprite)
	hp_sprite.set_meta("gradient_tex", grad)


func _stomach_spawn_effect() -> void:
	global_position.y = -1.0 
	var tween = create_tween()
	tween.tween_property(self, "global_position:y", 0.5, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.3)

func _process(delta: float) -> void:
	if hit_cooldown > 0:
		hit_cooldown -= delta
	
	if steal_cooldown > 0:
		steal_cooldown -= delta
	
	if health_bar_timer > 0:
		health_bar_timer -= delta
		
	_update_ui_visibility(delta)
	
	# Polling fallback for player detection
	if not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("Player")
	
	# Meat detection if hungry and not already tracking meat
	if is_hungry and not is_zombie and not target_meat:
		_find_nearby_meat()

func _find_nearby_meat() -> void:
	var meats = get_tree().get_nodes_in_group("Meat")
	var best_dist = meat_detection_radius
	var found_meat = null
	
	for meat in meats:
		var d = global_position.distance_to(meat.global_position)
		if d < best_dist:
			best_dist = d
			found_meat = meat
	
	if found_meat:
		target_meat = found_meat

func _update_ui_visibility(delta: float) -> void:
	if not hp_sprite: return 
	
	if health <= 0:
		hp_sprite.modulate.a = 0
		return
		
	var should_be_visible = false
	if health_bar_timer > 0:
		should_be_visible = true
	elif (health < max_health or is_alert) and target_player:
		var dist = global_position.distance_to(target_player.global_position)
		if dist < detect_range:
			should_be_visible = true
			
	var target_alpha = 1.0 if should_be_visible else 0.0
	hp_sprite.modulate.a = lerp(hp_sprite.modulate.a, target_alpha, delta * 10.0)
	hp_sprite.visible = hp_sprite.modulate.a > 0.01

func _physics_process(delta: float) -> void:
	if health <= 0 or hit_cooldown > 0:
		return
		
	# Hungry AI Priority
	if is_hungry and target_meat and is_instance_valid(target_meat):
		_process_hungry_ai(delta)
		return
	
	if not target_player: return
	if not is_alert: return
	
	# Update strafe timer for direction changes
	strafe_timer += delta
	if strafe_timer >= strafe_change_interval:
		strafe_timer = 0.0
		strafe_offset = randf_range(-0.6, 0.6) 
		strafe_change_interval = randf_range(0.5, 1.5) 
	
	# Wobble animation timer
	wobble_time += delta
	
	# Calculate direction to player (ignoring Y)
	var to_player = target_player.global_position - global_position
	to_player.y = 0
	
	if to_player.length() > 0.5:
		var dir = to_player.normalized()
		
		var strafe_dir = Vector3(-dir.z, 0, dir.x) 
		var move_dir = (dir + strafe_dir * strafe_offset).normalized()
		
		var desired_velocity = move_dir * chase_speed
		var current_velocity = linear_velocity
		current_velocity.y = 0
		
		# Separation
		var separation_force = Vector3.ZERO
		var main_node = get_tree().get_first_node_in_group("Main")
		var enemies = main_node.cached_enemies if main_node and "cached_enemies" in main_node else get_tree().get_nodes_in_group("Enemy")

		for other in enemies:
			if other == self or not is_instance_valid(other): continue
			var to_other = other.global_position - global_position
			to_other.y = 0
			var dist = to_other.length()
			if dist > 0.1 and dist < 2.0: 
				var repel_strength = (2.0 - dist) * 3.0 
				separation_force -= to_other.normalized() * repel_strength
		
		var force = (desired_velocity - current_velocity) * acceleration + separation_force
		apply_central_force(force)
		
		global_position.y = 0.5
		
		# Face TOWARD player
		var target_basis = Basis.looking_at(dir, Vector3.UP)
		basis = basis.slerp(target_basis, delta * 8.0)
		
		# Wobble
		var wobble_angle = sin(wobble_time * 10.0) * 0.1 * linear_velocity.length() / chase_speed
		rotate_object_local(Vector3.FORWARD, wobble_angle * delta * 5.0)

func hit(velocity: Vector3) -> void:
	if hit_cooldown > 0:
		return
	
	hit_cooldown = 0.3 
	
	if is_hungry:
		if randf() < 0.7: 
			is_hungry = false
			target_meat = null
			is_alert = true
	
	var flattened_velocity = velocity
	flattened_velocity.y = 0
	
	var knockback = flattened_velocity * 4.5
	apply_central_impulse(knockback)
	
	if get_tree().root.has_node("ProceduralAudio"):
		get_tree().root.get_node("ProceduralAudio").call("play_tick", 1, velocity.length()) 
	
	health -= 1
	
	if hp_sprite and hp_sprite.has_meta("gradient_tex"):
		var grad_tex = hp_sprite.get_meta("gradient_tex") as GradientTexture2D
		if grad_tex:
			var pct = float(health) / float(max_health)
			grad_tex.gradient.set_offset(1, pct)
			
	health_bar_timer = 5.0 
	
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			var intensity = clamp(velocity.length() * 0.08, 0.2, 1.0)
			cam.add_shake(intensity)
	
	if health <= 0:
		_die(velocity)
		return
	
	if mesh:
		var tween = create_tween()
		tween.tween_property(mesh, "scale", base_scale * 1.15, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(mesh, "scale", base_scale, 0.1).set_trans(Tween.TRANS_BOUNCE)

func _die(last_velocity: Vector3) -> void:
	if get_tree().root.has_node("ProceduralAudio"):
		get_tree().root.get_node("ProceduralAudio").call("play_crab_death")
	
	var main = get_tree().get_first_node_in_group("Main")
	if main and main.has_method("on_enemy_defeated"):
		main.on_enemy_defeated(enemy_type)
	
	if stolen_tokens > 0:
		_drop_stolen_tokens()
	
	if ExplosionFX:
		var fx = ExplosionFX.instantiate()
		get_parent().add_child(fx)
		fx.global_position = global_position
		
		if fx.process_material is ParticleProcessMaterial:
			if is_zombie:
				fx.process_material.color = Color(0.2, 0.8, 0.2) 
			else:
				fx.process_material.color = Color(0.8, 0.1, 0.1) 
	
	# Zombie death effect: Acid Puddle skipped for now as not migrated
	
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			var intensity = clamp(last_velocity.length() * 0.1, 0.3, 1.0)
			cam.add_shake(intensity)
		
	queue_free()

func _drop_stolen_tokens() -> void:
	if not get_tree().root.has_node("ObjectPool"): return
	
	for i in range(stolen_tokens):
		var spawn_pos = global_position + Vector3(0, 0.5, 0)
		var token = get_tree().root.get_node("ObjectPool").call("get_token", spawn_pos)
		if not token: continue
		var angle = randf() * TAU
		var force = randf_range(6.0, 10.0)
		token.apply_impulse(Vector3(cos(angle), 1.0, sin(angle)) * force)

func _exit_tree() -> void:
	var main = get_tree().get_first_node_in_group("Main")
	if main and main.has_method("unregister_enemy"):
		main.unregister_enemy(self)

func _process_hungry_ai(delta: float) -> void:
	if not target_meat or not is_instance_valid(target_meat):
		is_hungry = false
		return
		
	var to_meat = target_meat.global_position - global_position
	to_meat.y = 0
	
	if to_meat.length() < 0.8:
		eating_timer += delta
		mesh.position.x = sin(Time.get_ticks_msec() * 0.05) * 0.05
		if eating_timer >= 1.5: 
			if target_meat.has_method("eaten_by"):
				target_meat.eaten_by(self)
			eating_timer = 0
		return
	else:
		eating_timer = 0 
		mesh.position.x = 0
		
	var dir = to_meat.normalized()
	var desired_velocity = dir * chase_speed * 1.2 
	var current_velocity = linear_velocity
	current_velocity.y = 0
	
	var force = (desired_velocity - current_velocity) * acceleration
	apply_central_force(force)
	
	var look_target = global_position - dir
	look_target.y = global_position.y
	var target_basis = Basis.looking_at(look_target - global_position, Vector3.UP)
	basis = basis.slerp(target_basis, delta * 8.0)

func transform_to_zombie() -> void:
	if is_zombie: return
	is_zombie = true
	enemy_type = "Zombie Crab"
	is_hungry = false
	is_alert = true
	
	chase_speed *= 1.8
	acceleration *= 2.0
	health = 8
	max_health = 8
	
	# Visual change
	if mesh:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.2)
		mat.vertex_color_use_as_albedo = true
		mesh.material_override = mat
			
	var tween = create_tween()
	tween.tween_property(mesh, "scale", base_scale * 1.4, 0.2)
	tween.tween_property(mesh, "scale", base_scale * 1.6, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		var push_dir = (global_position - body.global_position).normalized()
		push_dir.y = 0
		apply_central_impulse(push_dir * 10.0)
		
		# DEAL DAMAGE
		var hit_accepted = false
		if body.has_method("receive_hit"):
			var damage = 20.0 if not is_zombie else 40.0
			hit_accepted = body.receive_hit(global_position, damage)
			
		# TOKEN STEALING (Only if damage was actually dealt/accepted)
		if hit_accepted:
			var main_node = get_tree().get_first_node_in_group("Main")
			if main_node and main_node.get("tokens") > 0 and steal_cooldown <= 0:
				var stolen = randi_range(1, 3)
				stolen = min(stolen, main_node.tokens)
				main_node.tokens -= stolen
				if main_node.has_method("_update_token_ui"):
					main_node._update_token_ui()
				stolen_tokens += stolen
				steal_cooldown = 2.0 
				
				if get_tree().root.has_node("ProceduralAudio"):
					get_tree().root.get_node("ProceduralAudio").call("play_tick", 0, 600.0)
