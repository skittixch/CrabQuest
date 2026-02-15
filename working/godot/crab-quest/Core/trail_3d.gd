extends MeshInstance3D
class_name Trail3D

## High-Quality 3D Volumetric Trail
## Uses ImmediateMesh to draw multiple thin ribbons with path subdivision
## Supports scattering to create a "ghosting" or "multi-strand" effect.

@export var max_points: int = 80
@export var lifetime: float = 0.5
@export var width_curve: Curve
@export var color_gradient: Gradient

# Multi-strand properties
@export var num_strands: int = 4
@export var strand_rotation_offset: float = 0.0 # Rotate the whole set
@export var scatter_radius: float = 0.0 # Randomly offset each strand from the main path
@export var divergence: float = 0.5 # How much strands drift apart at the tail

# Smoothing
@export var subdivisions: int = 2 # Number of extra points between each recorded point

# Physics-like delay/drift properties
@export var point_drift_speed: float = 0.15  # Upward drift
@export var point_damping: float = 0.95

var points: Array[Vector3] = []
var point_velocities: Array[Vector3] = []
var point_times: Array[float] = []
var strand_offsets: Array[Vector3] = []
var strand_drift_vectors: Array[Vector3] = []

func _ready() -> void:
	mesh = ImmediateMesh.new()
	if not width_curve:
		width_curve = Curve.new()
		width_curve.add_point(Vector2(0, 1))
		width_curve.add_point(Vector2(1, 0))
	if not color_gradient:
		color_gradient = Gradient.new()
	
	if OS.has_feature("web"):
		max_points = min(max_points, 40)
		num_strands = min(num_strands, 2)
		subdivisions = min(subdivisions, 1)
	
	_generate_strand_offsets()

func _generate_strand_offsets() -> void:
	strand_offsets.clear()
	strand_drift_vectors.clear()
	for i in range(num_strands):
		if scatter_radius > 0:
			var offset = Vector3(
				randf_range(-1, 1),
				randf_range(-1, 1),
				randf_range(-1, 1)
			).normalized() * randf_range(0, scatter_radius)
			strand_offsets.append(offset)
			
			# Generate random drift direction for divergence
			var drift = Vector3(
				randf_range(-1, 1),
				randf_range(-1, 1),
				randf_range(-1, 1)
			).normalized() * divergence
			strand_drift_vectors.append(drift)
		else:
			strand_offsets.append(Vector3.ZERO)
			strand_drift_vectors.append(Vector3.ZERO)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	# Regenerate offsets if scatter changes or strands change
	if strand_offsets.size() != num_strands:
		_generate_strand_offsets()
		
	# Update point lifetimes and drift physics
	var i = 0
	while i < point_times.size():
		point_times[i] -= delta
		if point_times[i] <= 0:
			point_times.remove_at(i)
			points.remove_at(i)
			point_velocities.remove_at(i)
		else:
			# Apply drift physics
			points[i] += point_velocities[i] * delta
			point_velocities[i] *= point_damping
			point_velocities[i].y += point_drift_speed * delta 
			i += 1
	
	_update_trail_mesh()

func append_point(pos: Vector3, initial_velocity: Vector3 = Vector3.ZERO) -> void:
	if points.size() > 0 and points[points.size() - 1].distance_to(pos) < 0.015:
		return
		
	points.append(pos)
	# Inherit some velocity for that "weighted" delay feel
	point_velocities.append(initial_velocity * 0.1)
	point_times.append(lifetime)
	
	if points.size() > max_points:
		points.remove_at(0)
		point_velocities.remove_at(0)
		point_times.remove_at(0)

func _update_trail_mesh() -> void:
	var imm_mesh := mesh as ImmediateMesh
	imm_mesh.clear_surfaces()
	
	if points.size() < 2:
		return
	
	# Generate subdivided path using Cubic Interpolation (Spline)
	var smooth_points: Array[Vector3] = []
	var smooth_times: Array[float] = []
	
	for i in range(points.size() - 1):
		var p0 = points[i-1] if i > 0 else points[i]
		var p1 = points[i]
		var p2 = points[i+1]
		var p3 = points[i+2] if i < points.size() - 2 else points[i+1]
		
		smooth_points.append(p1)
		smooth_times.append(point_times[i])
		
		# Cubic subdivision
		for s in range(1, subdivisions + 1):
			var t = float(s) / (subdivisions + 1)
			# standard cubic_interpolate(b, pre_a, post_b, weight)
			# maps to: p1.cubic_interpolate(p2, p0, p3, t)
			smooth_points.append(p1.cubic_interpolate(p2, p0, p3, t))
			smooth_times.append(lerp(point_times[i], point_times[i+1], t))
			
	smooth_points.append(points[points.size() - 1])
	smooth_times.append(point_times[point_times.size() - 1])
	
	# Draw ribbons
	var angle_step = PI / num_strands
	for r in range(num_strands):
		imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		_draw_ribbon_strip(imm_mesh, r * angle_step + strand_rotation_offset, smooth_points, smooth_times, strand_offsets[r], strand_drift_vectors[r])
		imm_mesh.surface_end()

func _draw_ribbon_strip(imm_mesh: ImmediateMesh, angle_offset: float, p_list: Array[Vector3], t_list: Array[float], s_offset: Vector3, drift: Vector3) -> void:
	for j in range(p_list.size()):
		var life_t = clamp(1.0 - (t_list[j] / lifetime), 0.0, 1.0)
		var width = width_curve.sample(life_t)
		var color = color_gradient.sample(life_t)
		
		# Basis orientation
		var forward: Vector3
		if j < p_list.size() - 1:
			forward = (p_list[j+1] - p_list[j]).normalized()
		else:
			forward = (p_list[j] - p_list[j-1]).normalized()
			
		var up = Vector3.UP
		if abs(forward.dot(up)) > 0.9:
			up = Vector3.FORWARD
			
		var right = forward.cross(up).normalized()
		var real_up = right.cross(forward).normalized()
		
		# Rotate the side vector
		var side = (right * cos(angle_offset) + real_up * sin(angle_offset)).normalized()
		
		# Apply strand offset and divergence drift to point
		# drift scales with life_t (0 at head, 1 at tail)
		var p = p_list[j] + s_offset + (drift * life_t)
		
		var v1 = p + side * width * 0.5
		var v2 = p - side * width * 0.5
		
		imm_mesh.surface_set_color(color)
		imm_mesh.surface_add_vertex(v1)
		imm_mesh.surface_set_color(color)
		imm_mesh.surface_add_vertex(v2)
