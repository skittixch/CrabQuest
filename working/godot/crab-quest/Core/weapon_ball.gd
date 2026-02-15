extends RigidBody3D

@export_range(4, 64) var spike_count: int = 24:
	set(val):
		spike_count = val
		_regenerate()

@export var spike_radius: float = 0.11:
	set(val):
		spike_radius = val
		_regenerate()

@export var spike_height: float = 0.4:
	set(val):
		spike_height = val
		_regenerate()

@export var base_color: Color = Color(0.25, 0.25, 0.25):
	set(val):
		base_color = val
		_update_material()

@export var spike_color: Color = Color(0.45, 0.45, 0.45):
	set(val):
		spike_color = val
		_update_material()

var visibility_state: float = 1.0
var fog_ref: Node3D = null
var player: Node3D = null

@onready var visual_sphere: MeshInstance3D = $VisualSphere
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

@export var sparks_scene: PackedScene = preload("res://Core/sparks_fx.tscn")

var spike_mat: Material = null
var chain_attachment: Node3D = null
var chain_node: Node3D = null # Reference to the chain

# Trails
var normal_trail: Trail3D = null
var fierce_trail: Trail3D = null
var trail_chase_pos: Vector3 = Vector3.ZERO # For stabilized/smooth trail following

# Bounce animation
var bounce_time: float = 0.0
var bounce_period: float = 1.5 # Tenths of seconds per bounce (1.5 = 0.15s per hop)
var bounce_height: float = 0.15 # Max bounce offset
var bounce_rotation_amp: float = 15.0 # Degrees of tilt

func _ready() -> void:
	# Add shadow
	var shadow_scene = load("res://Core/shadow.tscn")
	if shadow_scene:
		var shadow = shadow_scene.instantiate()
		add_child(shadow)
		shadow.base_scale = 0.5 # Match ball radius (0.45)
		
	if not Engine.is_editor_hint():
		# Physics setup
		mass = 1.0
		gravity_scale = 1.0
		linear_damp = 1.0
		angular_damp = 1.0
		continuous_cd = true # Prevent tunneling through walls
		
		# Force collision layers/masks
		collision_layer = 128
		collision_mask = 1 | 2 | 512 # World, Enemy, Shards (Player layer 8 excluded)
		
		# Hit detection
		contact_monitor = true
		max_contacts_reported = 32 # Increased from 16
		sleeping = false
		can_sleep = false
		body_entered.connect(_on_body_entered)
		
		# Find fog and generator
		fog_ref = get_tree().get_first_node_in_group("Fog")
	
	# Create VisualSphere if it doesn't exist
	if not has_node("VisualSphere"):
		visual_sphere = MeshInstance3D.new()
		visual_sphere.name = "VisualSphere"
		var s_mesh = SphereMesh.new()
		s_mesh.radius = 0.45
		s_mesh.height = 0.9
		visual_sphere.mesh = s_mesh
		add_child(visual_sphere)
	
		# Create CollisionShape if it doesn't exist
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var shape = SphereShape3D.new()
		shape.radius = 0.7 # Increased from 0.45 for better hit reliability
		collision_shape.shape = shape
		add_child(collision_shape)

	_update_material()
	_update_material()
	_regenerate()
	_setup_trails()

