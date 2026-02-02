extends Node3D

## Master Session Runner
## Manages persistent nodes (Player, Camera) and swaps environment scenes.

@onready var world_container: Node3D = $CurrentEnvironment
@onready var player: CharacterBody3D = $Player
@onready var main_camera: Camera3D = $GameplayCamera

var cached_enemies: Array = []
var is_endgame_active: bool = false
var tokens: int = 0

func _ready() -> void:
	add_to_group("Main")
	# Start with the gameplay for this test
	load_environment("res://Scenes/World.tscn")

func load_environment(path: String) -> void:
	# Clear previous environment
	for child in world_container.get_children():
		child.queue_free()
	
	# Load new environment
	var scene = load(path)
	if scene:
		var instance = scene.instantiate()
		world_container.add_child(instance)
		
		# If it's the dungeon, move player to spawn point
		if path.contains("World") or path.contains("Dungeon"):
			_setup_gameplay()

func _setup_gameplay() -> void:
	# Snapping player to dungeon start
	player.global_position = Vector3.ZERO
	player.visible = true
	# Enable player controls, etc.
	if player.has_method("enable_controls"):
		player.call("enable_controls")

func register_enemy(enemy: Node) -> void:
	if not cached_enemies.has(enemy):
		cached_enemies.append(enemy)

func unregister_enemy(enemy: Node) -> void:
	cached_enemies.erase(enemy)

func on_enemy_defeated(_type: String) -> void:
	print("MainSession: Enemy defeated: ", _type)

func _update_token_ui() -> void:
	pass # Stub
