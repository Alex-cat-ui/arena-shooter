extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("WEAPONS STARTUP POLICY ON TEST")
	print("============================================================")

	_test_enemy_toggle_flag_removed_from_config()
	await _test_controller_pipeline_still_wired()
	await _test_enemy_snapshot_has_no_toggle_field()
	await _test_enemy_toggle_api_removed()

	_t.summary("WEAPONS STARTUP POLICY ON RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_toggle_flag_removed_from_config() -> void:
	var cfg := STEALTH_TEST_CONFIG_SCRIPT.values()
	_t.run_test("config: enemy_weapons_enabled_on_start removed",
		not cfg.has("enemy_weapons_enabled_on_start"))


func _test_controller_pipeline_still_wired() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	_t.run_test("startup: controller exists", controller != null)
	if controller == null:
		room.queue_free()
		await get_tree().process_frame
		return

	var pipeline := controller.debug_get_combat_pipeline_summary() as Dictionary
	_t.run_test("startup: combat system exists in pipeline",
		bool(pipeline.get("combat_system_exists", false)))
	_t.run_test("startup: ability system exists in pipeline",
		bool(pipeline.get("ability_system_exists", false)))

	room.queue_free()
	await get_tree().process_frame


func _test_enemy_snapshot_has_no_toggle_field() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemy := _first_enemy_under(room)
	_t.run_test("snapshot: enemy exists", enemy != null)
	if enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("snapshot: weapons_enabled field removed",
		not snapshot.has("weapons_enabled"))

	room.queue_free()
	await get_tree().process_frame


func _test_enemy_toggle_api_removed() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemy := _first_enemy_under(room)
	if enemy == null:
		_t.run_test("single-source: enemy exists", false)
		room.queue_free()
		await get_tree().process_frame
		return

	_t.run_test("single-source: enemy has no weapons toggle method",
		not enemy.has_method("set_weapons_enabled_for_test") and not enemy.has_method("is_weapons_enabled_for_test"))

	room.queue_free()
	await get_tree().process_frame


func _first_enemy_under(ancestor: Node) -> Enemy:
	for member_variant in get_tree().get_nodes_in_group("enemies"):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member as Enemy
	return null
