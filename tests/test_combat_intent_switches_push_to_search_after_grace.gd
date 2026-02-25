extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
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
	print("COMBAT NO-LOS -> ALERT SEARCH TEST")
	print("============================================================")

	await _test_combat_no_los_drops_to_alert_search()

	_t.summary("COMBAT NO-LOS -> ALERT SEARCH RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_no_los_drops_to_alert_search() -> void:
	if RuntimeState:
		RuntimeState.player_hp = 100
	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(320.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(0.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(4901, "zombie")
	enemy.set_runtime_budget_scheduler_enabled(true)
	enemy.debug_force_awareness_state("COMBAT")
	_freeze_enemy_motion(enemy)
	enemy.runtime_budget_tick(0.1)

	var remembered := player.global_position
	var blocker := _spawn_blocker(world, Vector2(230.0, 0.0), Vector2(32.0, 640.0))
	_t.run_test("setup: blocker exists", blocker != null)
	player.global_position = Vector2(900.0, 200.0)
	if RuntimeState:
		RuntimeState.player_hp = 0
	var had_player_group := player.is_in_group("player")
	if had_player_group:
		player.remove_from_group("player")
	await get_tree().physics_frame

	enemy.runtime_budget_tick(0.75)
	var combat_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var combat_target := (enemy.get_current_intent() as Dictionary).get("target", Vector2.ZERO) as Vector2
	_t.run_test("during COMBAT no-LOS: state remains COMBAT", int(combat_snapshot.get("state", -1)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	_t.run_test("during COMBAT no-LOS: target_is_last_seen=false", not bool(combat_snapshot.get("target_is_last_seen", true)))
	_t.run_test("during COMBAT no-LOS: target not remembered last_seen", combat_target.distance_to(remembered) > 48.0)

	var combat_ttl := ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	var steps := maxi(int(ceil((combat_ttl + 0.5) / 0.1)), 1)
	for _i in range(steps):
		_lock_enemy_facing(enemy, Vector2.RIGHT)
		enemy.runtime_budget_tick(0.1)
		await get_tree().physics_frame

	var after_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var after_intent := enemy.get_current_intent() as Dictionary
	var after_type := int(after_intent.get("type", -1))
	var after_target := after_intent.get("target", Vector2.ZERO) as Vector2
	_t.run_test("after timer: state degraded to ALERT", int(after_snapshot.get("state", -1)) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	var settled_snapshot := after_snapshot
	var settled_intent := after_intent
	var settled_type := after_type
	var settled_target := after_target
	for _j in range(12):
		if bool(settled_snapshot.get("target_is_last_seen", false)) and (
			settled_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
			or settled_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		):
			break
		_lock_enemy_facing(enemy, Vector2.RIGHT)
		enemy.runtime_budget_tick(0.1)
		await get_tree().physics_frame
		settled_snapshot = enemy.get_debug_detection_snapshot() as Dictionary
		settled_intent = enemy.get_current_intent() as Dictionary
		settled_type = int(settled_intent.get("type", -1))
		settled_target = settled_intent.get("target", Vector2.ZERO) as Vector2
	_t.run_test("after timer: target_is_last_seen=true in ALERT", bool(settled_snapshot.get("target_is_last_seen", false)))
	_t.run_test(
		"after timer: ALERT intent becomes INVESTIGATE/SEARCH around remembered point",
		(
			settled_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
			or settled_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		)
		and settled_target.distance_to(remembered) <= 24.0
	)

	world.queue_free()
	await get_tree().process_frame


func _spawn_blocker(parent: Node2D, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	return body


func _freeze_enemy_motion(enemy: Enemy) -> void:
	enemy.debug_set_pursuit_speed_tiles_for_test(0.0)
	_lock_enemy_facing(enemy, Vector2.RIGHT)


func _lock_enemy_facing(enemy: Enemy, face_dir: Vector2) -> void:
	enemy.debug_set_pursuit_facing_for_test(face_dir)
