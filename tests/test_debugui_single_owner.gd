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
	print("DEBUG UI SINGLE OWNER TEST")
	print("============================================================")

	await _test_debugui_single_owner()

	_t.summary("DEBUG UI SINGLE OWNER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_debugui_single_owner() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var debugui_count := _count_nodes_named(room, "DebugUI")
	var debug_label_count := _count_nodes_named(room, "DebugLabel")
	var hint_label_count := _count_nodes_named(room, "HintLabel")

	_t.run_test("debugui: count_nodes(DebugUI) == 1", debugui_count == 1)
	_t.run_test("debugui: single stats label exists", debug_label_count == 1)
	_t.run_test("debugui: single hint label exists", hint_label_count == 1)

	room.queue_free()
	await get_tree().process_frame


func _count_nodes_named(node: Node, target_name: String) -> int:
	if node == null:
		return 0
	var count := 1 if node.name == target_name else 0
	for child_variant in node.get_children():
		var child := child_variant as Node
		count += _count_nodes_named(child, target_name)
	return count
