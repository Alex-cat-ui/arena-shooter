extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_EVENTS_CONTROLLER_SCRIPT := preload("res://src/levels/level_events_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakePlayer:
	extends CharacterBody2D
	var damage_calls: int = 0
	var total_damage: int = 0
	func take_damage(amount: int) -> void:
		damage_calls += 1
		total_damage += amount


class FakeCameraShake:
	extends "res://src/systems/camera_shake.gd"
	var shake_calls: int = 0
	var last_amp: float = 0.0
	var last_dur: float = 0.0
	func shake(amp: float, dur: float) -> void:
		shake_calls += 1
		last_amp = amp
		last_dur = dur


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("LEVEL EVENTS CONTROLLER TEST")
	print("============================================================")

	await _test_bind_unbind_and_single_reaction()

	_t.summary("LEVEL EVENTS CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_bind_unbind_and_single_reaction() -> void:
	var controller = LEVEL_EVENTS_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.player = FakePlayer.new()
	ctx.camera_shake = FakeCameraShake.new()

	add_child(ctx.player)
	add_child(ctx.camera_shake)

	controller.bind(ctx)
	controller.bind(ctx)

	EventBus.emit_player_damaged(7, 93, "unit")
	EventBus.emit_rocket_exploded(Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame

	var fake_player := ctx.player as FakePlayer
	var fake_shake := ctx.camera_shake as FakeCameraShake
	_t.run_test("player_damaged handled exactly once after duplicate bind", fake_player.damage_calls == 1 and fake_player.total_damage == 7)
	_t.run_test("rocket_exploded handled via camera shake", fake_shake.shake_calls == 1)

	controller.unbind()
	EventBus.emit_player_damaged(5, 88, "after_unbind")
	await get_tree().process_frame
	await get_tree().process_frame
	_t.run_test("unbind prevents duplicate future reactions", fake_player.damage_calls == 1)

	ctx.player.queue_free()
	ctx.camera_shake.queue_free()
	await get_tree().process_frame