func _setup_trails() -> void:
	# Shared Material for vertex colors
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	# 1. Normal Ribbon Trail
	normal_trail = Trail3D.new()
	normal_trail.name = "NormalTrail"
	normal_trail.top_level = true
	normal_trail.num_strands = 2
	normal_trail.scatter_radius = 0.03
	normal_trail.lifetime = 0.3
	normal_trail.subdivisions = 4 # Increased for spline smoothing
	normal_trail.width_curve = Curve.new()
	normal_trail.width_curve.add_point(Vector2(0, 0.5))
	normal_trail.width_curve.add_point(Vector2(1, 0.0))
	
	# White gradient (subtle)
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.4))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	normal_trail.color_gradient = grad
	normal_trail.material_override = mat
	
	# 2. Intense Inner Trail (for fierce movements)
	fierce_trail = Trail3D.new()
	fierce_trail.name = "FierceTrail"
	fierce_trail.top_level = true
	fierce_trail.num_strands = 3
	fierce_trail.scatter_radius = 0.01
	fierce_trail.lifetime = 0.15
	fierce_trail.subdivisions = 4 # Increased for spline smoothing
	fierce_trail.width_curve = Curve.new() # Reuse or new curve? Default is fine but let's be explicit
	fierce_trail.width_curve.add_point(Vector2(0, 0.6))
	fierce_trail.width_curve.add_point(Vector2(1, 0.0))
	
	# Fierce gradient (slightly brighter start)
	var fierce_grad = Gradient.new()
	fierce_grad.set_color(0, Color(1, 1, 1, 0.6))
	fierce_grad.set_color(1, Color(1, 1, 1, 0.0))
	fierce_trail.color_gradient = fierce_grad
	fierce_trail.material_override = mat
	
	add_child(normal_trail)
	add_child(fierce_trail)

func _update_material() -> void:
	if not visual_sphere: return
	
	# Standard Top Level Material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = 0.5
	
	if visual_sphere.mesh:
		visual_sphere.material_override = mat # Prefer material_override for consistency
	
	# Spikes Material
	spike_mat = StandardMaterial3D.new()
	spike_mat.albedo_color = Color(1.0, 0.2, 0.4) # Hot Pink
	spike_mat.roughness = 0.5

func _regenerate() -> void:
	if not visual_sphere: return
	
	# Clean children of visual_sphere
	for child in visual_sphere.get_children():
		child.free()
			
	var phi: float = PI * (3.0 - sqrt(5.0))
	for i in range(spike_count):
		var y: float = 1.0 - (i / float(spike_count - 1)) * 2.0
		var radius_at_y: float = sqrt(1.0 - y * y)
		var theta: float = phi * i
		var x: float = cos(theta) * radius_at_y
		var z: float = sin(theta) * radius_at_y
		var direction := Vector3(x, y, z).normalized()
		
		# Skip spikes at the very top to leave room for the chain attachment
		if direction.dot(Vector3.UP) > 0.9:
			continue
			
		var spike := MeshInstance3D.new()
		var s_mesh := CylinderMesh.new()
		s_mesh.top_radius = 0.0
		s_mesh.bottom_radius = spike_radius
		s_mesh.height = spike_height
		s_mesh.radial_segments = 6 # Low poly (was 8)
		s_mesh.rings = 1
		spike.mesh = s_mesh
		
		visual_sphere.add_child(spike)
		var base_mat: Material = null
		if visual_sphere.material_override:
			base_mat = visual_sphere.material_override
		elif visual_sphere is MeshInstance3D:
			base_mat = visual_sphere.get_active_material(0)
		elif "material" in visual_sphere:
			base_mat = visual_sphere.material
			
		spike.material_override = spike_mat if spike_mat else base_mat
		spike.position = direction * visual_sphere.mesh.radius
		if direction.is_equal_approx(Vector3.DOWN):
			spike.rotation.x = PI
		else:
			spike.quaternion = Quaternion(Vector3.UP, direction)

	# Add attachment point at the top
	_add_attachment_point()

func _add_attachment_point() -> void:
	var anchor = MeshInstance3D.new()
	var a_mesh = TorusMesh.new()
	a_mesh.inner_radius = 0.05
	a_mesh.outer_radius = 0.15
	a_mesh.ring_segments = 6 # Low poly (was 8)
	a_mesh.rings = 8 # Corrected property (was radial_segments 12)
	anchor.mesh = a_mesh
	
	anchor.name = "ChainAttachment"
	var base_mat: Material = null
	if visual_sphere.material_override:
		base_mat = visual_sphere.material_override
	elif visual_sphere is MeshInstance3D:
		base_mat = visual_sphere.get_active_material(0)
	elif "material" in visual_sphere:
		base_mat = visual_sphere.material
		
	anchor.material_override = spike_mat if spike_mat else base_mat
	
	visual_sphere.add_child(anchor)
	anchor.position = Vector3.UP * visual_sphere.mesh.radius
	# Store reference for updating orientation
	chain_attachment = anchor

