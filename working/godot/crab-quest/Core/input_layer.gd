extends Control
class_name InputLayer

signal movement_input(velocity: Vector2)
signal weapon_input(direction: Vector2, magnitude: float)
signal tap_detected(position: Vector2)

@export_group("Joysticks")
@export var max_movement_radius: float = 100.0
@export var drift_speed: float = 6.0
@export var movement_drift_speed: float = 3.0

@export_group("Debug")
@export var show_debug_visuals: bool = false

var touch_active: bool = false
var current_touch: Vector2 = Vector2.ZERO
var start_anchor: Vector2 = Vector2.ZERO
var drift_anchor: Vector2 = Vector2.ZERO
var touch_start_time: float = 0.0
var max_touch_drag: float = 0.0

var current_touch_index: int = -1



# --- DEBUG & SAFETY ---
var debug_label: Label
var has_seen_touch: bool = false

func _ready() -> void:
	add_to_group("InputLayer")
	# Create on-screen debug log
	debug_label = Label.new()
	debug_label.position = Vector2(20, 300)
	debug_label.modulate = Color(1, 1, 0) # Yellow
	add_child(debug_label)
	
	# Safety: Ensure accumulated input doesn't drop frames on web
	Input.use_accumulated_input = false

func _input(event: InputEvent) -> void:
	# VISUAL DEBUGGING
	if debug_label and show_debug_visuals:
		debug_label.text = "Active: %s\nIdx: %d\nEv: %s" % [str(touch_active), current_touch_index, event.get_class()]

	# Touch Support
	if event is InputEventScreenTouch:
		has_seen_touch = true
		if event.pressed:
			# Only accept new touch if we aren't already tracking one
			if current_touch_index == -1:
				current_touch_index = event.index
				_on_touch_start(event.position)
		else:
			# Check for CANCELED (often happens if dragged off screen or gesture interrupts)
			if event.canceled:
				_on_touch_end()
				current_touch_index = -1
				return
				
			# Only end if it's OUR touch
			if event.index == current_touch_index:
				_on_touch_end()
				current_touch_index = -1
	
	if event is InputEventScreenDrag and touch_active:
		if event.index == current_touch_index:
			current_touch = event.position
			var drag_dist = (current_touch - start_anchor).length()
			if drag_dist > max_touch_drag:
				max_touch_drag = drag_dist
			
	# Mouse Support (Ignore if we know we are on a touchscreen device to avoid emulation conflicts)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if current_touch_index == -1:
					current_touch_index = -2 # Special Mouse Index
					_on_touch_start(event.position)
			else:
				if current_touch_index == -2:
					_on_touch_end()
					current_touch_index = -1
	
	if event is InputEventMouseMotion and touch_active:
		if current_touch_index == -2:
			current_touch = event.position
			var drag_dist = (current_touch - start_anchor).length()
			if drag_dist > max_touch_drag:
				max_touch_drag = drag_dist

func _notification(what: int) -> void:
	# Catch-all for "Tab switching", "Alert boxes", etc
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if touch_active:
			_on_touch_end()
			current_touch_index = -1


func _on_touch_start(pos: Vector2) -> void:
	touch_active = true
	current_touch = pos
	start_anchor = pos
	drift_anchor = pos
	touch_start_time = Time.get_ticks_msec() / 1000.0
	max_touch_drag = 0.0

func _on_touch_end() -> void:
	var duration = (Time.get_ticks_msec() / 1000.0) - touch_start_time
	
	# Detect as tap if short duration and minimal movement
	if duration < 0.25 and max_touch_drag < 15.0:
		tap_detected.emit(current_touch)
	
	touch_active = false
	movement_input.emit(Vector2.ZERO)
	weapon_input.emit(Vector2.ZERO, 0.0)
	queue_redraw()

func _process(delta: float) -> void:
	if not touch_active:
		return
	
	# === MOVEMENT (Fixed-ish Anchor) ===
	var move_vec: Vector2 = current_touch - start_anchor
	if move_vec.length() > max_movement_radius:
		var target_anchor := current_touch - move_vec.normalized() * max_movement_radius
		start_anchor = start_anchor.lerp(target_anchor, delta * movement_drift_speed)
		move_vec = current_touch - start_anchor
		move_vec = move_vec.normalized() * max_movement_radius
	
	movement_input.emit(move_vec / max_movement_radius)
	
	# === WEAPON (Drifting Anchor) ===
	var weapon_vec: Vector2 = current_touch - drift_anchor
	var weapon_mag := weapon_vec.length()
	var weapon_dir := weapon_vec.normalized() if weapon_mag > 0.01 else Vector2.ZERO
	
	weapon_input.emit(weapon_dir, weapon_mag)
	
	# Anchor drift
	drift_anchor = drift_anchor.lerp(current_touch, delta * drift_speed)
	queue_redraw()

func _draw() -> void:
	if not show_debug_visuals or not touch_active:
		return
	
	# Anchors
	draw_circle(start_anchor, 12, Color(1, 1, 1, 0.3))
	draw_circle(drift_anchor, 10, Color(1, 0.2, 0.2, 0.5))
	
	# Finger
	draw_circle(current_touch, 14, Color(0.2, 1, 0.2, 0.6))
	
	# Connections
	draw_line(start_anchor, current_touch, Color(1, 1, 1, 0.4), 2.0)
	draw_line(drift_anchor, current_touch, Color(1, 0.2, 0.2, 0.8), 4.0)

# Simplified jabbing for logic compatibility if still needed
func is_jabbing() -> bool:
	return false 
