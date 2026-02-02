extends GPUParticles3D

func _ready() -> void:
	emitting = true
	var timer = get_tree().create_timer(lifetime + 0.5)
	timer.timeout.connect(queue_free)
