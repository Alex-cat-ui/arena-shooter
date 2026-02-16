extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_CAMERA_CONTROLLER_SCRIPT := preload("res://src/levels/level_camera_controller.gd")

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
	print("LEVEL CAMERA CONTROLLER TEST")
	print("============================================================")

	await _test_follow_lerp_and_rotation_invariant()
	await _test_reset_follow()

	_t.summary("LEVEL CAMERA CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_follow_lerp_and_rotation_invariant() -> void:
	var controller = LEVEL_CAMERA_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.player = CharacterBody2D.new()
	ctx.camera = Camera2D.new()
	ctx.player.position = Vector2(0, 0)
	ctx.player.velocity = Vector2(240, 0)
	ctx.camera.rotation = 0.5
	ctx.camera_follow_initialized = false

	add_child(ctx.player)
	add_child(ctx.camera)

	controller.update_follow(ctx, 0.1)
	ctx.player.position = Vector2(200, 0)
	controller.update_follow(ctx, 0.1)

	_t.run_test("camera follow moves toward player target", ctx.camera.position.x > 0.0)
	_t.run_test("camera rotation invariant remains zero", is_equal_approx(ctx.camera.rotation, 0.0))

	ctx.player.queue_free()
	ctx.camera.queue_free()
	await get_tree().process_frame


func _test_reset_follow() -> void:
	var controller = LEVEL_CAMERA_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.player = CharacterBody2D.new()
	ctx.camera = Camera2D.new()
	ctx.player.position = Vector2(123.0, -45.0)
	ctx.camera.position = Vector2.ZERO
	ctx.camera.rotation = 1.2
	add_child(ctx.player)
	add_child(ctx.camera)

	controller.reset_follow(ctx)

	_t.run_test("reset_follow places camera at player position", ctx.camera.position == ctx.player.position)
	_t.run_test("reset_follow enables camera", ctx.camera.enabled)
	_t.run_test("reset_follow keeps rotation invariant", is_equal_approx(ctx.camera.rotation, 0.0))

	ctx.player.queue_free()
	ctx.camera.queue_free()
	await get_tree().process_frame
