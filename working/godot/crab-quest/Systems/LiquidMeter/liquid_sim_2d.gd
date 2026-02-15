extends Node2D

## LiquidSim2D
## Ports the JS fluid simulation to Godot for a pixel-threshold life meter.

@export_group("Physics")
@export var tension: float = 0.07
@export var dampening: float = 0.1
@export var spread: float = 0.14

@export_group("Dimensions")
@export var width: int = 10
@export var height: int = 10
@export var columns: int = 10

var column_width: float
var points: Array = []
var target_level: float = -1.0 # Buffer above rim (y=0)
var actual_target_level: float = -1.0 

# Flash Logic
var damage_flash_active: bool = false
var damage_flash_timer: float = 0.0
var flash_duration: float = 0.15 
var is_sleeping: bool = false
var step_timer: float = 0.0
const VISUAL_STEP_RATE: float = 1.0 / 30.0
var visual_points: Array = []

# Child nodes for exclusion flash
var flash_rect: ColorRect
var back_buffer_copy: BackBufferCopy

func _ready() -> void:
	column_width = float(width) / columns
	reset_life()
	_setup_flash_node()

func _setup_flash_node() -> void:
	# 1. BackBufferCopy to capture what we draw in _draw()
	back_buffer_copy = BackBufferCopy.new()
	back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(back_buffer_copy)
	
	# 2. ColorRect with Exclusion shader
	flash_rect = ColorRect.new()
	flash_rect.name = "FlashOverlay"
	flash_rect.color = Color.WHITE
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
	uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
	uniform bool use_exclusion = true;
	
	void fragment() {
		if (use_exclusion) {
			vec4 bg = texture(screen_texture, SCREEN_UV);
			COLOR = vec4(1.0 - bg.rgb, 1.0);
		} else {
			COLOR = flash_color;
		}
	}
	"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	flash_rect.material = mat
	flash_rect.visible = false
	add_child(flash_rect)

func reset_life() -> void:
	points.clear()
	visual_points.clear()
	target_level = -1.0
	actual_target_level = -1.0
	for i in range(columns):
		var p = {
			"y": target_level,
			"target_y": target_level,
			"velocity": 0.0
		}
		points.append(p)
		visual_points.append(target_level)

func _process(delta: float) -> void:
	if is_sleeping:
		return

	# 1. Physics Simulation (Full Speed)
	if damage_flash_active:
		damage_flash_timer -= delta
		if damage_flash_timer <= 0:
			damage_flash_active = false
			if flash_rect: flash_rect.visible = false
	
	var speed_scale = delta * 60.0
	var active_movement = false
	
	for i in range(len(points)):
		var p = points[i]
		p.target_y = actual_target_level
		var diff = p.y - p.target_y
		var force = -tension * diff
		p.velocity += force * speed_scale
		p.y += p.velocity * speed_scale
		p.velocity *= (1.0 - dampening * speed_scale)
		
		if abs(p.velocity) > 0.01 or abs(diff) > 0.01:
			active_movement = true
		
		# Peak Limiter
		var limit_threshold = height * 0.25 
		var dist = abs(p.y - p.target_y)
		if dist > limit_threshold:
			var excess = dist - limit_threshold
			var pull_back = excess * 0.15 * speed_scale
			if p.y > p.target_y: p.y -= pull_back
			else: p.y += pull_back
			p.velocity *= 0.6 

	# Wave Propagation
	for i in range(len(points)):
		if i > 0:
			var left_delta = spread * (points[i].y - points[i-1].y)
			points[i-1].velocity += left_delta * speed_scale
		if i < len(points) - 1:
			var right_delta = spread * (points[i].y - points[i+1].y)
			points[i+1].velocity += right_delta * speed_scale

	# 2. Visual Throttling (Posterization)
	step_timer += delta
	if step_timer >= VISUAL_STEP_RATE:
		step_timer = fmod(step_timer, VISUAL_STEP_RATE)
		# Update snapshots for _draw
		for i in range(len(points)):
			visual_points[i] = points[i].y
		queue_redraw()

	# 3. Sleep check
	if not active_movement and not damage_flash_active:
		is_sleeping = true

func wake_up() -> void:
	is_sleeping = false

## set_level_instantly
## Snaps the liquid level with no splash or flash. Used for initialization or non-damage updates.
func set_level_instantly(new_level: float) -> void:
	target_level = new_level
	actual_target_level = new_level
	for p in points:
		p.y = new_level
		p.target_y = new_level
		p.velocity = 0.0
	wake_up()

