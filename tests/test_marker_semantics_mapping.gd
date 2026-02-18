extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const EnemyAlertLevelsScript = preload("res://src/systems/enemy_alert_levels.gd")
const EnemyAlertMarkerPresenterScript = preload("res://src/systems/enemy_alert_marker_presenter.gd")

const MARKER_DIR := "res://assets/textures/ui/markers"

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
	print("MARKER SEMANTICS MAPPING TEST")
	print("============================================================")

	_test_suspicious_uses_question_glyph()
	_test_alert_uses_exclamation_glyph()
	_test_combat_uses_exclamation_glyph()
	_test_calm_hides_marker()
	_test_transition_suspicious_to_alert()
	_test_transition_suspicious_to_combat()
	_test_missing_texture_hides_marker()

	_t.summary("MARKER SEMANTICS MAPPING RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_suspicious_uses_question_glyph() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	presenter.setup(sprite)
	presenter.set_alert_level(EnemyAlertLevelsScript.SUSPICIOUS)
	var tex := sprite.texture
	_t.run_test("SUSPICIOUS -> question mark texture (enemy_q_suspicious)", tex != null)
	# Verify the texture path contains "enemy_q_" (question mark asset)
	var path := EnemyAlertMarkerPresenterScript.SUSPICIOUS_TEXTURE_PATH as String
	_t.run_test("SUSPICIOUS texture path contains 'enemy_q_'", path.contains("enemy_q_"))
	sprite.queue_free()


func _test_alert_uses_exclamation_glyph() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	presenter.setup(sprite)
	presenter.set_alert_level(EnemyAlertLevelsScript.ALERT)
	var tex := sprite.texture
	_t.run_test("ALERT -> exclamation texture (enemy_excl_alert)", tex != null)
	var path := EnemyAlertMarkerPresenterScript.ALERT_TEXTURE_PATH as String
	_t.run_test("ALERT texture path contains 'enemy_excl_'", path.contains("enemy_excl_"))
	sprite.queue_free()


func _test_combat_uses_exclamation_glyph() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	presenter.setup(sprite)
	presenter.set_alert_level(EnemyAlertLevelsScript.COMBAT)
	var tex := sprite.texture
	_t.run_test("COMBAT -> exclamation texture (enemy_excl_combat)", tex != null)
	var path := EnemyAlertMarkerPresenterScript.COMBAT_TEXTURE_PATH as String
	_t.run_test("COMBAT texture path contains 'enemy_excl_'", path.contains("enemy_excl_"))
	sprite.queue_free()


func _test_calm_hides_marker() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	presenter.setup(sprite)
	presenter.set_alert_level(EnemyAlertLevelsScript.SUSPICIOUS)
	_t.run_test("Marker visible at SUSPICIOUS", sprite.visible == true)
	presenter.set_alert_level(EnemyAlertLevelsScript.CALM)
	_t.run_test("Marker hidden at CALM", sprite.visible == false)
	_t.run_test("Marker texture null at CALM", sprite.texture == null)
	sprite.queue_free()


func _test_transition_suspicious_to_alert() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	presenter.setup(sprite)
	presenter.set_alert_level(EnemyAlertLevelsScript.SUSPICIOUS)
	_t.run_test("? visible at SUSPICIOUS", sprite.visible == true and sprite.texture != null)
	presenter.set_alert_level(EnemyAlertLevelsScript.ALERT)
	_t.run_test("! visible at ALERT after ?", sprite.visible == true and sprite.texture != null)
	sprite.queue_free()


func _test_transition_suspicious_to_combat() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	presenter.setup(sprite)
	presenter.set_alert_level(EnemyAlertLevelsScript.SUSPICIOUS)
	_t.run_test("? visible at SUSPICIOUS (pre-combat)", sprite.visible == true)
	presenter.set_alert_level(EnemyAlertLevelsScript.COMBAT)
	_t.run_test("! visible at COMBAT after ?", sprite.visible == true and sprite.texture != null)
	sprite.queue_free()


func _test_missing_texture_hides_marker() -> void:
	# Test fail-safe: presenter with broken texture path should hide marker
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := EnemyAlertMarkerPresenterScript.new()
	if presenter.has_method("set_warnings_enabled"):
		presenter.set_warnings_enabled(false)
	presenter.setup(sprite)
	# Manually null out a texture to simulate missing asset
	presenter._alert_texture = null
	presenter.set_alert_level(EnemyAlertLevelsScript.SUSPICIOUS)
	presenter.set_alert_level(EnemyAlertLevelsScript.ALERT)
	_t.run_test("Missing ALERT texture -> marker hidden (fail-safe)", sprite.visible == false)
	sprite.queue_free()
