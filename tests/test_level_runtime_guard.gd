extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_RUNTIME_GUARD_SCRIPT := preload("res://src/levels/level_runtime_guard.gd")

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
	print("LEVEL RUNTIME GUARD TEST")
	print("============================================================")

	_test_enforce_on_start()
	_test_enforce_on_layout_reset()

	_t.summary("LEVEL RUNTIME GUARD RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enforce_on_start() -> void:
	RuntimeState.reset()
	RuntimeState.is_frozen = true

	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.debug_overlay_visible = true

	var guard = LEVEL_RUNTIME_GUARD_SCRIPT.new()
	guard.enforce_on_start(ctx)

	_t.run_test("enforce_on_start keeps runtime state intact", RuntimeState.is_frozen == true)
	_t.run_test("enforce_on_start keeps context intact", ctx.debug_overlay_visible == true)


func _test_enforce_on_layout_reset() -> void:
	RuntimeState.is_level_active = true

	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.north_transition_enabled = true

	var guard = LEVEL_RUNTIME_GUARD_SCRIPT.new()
	guard.enforce_on_layout_reset(ctx)

	_t.run_test("enforce_on_layout_reset keeps runtime state intact", RuntimeState.is_level_active == true)
	_t.run_test("enforce_on_layout_reset keeps context intact", ctx.north_transition_enabled == true)
