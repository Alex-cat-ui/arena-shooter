extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")

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
	print("DEBUG UI LAYOUT NO OVERLAP TEST")
	print("============================================================")

	await _test_labels_no_overlap()
	await _test_labels_width_sufficient()

	_t.summary("DEBUG UI LAYOUT NO OVERLAP RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_labels_no_overlap() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var debug_label := room.get_node_or_null("DebugUI/DebugLabel") as Label
	var hint_label := room.get_node_or_null("DebugUI/HintLabel") as Label

	_t.run_test("layout: DebugLabel exists", debug_label != null)
	_t.run_test("layout: HintLabel exists", hint_label != null)
	if debug_label == null or hint_label == null:
		room.queue_free()
		await get_tree().process_frame
		return

	var debug_bottom := debug_label.offset_bottom
	var hint_top := hint_label.offset_top
	_t.run_test("layout: HintLabel.top >= DebugLabel.bottom (no overlap)",
		hint_top >= debug_bottom)
	_t.run_test("layout: gap between labels >= 4px",
		(hint_top - debug_bottom) >= 4.0)

	room.queue_free()
	await get_tree().process_frame


func _test_labels_width_sufficient() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var debug_label := room.get_node_or_null("DebugUI/DebugLabel") as Label
	var hint_label := room.get_node_or_null("DebugUI/HintLabel") as Label

	if debug_label == null or hint_label == null:
		_t.run_test("width: labels exist", false)
		room.queue_free()
		await get_tree().process_frame
		return

	var debug_width := debug_label.offset_right - debug_label.offset_left
	var hint_width := hint_label.offset_right - hint_label.offset_left
	_t.run_test("width: DebugLabel width >= 800px", debug_width >= 800.0)
	_t.run_test("width: HintLabel width >= 800px", hint_width >= 800.0)

	room.queue_free()
	await get_tree().process_frame
