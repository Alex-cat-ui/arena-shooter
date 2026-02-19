extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")

const REASON_NO_COMBAT_STATE := "no_combat_state"
const REASON_NO_LOS := "no_los"
const REASON_OUT_OF_RANGE := "out_of_range"
const REASON_COOLDOWN := "cooldown"
const REASON_FIRST_ATTACK_DELAY := "first_attack_delay"

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _saved_ai_balance: Dictionary = {}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY SHOTGUN FIRE BLOCK REASONS TEST")
	print("============================================================")

	await _test_shotgun_fire_block_reasons_snapshot()

	_t.summary("ENEMY SHOTGUN FIRE BLOCK REASONS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shotgun_fire_block_reasons_snapshot() -> void:
	_saved_ai_balance = (GameConfig.ai_balance as Dictionary).duplicate(true) if GameConfig else {}

	var room := STEALTH_ROOM_SCENE.instantiate() as Node2D
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("fire reasons: player exists", player != null)
	_t.run_test("fire reasons: enemy exists", enemy != null)
	if player == null or enemy == null:
		await _cleanup(room)
		return

	if enemy.has_method("disable_suspicion_test_profile"):
		enemy.disable_suspicion_test_profile()
	if RuntimeState:
		RuntimeState.is_frozen = false
	if GameConfig:
		GameConfig.god_mode = true

	player.global_position = enemy.global_position + Vector2(260.0, 0.0)
	player.velocity = Vector2.ZERO
	await _set_enemy_facing(enemy, Vector2.RIGHT)
	await _advance_frames(6)

	var baseline_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("fire reasons: snapshot exposes shotgun_fire_block_reason", baseline_snapshot.has("shotgun_fire_block_reason"))

	if enemy.has_method("debug_force_awareness_state"):
		enemy.call("debug_force_awareness_state", "CALM")
	enemy.set("_shot_cooldown", 0.0)
	enemy.set("_combat_first_attack_delay_timer", 0.0)
	await _advance_frames(6)
	_t.run_test(
		"fire reasons: no_combat_state",
		_reason(enemy) == REASON_NO_COMBAT_STATE
	)

	if enemy.has_method("debug_force_awareness_state"):
		enemy.call("debug_force_awareness_state", "COMBAT")
	enemy.set("_shot_cooldown", 0.0)
	enemy.set("_combat_first_attack_delay_timer", 0.0)
	player.global_position = enemy.global_position + Vector2(700.0, 0.0)
	await _set_enemy_facing(enemy, Vector2.RIGHT)
	await _advance_frames(6)
	_t.run_test(
		"fire reasons: no_los",
		_reason(enemy) == REASON_NO_LOS
	)

	if GameConfig:
		_set_enemy_fire_range_override(120.0)
	if enemy.has_method("debug_force_awareness_state"):
		enemy.call("debug_force_awareness_state", "COMBAT")
	enemy.set("_shot_cooldown", 0.0)
	enemy.set("_combat_first_attack_delay_timer", 0.0)
	player.global_position = enemy.global_position + Vector2(260.0, 0.0)
	await _set_enemy_facing(enemy, Vector2.RIGHT)
	await _advance_frames(6)
	_t.run_test(
		"fire reasons: out_of_range",
		_reason(enemy) == REASON_OUT_OF_RANGE
	)

	if GameConfig:
		_restore_ai_balance()
	if enemy.has_method("debug_force_awareness_state"):
		enemy.call("debug_force_awareness_state", "COMBAT")
	enemy.set("_shot_cooldown", 0.45)
	enemy.set("_combat_first_attack_delay_timer", 0.0)
	player.global_position = enemy.global_position + Vector2(260.0, 0.0)
	await _set_enemy_facing(enemy, Vector2.RIGHT)
	await _advance_frames(4)
	_t.run_test(
		"fire reasons: cooldown",
		_reason(enemy) == REASON_COOLDOWN
	)

	if enemy.has_method("debug_force_awareness_state"):
		enemy.call("debug_force_awareness_state", "COMBAT")
	enemy.set("_shot_cooldown", 0.0)
	enemy.set("_combat_first_attack_delay_timer", 0.45)
	player.global_position = enemy.global_position + Vector2(260.0, 0.0)
	await _set_enemy_facing(enemy, Vector2.RIGHT)
	await _advance_frames(4)
	_t.run_test(
		"fire reasons: first_attack_delay",
		_reason(enemy) == REASON_FIRST_ATTACK_DELAY
	)

	await _cleanup(room)


func _reason(enemy: Enemy) -> String:
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	return String(snapshot.get("shotgun_fire_block_reason", ""))


func _set_enemy_facing(enemy: Enemy, dir: Vector2) -> void:
	var pursuit_variant: Variant = enemy.get("_pursuit")
	if pursuit_variant == null:
		return
	var pursuit := pursuit_variant as Object
	if pursuit == null:
		return
	var n_dir := dir.normalized()
	if n_dir.length_squared() <= 0.0001:
		return
	pursuit.set("facing_dir", n_dir)
	pursuit.set("_target_facing_dir", n_dir)
	await get_tree().physics_frame


func _set_enemy_fire_range_override(range_px: float) -> void:
	if not GameConfig:
		return
	var ai_balance := (GameConfig.ai_balance as Dictionary).duplicate(true)
	var enemy_vision := (ai_balance.get("enemy_vision", {}) as Dictionary).duplicate(true)
	enemy_vision["fire_attack_range_max_px"] = range_px
	ai_balance["enemy_vision"] = enemy_vision
	GameConfig.ai_balance = ai_balance


func _restore_ai_balance() -> void:
	if not GameConfig:
		return
	if _saved_ai_balance.is_empty():
		GameConfig.reset_to_defaults()
		return
	GameConfig.ai_balance = _saved_ai_balance.duplicate(true)


func _advance_frames(frames: int) -> void:
	for _i in range(maxi(frames, 0)):
		await get_tree().physics_frame
		await get_tree().process_frame


func _cleanup(room: Node) -> void:
	_restore_ai_balance()
	if room and is_instance_valid(room):
		room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
