extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")

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
	print("RING VISIBILITY POLICY TEST")
	print("============================================================")

	await _test_ring_visibility_policy()

	_t.summary("RING VISIBILITY POLICY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_ring_visibility_policy() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(7711, "zombie")
	enemy.enable_suspicion_test_profile(STEALTH_TEST_CONFIG_SCRIPT.suspicion_profile())
	await get_tree().process_frame

	var ring := enemy.get_node_or_null("SuspicionRing") as CanvasItem
	_t.run_test("ring policy: presenter exists", ring != null)
	if ring == null:
		world.queue_free()
		await get_tree().process_frame
		return

	enemy.set_meta("awareness_state", "CALM")
	await get_tree().process_frame
	_t.run_test("test_ring_visibility_policy: CALM => ring hidden", not ring.visible)

	enemy.set_meta("awareness_state", "ALERT")
	await get_tree().process_frame
	_t.run_test("test_ring_visibility_policy: ALERT => ring visible", ring.visible)

	enemy.set_meta("awareness_state", "COMBAT")
	await get_tree().process_frame
	_t.run_test("test_ring_visibility_policy: COMBAT => ring visible", ring.visible)

	world.queue_free()
	await get_tree().process_frame