func get_effective_radius() -> float:
	return visual_sphere.mesh.radius + spike_height * 0.5

func _physics_process(delta: float) -> void:
	_update_fog_darkness(delta)
	
	# Update trails
	if visual_sphere:
		if trail_chase_pos == Vector3.ZERO:
			trail_chase_pos = visual_sphere.global_position
			
		# "Stroke Stabilization" - trails lag slightly for smoother curves
		trail_chase_pos = trail_chase_pos.lerp(visual_sphere.global_position, delta * 20.0)
		
		var speed = linear_velocity.length()
		
		# Main trail (> 14.5 - +20% threshold)
		if normal_trail and speed > 14.5:
			normal_trail.append_point(trail_chase_pos)
			
		# Fierce trail (> 26.5 - +20% threshold)
		if fierce_trail and speed > 26.5:
			fierce_trail.append_point(trail_chase_pos)
		
	# --- BOUNCY PUPPY-HOP ANIMATION ---
	var speed = linear_velocity.length()
	if speed > 1.0 and visual_sphere:
		# Period is in tenths of seconds, so actual_period = bounce_period / 10.0
		var actual_period = bounce_period / 10.0
		bounce_time += delta / actual_period
		
		# Absolute sine wave for the bounce (always positive, like a hopping ball)
		var bounce_phase = abs(sin(bounce_time * TAU))
		var bounce_offset = bounce_phase * bounce_height * clamp(speed / 15.0, 0.0, 1.0)
		
		# Apply bounce to visual offset (local Y)
		visual_sphere.position.y = bounce_offset
		
		# Alternating rotation: use regular sin (not abs) so it tilts back and forth
		var tilt_phase = sin(bounce_time * TAU)
		var move_dir = linear_velocity.normalized()
		
		# Tilt perpendicular to movement direction
		var tilt_axis = Vector3(-move_dir.z, 0, move_dir.x).normalized()
		if tilt_axis.length() < 0.1:
			tilt_axis = Vector3.RIGHT
		
		var tilt_angle = deg_to_rad(bounce_rotation_amp * tilt_phase * clamp(speed / 10.0, 0.0, 1.0))
		
		# Apply tilt rotation (additive to existing orientation)
		var base_basis = Basis.IDENTITY
		visual_sphere.basis = base_basis.rotated(tilt_axis, tilt_angle)
	else:
		# Reset to neutral when slow/stationary
		if visual_sphere:
			visual_sphere.position.y = lerp(visual_sphere.position.y, 0.0, delta * 8.0)
			visual_sphere.basis = visual_sphere.basis.slerp(Basis.IDENTITY, delta * 8.0)
	
	
	# Check for sustained collisions
	var bodies = get_colliding_bodies()
	if not bodies.is_empty() and Engine.get_process_frames() % 120 == 0:
		pass
		
	for body in bodies:
		if not is_instance_valid(body): continue
		
		if (body.is_in_group("Enemy") or body.is_in_group("Treasure")) and body.has_method("hit"):
			# Only trigger if the target's hit_cooldown (if it exists) is zero
			var cooldown = body.get("hit_cooldown")
			if cooldown == null or cooldown <= 0.05:
				if body.is_in_group("Enemy"):
					_on_enemy_hit(body)
				else:
					_on_treasure_hit(body)

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body) or body.is_in_group("Player"): return
	
	if (body.is_in_group("Enemy") or body.is_in_group("Treasure")) and body.has_method("hit"):
		print("Ball IMPACT with: ", body.name, " (", body.get_groups(), ")")
		if body.is_in_group("Enemy"):
			_on_enemy_hit(body)
		else:
			_on_treasure_hit(body)
	else:
		# Audio feedback for world/object collision
		var impact_speed = linear_velocity.length()
		if impact_speed > 5.0 and get_tree().root.has_node("ProceduralAudio"):
			var material_type = 0 # WALL
			if body.is_in_group("Shard"):
				material_type = 2 # OBJECT
			get_tree().root.get_node("ProceduralAudio").call("play_tick", material_type, impact_speed * 100.0)
		
		if impact_speed > 8.0:
			_spawn_sparks(global_position)
		
		# Stomach damage feedback
		if body.is_in_group("World"):
			_on_world_hit(global_position)
			if impact_speed > 10.0:
				Input.vibrate_handheld(20) # Light tactile tick for wall slams

