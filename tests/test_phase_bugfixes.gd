extends Node

const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")

var _tests_run: int = 0
var _tests_passed: int = 0
var _max_phase: int = 6


class PhaseShadowNavStub:
	extends Node

	var in_shadow: bool = true

	func is_point_in_shadow(_point: Vector2) -> bool:
		return in_shadow


class PhaseShadowOwner:
	extends CharacterBody2D

	var flashlight_active_for_nav: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active_for_nav


class PhaseShadowZoneStub:
	extends Node2D

	func contains_point(_point: Vector2) -> bool:
		return true


func _ready() -> void:
	var max_phase_env := String(OS.get_environment("PHASE_MAX"))
	if max_phase_env != "":
		_max_phase = maxi(int(max_phase_env), 1)
	print("PHASE BUGFIX SUITE (max_phase=%d)" % _max_phase)
	_run_suite()
	print("PHASE BUGFIX RESULTS: %d/%d passed" % [_tests_passed, _tests_run])
	get_tree().quit(0 if _tests_passed == _tests_run else 1)


func _run_suite() -> void:
	if _max_phase >= 1:
		_test_phase_1_noise_anchor()
	if _max_phase >= 2:
		_test_phase_2_confirm_reset()
	if _max_phase >= 3:
		_test_phase_3_stuck_detection()
	if _max_phase >= 4:
		_test_phase_4_flashlight_delay()
	if _max_phase >= 5:
		_test_phase_5_shadow_escape_guard()
	if _max_phase >= 6:
		_test_phase_6_shadow_check_feature()


func _run_test(name: String, ok: bool) -> void:
	_tests_run += 1
	if ok:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)


func _test_phase_1_noise_anchor() -> void:
	var enemy = ENEMY_SCRIPT.new()
	enemy._awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	enemy._awareness.reset()
	var shot_pos := Vector2(300.0, 200.0)
	enemy.on_heard_shot(0, shot_pos)
	_run_test(
		"Phase 1: on_heard_shot sets investigate anchor",
		enemy._investigate_anchor == shot_pos and bool(enemy._investigate_anchor_valid)
	)
	enemy.free()


func _test_phase_2_confirm_reset() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness._confirm_progress = 0.5
	awareness._state = ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS
	awareness.register_noise()
	_run_test(
		"Phase 2: noise->ALERT resets confirm progress",
		awareness.get_state_name() == "ALERT" and is_equal_approx(awareness._confirm_progress, 0.0)
	)

	awareness.reset()
	awareness._state = ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT
	awareness._confirm_progress = 0.8
	var transitions: Array[Dictionary] = []
	awareness._transition_to(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT, "timer", transitions)
	_run_test(
		"Phase 2: COMBAT->ALERT keeps confirm progress",
		awareness.get_state_name() == "ALERT" and is_equal_approx(awareness._confirm_progress, 0.8)
	)


func _test_phase_3_stuck_detection() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2(100.0, 0.0)
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(null, -1)
	var route: Array[Vector2] = [Vector2(500.0, 0.0), Vector2(1000.0, 0.0)]
	patrol._route = route
	patrol._route_index = 0
	patrol._state = ENEMY_PATROL_SYSTEM_SCRIPT.PatrolState.MOVE
	patrol._route_rebuild_timer = 999.0
	patrol._stuck_check_timer = 0.01
	patrol._stuck_check_last_pos = Vector2(100.0, 0.0)
	patrol.update(0.05, Vector2.RIGHT)
	_run_test(
		"Phase 3: stuck timer moves patrol to next waypoint",
		patrol._route_index == 1 and patrol._state == ENEMY_PATROL_SYSTEM_SCRIPT.PatrolState.PAUSE
	)
	owner.free()


