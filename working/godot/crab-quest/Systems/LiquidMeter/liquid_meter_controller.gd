extends CanvasLayer

## LiquidMeterController
## Links the player's health status to the 2D fluid simulation in UI space.

@onready var sim: Node2D = $SubViewport/LiquidSim2D
@onready var texture_rect: TextureRect = $Display/TextureRect
@onready var sub_viewport: SubViewport = $SubViewport

func _ready() -> void:
	# Assign the viewport texture to the UI element
	# ViewportTexture must be set at runtime if not configured via NodePath in editor
	texture_rect.texture = sub_viewport.get_texture()
	
	# Find player and connect
	# We use a slight delay or group search to ensure player is ready
	await get_tree().process_frame
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		_connect_player(player)
	else:
		print("LiquidMeter: Player not found in 'Player' group yet.")

func _connect_player(player: Node) -> void:
	if player.has_signal("took_damage"):
		if not player.took_damage.is_connected(_on_player_took_damage):
			player.took_damage.connect(_on_player_took_damage)
			print("LiquidMeter: Connected to Player damage signal.")
	
	# Initial sync if starting mid-game
	if "health" in player and "max_health" in player:
		pass

func _on_player_took_damage(_new_health: float, amount: float) -> void:
	if sim and sim.has_method("take_damage"):
		# Map player damage (100 base) to sim height (40 base)
		var sim_damage = amount * (float(sim.height) / 100.0)
		sim.take_damage(sim_damage)
		print("LiquidMeter: Received hit, damage: ", amount, " -> sim: ", sim_damage)
