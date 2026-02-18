extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _enemy_shot_count: int = 0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("EVENT BUS BACKPRESSURE TEST")
	print("============================================================")

	if EventBus == null:
		_t.run_test("event bus singleton exists", false)
		_t.summary("EVENT BUS BACKPRESSURE RESULTS")
		return {
			"ok": _t.quit_code() == 0,
			"run": _t.tests_run,
			"passed": _t.tests_passed,
		}

	_t.run_test("event bus singleton exists", true)
	_t.run_test(
		"event bus exposes queue debug API for tests",
		EventBus.has_method("debug_reset_queue_for_tests") and EventBus.has_method("debug_get_pending_event_count")
	)
	if not EventBus.has_method("debug_reset_queue_for_tests") or not EventBus.has_method("debug_get_pending_event_count"):
		_t.summary("EVENT BUS BACKPRESSURE RESULTS")
		return {
			"ok": _t.quit_code() == 0,
			"run": _t.tests_run,
			"passed": _t.tests_passed,
		}
	EventBus.call("debug_reset_queue_for_tests")

	if EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)
	EventBus.enemy_shot.connect(_on_enemy_shot)

	const BURST_EVENTS := 900
	for i in range(BURST_EVENTS):
		EventBus.emit_enemy_shot(i, "shotgun", Vector3.ZERO, Vector3.RIGHT)

	var delivered_on_first_dispatch := 0
	var pending_after_first_dispatch := BURST_EVENTS
	for _i in range(8):
		await get_tree().process_frame
		var pending_now := int(EventBus.call("debug_get_pending_event_count"))
		if _enemy_shot_count > 0:
			delivered_on_first_dispatch = _enemy_shot_count
			pending_after_first_dispatch = pending_now
			break
	_t.run_test(
		"event bus dispatches first burst chunk only",
		delivered_on_first_dispatch > 0 and delivered_on_first_dispatch < BURST_EVENTS
	)
	_t.run_test(
		"event bus keeps overflow queued for later frames",
		pending_after_first_dispatch > 0 and pending_after_first_dispatch < BURST_EVENTS
	)

	var drained := false
	for _frame in range(16):
		await get_tree().process_frame
		var pending_now := int(EventBus.call("debug_get_pending_event_count"))
		if pending_now == 0 and _enemy_shot_count == BURST_EVENTS:
			drained = true
			break
	_t.run_test("event bus drains overflow across subsequent frames", drained)

	if EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)
	if EventBus.has_method("debug_reset_queue_for_tests"):
		EventBus.call("debug_reset_queue_for_tests")

	_t.summary("EVENT BUS BACKPRESSURE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _on_enemy_shot(_enemy_id: int, _weapon_type: String, _position: Vector3, _direction: Vector3) -> void:
	_enemy_shot_count += 1
