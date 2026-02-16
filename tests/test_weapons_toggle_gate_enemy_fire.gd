extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _enemy_shots: int = 0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("WEAPONS TOGGLE GATE TEST")
	print("============================================================")

	_connect_enemy_shot_signal()
	await _test_weapons_toggle_gate_enemy_fire()
	await _test_weapons_toggle_same_tick()
	_disconnect_enemy_shot_signal()

	_t.summary("WEAPONS TOGGLE GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_weapons_toggle_gate_enemy_fire() -> void:
	_enemy_shots = 0
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("weapons gate: controller exists", controller != null)
	_t.run_test("weapons gate: player exists", player != null)
	_t.run_test("weapons gate: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	player.global_position = Vector2(300.0, -40.0)
	player.velocity = Vector2.ZERO
	if enemy.has_method("disable_suspicion_test_profile"):
		enemy.disable_suspicion_test_profile()
	await get_tree().physics_frame

	if controller.has_method("_set_test_weapons_enabled"):
		controller.call("_set_test_weapons_enabled", false)
	_press_key(controller, KEY_3)

	var shots_before_off_window := _enemy_shots
	for _i in range(180):
		await get_tree().physics_frame
		await get_tree().process_frame
	_t.run_test(
		"weapons gate: toggle OFF blocks COMBAT fire",
		_enemy_shots == shots_before_off_window
	)

	_press_key(controller, KEY_F7)
	var shots_before_on_window := _enemy_shots
	for _i in range(240):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _enemy_shots > shots_before_on_window:
			break
	_t.run_test(
		"weapons gate: toggle ON allows COMBAT fire",
		_enemy_shots > shots_before_on_window
	)

	room.queue_free()
	await get_tree().process_frame


func _test_weapons_toggle_same_tick() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("weapons same-tick: controller exists", controller != null)
	_t.run_test("weapons same-tick: enemy exists", enemy != null)
	if controller == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	if controller.has_method("_set_test_weapons_enabled"):
		controller.call("_set_test_weapons_enabled", false)
	var snapshot_before := enemy.get_debug_detection_snapshot() as Dictionary
	var before_enabled := bool(snapshot_before.get("weapons_enabled", true))

	_press_key(controller, KEY_F7)
	var snapshot_after_on := enemy.get_debug_detection_snapshot() as Dictionary
	var after_on_enabled := bool(snapshot_after_on.get("weapons_enabled", false))
	var internal_on := enemy.has_method("is_weapons_enabled_for_test") and enemy.is_weapons_enabled_for_test()

	_press_key(controller, KEY_F7)
	var snapshot_after_off := enemy.get_debug_detection_snapshot() as Dictionary
	var after_off_enabled := bool(snapshot_after_off.get("weapons_enabled", true))
	var internal_off := enemy.has_method("is_weapons_enabled_for_test") and not enemy.is_weapons_enabled_for_test()

	_t.run_test("weapons same-tick: starts OFF in snapshot", not before_enabled)
	_t.run_test("weapons same-tick: snapshot flips ON immediately", after_on_enabled)
	_t.run_test("weapons same-tick: internal gate flips ON immediately", internal_on)
	_t.run_test("weapons same-tick: snapshot flips OFF immediately", not after_off_enabled)
	_t.run_test("weapons same-tick: internal gate flips OFF immediately", internal_off)

	room.queue_free()
	await get_tree().process_frame


func _press_key(controller: Node, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	key.physical_keycode = keycode
	controller.call("_unhandled_input", key)


func _connect_enemy_shot_signal() -> void:
	if EventBus and EventBus.has_signal("enemy_shot") and not EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.connect(_on_enemy_shot)


func _disconnect_enemy_shot_signal() -> void:
	if EventBus and EventBus.has_signal("enemy_shot") and EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)


func _on_enemy_shot(_enemy_id: int, _weapon: String, _position: Vector3, _direction: Vector3) -> void:
	_enemy_shots += 1


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
