extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const THREE_ZONE_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

const FIRE_ATTEMPTS := 20

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _player_shot_events: int = 0
var _player_shotgun_events: int = 0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("3-ZONE PLAYER SHOTGUN FIRE PIPELINE TEST")
	print("============================================================")

	await _test_weapon_2_plus_shoot_emits_shotgun_event_20_of_20()

	_t.summary("3-ZONE PLAYER SHOTGUN FIRE PIPELINE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_weapon_2_plus_shoot_emits_shotgun_event_20_of_20() -> void:
	_player_shot_events = 0
	_player_shotgun_events = 0
	if EventBus and EventBus.has_signal("player_shot") and not EventBus.player_shot.is_connected(_on_player_shot):
		EventBus.player_shot.connect(_on_player_shot)

	var level := THREE_ZONE_SCENE.instantiate() as Node2D
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D

	_t.run_test("3zone fire: controller exists", controller != null)
	_t.run_test("3zone fire: player exists", player != null)
	if controller == null or player == null:
		await _cleanup(level)
		return

	var summary := controller.call("debug_get_combat_pipeline_summary") as Dictionary if controller.has_method("debug_get_combat_pipeline_summary") else {}
	var pipeline_ok := (
		bool(summary.get("combat_system_exists", false))
		and bool(summary.get("projectile_system_exists", false))
		and bool(summary.get("ability_system_exists", false))
		and bool(summary.get("player_ability_wired", false))
		and bool(summary.get("ability_projectile_wired", false))
		and bool(summary.get("ability_combat_wired", false))
		and not ("projectile_system" in player)
	)
	_t.run_test("3zone fire: player weapon pipeline is wired", pipeline_ok)

	var ability: Variant = player.ability_system if "ability_system" in player else null
	if ability == null or not ability.has_method("set_weapon_by_index") or not ability.has_method("get_current_weapon"):
		_t.run_test("3zone fire: player ability system available", false)
		await _cleanup(level)
		return
	_t.run_test("3zone fire: player ability system available", true)

	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_aim_dir = Vector3(1.0, 0.0, 0.0)

	var successful_attempts := 0
	for _attempt in range(FIRE_ATTEMPTS):
		ability.set_weapon_by_index(0)
		await get_tree().physics_frame

		Input.action_press("weapon_2")
		await get_tree().physics_frame
		await get_tree().process_frame
		Input.action_release("weapon_2")
		await get_tree().process_frame

		var before_shotgun := _player_shotgun_events
		Input.action_press("shoot")
		await get_tree().physics_frame
		await get_tree().process_frame
		Input.action_release("shoot")
		await get_tree().process_frame
		await get_tree().process_frame

		if _player_shotgun_events > before_shotgun:
			successful_attempts += 1

	_t.run_test("3zone fire: weapon_2 + shoot emits shotgun shot event 20/20", successful_attempts == FIRE_ATTEMPTS)
	_t.run_test("3zone fire: all captured player_shot events are shotgun", _player_shot_events == _player_shotgun_events)

	await _cleanup(level)


func _cleanup(level: Node) -> void:
	Input.action_release("weapon_2")
	Input.action_release("shoot")
	if EventBus and EventBus.has_signal("player_shot") and EventBus.player_shot.is_connected(_on_player_shot):
		EventBus.player_shot.disconnect(_on_player_shot)
	if level and is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_player_shot(weapon_type: String, _position: Vector3, _direction: Vector3) -> void:
	_player_shot_events += 1
	if weapon_type == "shotgun":
		_player_shotgun_events += 1
