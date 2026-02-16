extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")

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
	print("MAIN MENU STEALTH ENTRY TEST")
	print("============================================================")

	await _test_main_menu_stealth_entry_preflight()

	_t.summary("MAIN MENU STEALTH ENTRY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_main_menu_stealth_entry_preflight() -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as Control
	add_child(menu)
	await get_tree().process_frame

	var stealth_button := menu.get_node_or_null("VBoxContainer/StealthTestButton") as Button
	var status_label := menu.get_node_or_null("VBoxContainer/StatusLabel") as Label

	_t.run_test("main menu stealth entry: button exists", stealth_button != null)
	_t.run_test("main menu stealth entry: status label exists", status_label != null)
	_t.run_test(
		"main menu stealth entry: preflight method exists",
		menu.has_method("open_stealth_test_scene")
	)

	if menu.has_method("open_stealth_test_scene"):
		var preflight_err := int(menu.call("open_stealth_test_scene", false))
		_t.run_test("main menu stealth entry: stealth scene preflight passes", preflight_err == OK)

	menu.queue_free()
	await get_tree().process_frame
