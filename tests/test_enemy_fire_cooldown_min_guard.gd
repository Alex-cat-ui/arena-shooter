extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _saved_weapon_stats: Dictionary = {}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY FIRE COOLDOWN MIN GUARD TEST")
	print("============================================================")

	await _test_enemy_fire_cooldown_min_guard()

	_t.summary("ENEMY FIRE COOLDOWN MIN GUARD RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_fire_cooldown_min_guard() -> void:
	if GameConfig:
		_saved_weapon_stats = (GameConfig.weapon_stats as Dictionary).duplicate(true)

	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(7605, "zombie")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("fire cooldown guard: runtime helper exists", runtime != null)
	if runtime == null:
		if GameConfig:
			GameConfig.weapon_stats = _saved_weapon_stats.duplicate(true)
		world.queue_free()
		await get_tree().process_frame
		return

	if GameConfig:
		var stats := (GameConfig.weapon_stats as Dictionary).duplicate(true)
		var shotgun := (stats.get("shotgun", {}) as Dictionary).duplicate(true)
		shotgun["cooldown_sec"] = 0.05
		stats["shotgun"] = shotgun
		GameConfig.weapon_stats = stats
	var guarded_low := float(runtime.call("shotgun_cooldown_sec"))

	if GameConfig:
		var stats_high := (GameConfig.weapon_stats as Dictionary).duplicate(true)
		var shotgun_high := (stats_high.get("shotgun", {}) as Dictionary).duplicate(true)
		shotgun_high["cooldown_sec"] = 0.6
		stats_high["shotgun"] = shotgun_high
		GameConfig.weapon_stats = stats_high
	var guarded_high := float(runtime.call("shotgun_cooldown_sec"))

	_t.run_test("cooldown guard clamps too-low cooldown to >= 0.25s", guarded_low >= 0.25 and guarded_low <= 0.2501)
	_t.run_test("cooldown guard keeps larger weapon cooldown unchanged", is_equal_approx(guarded_high, 0.6))

	if GameConfig:
		GameConfig.weapon_stats = _saved_weapon_stats.duplicate(true)
	world.queue_free()
	await get_tree().process_frame
