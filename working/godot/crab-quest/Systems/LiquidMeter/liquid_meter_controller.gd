extends Node

## LiquidMeterController
## Links the player's health status to the 2D fluid simulation.

# References to the Sim inside the complex Viewport tree
@export var sim_path: NodePath
@export var liquid_mat: Material # Assigned in scene

var sim: Node2D

func _ready() -> void:
	if sim_path:
		sim = get_node(sim_path)
	
	# SETUP HEART MATERIAL
	# Find the heart mesh instance in the viewport hierarchy
	var heart_root = get_node_or_null("UIContainer/DisplayInit/Heart3DViewport/SceneRoot/heart")
	if heart_root:
		var mesh_instance = _find_mesh_recursive(heart_root)
		if mesh_instance:
			_apply_liquid_to_surface(mesh_instance, "HeartIn")
		else:
			print("LiquidMeter: Could not find MeshInstance3D in heart.glb")
	
	# Delay connection to ensure Player exists
	await get_tree().process_frame
	
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		_connect_player(player)

func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_mesh_recursive(child)
		if result:
			return result
	return null

func _apply_liquid_to_surface(mesh_inst: MeshInstance3D, mat_name: String) -> void:
	var mesh = mesh_inst.mesh
	if not mesh: return
	
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		if mat and mat.resource_name == mat_name:
			print("LiquidMeter: Found surface '", mat_name, "' at index ", i, ". Applying liquid.")
			mesh_inst.set_surface_override_material(i, liquid_mat)
			return
	
	print("LiquidMeter: SURFACE NOT FOUND: ", mat_name)


func _connect_player(player: Node) -> void:
	if player.has_signal("took_damage"):
		if not player.took_damage.is_connected(_on_player_took_damage):
			player.took_damage.connect(_on_player_took_damage)
			print("LiquidMeter: Connected to Player damage.")

func _on_player_took_damage(_new_health: float, amount: float) -> void:
	if sim and sim.has_method("take_damage"):
		# Map player damage (100 base) to sim height (10 base)
		var sim_damage = amount * (float(sim.height) / 100.0)
		sim.take_damage(sim_damage)
		print("LiquidMeter: Hit! Damage: ", amount)