func _spawn_sparks(pos: Vector3) -> void:
	if not sparks_scene: return
	var sparks = sparks_scene.instantiate()
	get_parent().add_child(sparks)
	sparks.global_position = pos

func _on_world_hit(_pos: Vector3) -> void:
	# General world impact feedback
	pass

func _on_stomach_hit(_pos: Vector3) -> void:
	# Blood splatter instead of sparks?
	# For now, let's trigger a screen shake and a special sound
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.2)
	
	# Pass damage to input_demo
	var main = get_tree().get_first_node_in_group("Main")
	if main and main.has_method("on_stomach_damaged"):
		main.on_stomach_damaged(1.0)

func _on_enemy_hit(enemy: Node) -> void:
	# --- HIT FLOW ---
	Input.vibrate_handheld(80) # Satisfying impact buzz
	_spawn_sparks(enemy.global_position)

	# Get impact velocity
	var impact_vel = linear_velocity
	
	# If moving slow (e.g. pushing/dragging), use a stronger minimum force
	if impact_vel.length() < 3.0:
		var push_dir = (enemy.global_position - global_position).normalized()
		# Add a bit of jitter to the push to keep things dynamic
		push_dir.x += randf_range(-0.1, 0.1)
		push_dir.z += randf_range(-0.1, 0.1)
		impact_vel = push_dir.normalized() * 12.0 # Significantly more "push" power
		
	enemy.hit(impact_vel)
	
	# Bounce ball back slightly to prevent sticking
	var bounce_force = 8.0 if impact_vel.length() < 15.0 else 5.0
	var bounce_dir = -impact_vel.normalized()
	apply_central_impulse(bounce_dir * bounce_force)
	
	# Small shake on hit
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.3)

func _on_treasure_hit(treasure: Node) -> void:
	if treasure.get("is_open"): return
	Input.vibrate_handheld(50) # Light impact
	_spawn_sparks(treasure.global_position)
	
	var impact_vel = linear_velocity
	if impact_vel.length() < 3.0:
		impact_vel = (treasure.global_position - global_position).normalized() * 12.0
		
	treasure.hit(impact_vel)
	
	# Bounce back
	apply_central_impulse(-impact_vel.normalized() * 5.0)
	
	# Small shake
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.2)

func smash_to(target_pos: Vector3) -> void:
	# 1. Calculate direction
	var to_target = target_pos - global_position
	var dist = to_target.length()
	if dist < 0.1: return
	
	var dir = to_target.normalized()
	
	# 2. Apply a massive impulse
	Input.vibrate_handheld(150) # Heavy charge up/smash
	# We use a strength that scales a bit with distance but has a high floor
	var smash_strength = 60.0 + clamp(dist * 5.0, 0, 40.0)
	
	# Kill existing velocity for more surgical strike
	linear_velocity *= 0.2
	apply_central_impulse(dir * smash_strength)
	
	# Audio feedback
	if get_tree().root.has_node("ProceduralAudio"):
		get_tree().root.get_node("ProceduralAudio").call("play_gurgle") # High energy tonal sweep
	
	# 3. Visual feedback
	# Trigger a larger shake
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.8)
	
	# We can also signal the main script to show the fierce trail or handle it via velocity (already implemented)


func _update_fog_darkness(_delta: float) -> void:
	# Now handled automatically by the toon_actor shader!
	pass
