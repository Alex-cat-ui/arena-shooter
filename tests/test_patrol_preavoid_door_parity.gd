extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted

	var valid: bool = true
	var doors: Array = [Rect2(-60.0, -6.0, 120.0, 12.0)]
	var _entry_gate: Rect2 = Rect2()

	func _door_wall_thickness() -> float:
		return 16.0


class FakeNav:
	extends Node

	func room_id_at_point(_point: Vector2) -> int:
		return 0

	func can_enemy_traverse_point(_enemy: Node, _point: Vector2) -> bool:
		return true

	func build_policy_valid_path(_from: Vector2, to: Vector2, _enemy: Node = null, _cost_profile: Dictionary = {}) -> Dictionary:
		return {
			"status": "ok",
			"path_points": [to],
			"reason": "ok",
		}


class FakePatrolDecision:
	extends RefCounted

	var fixed_target: Vector2 = Vector2.ZERO

	func _init(target: Vector2) -> void:
		fixed_target = target

	func configure(_nav_system: Node, _home_room_id: int) -> void:
		pass

	func update(_delta: float, _facing_dir: Vector2) -> Dictionary:
		return {
			"waiting": false,
			"target": fixed_target,
			"speed_scale": 1.0,
		}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("PATROL PREAVOID DOOR PARITY TEST")
	print("============================================================")

	await _test_preavoid_keeps_door_flow_intact()

	_t.summary("PATROL PREAVOID DOOR PARITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_preavoid_keeps_door_flow_intact() -> void:
	var world := await _create_world()
	var root := world.get("root") as Node2D
	var door := world.get("door") as Node2D
	var door_system := world.get("door_system") as Node

	var enemy := TestHelpers.spawn_mover(root, Vector2(0.0, 56.0), 2, 1, "enemies")
	enemy.set_meta("door_system", door_system)
	var nav := FakeNav.new()
	root.add_child(nav)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(enemy, null, 2.4)
	pursuit.configure_navigation(nav, 0)
	var patrol_target := Vector2(0.0, -120.0)
	pursuit.set("_patrol", FakePatrolDecision.new(patrol_target))

	await get_tree().process_frame
	await get_tree().physics_frame

	var door_opened := false
	var reached := false
	var preavoid_door_contract_ok := true
	var saw_preavoid_door := false
	var saw_preavoid_non_door := false
	for _i in range(420):
		pursuit.execute_intent(
			1.0 / 60.0,
			{"type": ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL},
			_patrol_context(patrol_target)
		)
		await get_tree().physics_frame
		var snapshot := pursuit.debug_get_navigation_policy_snapshot() as Dictionary
		if bool(snapshot.get("preavoid_triggered", false)) and String(snapshot.get("preavoid_kind", "")) == "door":
			saw_preavoid_door = true
			preavoid_door_contract_ok = preavoid_door_contract_ok and (
				not bool(snapshot.get("preavoid_forced_repath", true))
				and String(snapshot.get("preavoid_side", "none")) == "none"
			)
		if bool(snapshot.get("preavoid_triggered", false)) and String(snapshot.get("preavoid_kind", "")) == "non_door":
			saw_preavoid_non_door = true

		var metrics := door.get_debug_metrics() as Dictionary
		var angle_deg := absf(float(metrics.get("angle_deg", 0.0)))
		if angle_deg > 0.5:
			door_opened = true
		if enemy.global_position.distance_to(patrol_target) <= 20.0:
			reached = true
			break

	_t.run_test("preavoid door parity: door opens on approach", door_opened)
	_t.run_test("preavoid door parity: patrol crosses through door", reached)
	_t.run_test("preavoid door parity: preavoid door snapshots never force repath", preavoid_door_contract_ok)
	_t.run_test("preavoid door parity: door kind is observable when predicted", (not saw_preavoid_door) or preavoid_door_contract_ok)
	_t.run_test(
		"preavoid door parity: no false non-door preavoid around centered door approach",
		not saw_preavoid_non_door
	)

	enemy.queue_free()
	await _free_world(world)


func _create_world() -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	TestHelpers.add_wall(root, Vector2(-180.0, 0.0), Vector2(240.0, 16.0))
	TestHelpers.add_wall(root, Vector2(180.0, 0.0), Vector2(240.0, 16.0))

	var doors_parent := Node2D.new()
	doors_parent.name = "LayoutDoors"
	root.add_child(doors_parent)

	var door_system := LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	door_system.name = "LayoutDoorSystem"
	root.add_child(door_system)
	door_system.initialize(doors_parent)
	door_system.rebuild_for_layout(FakeLayout.new())

	await get_tree().process_frame
	await get_tree().physics_frame

	var door: Node2D = door_system.find_nearest_door(Vector2.ZERO, 9999.0)
	return {
		"root": root,
		"door_system": door_system,
		"door": door,
	}


func _free_world(world: Dictionary) -> void:
	var root := world.get("root", null) as Node
	if root:
		root.queue_free()
	await get_tree().physics_frame


func _patrol_context(player_pos: Vector2) -> Dictionary:
	return {
		"player_pos": player_pos,
		"known_target_pos": Vector2.ZERO,
		"last_seen_pos": Vector2.ZERO,
		"investigate_anchor": Vector2.ZERO,
		"home_position": Vector2.ZERO,
		"alert_level": 0,
		"los": false,
		"combat_lock": false,
	}


func can_enemy_traverse_geometry_point(_enemy: Node, _point: Vector2) -> bool:
	return true
