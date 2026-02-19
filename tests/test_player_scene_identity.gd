extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const PRODUCTION_PLAYER_SCENE := preload("res://scenes/entities/player.tscn")

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
	print("PLAYER SCENE IDENTITY TEST")
	print("============================================================")

	await _test_player_scene_identity()

	_t.summary("PLAYER SCENE IDENTITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_player_scene_identity() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var production_player := PRODUCTION_PLAYER_SCENE.instantiate() as CharacterBody2D
	var same_script := false
	if player and production_player:
		same_script = player.get_script() == production_player.get_script()
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D if player else null

	_t.run_test("player identity: stealth room has player node", player != null)
	_t.run_test("player identity: instance is ProductionPlayerClass", same_script)
	_t.run_test("player identity: sprite node exists", sprite != null and sprite.texture != null)
	_t.run_test("player identity: placeholder visual removed", player != null and player.get_node_or_null("PlayerVisual") == null)

	if production_player:
		production_player.free()
	room.queue_free()
	await get_tree().process_frame
