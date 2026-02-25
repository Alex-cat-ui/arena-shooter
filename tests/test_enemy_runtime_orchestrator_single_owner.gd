extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

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
	print("ENEMY RUNTIME ORCHESTRATOR SINGLE OWNER TEST")
	print("============================================================")

	_test_runtime_budget_tick_orchestrator_only()

	_t.summary("ENEMY RUNTIME ORCHESTRATOR SINGLE OWNER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_runtime_budget_tick_orchestrator_only() -> void:
	var script_text := _read_text("res://src/entities/enemy.gd")
	_t.run_test("orchestrator: enemy script text loads", script_text != "")
	if script_text == "":
		return

	var tick_block := _extract_function_block(script_text, "runtime_budget_tick")
	_t.run_test("orchestrator: runtime_budget_tick function exists", tick_block != "")
	if tick_block == "":
		return

	var pipeline_block := _extract_function_block(script_text, "_runtime_budget_tick_execute_pipeline")
	_t.run_test("orchestrator: pipeline helper exists", pipeline_block != "")

	var non_empty_body_lines := _count_non_empty_body_lines(tick_block)
	_t.run_test("orchestrator: runtime_budget_tick body is compact", non_empty_body_lines <= 8)
	_t.run_test(
		"orchestrator: runtime_budget_tick delegates to pipeline helper",
		tick_block.find("_runtime_budget_tick_execute_pipeline(") >= 0
	)
	_t.run_test(
		"orchestrator: runtime_budget_tick keeps top-level guard",
		tick_block.find("if not _perception or not _pursuit:") >= 0
	)
	_t.run_test(
		"orchestrator: runtime_budget_tick keeps watchdog begin/end ownership",
		tick_block.find("AIWatchdog.begin_ai_tick()") >= 0
			and pipeline_block.find("AIWatchdog.end_ai_tick()") >= 0
	)

	var forbidden_tokens := [
		"can_see_player(",
		"process_confirm(",
		"execute_intent(",
		"_evaluate_fire_contact(",
		"_update_first_shot_delay_runtime(",
		"_try_fire_at_player(",
		"_record_runtime_tick_debug_state(",
	]
	_t.run_test(
		"orchestrator: runtime_budget_tick has no direct domain internals",
		_contains_none(tick_block, forbidden_tokens)
	)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _extract_function_block(text: String, function_name: String) -> String:
	var marker := "func %s(" % function_name
	var start := text.find(marker)
	if start < 0:
		return ""
	var next_func := text.find("\nfunc ", start + marker.length())
	if next_func < 0:
		return text.substr(start)
	return text.substr(start, next_func - start)


func _count_non_empty_body_lines(function_block: String) -> int:
	if function_block == "":
		return 0
	var lines := function_block.split("\n")
	var count := 0
	for i in range(lines.size()):
		if i == 0:
			continue
		var line := String(lines[i]).strip_edges()
		if line == "":
			continue
		count += 1
	return count


func _contains_none(text: String, needles: Array) -> bool:
	for needle_variant in needles:
		var needle := String(needle_variant)
		if text.find(needle) >= 0:
			return false
	return true
