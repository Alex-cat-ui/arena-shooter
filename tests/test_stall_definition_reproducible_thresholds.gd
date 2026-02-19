extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

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
	print("STALL DEFINITION REPRODUCIBLE THRESHOLDS TEST")
	print("============================================================")

	_test_stall_threshold_contract()

	_t.summary("STALL DEFINITION REPRODUCIBLE THRESHOLDS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_stall_threshold_contract() -> void:
	var owner := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	owner.add_child(sprite)
	add_child(owner)

	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	pursuit.call("_reset_stall_monitor")

	var win1 := pursuit.debug_feed_stall_window(7.9, 11.9) as Dictionary
	var win2 := pursuit.debug_feed_stall_window(7.8, 10.0) as Dictionary
	var speed_edge := pursuit.debug_feed_stall_window(8.0, 5.0) as Dictionary
	var progress_edge := pursuit.debug_feed_stall_window(6.0, 12.0) as Dictionary

	_t.run_test("window#1: below thresholds is stall but not hard_stall yet", bool(win1.get("stalled_window", false)) and not bool(win1.get("hard_stall", true)))
	_t.run_test("window#2: second consecutive stall becomes hard_stall", bool(win2.get("stalled_window", false)) and bool(win2.get("hard_stall", false)))
	_t.run_test("speed boundary: speed_avg == 8 px/s is not stall", not bool(speed_edge.get("stalled_window", true)))
	_t.run_test("progress boundary: path_progress == 12 px is not stall", not bool(progress_edge.get("stalled_window", true)))

	owner.queue_free()
