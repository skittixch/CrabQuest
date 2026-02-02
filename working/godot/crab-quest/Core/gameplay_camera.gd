extends Camera3D
## Gameplay Camera - Telephoto "Nearly Ortho" Look
## High distance + low FOV for pixel art readability.

@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 5.0
@export var min_distance: float = 3.0
@export var max_distance: float = 500.0

@export var use_orthographic: bool = false  # False = nearly-ortho perspective
@export var ortho_size: float = 8.0  # Size of orthographic view

var is_orbiting: bool = false
var orbit_distance: float = 160.0 # Splitting the difference
var orbit_rotation: Vector2 = Vector2(0.8, 0.0) # Look straight ahead
@export var orbit_fov: float = 11.0  # Splitting the difference

@export var look_at_target: Vector3 = Vector3.ZERO
@export var follow_smoothing: float = 4.5
var current_target_pos: Vector3 = Vector3.ZERO

# Shake
var shake_rotation: Vector3 = Vector3.ZERO # X=pitch (nod), Y=yaw, Z=roll (dutch)
var shake_intensity: float = 0.0
@export var shake_decay: float = 10.0


func _ready() -> void:
	# Set up orthographic projection if enabled
	if use_orthographic:
		projection = PROJECTION_ORTHOGONAL
		size = ortho_size
	else:
		projection = PROJECTION_PERSPECTIVE
	
	# Apply initial camera position immediately
	current_target_pos = look_at_target
	_update_camera_transform()


func _process(delta: float) -> void:
	# Smoothly follow the XZ plane of the look_at_target
	# Ensure we don't jump on first frame
	if current_target_pos == Vector3.ZERO and look_at_target != Vector3.ZERO:
		current_target_pos = look_at_target
		
	current_target_pos = current_target_pos.lerp(look_at_target, delta * follow_smoothing)
	
	# Handle Shake
	if shake_intensity > 0:
		shake_intensity = move_toward(shake_intensity, 0.0, delta * shake_decay)
		# Primarily X-axis (pitch/nod), small Z-axis (roll/dutch)
		shake_rotation = Vector3(
			randf_range(-1, 1) * shake_intensity * 0.02,  # Pitch (nod up/down)
			randf_range(-1, 1) * shake_intensity * 0.003, # Yaw (tiny)
			randf_range(-1, 1) * shake_intensity * 0.007  # Roll (subtle dutch)
		)
	else:
		shake_rotation = Vector3.ZERO
		
	# Always update transform to apply shake
	_update_camera_transform()


func _input(event: InputEvent) -> void:
	# Middle mouse button for orbiting
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
	
	# Scroll wheel for zoom
	if event is InputEventMouseButton:
		if use_orthographic:
			# Orthographic zoom changes size
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				ortho_size = max(2.0, ortho_size - 0.5)
				size = ortho_size
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				ortho_size = min(20.0, ortho_size + 0.5)
				size = ortho_size
		else:
			# Perspective zoom changes distance
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				orbit_distance = max(min_distance, orbit_distance - zoom_speed)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				orbit_distance = min(max_distance, orbit_distance + zoom_speed)
	
	# Mouse motion for orbit
	if event is InputEventMouseMotion and is_orbiting:
		orbit_rotation.y += event.relative.x * orbit_speed
		orbit_rotation.x += event.relative.y * orbit_speed
		orbit_rotation.x = clamp(orbit_rotation.x, -PI/2 + 0.1, PI/2 - 0.1)


func add_shake(amount: float) -> void:
	shake_intensity += amount


func _update_camera_transform() -> void:
	var offset := Vector3.ZERO
	offset.x = cos(orbit_rotation.x) * sin(orbit_rotation.y) * orbit_distance
	offset.y = sin(orbit_rotation.x) * orbit_distance
	offset.z = cos(orbit_rotation.x) * cos(orbit_rotation.y) * orbit_distance
	
	fov = orbit_fov
	
	global_position = current_target_pos + offset
	look_at(current_target_pos)
	
	# Apply rotational shake after look_at
	rotation += shake_rotation
