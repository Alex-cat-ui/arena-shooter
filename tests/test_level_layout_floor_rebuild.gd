extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_LAYOUT_CONTROLLER_SCRIPT := preload("res://src/levels/level_layout_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeLayout:
	extends RefCounted
	var valid: bool = true
	var rooms: Array = []
	var _void_ids: Array = []


class FakeInvalidLayout:
	extends RefCounted
	var valid: bool = false


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("LEVEL LAYOUT FLOOR REBUILD TEST")
	print("============================================================")

	await _test_floor_rebuild_for_valid_layout()
	await _test_floor_fallback_for_invalid_layout()

	_t.summary("LEVEL LAYOUT FLOOR REBUILD RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_floor_rebuild_for_valid_layout() -> void:
	var controller = LEVEL_LAYOUT_CONTROLLER_SCRIPT.new()
	var ctx = _make_floor_ctx()
	var layout = FakeLayout.new()
	layout.rooms = [
		{
			"rects": [Rect2(-64.0, -64.0, 128.0, 128.0)],
			"is_corridor": false,
		}
	]
	ctx.layout = layout

	controller.rebuild_walkable_floor(ctx)
	var floor_children = ctx.walkable_floor.get_child_count() if ctx.walkable_floor else 0
	_t.run_test("valid layout hides base floor sprite", ctx.floor_sprite.visible == false)
	_t.run_test("valid layout builds walkable floor patches", floor_children >= 2)

	ctx.level.queue_free()
	await get_tree().process_frame


func _test_floor_fallback_for_invalid_layout() -> void:
	var controller = LEVEL_LAYOUT_CONTROLLER_SCRIPT.new()
	var ctx = _make_floor_ctx()
	ctx.layout = FakeInvalidLayout.new()

	controller.rebuild_walkable_floor(ctx)
	_t.run_test("invalid layout keeps base floor sprite visible", ctx.floor_sprite.visible == true)

	ctx.level.queue_free()
	await get_tree().process_frame


func _make_floor_ctx():
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var level = Node2D.new()
	add_child(level)

	ctx.level = level
	ctx.floor_root = Node2D.new()
	ctx.floor_sprite = Sprite2D.new()
	ctx.floor_sprite.texture = _make_test_texture()
	ctx.floor_root.add_child(ctx.floor_sprite)
	level.add_child(ctx.floor_root)

	ctx.arena_min = Vector2(-200.0, -200.0)
	ctx.arena_max = Vector2(200.0, 200.0)
	return ctx


func _make_test_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(img)
