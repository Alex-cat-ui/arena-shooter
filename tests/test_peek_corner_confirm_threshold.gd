extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
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
	print("PEEK CORNER CONFIRM THRESHOLD TEST")
	print("============================================================")

	await _test_peek_threshold_respects_4_8_vs_5_1_sec()

	_t.summary("PEEK CORNER CONFIRM THRESHOLD RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_peek_threshold_respects_4_8_vs_5_1_sec() -> void:
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
	enemy.initialize(5101, "zombie")
	enemy.set_runtime_budget_scheduler_enabled(true)
	enemy.debug_force_awareness_state("CALM")
	_freeze_enemy_motion(enemy)

	for _i in range(48):
		_lock_enemy_facing(enemy, Vector2.RIGHT)
		enemy.runtime_budget_tick(0.1)
		await get_tree().physics_frame

	var blocker := _spawn_blocker(world, Vector2(160.0, 0.0), Vector2(32.0, 640.0))
	_t.run_test("peek setup: blocker exists", blocker != null)
	for _i in range(6):
		_lock_enemy_facing(enemy, Vector2.RIGHT)
		enemy.runtime_budget_tick(0.1)
		await get_tree().physics_frame

	var interrupted_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"peek 4.8s then break LOS: no COMBAT",
		int(interrupted_snapshot.get("state", -1)) != ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	if blocker and is_instance_valid(blocker):
		blocker.queue_free()
	await get_tree().physics_frame
	if RuntimeState:
		RuntimeState.player_hp = 100
	if not player.is_in_group("player"):
		player.add_to_group("player")
	player.global_position = Vector2(320.0, 0.0)
	enemy.debug_force_awareness_state("CALM")
	_freeze_enemy_motion(enemy)

	var reached_combat := false
	for _i in range(51):
		_lock_enemy_facing(enemy, Vector2.RIGHT)
		enemy.runtime_budget_tick(0.1)
		await get_tree().physics_frame
		var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
		if int(snapshot.get("state", -1)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT:
			reached_combat = true
			break
	_t.run_test("peek 5.1s continuous: reaches COMBAT", reached_combat)

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
	var pursuit_variant: Variant = enemy.get("_pursuit")
	if pursuit_variant == null:
		return
	var pursuit_obj := pursuit_variant as Object
	if pursuit_obj == null:
		return
	if pursuit_obj.has_method("set_speed_tiles"):
		pursuit_obj.call("set_speed_tiles", 0.0)
	_lock_enemy_facing(enemy, Vector2.RIGHT)


func _lock_enemy_facing(enemy: Enemy, face_dir: Vector2) -> void:
	var pursuit_variant: Variant = enemy.get("_pursuit")
	if pursuit_variant == null:
		return
	var pursuit_obj := pursuit_variant as Object
	if pursuit_obj == null:
		return
	var dir := face_dir.normalized()
	if dir.length_squared() <= 0.0001:
		return
	pursuit_obj.set("facing_dir", dir)
	pursuit_obj.set("_target_facing_dir", dir)
