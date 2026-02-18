extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_ALERT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_alert_system.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_RUNTIME_BUDGET_CONTROLLER_SCRIPT := preload("res://src/levels/level_runtime_budget_controller.gd")

class FakeNav extends Node:
	var graph := {
		0: [1],
		1: [0, 2],
		2: [1],
	}

	func room_id_at_point(p: Vector2) -> int:
		if p.x < -200.0:
			return 0
		if p.x < 200.0:
			return 1
		return 2

	func get_neighbors(room_id: int) -> Array[int]:
		if not graph.has(room_id):
			return []
		var out: Array[int] = []
		for rid_variant in graph[room_id]:
			out.append(int(rid_variant))
		return out

	func build_path_points(_from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
		return [to_pos]

	func random_point_in_room(room_id: int, _margin: float = 20.0) -> Vector2:
		match room_id:
			0:
				return Vector2(-320.0, 0.0)
			1:
				return Vector2(0.0, 0.0)
			2:
				return Vector2(320.0, 0.0)
			_:
				return Vector2.ZERO

	func get_room_center(room_id: int) -> Vector2:
		return random_point_in_room(room_id)

	func get_enemy_room_id(enemy: Node) -> int:
		var node := enemy as Node2D
		return room_id_at_point(node.global_position) if node else -1

	func get_enemy_room_id_by_id(_enemy_id: int) -> int:
		return 0


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
	print("ENEMY BEHAVIOR INTEGRATION TEST")
	print("============================================================")

	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100

	var world := Node2D.new()
	add_child(world)

	var entities := Node2D.new()
	world.add_child(entities)

	var player := CharacterBody2D.new()
	player.global_position = Vector2(160.0, 0.0)
	player.add_to_group("player")
	entities.add_child(player)

	var enemy_scene := load("res://scenes/entities/enemy.tscn") as PackedScene
	_t.run_test("Enemy scene available", enemy_scene != null)
	if enemy_scene == null:
		world.queue_free()
		return _result()

	var enemy = enemy_scene.instantiate()
	enemy.global_position = Vector2(-420.0, 0.0)
	entities.add_child(enemy)
	await get_tree().process_frame
	enemy.initialize(9001, "zombie")

	var nav := FakeNav.new()
	world.add_child(nav)

	var alert_system = ENEMY_ALERT_SYSTEM_SCRIPT.new()
	world.add_child(alert_system)
	alert_system.initialize(nav)

	var squad_system = ENEMY_SQUAD_SYSTEM_SCRIPT.new()
	world.add_child(squad_system)
	squad_system.initialize(player, nav, entities)

	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.entities_container = entities
	ctx.enemy_squad_system = squad_system
	ctx.navigation_service = nav
	ctx.runtime_budget_controller = LEVEL_RUNTIME_BUDGET_CONTROLLER_SCRIPT.new()
	ctx.runtime_budget_controller.bind(ctx)

	enemy.set_room_navigation(nav, 0)
	enemy.set_tactical_systems(alert_system, squad_system)

	var start_pos: Vector2 = enemy.global_position
	EventBus.emit_enemy_player_spotted(9001, Vector3(enemy.global_position.x, enemy.global_position.y, 0.0))
	await get_tree().process_frame

	for _i in range(240):
		ctx.runtime_budget_controller.process_frame(ctx, 1.0 / 60.0)
		await get_tree().physics_frame

	var marker := enemy.get_node_or_null("AlertMarker") as Sprite2D
	var budget_stats := ctx.runtime_budget_last_frame as Dictionary
	_t.run_test("Room alert level drives enemy to COMBAT marker state",
		enemy.get_current_alert_level() == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	_t.run_test("AlertMarker visible in combat", marker != null and marker.visible)
	_t.run_test("Squad assignment exists", bool(squad_system.get_assignment(9001).get("has_slot", false)))
	_t.run_test("Runtime budget enemy quota respected", int(budget_stats.get("enemy_ai_updates", 0)) <= int(budget_stats.get("enemy_ai_quota", 0)))
	_t.run_test("Runtime budget squad quota respected", int(budget_stats.get("squad_rebuild_updates", 0)) <= int(budget_stats.get("squad_rebuild_quota", 0)))

	var intent := enemy.get_current_intent() as Dictionary
	var intent_type := int(intent.get("type", -1))
	var moved_from_start: bool = enemy.global_position.distance_to(start_pos) > 1.0
	_t.run_test("Utility intent is active (not PATROL in combat)",
		intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL)
	_t.run_test("PUSH intent advances enemy when selected",
		intent_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH or moved_from_start)

	ctx.runtime_budget_controller.unbind()
	world.queue_free()
	await get_tree().process_frame

	_t.summary("ENEMY BEHAVIOR INTEGRATION RESULTS")
	return _result()


func _result() -> Dictionary:
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}
