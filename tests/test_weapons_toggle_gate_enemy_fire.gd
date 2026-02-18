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
	await _test_enemy_combat_without_toggle_gate()
	await _test_enemy_toggle_input_removed()
	_disconnect_enemy_shot_signal()

	_t.summary("WEAPONS TOGGLE GATE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_combat_without_toggle_gate() -> void:
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

	player.global_position = Vector2(520.0, -40.0)
	player.velocity = Vector2.ZERO
	if enemy.has_method("disable_suspicion_test_profile"):
		enemy.disable_suspicion_test_profile()
	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")
	await get_tree().physics_frame

	for _i in range(300):
		await get_tree().physics_frame
		await get_tree().process_frame
		var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
		if String(snapshot.get("state_name", "")) == "COMBAT":
			break
	var final_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"weapons gate removed: enemy reaches COMBAT without toggle",
		String(final_snapshot.get("state_name", "")) == "COMBAT"
	)

	room.queue_free()
	await get_tree().process_frame


func _test_enemy_toggle_input_removed() -> void:
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

	var snapshot_before := enemy.get_debug_detection_snapshot() as Dictionary
	var before_has_field := snapshot_before.has("weapons_enabled")

	_press_key(controller, KEY_F7)
	await get_tree().process_frame
	var snapshot_after_on := enemy.get_debug_detection_snapshot() as Dictionary
	var after_has_field := snapshot_after_on.has("weapons_enabled")
	var toggle_api_removed := not enemy.has_method("set_weapons_enabled_for_test") and not enemy.has_method("is_weapons_enabled_for_test")

	_t.run_test("weapons same-tick: snapshot has no weapons_enabled field", not before_has_field and not after_has_field)
	_t.run_test("weapons same-tick: enemy toggle API removed", toggle_api_removed)

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
