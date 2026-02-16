extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_TRANSITION_CONTROLLER_SCRIPT := preload("res://src/levels/level_transition_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _regen_calls: int = 0


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = [
		{"rects": [Rect2(-100.0, -100.0, 200.0, 200.0)]},
	]
	var _void_ids: Array = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("LEVEL TRANSITION CONTROLLER TEST")
	print("============================================================")

	await _test_unlock_block_and_mission_cycle()

	_t.summary("LEVEL TRANSITION CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_unlock_block_and_mission_cycle() -> void:
	var controller = LEVEL_TRANSITION_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.level = Node2D.new()
	ctx.player = CharacterBody2D.new()
	ctx.layout = FakeLayout.new()
	ctx.mission_cycle_pos = 0
	ctx.level.add_child(ctx.player)
	add_child(ctx.level)

	controller.setup_north_transition_trigger(ctx)
	_t.run_test("transition trigger setup enables rect", ctx.north_transition_enabled and ctx.north_transition_rect != Rect2())

	ctx.player.position = ctx.north_transition_rect.get_center()
	_regen_calls = 0
	var before := controller.current_mission_index(ctx)

	var enemy := Node2D.new()
	enemy.add_to_group("enemies")
	ctx.level.add_child(enemy)
	ctx.north_transition_cooldown = 0.0
	controller.check_north_transition(ctx, Callable(self, "_on_transition_regen_callback"))
	var blocked := controller.current_mission_index(ctx) == before
	_t.run_test("transition blocked while alive enemies exist", blocked and _regen_calls == 0)

	enemy.queue_free()
	await get_tree().process_frame
	ctx.north_transition_cooldown = 0.0
	controller.check_north_transition(ctx, Callable(self, "_on_transition_regen_callback"))
	var after := controller.current_mission_index(ctx)
	_t.run_test("transition unlocked when alive_scene_enemies_count == 0", controller.is_north_transition_unlocked(ctx))
	_t.run_test("mission cycle advances on unlocked transition", after != before)
	_t.run_test("regenerate callback fired once on transition", _regen_calls == 1)

	ctx.level.queue_free()
	await get_tree().process_frame


func _on_transition_regen_callback() -> void:
	_regen_calls += 1
