extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const THREE_ZONE_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

const STRESS_FRAMES := 900
const POST_GAME_OVER_DRAIN_FRAMES := 180
const EVENT_QUEUE_HARD_CAP := 2048
const ALERT_COMBAT_TRANSITION_LOOPS := 200
const CONFIRM_CONFIG := {
	"confirm_time_to_engage": 5.0,
	"confirm_decay_rate": 0.10,
	"confirm_grace_window": 0.50,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
}

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
	print("3-ZONE COMBAT TRANSITION STRESS TEST")
	print("============================================================")

	_test_alert_to_combat_transition_loop_no_freeze()
	await _test_mass_combat_transition_no_hard_freeze()

	_t.summary("3-ZONE COMBAT TRANSITION STRESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func run_gate_report() -> Dictionary:
	var suite_result := await run_suite()
	var ok := bool(suite_result.get("ok", false))
	return {
		"gate_status": "PASS" if ok else "FAIL",
		"gate_reason": "ok" if ok else "stress_assertion_failed",
		"suite_run": int(suite_result.get("run", 0)),
		"suite_passed": int(suite_result.get("passed", 0)),
	}


func _test_alert_to_combat_transition_loop_no_freeze() -> void:
	var all_iterations_ok := true
	var reached_combat_count := 0
	for _iter in range(ALERT_COMBAT_TRANSITION_LOOPS):
		var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		awareness.reset()
		var reached_combat := false
		for _i in range(100):
			var has_los := true
			var transitions := awareness.process_confirm(0.1, has_los, false, false, CONFIRM_CONFIG)
			for tr_variant in transitions:
				var tr := tr_variant as Dictionary
				if String(tr.get("to_state", "")) == "COMBAT":
					reached_combat = true
					break
			if reached_combat:
				break
		if reached_combat:
			reached_combat_count += 1
		else:
			all_iterations_ok = false
			break

	_t.run_test(
		"stress: ALERT->COMBAT transition loop has no freeze in 200 iterations",
		all_iterations_ok and reached_combat_count == ALERT_COMBAT_TRANSITION_LOOPS
	)


func _test_mass_combat_transition_no_hard_freeze() -> void:
	if EventBus and EventBus.has_method("debug_reset_queue_for_tests"):
		EventBus.call("debug_reset_queue_for_tests")
	if EventBus and EventBus.has_signal("enemy_shot") and not EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.connect(_on_enemy_shot)
	_enemy_shot_count = 0

	var level := THREE_ZONE_SCENE.instantiate() as Node2D
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemies := _members_in_group_under("enemies", level)
	_t.run_test("stress: 3zone level controller exists", controller != null)
	_t.run_test("stress: player exists", player != null)
	_t.run_test("stress: all 6 enemies exist", enemies.size() == 6)
	if controller == null or player == null or enemies.size() != 6:
		_disconnect_event_bus_hooks()
		level.queue_free()
		await get_tree().process_frame
		return

	var prev_god_mode := false
	if GameConfig:
		prev_god_mode = bool(GameConfig.god_mode)
		GameConfig.god_mode = false
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 3
		RuntimeState.player_visibility_mul = 1.0

	player.global_position = Vector2(520.0, 240.0)
	player.velocity = Vector2.ZERO
	var center := player.global_position
	for i in range(enemies.size()):
		var enemy := enemies[i] as Enemy
		if enemy == null:
			continue
		var angle := (TAU * float(i)) / float(maxi(enemies.size(), 1))
		enemy.global_position = center + Vector2.RIGHT.rotated(angle) * 180.0
		enemy.set_meta("room_id", 0)
		var face_dir := (center - enemy.global_position).normalized()
		enemy.debug_set_pursuit_facing_for_test(face_dir)
		if enemy.has_method("debug_force_awareness_state"):
			enemy.call("debug_force_awareness_state", "COMBAT")

	var reached_game_over := false
	var max_pending_queue := 0
	var frame_of_game_over := -1
	for frame in range(STRESS_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
		if EventBus and EventBus.has_method("debug_get_pending_event_count"):
			var pending := int(EventBus.call("debug_get_pending_event_count"))
			max_pending_queue = maxi(max_pending_queue, pending)
		if StateManager and StateManager.current_state == GameState.State.GAME_OVER:
			reached_game_over = true
			frame_of_game_over = frame
			break

	var drained_after_game_over := false
	if reached_game_over:
		for _i in range(POST_GAME_OVER_DRAIN_FRAMES):
			await get_tree().process_frame
			var pending_after := int(EventBus.call("debug_get_pending_event_count")) if EventBus and EventBus.has_method("debug_get_pending_event_count") else 0
			if pending_after == 0:
				drained_after_game_over = true
				break

	_t.run_test("stress: enemies still fire after mass COMBAT transition", _enemy_shot_count > 0)
	_t.run_test("stress: transition reaches GAME_OVER without stall", reached_game_over)
	_t.run_test(
		"stress: GAME_OVER reached within frame budget",
		frame_of_game_over >= 0 and frame_of_game_over < STRESS_FRAMES
	)
	_t.run_test(
		"stress: EventBus pending queue remains below hard cap",
		max_pending_queue < EVENT_QUEUE_HARD_CAP
	)
	_t.run_test("stress: EventBus queue drains after GAME_OVER", drained_after_game_over)

	if GameConfig:
		GameConfig.god_mode = prev_god_mode
	_disconnect_event_bus_hooks()
	if EventBus and EventBus.has_method("debug_reset_queue_for_tests"):
		EventBus.call("debug_reset_queue_for_tests")
	level.queue_free()
	await get_tree().process_frame


func _disconnect_event_bus_hooks() -> void:
	if EventBus and EventBus.has_signal("enemy_shot") and EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)


func _on_enemy_shot(_enemy_id: int, _weapon_type: String, _position: Vector3, _direction: Vector3) -> void:
	_enemy_shot_count += 1


func _members_in_group_under(group_name: String, ancestor: Node) -> Array:
	var out: Array = []
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			out.append(member)
	return out
