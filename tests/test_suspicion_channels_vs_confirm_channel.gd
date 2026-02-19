extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()

const CONFIG := {
	"confirm_time_to_engage": 5.0,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SUSPICION CHANNELS VS CONFIRM CHANNEL TEST")
	print("============================================================")

	_test_silhouette_increases_suspicion_without_confirm()
	_test_flashlight_glimpse_increases_suspicion_without_confirm()
	_test_valid_contact_is_only_confirm_channel()

	_t.summary("SUSPICION CHANNELS VS CONFIRM CHANNEL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_silhouette_increases_suspicion_without_confirm() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	for _i in range(10):
		awareness.process_confirm(0.1, true, true, false, CONFIG)
	var snapshot := awareness.get_ui_snapshot() as Dictionary
	var confirm01 := float(snapshot.get("confirm01", -1.0))
	var suspicion01 := float(snapshot.get("suspicion01", -1.0))
	_t.run_test("silhouette channel raises suspicion", suspicion01 > 0.0)
	_t.run_test("silhouette channel does not raise confirm", is_zero_approx(confirm01))


func _test_flashlight_glimpse_increases_suspicion_without_confirm() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	for _i in range(6):
		awareness.process_confirm(0.1, false, false, true, CONFIG)
	var snapshot := awareness.get_ui_snapshot() as Dictionary
	var confirm01 := float(snapshot.get("confirm01", -1.0))
	var suspicion01 := float(snapshot.get("suspicion01", -1.0))
	_t.run_test("flashlight glimpse can raise suspicion", suspicion01 > 0.0)
	_t.run_test("flashlight glimpse without LOS does not raise confirm", is_zero_approx(confirm01))


func _test_valid_contact_is_only_confirm_channel() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	for _i in range(10):
		awareness.process_confirm(0.1, true, true, true, CONFIG)
	var snapshot := awareness.get_ui_snapshot() as Dictionary
	var confirm01 := float(snapshot.get("confirm01", 0.0))
	_t.run_test("valid_contact (LOS && flashlight_hit in shadow) raises confirm", confirm01 > 0.0)