## apply_hit
## The PRIMARY way to take damage.
## new_level: where the target should land (0..10)
## splash_strength: how much disturbance to add
func apply_hit(new_level: float, splash_strength: float) -> void:
	if actual_target_level >= 10.0:
		return # Already dead
		
	var old_level = actual_target_level
	# If we are going to empty, force full heart flash
	var is_depleting = (new_level >= 9.8)
	
	# 1. SETUP FLASH
	damage_flash_active = true
	damage_flash_timer = flash_duration
	if flash_rect:
		flash_rect.visible = true
		# RESET SHADER STATE (Fix for "Green Flash" bug)
		flash_rect.material.set_shader_parameter("use_exclusion", true)
		
		var f_top: float
		var f_bottom: float
		
		if is_depleting:
			f_top = -1.0 # From very top rim
			f_bottom = height + 1.0 # To very bottom
		else:
			# Just the slice being removed
			f_top = old_level
			f_bottom = new_level
			
		# Clamp Flash Rect to ensure it exists and covers full width
		flash_rect.position = Vector2(0, f_top)
		flash_rect.size = Vector2(width, max(2.0, f_bottom - f_top))

	# 2. START TRANSITION
	if is_depleting:
		# Instant empty (snaps to black)
		set_level_instantly(11.0) # Down past the bottom
	else:
		# Smooth drain via tween
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "actual_target_level", new_level, 0.6)
		target_level = new_level
		
		# 3. SPLASH (Rock Throw with momentum)
		wake_up()
		var center_idx = columns / 2
		var radius = columns / 3.0
		var vy = splash_strength 
		var vx = randf_range(-4.0, 4.0) # Rock throw slant
		
		for i in range(len(points)):
			var dist = abs(i - center_idx)
			if dist < radius:
				var factor = cos((float(dist) / radius) * (PI/2))
				
				# Rock Throw Momentum slant
				var direction = sign(vx)
				var relative_pos = (i - center_idx) * direction
				var momentum_factor = 1.0 + (relative_pos / radius) * (abs(vx) / 8.0) * 1.5
				
				points[i].y += vy * factor
				points[i].velocity += (vy * 1.2 * factor * momentum_factor)

## apply_heal
## Feedback-enabled healing.
func apply_heal(new_level: float, splash_strength: float) -> void:
	var old_level = actual_target_level
	
	# 1. SETUP FLASH (Green Rectangle)
	damage_flash_active = true
	damage_flash_timer = flash_duration
	if flash_rect:
		flash_rect.visible = true
		flash_rect.material.set_shader_parameter("use_exclusion", false)
		flash_rect.material.set_shader_parameter("flash_color", Color(0.0, 1.0, 0.2, 0.8))
		
		# Top of filling area is the NEW level, bottom is OLD level
		var f_top = new_level
		var f_bottom = old_level
		
		flash_rect.position = Vector2(0, f_top)
		flash_rect.size = Vector2(width, max(2.0, f_bottom - f_top))

	# 2. START TRANSITION
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "actual_target_level", new_level, 0.8)
	target_level = new_level
	
	# 3. SPLASH (Inverted upward push)
	wake_up()
	var center_idx = columns / 2
	var radius = columns / 2.5
	var vy = -splash_strength * 1.5 # Negative = Push UP
	var vx = randf_range(-3.0, 3.0)
	
	for i in range(len(points)):
		var dist = abs(i - center_idx)
		if dist < radius:
			var factor = cos((float(dist) / radius) * (PI/2))
			
			# Rock Throw Momentum slant
			var direction = sign(vx)
			var relative_pos = (i - center_idx) * direction
			var momentum_factor = 1.0 + (relative_pos / radius) * (abs(vx) / 6.0) * 1.2
			
			points[i].y += vy * factor
			points[i].velocity += (vy * 1.2 * factor * momentum_factor)

func _draw() -> void:
	# Draw Background (Black)
	draw_rect(Rect2(0, 0, width, height), Color.BLACK)
	
	if actual_target_level >= 10.0:
		return

	# Draw Liquid (Red)
	var poly_points = PackedVector2Array()
	poly_points.append(Vector2(width, height + 5))
	poly_points.append(Vector2(0, height + 5))
	
	for i in range(len(visual_points)):
		var px = i * column_width
		var py = round(visual_points[i])
		poly_points.append(Vector2(px, py))
	
	poly_points.append(Vector2(width, round(visual_points[-1])))
	draw_polygon(poly_points, PackedColorArray([Color.RED]))
