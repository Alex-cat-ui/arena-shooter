extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _saved_mode: String = "auto"
var _saved_profiles: Dictionary = {}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("TELEGRAPH PROFILE PRODUCTION VS DEBUG TEST")
	print("============================================================")

	await _test_telegraph_profile_production_vs_debug()

	_t.summary("TELEGRAPH PROFILE PRODUCTION VS DEBUG RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_telegraph_profile_production_vs_debug() -> void:
	if GameConfig:
		_saved_mode = String(GameConfig.ai_fire_profile_mode)
		_saved_profiles = (GameConfig.ai_fire_profiles as Dictionary).duplicate(true)

	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(7603, "zombie")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("telegraph profile: runtime helper exists", runtime != null)
	if runtime == null:
		if GameConfig:
			GameConfig.ai_fire_profile_mode = _saved_mode
			GameConfig.ai_fire_profiles = _saved_profiles.duplicate(true)
		world.queue_free()
		await get_tree().process_frame
		return

	if GameConfig:
		GameConfig.ai_fire_profile_mode = "production"
	var production_roll := float(runtime.call("roll_telegraph_duration_sec"))

	if GameConfig:
		GameConfig.ai_fire_profile_mode = "debug_test"
	var debug_roll := float(runtime.call("roll_telegraph_duration_sec"))

	if GameConfig:
		GameConfig.ai_fire_profile_mode = "auto"
	var auto_roll := float(runtime.call("roll_telegraph_duration_sec"))
	var auto_mode := String(runtime.call("resolve_ai_fire_profile_mode"))

	_t.run_test("production profile telegraph is 0.10..0.18s", production_roll >= 0.10 and production_roll <= 0.18)
	_t.run_test("debug_test profile telegraph is 0.35..0.60s", debug_roll >= 0.35 and debug_roll <= 0.60)
	_t.run_test("auto resolves to debug_test inside tests", auto_mode == "debug_test")
	_t.run_test("auto profile telegraph uses debug range in tests", auto_roll >= 0.35 and auto_roll <= 0.60)

	if GameConfig:
		GameConfig.ai_fire_profile_mode = _saved_mode
		GameConfig.ai_fire_profiles = _saved_profiles.duplicate(true)
	world.queue_free()
	await get_tree().process_frame
