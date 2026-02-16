extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_ALERT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_alert_system.gd")

class FakeRoomNav extends Node:
	var enemy_rooms: Dictionary = {}
	var graph := {
		0: [1],
		1: [0, 2],
		2: [1],
	}

	func room_id_at_point(p: Vector2) -> int:
		if p.x < -40.0:
			return 0
		if p.x < 40.0:
			return 1
		return 2

	func get_neighbors(room_id: int) -> Array[int]:
		if not graph.has(room_id):
			return []
		var out: Array[int] = []
		for rid_variant in graph[room_id]:
			out.append(int(rid_variant))
		return out

	func get_enemy_room_id_by_id(enemy_id: int) -> int:
		return int(enemy_rooms.get(enemy_id, -1))


var embedded_mode: bool = false
var _t := TestHelpers.new()

var _nav: FakeRoomNav = null
var _alert_system = null


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY ALERT SYSTEM TEST")
	print("============================================================")

	await _setup_system()
	await _test_player_shot_propagation()
	await _test_spotted_escalation()
	await _test_enemy_killed_signal()
	_test_decay_chain()
	_test_reset_on_layout_regen()
	_cleanup_system()

	_t.summary("ENEMY ALERT SYSTEM RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _setup_system() -> void:
	_nav = FakeRoomNav.new()
	add_child(_nav)
	_alert_system = ENEMY_ALERT_SYSTEM_SCRIPT.new()
	add_child(_alert_system)
	_alert_system.initialize(_nav)
	_alert_system.reset_all()
	await get_tree().process_frame


func _cleanup_system() -> void:
	if _alert_system:
		_alert_system.queue_free()
	if _nav:
		_nav.queue_free()


func _test_player_shot_propagation() -> void:
	_alert_system.reset_all()
	EventBus.emit_player_shot("pistol", Vector3(-120.0, 0.0, 0.0), Vector3.RIGHT)
	await get_tree().process_frame
	_t.run_test("player_shot: source room -> ALERT",
		_alert_system.get_room_alert_level(0) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	_t.run_test("player_shot: neighbor room -> SUSPICIOUS",
		_alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)
	_t.run_test("player_shot: non-neighbor remains CALM",
		_alert_system.get_room_alert_level(2) == ENEMY_ALERT_LEVELS_SCRIPT.CALM)


func _test_spotted_escalation() -> void:
	_alert_system.reset_all()
	EventBus.emit_enemy_player_spotted(101, Vector3(0.0, 0.0, 0.0))
	await get_tree().process_frame
	_t.run_test("spotted: source room -> COMBAT",
		_alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	_t.run_test("spotted: both neighbors -> ALERT",
		_alert_system.get_room_alert_level(0) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT
		and _alert_system.get_room_alert_level(2) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT)


func _test_enemy_killed_signal() -> void:
	_alert_system.reset_all()
	_nav.enemy_rooms[501] = 2
	EventBus.emit_enemy_killed(501, "zombie")
	await get_tree().process_frame
	_t.run_test("enemy_killed: room -> SUSPICIOUS",
		_alert_system.get_room_alert_level(2) == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)


func _test_decay_chain() -> void:
	_alert_system.reset_all()
	_alert_system._on_enemy_player_spotted(777, Vector3(0.0, 0.0, 0.0))
	_t.run_test("Decay setup starts in COMBAT",
		_alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)

	_advance_alert_system(ENEMY_ALERT_LEVELS_SCRIPT.COMBAT_TTL_SEC + 0.05)
	_t.run_test("COMBAT decays to ALERT",
		_alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT)

	_advance_alert_system(ENEMY_ALERT_LEVELS_SCRIPT.ALERT_TTL_SEC + 0.05)
	_t.run_test("ALERT decays to SUSPICIOUS",
		_alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)

	_advance_alert_system(ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS_TTL_SEC + 0.05)
	_t.run_test("SUSPICIOUS decays to CALM",
		_alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.CALM)


func _test_reset_on_layout_regen() -> void:
	_alert_system._on_player_shot("pistol", Vector3(-120.0, 0.0, 0.0), Vector3.RIGHT)
	_t.run_test("Non-calm state exists before reset",
		_alert_system.get_room_alert_level(0) != ENEMY_ALERT_LEVELS_SCRIPT.CALM)
	_alert_system.reset_all()
	_t.run_test("reset_all clears state",
		_alert_system.get_room_alert_level(0) == ENEMY_ALERT_LEVELS_SCRIPT.CALM
		and _alert_system.get_room_alert_level(1) == ENEMY_ALERT_LEVELS_SCRIPT.CALM
		and _alert_system.get_room_alert_level(2) == ENEMY_ALERT_LEVELS_SCRIPT.CALM)


func _advance_alert_system(total_sec: float) -> void:
	var t := 0.0
	while t < total_sec:
		var step := minf(0.1, total_sec - t)
		_alert_system.update(step)
		t += step
