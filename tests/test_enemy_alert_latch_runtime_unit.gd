extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_ALERT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_alert_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

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


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY ALERT LATCH RUNTIME UNIT TEST")
	print("============================================================")

	await _test_latch_runtime_register_unregister_contract()
	await _test_latch_runtime_migration_hysteresis_contract()

	_t.summary("ENEMY ALERT LATCH RUNTIME UNIT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, id: int) -> Dictionary:
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
	await get_tree().physics_frame

	enemy.initialize(id, "zombie")
	nav.enemy_ref = enemy
	enemy.set_room_navigation(nav, 0)
	enemy.set_tactical_systems(alert_system, null)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("alert_latch_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
		"alert_system": alert_system,
	}


func _test_latch_runtime_register_unregister_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84801)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)
	var alert_system := refs.get("alert_system", null) as Node

	_t.run_test("alert-latch runtime: helper is available", runtime != null)
	if runtime == null or enemy == null or alert_system == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("sync_combat_latch_with_awareness_state", "COMBAT")
	var room_id := int(enemy.get_meta("room_id", -1))
	var snapshot := runtime.call("resolve_room_alert_snapshot") as Dictionary
	_t.run_test(
		"alert-latch runtime: COMBAT sync registers latch in room",
		room_id >= 0
		and int(alert_system.get_room_latch_count(room_id)) == 1
		and bool(runtime.call("is_combat_latched"))
		and int(snapshot.get("effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	_t.run_test(
		"alert-latch runtime: resolve_room_alert_level matches snapshot",
		int(runtime.call("resolve_room_alert_level")) == int(snapshot.get("effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	)

	runtime.call("sync_combat_latch_with_awareness_state", "ALERT")
	snapshot = runtime.call("resolve_room_alert_snapshot") as Dictionary
	_t.run_test(
		"alert-latch runtime: non-COMBAT sync unregisters latch",
		int(alert_system.get_room_latch_count(room_id)) == 0
		and not bool(runtime.call("is_combat_latched"))
		and int(snapshot.get("latch_count", 1)) == 0
	)

	world.queue_free()
	await get_tree().process_frame


func _test_latch_runtime_migration_hysteresis_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84802)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)
	var alert_system := refs.get("alert_system", null) as Node

	_t.run_test("alert-latch runtime: helper exists for migration contract", runtime != null)
	if runtime == null or enemy == null or alert_system == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("sync_combat_latch_with_awareness_state", "COMBAT")
	enemy.global_position = Vector2(96.0, 0.0)
	runtime.call("update_combat_latch_migration", 0.10)
	_t.run_test(
		"alert-latch runtime: migration keeps old room before hysteresis",
		int(alert_system.get_room_latch_count(0)) == 1
		and int(alert_system.get_room_latch_count(1)) == 0
		and int(runtime.call("get_combat_latched_room_id")) == 0
	)

	runtime.call("update_combat_latch_migration", 0.11)
	_t.run_test(
		"alert-latch runtime: migration switches room after hysteresis",
		int(alert_system.get_room_latch_count(0)) == 0
		and int(alert_system.get_room_latch_count(1)) == 1
		and int(runtime.call("get_combat_latched_room_id")) == 1
	)

	world.queue_free()
	await get_tree().process_frame
