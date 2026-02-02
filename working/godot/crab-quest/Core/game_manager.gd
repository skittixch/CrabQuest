extends Node

## Global Game Manager
## Handles scene transitions and player state continuity.

var player_start_pos: Vector3 = Vector3.ZERO
var player_start_rotation: Vector3 = Vector3.ZERO
var camera_start_rotation: Vector2 = Vector2.ZERO
var camera_start_distance: float = 80.0

func transition_to_gameplay(final_player_pos: Vector3, final_player_rot: Vector3, final_cam_rot: Vector2):
	# Save the "End State" of the cutscene
	player_start_pos = final_player_pos
	player_start_rotation = final_player_rot
	camera_start_rotation = final_cam_rot
	
	# Jump to the gameplay world
	get_tree().change_scene_to_file("res://Scenes/World.tscn")

func start_cinematic():
	get_tree().change_scene_to_file("res://Scenes/OpeningPrototype.tscn")
