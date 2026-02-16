extends RefCounted
class_name LevelEventsController

var _ctx = null


func bind(ctx) -> void:
	_ctx = ctx
	if not EventBus:
		return
	if not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.rocket_exploded.is_connected(_on_rocket_exploded):
		EventBus.rocket_exploded.connect(_on_rocket_exploded)


func unbind() -> void:
	if EventBus:
		if EventBus.player_damaged.is_connected(_on_player_damaged):
			EventBus.player_damaged.disconnect(_on_player_damaged)
		if EventBus.player_died.is_connected(_on_player_died):
			EventBus.player_died.disconnect(_on_player_died)
		if EventBus.rocket_exploded.is_connected(_on_rocket_exploded):
			EventBus.rocket_exploded.disconnect(_on_rocket_exploded)
	_ctx = null


func _on_player_damaged(amount: int, new_hp: int, source: String) -> void:
	print("[LevelMVP] Player damaged: %d (HP: %d, source: %s)" % [amount, new_hp, source])
	if _ctx and _ctx.player and _ctx.player.has_method("take_damage"):
		_ctx.player.take_damage(amount)


func _on_player_died() -> void:
	print("[LevelMVP] Player died!")


func _on_rocket_exploded(_pos: Vector3) -> void:
	if _ctx and _ctx.camera_shake:
		var amp: float = GameConfig.rocket_shake_amplitude if GameConfig else 3.0
		var dur: float = GameConfig.rocket_shake_duration if GameConfig else 0.15
		_ctx.camera_shake.shake(amp, dur)
