extends Node3D

@export var segment_count: int = 8:
	set(val):
		segment_count = val
		if is_inside_tree():
			_initialize_chain()

@export var segment_length: float = 0.4
@export var gravity: Vector3 = Vector3(0, -9.8, 0)
@export var damping: float = 0.95
@export var constraint_iterations: int = 5
@export var ground_y: float = 0.1

@export_group("Visuals")
@export var torus_inner_radius: float = 0.08
@export var torus_outer_radius: float = 0.22
@export var even_rotation: Vector3 = Vector3(180.0, 93.0, -180.0)
@export var odd_rotation: Vector3 = Vector3(180.0, 61.0, -94.0)

@export_group("Collision")
@export var collision_node: Node3D = null
@export var collision_radius: float = 0.85 # Slightly larger than player radius
@export var enemy_collision_radius: float = 0.6 # Radius for enemy detection
@export var enemy_push_strength: float = 3.0 # How hard to push enemies sideways (multiplied by chain velocity)

var points: Array[Vector3] = []
var old_points: Array[Vector3] = []
var constraints: Array[Vector2i] = []

var start_target: Node3D = null
var end_target: Node3D = null

var links: Array[MeshInstance3D] = []

func _ready() -> void:
	_initialize_chain()

func _initialize_chain() -> void:
	# Clean up existing links
	if is_inside_tree():
		for link in links:
			if is_instance_valid(link):
				link.queue_free()
	else:
		for link in links:
			if is_instance_valid(link):
				link.free()
			
	links.clear()
	points.clear()
	old_points.clear()
	constraints.clear()
	
	# Initialize points
	var base_pos = start_target.global_position if start_target else global_position
	
	for i in range(segment_count + 1):
		var pos = base_pos + Vector3(0, -i * segment_length, 0)
		points.append(pos)
		old_points.append(pos)
		if i > 0:
			constraints.append(Vector2i(i - 1, i))
	
	_create_visual_links()
	
	# If we already have targets, snap to them
	if start_target and end_target:
		var start_pos = start_target.global_position
		var end_pos = end_target.global_position
		for i in range(points.size()):
			var t = float(i) / (points.size() - 1)
			points[i] = start_pos.lerp(end_pos, t)
			old_points[i] = points[i]

func _create_visual_links() -> void:
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = torus_inner_radius
	torus_mesh.outer_radius = torus_outer_radius
	torus_mesh.rings = 24
	torus_mesh.ring_segments = 12
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.35, 0.38)
	mat.metallic = 0.8
	mat.roughness = 0.2
	
	for i in range(segment_count):
		var link = MeshInstance3D.new()
		link.mesh = torus_mesh
		link.material_override = mat
		add_child(link)
		links.append(link)

