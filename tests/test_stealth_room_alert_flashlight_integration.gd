extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

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
	print("STEALTH ROOM ALERT FLASHLIGHT INTEGRATION TEST")
	print("============================================================")

	await _test_alert_flashlight_growth_in_scene()

	_t.summary("STEALTH ROOM ALERT FLASHLIGHT INTEGRATION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_flashlight_growth_in_scene() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("stealth room integration: controller exists", controller != null)
	_t.run_test("stealth room integration: player exists", player != null)
	_t.run_test("stealth room integration: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0

	var cfg := STEALTH_TEST_CONFIG_SCRIPT.values()
	player.global_position = enemy.global_position + Vector2(300.0, 0.0)
	player.velocity = Vector2.ZERO
	await get_tree().physics_frame

	if controller.has_method("_force_enemy_alert"):
		controller.call("_force_enemy_alert")

	var pursuit_controller = enemy.get("_pursuit")
	if pursuit_controller:
		pursuit_controller.set("facing_dir", Vector2.RIGHT)
		pursuit_controller.set("_target_facing_dir", Vector2.RIGHT)

	enemy.set_physics_process(false)
	enemy.runtime_budget_tick(0.5)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test("scene ALERT flashlight is active", bool(snapshot.get("flashlight_active", false)))
	_t.run_test("scene ALERT flashlight reports in-cone", bool(snapshot.get("in_cone", false)))
	_t.run_test("scene ALERT flashlight hits player in cone", bool(snapshot.get("flashlight_hit", false)))
	_t.run_test("scene ALERT flashlight path keeps LOS", bool(snapshot.get("los_to_player", snapshot.get("has_los", false))))
	_t.run_test("scene ALERT flashlight path grows suspicion", float(snapshot.get("suspicion", 0.0)) > 0.0)
	_t.run_test(
		"scene ALERT flashlight debug exposes facing used for calculation",
		snapshot.has("facing_used_for_flashlight") and snapshot.has("facing_after_move")
	)
	_t.run_test(
		"scene ALERT flashlight post-clamp visibility is in bounds",
		float(snapshot.get("effective_visibility_post_clamp", -1.0)) >= 0.0
		and float(snapshot.get("effective_visibility_post_clamp", 2.0)) <= 1.0
	)
	var shadow_zone := room.get_node_or_null("ShadowZone")
	if shadow_zone:
		_t.run_test(
			"scene shadow zone uses configured multiplier",
			is_equal_approx(float(shadow_zone.get("shadow_multiplier")), float(cfg.get("shadow_multiplier_default", 0.35)))
		)

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")
	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id < 0 and enemy.has_method("_resolve_room_id_for_events"):
		room_id = int(enemy.call("_resolve_room_id_for_events"))
	var room_alert_level := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var alert_system = controller.get("_enemy_alert_system")
	if alert_system and alert_system.has_method("get_room_alert_level") and room_id >= 0:
		room_alert_level = int(alert_system.get_room_alert_level(room_id))
	_t.run_test(
		"scene COMBAT same tick room alert escalates",
		room_alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)

	enemy.runtime_budget_tick(0.1)
	snapshot = enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"scene COMBAT snapshot has no COMBAT|CALM mismatch",
		not (
			int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
			and int(snapshot.get("room_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.CALM
		)
	)
	_t.run_test("scene COMBAT keeps enemy latched", bool(snapshot.get("latched", false)))
	_t.run_test("scene COMBAT keeps flashlight active", bool(snapshot.get("flashlight_active", false)))
	player.global_position = enemy.global_position + Vector2(120.0, 260.0)
	player.velocity = Vector2.ZERO
	enemy.runtime_budget_tick(0.2)
	snapshot = enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("scene COMBAT remains flashlight-active out of cone", bool(snapshot.get("flashlight_active", false)))
	_t.run_test(
		"scene COMBAT out-of-cone reason is exposed",
		String(snapshot.get("flashlight_inactive_reason", "")) == "cone_miss"
	)

	room.queue_free()
	await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
