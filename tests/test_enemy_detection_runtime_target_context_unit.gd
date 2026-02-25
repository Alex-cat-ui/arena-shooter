extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeShadowQueryNav:
	extends Node

	var shadow_center: Vector2 = Vector2(300.0, 20.0)
	var room_centers := {3: Vector2(64.0, 16.0)}

	func is_point_in_shadow(point: Vector2) -> bool:
		return point.distance_to(shadow_center) <= 0.001

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY DETECTION RUNTIME TARGET CONTEXT UNIT TEST")
	print("============================================================")

	await _test_resolve_known_target_context_priority_contract()
	await _test_build_utility_context_contract_and_shadow_priority()

	_t.summary("ENEMY DETECTION RUNTIME TARGET CONTEXT UNIT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, id: int) -> Dictionary:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(id, "zombie")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("detection_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
	}


func _test_resolve_known_target_context_priority_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84951)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("detection runtime target-context: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var live_pos := Vector2(64.0, 8.0)
	var live_ctx := runtime.call("resolve_known_target_context", true, live_pos, true) as Dictionary
	var live_ok := (
		bool(live_ctx.get("has_known_target", false))
		and not bool(live_ctx.get("target_is_last_seen", true))
		and _vec_eq(live_ctx.get("known_target_pos", Vector2.ZERO) as Vector2, live_pos)
	)

	enemy.debug_force_awareness_state("COMBAT")
	var search_pos := Vector2(220.0, 20.0)
	runtime.call("set_state_value", "_combat_search_target_pos", search_pos)
	var combat_ctx := runtime.call("resolve_known_target_context", false, Vector2.ZERO, false) as Dictionary
	var combat_ok := (
		bool(combat_ctx.get("has_known_target", false))
		and not bool(combat_ctx.get("target_is_last_seen", true))
		and _vec_eq(combat_ctx.get("known_target_pos", Vector2.ZERO) as Vector2, search_pos)
	)

	enemy.debug_force_awareness_state("ALERT")
	var last_seen_pos := Vector2(128.0, 48.0)
	runtime.call("set_state_value", "_combat_search_target_pos", Vector2.ZERO)
	runtime.call("set_state_value", "_last_seen_pos", last_seen_pos)
	runtime.call("set_state_value", "_last_seen_age", 0.3)
	var last_seen_ctx := runtime.call("resolve_known_target_context", false, Vector2.ZERO, false) as Dictionary
	var last_seen_ok := (
		bool(last_seen_ctx.get("has_known_target", false))
		and bool(last_seen_ctx.get("target_is_last_seen", false))
		and _vec_eq(last_seen_ctx.get("known_target_pos", Vector2.ZERO) as Vector2, last_seen_pos)
	)

	_t.run_test("detection runtime target-context: visible player has top priority", live_ok)
	_t.run_test("detection runtime target-context: COMBAT uses combat-search target", combat_ok)
	_t.run_test("detection runtime target-context: finite last-seen is preserved outside COMBAT", last_seen_ok)

	world.queue_free()
	await get_tree().process_frame


func _test_build_utility_context_contract_and_shadow_priority() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84952)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)
	var nav := FakeShadowQueryNav.new()
	world.add_child(nav)

	_t.run_test("detection runtime utility-context: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "nav_system", nav)
	runtime.call("set_state_value", "home_room_id", 3)
	runtime.call("set_state_value", "_current_alert_level", ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	runtime.call("set_state_value", "_awareness", null)
	runtime.call("set_state_value", "_last_seen_age", 0.5)
	runtime.call("set_state_value", "_last_seen_pos", Vector2(200.0, 20.0))
	runtime.call("set_state_value", "_investigate_anchor", Vector2(100.0, 20.0))
	runtime.call("set_state_value", "_investigate_anchor_valid", true)

	var assignment := {
		"role": 0,
		"slot_role": 0,
		"slot_position": Vector2(96.0, 0.0),
		"path_ok": true,
		"path_status": "ok",
		"slot_path_eta_sec": 0.75,
		"has_slot": true,
	}
	var known_context := {
		"known_target_pos": Vector2(300.0, 20.0),
		"target_is_last_seen": false,
		"has_known_target": true,
	}
	var known_ctx := runtime.call("build_utility_context", false, false, assignment, known_context) as Dictionary

	var required_keys := [
		"dist",
		"los",
		"alert_level",
		"combat_lock",
		"last_seen_age",
		"last_seen_pos",
		"has_last_seen",
		"dist_to_last_seen",
		"investigate_anchor",
		"has_investigate_anchor",
		"dist_to_investigate_anchor",
		"role",
		"slot_role",
		"slot_position",
		"dist_to_slot",
		"hp_ratio",
		"path_ok",
		"slot_path_status",
		"slot_path_eta_sec",
		"flank_slot_contract_ok",
		"has_slot",
		"player_pos",
		"known_target_pos",
		"target_is_last_seen",
		"has_known_target",
		"target_context_exists",
		"home_position",
		"shadow_scan_target",
		"has_shadow_scan_target",
		"shadow_scan_target_in_shadow",
		"shadow_scan_source",
		"shadow_scan_completed",
		"shadow_scan_completed_reason",
	]
	var has_all := true
	for key_variant in required_keys:
		var key := String(key_variant)
		if not known_ctx.has(key):
			has_all = false
			break

	var known_priority_ok := (
		String(known_ctx.get("shadow_scan_source", "")) == "known_target_pos"
		and _vec_eq(known_ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2, Vector2(300.0, 20.0))
		and bool(known_ctx.get("shadow_scan_target_in_shadow", false))
	)
	var home_ok := _vec_eq(known_ctx.get("home_position", Vector2.ZERO) as Vector2, Vector2(64.0, 16.0))

	var no_known_ctx := runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}) as Dictionary
	var last_seen_priority_ok := (
		String(no_known_ctx.get("shadow_scan_source", "")) == "last_seen"
		and _vec_eq(no_known_ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2, Vector2(200.0, 20.0))
	)

	runtime.call("set_state_value", "_last_seen_age", INF)
	var anchor_ctx := runtime.call("build_utility_context", false, false, assignment, {
		"known_target_pos": Vector2.ZERO,
		"target_is_last_seen": false,
		"has_known_target": false,
	}) as Dictionary
	var anchor_priority_ok := (
		String(anchor_ctx.get("shadow_scan_source", "")) == "investigate_anchor"
		and _vec_eq(anchor_ctx.get("shadow_scan_target", Vector2.ZERO) as Vector2, Vector2(100.0, 20.0))
	)

	_t.run_test("detection runtime utility-context: required key contract is preserved", has_all)
	_t.run_test("detection runtime utility-context: shadow target priority known_target_pos", known_priority_ok)
	_t.run_test("detection runtime utility-context: shadow target priority last_seen", last_seen_priority_ok)
	_t.run_test("detection runtime utility-context: shadow target priority investigate_anchor fallback", anchor_priority_ok)
	_t.run_test("detection runtime utility-context: home_position uses nav room center", home_ok)

	world.queue_free()
	await get_tree().process_frame


func _vec_eq(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= 0.001