func _test_phase_4_flashlight_delay() -> void:
	var enemy = ENEMY_SCRIPT.new()
	enemy.global_position = Vector2.ZERO
	enemy.on_heard_shot(0, Vector2(200.0, 0.0))
	var near_delay := float(enemy._flashlight_activation_delay_timer)
	_run_test(
		"Phase 4: near shot delay in [0.5, 1.2]",
		near_delay >= 0.5 and near_delay <= 1.2
	)

	enemy.on_heard_shot(0, Vector2(600.0, 0.0))
	var far_delay := float(enemy._flashlight_activation_delay_timer)
	_run_test(
		"Phase 4: far shot delay in [1.5, 3.0]",
		far_delay >= 1.5 and far_delay <= 3.0
	)

	enemy._flashlight_activation_delay_timer = 1.0
	var blocked := enemy._flashlight_policy_active_in_alert() == false
	enemy._flashlight_activation_delay_timer = 0.0
	var active := enemy._flashlight_policy_active_in_alert() == true
	_run_test(
		"Phase 4: flashlight policy is blocked until delay expires",
		blocked and active
	)
	enemy.free()


func _test_phase_5_shadow_escape_guard() -> void:
	var owner := PhaseShadowOwner.new()
	owner.global_position = Vector2.ZERO
	var sprite := Sprite2D.new()
	var pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner, sprite, 2.0)
	var nav := PhaseShadowNavStub.new()
	pursuit.nav_system = nav

	owner.set_meta("awareness_state", "CALM")
	var calm_ok := pursuit._is_owner_in_shadow_without_flashlight() == false
	owner.set_meta("awareness_state", "SUSPICIOUS")
	var suspicious_ok := pursuit._is_owner_in_shadow_without_flashlight() == false
	owner.set_meta("awareness_state", "ALERT")
	var alert_ok := pursuit._is_owner_in_shadow_without_flashlight() == true

	_run_test(
		"Phase 5: CALM/SUSPICIOUS do not trigger shadow escape; ALERT can",
		calm_ok and suspicious_ok and alert_ok
	)
	nav.free()
	sprite.free()
	owner.free()


func _test_phase_6_shadow_check_feature() -> void:
	var owner := CharacterBody2D.new()
	owner.global_position = Vector2.ZERO
	var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
	patrol.configure(null, -1)
	patrol._state = ENEMY_PATROL_SYSTEM_SCRIPT.PatrolState.PAUSE
	patrol._shadow_check_active = true
	patrol._shadow_check_dir = Vector2.RIGHT
	patrol._shadow_check_phase = 0.0
	patrol._shadow_check_timer = 1.0
	var decision := patrol.update(0.1, Vector2.RIGHT)
	_run_test(
		"Phase 6: active shadow check returns look_dir and shadow_check flag",
		bool(decision.get("waiting", false))
		and bool(decision.get("shadow_check", false))
		and (decision.get("look_dir", Vector2.ZERO) as Vector2).length_squared() > 0.0001
	)
	owner.free()

	var enemy = ENEMY_SCRIPT.new()
	enemy._awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	enemy._awareness.reset()
	enemy.set_shadow_check_flashlight(true)
	var override_on := enemy.is_flashlight_active_for_navigation()
	enemy.set_shadow_check_flashlight(false)
	var override_off := not enemy.is_flashlight_active_for_navigation()
	_run_test(
		"Phase 6: calm flashlight override controls navigation flashlight",
		override_on and override_off
	)
	enemy.free()

	var nav := NAVIGATION_SERVICE_SCRIPT.new()
	add_child(nav)
	var zone := PhaseShadowZoneStub.new()
	zone.global_position = Vector2(64.0, 0.0)
	zone.add_to_group("shadow_zones")
	add_child(zone)
	var nearest := nav.get_nearest_shadow_zone_direction(Vector2.ZERO, 96.0) as Dictionary
	var found := bool(nearest.get("found", false))
	var direction := nearest.get("direction", Vector2.ZERO) as Vector2
	_run_test(
		"Phase 6: navigation finds nearest shadow zone direction",
		found and direction.dot(Vector2.RIGHT) > 0.9
	)
	zone.queue_free()
	nav.queue_free()
