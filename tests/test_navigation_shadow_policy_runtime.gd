extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends Node2D
	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NAVIGATION SHADOW POLICY RUNTIME TEST")
	print("============================================================")

	await _test_shadow_policy_contracts()

	_t.summary("NAVIGATION SHADOW POLICY RUNTIME RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_shadow_policy_contracts() -> void:
	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	add_child(nav)

	var zone := ShadowZone.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120.0, 120.0)
	shape.shape = rect
	zone.add_child(shape)
	add_child(zone)
	await get_tree().process_frame

	var enemy_dark := FakeEnemy.new()
	enemy_dark.flashlight_active = false
	enemy_dark.global_position = Vector2(200.0, 0.0)
	add_child(enemy_dark)

	var enemy_lit := FakeEnemy.new()
	enemy_lit.flashlight_active = true
	add_child(enemy_lit)

	_t.run_test("is_point_in_shadow detects point inside shadow zone", nav.is_point_in_shadow(Vector2.ZERO))
	_t.run_test(
		"shadow split API blocks entry without flashlight when enemy is outside shadow",
		not nav.can_enemy_traverse_shadow_policy_point(enemy_dark, Vector2.ZERO)
	)
	enemy_dark.global_position = Vector2.ZERO
	_t.run_test(
		"shadow split API lets enemy already in shadow keep moving to escape",
		nav.can_enemy_traverse_shadow_policy_point(enemy_dark, Vector2(20.0, 0.0))
	)
	_t.run_test(
		"shadow split API flashlight grants traversal override in shadow",
		nav.can_enemy_traverse_shadow_policy_point(enemy_lit, Vector2.ZERO)
	)
	_t.run_test(
		"shadow split API outside shadow remains traversable",
		nav.can_enemy_traverse_shadow_policy_point(enemy_dark, Vector2(300.0, 300.0))
	)
	_t.run_test(
		"geometry split API returns false when nav map is unavailable",
		not nav.can_enemy_traverse_geometry_point(enemy_dark, Vector2.ZERO)
	)

	nav.queue_free()
	enemy_dark.queue_free()
	enemy_lit.queue_free()
	zone.queue_free()
	await get_tree().process_frame
