extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_ALERT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_alert_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

class FakeNav extends Node:
	var enemy_ref: Enemy = null
	var graph := {
		0: [1],
		1: [0],
	}

	func room_id_at_point(p: Vector2) -> int:
		return 0 if p.x < 0.0 else 1

	func get_neighbors(room_id: int) -> Array[int]:
		if not graph.has(room_id):
			return []
		var out: Array[int] = []
		for rid_variant in graph[room_id]:
			out.append(int(rid_variant))
		return out

	func get_enemy_room_id(enemy: Node) -> int:
		var node := enemy as Node2D
		if node == null:
			return -1
		return room_id_at_point(node.global_position)

	func get_enemy_room_id_by_id(_enemy_id: int) -> int:
		if enemy_ref == null:
			return -1
		return get_enemy_room_id(enemy_ref)

	func get_enemies_in_room(room_id: int) -> Array:
		var out: Array = []
		var tree := get_tree()
		if tree == null:
			return out
		for enemy_variant in tree.get_nodes_in_group("enemies"):
			var enemy_node := enemy_variant as Node
			if enemy_node == null:
				continue
			if "is_dead" in enemy_node and bool(enemy_node.is_dead):
				continue
			var own_room := int(enemy_node.get_meta("room_id", -1))
			if own_room == room_id:
				out.append(enemy_node)
		return out


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
	print("ENEMY LATCH REGISTER/UNREGISTER TEST")
	print("============================================================")

	await _test_enemy_latch_register_unregister()

	_t.summary("ENEMY LATCH REGISTER/UNREGISTER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_latch_register_unregister() -> void:
	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(240.0, 0.0)
	world.add_child(player)

	var nav := FakeNav.new()
	world.add_child(nav)

	var alert_system = ENEMY_ALERT_SYSTEM_SCRIPT.new()
	world.add_child(alert_system)
	alert_system.initialize(nav)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(-96.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(4401, "zombie")
	nav.enemy_ref = enemy
	enemy.set_room_navigation(nav, 0)
	enemy.set_tactical_systems(alert_system, null)

	enemy.debug_force_awareness_state("COMBAT")
	await get_tree().process_frame
	var room_id: int = int(enemy.get_meta("room_id", -1))
	_t.run_test(
		"combat transition registers enemy into room latch",
		room_id >= 0
		and int(alert_system.get_room_latch_count(room_id)) == 1
		and int(alert_system.get_room_effective_level(room_id)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	enemy.runtime_budget_tick(0.05)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"snapshot exposes effective/transient/latch fields",
		snapshot.has("room_alert_effective")
		and snapshot.has("room_alert_transient")
		and snapshot.has("room_latch_count")
		and snapshot.has("latched")
	)
	_t.run_test(
		"snapshot reports latched combat state",
		bool(snapshot.get("latched", false))
		and int(snapshot.get("room_latch_count", 0)) > 0
		and int(snapshot.get("room_alert_effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	enemy.debug_force_awareness_state("ALERT")
	_t.run_test(
		"exit COMBAT unregisters enemy from latch",
		int(alert_system.get_room_latch_count(room_id)) == 0
		and int(alert_system.get_room_effective_level(room_id)) != ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	await get_tree().process_frame

	enemy.debug_force_awareness_state("COMBAT")
	await get_tree().process_frame
	_t.run_test(
		"re-enter COMBAT registers enemy back to latch",
		int(alert_system.get_room_latch_count(room_id)) == 1
		and int(alert_system.get_room_effective_level(room_id)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	enemy.die()
	await get_tree().process_frame
	_t.run_test(
		"death unregisters enemy from latch",
		int(alert_system.get_room_latch_count(room_id)) == 0
	)
	if is_instance_valid(enemy):
		var dead_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
		_t.run_test(
			"snapshot marks latched=false after death",
			not bool(dead_snapshot.get("latched", true))
		)
	else:
		_t.run_test("snapshot marks latched=false after death", true)

	world.queue_free()
	await get_tree().process_frame
