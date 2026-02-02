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
var target_level: float = 1.0 # 1 pixel from the top

func _ready() -> void:
	column_width = float(width) / columns
	reset_life()

func reset_life() -> void:
	points.clear()
	target_level = 1.0
	for i in range(columns):
		points.append({
			"y": target_level,
			"target_y": target_level,
			"velocity": 0.0
		})

func _process(delta: float) -> void:
	# Update Simulation (approx 60fps logic synced to delta)
	var speed_scale = delta * 60.0
	
	for i in range(len(points)):
		var p = points[i]
		var diff = p.y - p.target_y
		var force = -tension * diff
		p.velocity += force * speed_scale
		p.y += p.velocity * speed_scale
		p.velocity *= (1.0 - dampening * speed_scale)

	var left_deltas = []
	var right_deltas = []
	left_deltas.resize(len(points))
	right_deltas.resize(len(points))
	left_deltas.fill(0.0)
	right_deltas.fill(0.0)

	for i in range(len(points)):
		if i > 0:
			left_deltas[i] = spread * (points[i].y - points[i-1].y)
			points[i-1].velocity += left_deltas[i] * speed_scale
		if i < len(points) - 1:
			right_deltas[i] = spread * (points[i].y - points[i+1].y)
			points[i+1].velocity += right_deltas[i] * speed_scale

	queue_redraw()

func take_damage(amount: float = 5.0) -> void:
	# DRAIN EFFECT
	target_level = min(height - 1.0, target_level + amount)
	for p in points:
		p.target_y = target_level
	
	# SPLASH EFFECT
	var center_idx = columns / 2
	var total_impact = amount * 2.0 # More impact at low res
	var radius = 3 # Smaller radius for 10px width
	
	var angle = PI/2 + (randf() - 0.5) * (PI/2) # Random angle in 90deg window
	var vy = sin(angle) * total_impact
	var vx = cos(angle) * total_impact
	
	for i in range(len(points)):
		var dist = abs(i - center_idx)
		if dist < radius:
			var factor = cos((float(dist) / radius) * (PI/2))
			points[i].y += vy * factor
			
			var direction = sign(vx)
			var relative_pos = (i - center_idx) * direction
			var momentum_factor = 1.0 + (float(relative_pos) / radius) * (abs(vx) / total_impact) * 2.0
			
			points[i].velocity += vy * 1.2 * factor * momentum_factor

func _draw() -> void:
	# Clear Background (Solid Black)
	draw_rect(Rect2(0, 0, width, height), Color.BLACK)
	
	# Draw Water (Solid Red) with THRESHOLD
	var poly_points = PackedVector2Array()
	poly_points.append(Vector2(width, height))
	poly_points.append(Vector2(0, height))
	
	for i in range(len(points)):
		# Threshold: round to nearest pixel for the "on/off" feel
		var px = i * column_width
		var py = round(points[i].y)
		poly_points.append(Vector2(px, py))
	
	# Close the polygon correctly at the end
	poly_points.append(Vector2(width, round(points[-1].y)))
	
	draw_polygon(poly_points, PackedColorArray([Color.RED]))
