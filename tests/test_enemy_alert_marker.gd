extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const MARKER_DIR := "res://assets/textures/ui/markers"
const MARKER_FILES := [
	"enemy_q_suspicious.png",
	"enemy_excl_alert.png",
	"enemy_excl_combat.png",
]
const ENEMY_SCENE_PATH := "res://scenes/entities/enemy.tscn"

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
	print("ENEMY ALERT MARKER TEST")
	print("============================================================")

	_test_marker_files_exist()
	_test_marker_dimensions()
	_test_enemy_scene_marker_node()

	_t.summary("ENEMY ALERT MARKER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_marker_files_exist() -> void:
	for file_name in MARKER_FILES:
		var path := "%s/%s" % [MARKER_DIR, file_name]
		_t.run_test("%s exists" % file_name, FileAccess.file_exists(path))


func _test_marker_dimensions() -> void:
	for file_name in MARKER_FILES:
		var path := "%s/%s" % [MARKER_DIR, file_name]
		var texture := load(path) as Texture2D
		var ok := texture != null and texture.get_width() == 16 and texture.get_height() == 16
		_t.run_test("%s is 16x16" % file_name, ok)


func _test_enemy_scene_marker_node() -> void:
	var enemy_scene := load(ENEMY_SCENE_PATH) as PackedScene
	_t.run_test("Enemy scene loads", enemy_scene != null)
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate()
	_t.run_test("Enemy scene instantiates", enemy != null)
	if enemy == null:
		return

	var marker := enemy.get_node_or_null("AlertMarker") as Sprite2D
	_t.run_test("AlertMarker exists", marker != null)
	if marker == null:
		enemy.queue_free()
		return

	var body_sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
	_t.run_test("AlertMarker default hidden", marker.visible == false)
	_t.run_test("AlertMarker position is (0, -26)", marker.position.is_equal_approx(Vector2(0.0, -26.0)))
	_t.run_test("AlertMarker filter is nearest", marker.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	_t.run_test("AlertMarker z-index above enemy sprite", body_sprite != null and marker.z_index > body_sprite.z_index)

	enemy.queue_free()
