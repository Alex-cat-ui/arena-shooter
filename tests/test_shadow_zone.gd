extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const SHADOW_ZONE_SCRIPT := preload("res://src/systems/stealth/shadow_zone.gd")

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
	print("SHADOW ZONE TEST")
	print("============================================================")

	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0

	await _test_enter_exit_changes_visibility_multiplier()
	_test_runtime_reset_restores_default_visibility()

	_t.summary("SHADOW ZONE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enter_exit_changes_visibility_multiplier() -> void:
	var zone := SHADOW_ZONE_SCRIPT.new()
	zone.shadow_multiplier = 0.35
	add_child(zone)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)

	zone.call("_on_body_entered", player)
	_t.run_test(
		"player entering shadow zone updates RuntimeState multiplier",
		RuntimeState and is_equal_approx(RuntimeState.player_visibility_mul, 0.35)
	)

	zone.call("_on_body_exited", player)
	_t.run_test(
		"player exiting shadow zone restores RuntimeState multiplier",
		RuntimeState and is_equal_approx(RuntimeState.player_visibility_mul, 1.0)
	)

	player.queue_free()
	zone.queue_free()
	await get_tree().process_frame


func _test_runtime_reset_restores_default_visibility() -> void:
	if RuntimeState:
		RuntimeState.player_visibility_mul = 0.2
		RuntimeState.reset()
	_t.run_test(
		"RuntimeState.reset restores player visibility multiplier",
		RuntimeState and is_equal_approx(RuntimeState.player_visibility_mul, 1.0)
	)
