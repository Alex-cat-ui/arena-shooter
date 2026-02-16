extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_LAYOUT_CONTROLLER_SCRIPT := preload("res://src/levels/level_layout_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = []
	var _void_ids: Array = []


class SpyLayoutController:
	extends "res://src/levels/level_layout_controller.gd"

	var log: Array = []

	func clear_node_children_detached(parent: Node) -> void:
		log.append("clear_%s" % parent.name)
		super.clear_node_children_detached(parent)

	func generate_layout(_ctx, _arena_rect: Rect2, _seed_value: int, _mission_index: int):
		log.append("generate")
		return FakeLayout.new()

	func ensure_layout_recovered(_ctx, _arena_rect: Rect2, _seed_value: int, _mission_index: int) -> void:
		log.append("recover")

	func rebuild_walkable_floor(_ctx) -> void:
		log.append("floor")

	func update_layout_room_stats(_ctx) -> void:
		log.append("stats")

	func sync_layout_runtime_memory(_ctx, _mission_index: int) -> void:
		log.append("memory")

	func ensure_player_runtime_ready(_ctx) -> void:
		log.append("player_ready")


class FakeArenaBoundary:
	extends "res://src/systems/arena_boundary.gd"
	var shared_log: Array = []
	func initialize(_min_pos: Vector2, _max_pos: Vector2) -> void:
		shared_log.append("arena")


class FakeLayoutDoorSystem:
	extends Node
	var shared_log: Array = []
	func rebuild_for_layout(_layout) -> void:
		shared_log.append("doors")


class FakeRoomEnemySpawner:
	extends Node
	var shared_log: Array = []
	func rebuild_for_layout(_layout) -> void:
		shared_log.append("spawner")


class FakeRoomNavSystem:
	extends Node
	var shared_log: Array = []
	func rebuild_for_layout(_layout) -> void:
		shared_log.append("nav_rebuild")
	func bind_tactical_systems(_alert, _squad) -> void:
		shared_log.append("nav_bind")


class FakeEnemyRuntimeController:
	extends RefCounted
	var shared_log: Array = []
	func rebind_enemy_aggro_context(_ctx) -> void:
		shared_log.append("aggro_rebind")


class FakeTransitionController:
	extends RefCounted
	var shared_log: Array = []
	func current_mission_index(_ctx) -> int:
		return 3
	func setup_north_transition_trigger(_ctx) -> void:
		shared_log.append("transition")


class FakeCameraController:
	extends RefCounted
	var shared_log: Array = []
	func reset_follow(_ctx) -> void:
		shared_log.append("camera")


class FakeRuntimeGuard:
	extends RefCounted
	var shared_log: Array = []
	func enforce_on_layout_reset(_ctx) -> void:
		shared_log.append("guard")


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("LEVEL LAYOUT CONTROLLER REGEN TEST")
	print("============================================================")

	await _test_regen_order_and_rebinds()

	_t.summary("LEVEL LAYOUT CONTROLLER REGEN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_regen_order_and_rebinds() -> void:
	var layout_controller := SpyLayoutController.new()
	var transition := FakeTransitionController.new()
	var camera_ctrl := FakeCameraController.new()
	var enemy_runtime := FakeEnemyRuntimeController.new()
	var guard := FakeRuntimeGuard.new()
	layout_controller.set_dependencies(transition, camera_ctrl, enemy_runtime, guard)

	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.level = Node2D.new()
	add_child(ctx.level)
	ctx.layout_walls = Node2D.new()
	ctx.layout_walls.name = "LayoutWalls"
	ctx.layout_doors = Node2D.new()
	ctx.layout_doors.name = "LayoutDoors"
	ctx.layout_debug = Node2D.new()
	ctx.layout_debug.name = "LayoutDebug"
	ctx.level.add_child(ctx.layout_walls)
	ctx.level.add_child(ctx.layout_doors)
	ctx.level.add_child(ctx.layout_debug)
	ctx.arena_boundary = FakeArenaBoundary.new()
	ctx.arena_boundary.shared_log = layout_controller.log
	ctx.level.add_child(ctx.arena_boundary)
	ctx.layout_door_system = FakeLayoutDoorSystem.new()
	ctx.layout_door_system.shared_log = layout_controller.log
	ctx.level.add_child(ctx.layout_door_system)
	ctx.room_enemy_spawner = FakeRoomEnemySpawner.new()
	ctx.room_enemy_spawner.shared_log = layout_controller.log
	ctx.level.add_child(ctx.room_enemy_spawner)
	ctx.room_nav_system = FakeRoomNavSystem.new()
	ctx.room_nav_system.shared_log = layout_controller.log
	ctx.level.add_child(ctx.room_nav_system)
	ctx.enemy_alert_system = Node.new()
	ctx.enemy_squad_system = Node.new()
	ctx.level.add_child(ctx.enemy_alert_system)
	ctx.level.add_child(ctx.enemy_squad_system)
	ctx.player = CharacterBody2D.new()
	ctx.level.add_child(ctx.player)
	enemy_runtime.shared_log = layout_controller.log
	transition.shared_log = layout_controller.log
	camera_ctrl.shared_log = layout_controller.log
	guard.shared_log = layout_controller.log

	layout_controller.regenerate_layout(ctx, 42)

	var log := layout_controller.log

	_t.run_test("regen clears walls first", _idx(log, "clear_LayoutWalls") < _idx(log, "generate"))
	_t.run_test("regen order keeps doors after generate", _idx(log, "generate") < _idx(log, "doors"))
	_t.run_test("regen order keeps floor before stats", _idx(log, "floor") < _idx(log, "stats"))
	_t.run_test("regen order keeps stats before runtime memory", _idx(log, "stats") < _idx(log, "memory"))
	_t.run_test("regen rebinds spawner and room nav", log.has("spawner") and log.has("nav_rebuild") and log.has("nav_bind"))
	_t.run_test("regen rebinds enemy aggro context", log.has("aggro_rebind"))
	_t.run_test("regen sets transition before camera reset", _idx(log, "transition") <= _idx(log, "camera"))
	_t.run_test("regen applies runtime guard at the end", _idx(log, "guard") > _idx(log, "camera"))

	ctx.level.queue_free()
	await get_tree().process_frame


func _idx(arr: Array, key: String) -> int:
	for i in range(arr.size()):
		if String(arr[i]) == key:
			return i
	return 9999