func _physics_process(delta: float) -> void:
	if delta == 0 or points.is_empty(): return
	
	# 1. Update targets (Start and End)
	if start_target:
		points[0] = start_target.global_position
		old_points[0] = points[0]
	
	if end_target:
		var last = points.size() - 1
		points[last] = end_target.global_position
		old_points[last] = points[last]

	# 2. Verlet Integration
	for i in range(points.size()):
		# Skip pinned points if they are fully controlled
		if (i == 0 and start_target) or (i == points.size() - 1 and end_target):
			continue
			
		var vel = (points[i] - old_points[i]) * damping
		old_points[i] = points[i]
		points[i] += vel + gravity * delta * delta
		
		# Ground collision
		if points[i].y < ground_y:
			points[i].y = ground_y
			# Add extra friction on ground
			old_points[i].x = lerp(old_points[i].x, points[i].x, 0.1)
			old_points[i].z = lerp(old_points[i].z, points[i].z, 0.1)
			
		# World collision (Walls/Geometry)
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(old_points[i], points[i])
		query.collision_mask = 1 # World layer
		query.hit_from_inside = true # Handle segments that already dipped in
		var result = space_state.intersect_ray(query)
		if result:
			# Push out of wall
			points[i] = result.position + result.normal * 0.15 # Stronger push
			# Kill momentum to prevent sliding through
			old_points[i] = points[i]
			
		# Player/Body collision
		if collision_node:
			var to_node = points[i] - collision_node.global_position
			var dist = to_node.length()
			if dist < collision_radius:
				var push_dir = to_node.normalized()
				if dist < 0.01: push_dir = Vector3.UP
				points[i] = collision_node.global_position + push_dir * collision_radius
		
		# Enemy collision - push enemy sideways, chain hops over
		var enemies = get_tree().get_nodes_in_group("Enemy")
		for enemy in enemies:
			var to_enemy = points[i] - enemy.global_position
			to_enemy.y = 0 # Flatten to XZ plane
			var dist_to_enemy = to_enemy.length()
			
			if dist_to_enemy < enemy_collision_radius:
				# Calculate chain swing direction from velocity of this point
				var chain_vel = points[i] - old_points[i]
				chain_vel.y = 0
				var chain_speed = chain_vel.length()
				
				if chain_speed > 0.01 and collision_node:
					# Vector from enemy to player
					var enemy_to_player = collision_node.global_position - enemy.global_position
					enemy_to_player.y = 0
					enemy_to_player = enemy_to_player.normalized()
					
					# Sideways direction (perpendicular to enemy-player vector)
					var sideways = Vector3(-enemy_to_player.z, 0, enemy_to_player.x)
					
					# Determine which side based on chain swing direction
					if chain_vel.dot(sideways) < 0:
						sideways = -sideways
					
					# Apply push to enemy - scaled by chain velocity for natural physics
					if enemy is RigidBody3D:
						var push_force = sideways * chain_speed * enemy_push_strength
						enemy.apply_central_impulse(push_force)
				
				# Chain hops over the enemy (push chain point up and over)
				var push_out = to_enemy.normalized() if to_enemy.length() > 0.01 else Vector3.RIGHT
				points[i] = enemy.global_position + push_out * enemy_collision_radius
				points[i].y = max(points[i].y, 1.2) # Hop over enemy height

	# 3. Constraints (Distance)
	for it in range(constraint_iterations):
		for c in constraints:
			var p1 = points[c.x]
			var p2 = points[c.y]
			var diff = p2 - p1
			var dist = diff.length()
			if dist == 0: continue
			
			var error = (dist - segment_length) / dist
			var correction = diff * 0.5 * error
			
			var can_move_1 = true
			var can_move_2 = true
			
			if c.x == 0 and start_target: can_move_1 = false
			if c.y == points.size() - 1 and end_target: can_move_2 = false
			
			if can_move_1 and can_move_2:
				points[c.x] += correction
				points[c.y] -= correction
			elif can_move_1:
				points[c.x] += correction * 2.0
			elif can_move_2:
				points[c.y] -= correction * 2.0

	_update_visuals()

func _update_visuals() -> void:
	for i in range(links.size()):
		var p1 = points[i]
		var p2 = points[i+1]
		var center = (p1 + p2) * 0.5
		var dir = (p2 - p1).normalized()
		
		var link = links[i]
		link.global_position = center
		
		if dir.length() > 0.001:
			# Stable 'up' for look_at
			var up = Vector3.UP
			if abs(dir.dot(up)) > 0.99:
				up = Vector3.RIGHT
				
			link.look_at(p2, up)
			
			# look_at makes -Z point at p2. 
			# TorusMesh hole is Y. Rotate X by 90 to bring Y to -Z.
			link.rotate_object_local(Vector3.RIGHT, PI/2)
			
			# Apply individual axial rotations
			var rot = even_rotation if i % 2 == 0 else odd_rotation
			# Twist (Z) should probably be first as it's the main axis
			link.rotate_object_local(Vector3.FORWARD, deg_to_rad(rot.z))
			link.rotate_object_local(Vector3.UP, deg_to_rad(rot.x))
			link.rotate_object_local(Vector3.RIGHT, deg_to_rad(rot.y))
			
			# Make it an oval by scaling local X. 
			link.scale = Vector3(1.3, 1.0, 1.0)

func setup(start_node: Node3D, end_node: Node3D, body_node: Node3D = null) -> void:
	start_target = start_node
	end_target = end_node
	collision_node = body_node
	
	# Snap points initially
	var start_pos = start_target.global_position
	var end_pos = end_target.global_position
	for i in range(points.size()):
		var t = float(i) / (points.size() - 1)
		points[i] = start_pos.lerp(end_pos, t)
		old_points[i] = points[i]
