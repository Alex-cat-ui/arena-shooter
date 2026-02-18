extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")
const COMBAT_FIRST_ATTACK_DELAY_MIN_FRAMES := 72 # 1.2s @ 60 FPS
const COMBAT_FIRST_ATTACK_DELAY_MAX_FRAMES := 132 # 2.2s @ 60 FPS (queue/frame tolerance)

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _shot_count: int = 0
var _shotgun_shot_count: int = 0
var _player_damaged_count: int = 0
var _first_fire_frame: int = -1
var _damage_amounts: Array[int] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("STEALTH ROOM COMBAT FIRE TEST")
	print("============================================================")

	await _test_player_loadout_and_enemy_fire()

	_t.summary("STEALTH ROOM COMBAT FIRE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_player_loadout_and_enemy_fire() -> void:
	_shot_count = 0
	_shotgun_shot_count = 0
	_player_damaged_count = 0
	_first_fire_frame = -1
	_damage_amounts.clear()
	if EventBus and EventBus.has_signal("enemy_shot") and not EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.connect(_on_enemy_shot)
	if EventBus and EventBus.has_signal("player_damaged") and not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)

	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("stealth fire: controller exists", controller != null)
	_t.run_test("stealth fire: player exists", player != null)
	_t.run_test("stealth fire: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	_t.run_test("stealth fire: player ability system wired", "ability_system" in player and player.ability_system != null)
	_t.run_test("stealth fire: player projectile system wired", "projectile_system" in player and player.projectile_system != null)
	if controller.has_method("debug_get_combat_pipeline_summary"):
		var summary := controller.call("debug_get_combat_pipeline_summary") as Dictionary
		_t.run_test("stealth fire: combat system exists", bool(summary.get("combat_system_exists", false)))
		_t.run_test("stealth fire: ability wired to combat", bool(summary.get("ability_combat_wired", false)))
	else:
		_t.run_test("stealth fire: combat pipeline summary method available", false)

	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0

	# Place player 500px to the left of enemy spawn (260,-40) — within HOLD_RANGE (390-610px).
	# Clear LOS at y=-40: no obstacles between x=-240 and x=260 in the stealth test room.
	player.global_position = Vector2(-240.0, -40.0)
	player.velocity = Vector2.ZERO
	await get_tree().physics_frame

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")
	if enemy.has_method("disable_suspicion_test_profile"):
		enemy.disable_suspicion_test_profile()
	var armed_delay_sec := float(enemy.get("_combat_first_attack_delay_timer"))
	_t.run_test(
		"stealth fire: fallback profile is disabled before firing",
		not bool(enemy.get("_suspicion_test_profile_enabled"))
	)
	_t.run_test(
		"stealth fire: combat first-attack delay armed in 1.2-2.0s range",
		armed_delay_sec >= 1.2 and armed_delay_sec <= 2.0
	)

	# Face enemy toward player (player is to the LEFT at x=-240, enemy at x=260).
	# 180° FOV requires facing within 90° of player direction to detect.
	var pursuit = enemy.get("_pursuit")
	if pursuit:
		pursuit.set("facing_dir", Vector2.LEFT)
		pursuit.set("_target_facing_dir", Vector2.LEFT)

	# Disable squad slot positioning so pure distance logic applies.
	# At 500px (hold_range_min=390, hold_range_max=610) enemy picks HOLD_RANGE and fires.
	var old_squad_system = enemy.squad_system
	enemy.squad_system = null

	var fired_too_early := false
	for i in range(300):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _first_fire_frame < 0 and float(enemy.get("_shot_cooldown")) > 0.0:
			_first_fire_frame = i + 1
		if _first_fire_frame > 0 and _first_fire_frame < COMBAT_FIRST_ATTACK_DELAY_MIN_FRAMES:
			fired_too_early = true
		if _shot_count > 0 and _player_damaged_count > 0:
			break

	enemy.squad_system = old_squad_system

	_t.run_test("stealth fire: enemy fires at least once in COMBAT", _shot_count >= 1)
	_t.run_test("stealth fire: production weapon event is shotgun", _shotgun_shot_count >= 1)
	var player_hp_dropped := RuntimeState != null and RuntimeState.player_hp < 100
	_t.run_test(
		"stealth fire: combat system applies enemy shot damage to player",
		_player_damaged_count >= 1 and player_hp_dropped
	)
	_t.run_test(
		"stealth fire: enemy can fire without fallback profile",
		_shot_count >= 1 and not bool(enemy.get("_suspicion_test_profile_enabled"))
	)
	_t.run_test(
		"stealth fire: first combat shot occurs after min delay and within expected window",
		not fired_too_early
		and _first_fire_frame >= COMBAT_FIRST_ATTACK_DELAY_MIN_FRAMES
		and _first_fire_frame <= COMBAT_FIRST_ATTACK_DELAY_MAX_FRAMES
	)
	var damage_all_one := _damage_amounts.size() >= 1
	for amount in _damage_amounts:
		damage_all_one = damage_all_one and amount == 1
	_t.run_test(
		"stealth fire: each enemy damage tick is exactly 1 hp",
		damage_all_one
	)

	room.queue_free()
	await get_tree().process_frame
	if EventBus and EventBus.has_signal("enemy_shot") and EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.disconnect(_on_enemy_shot)
	if EventBus and EventBus.has_signal("player_damaged") and EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)


func _on_enemy_shot(_enemy_id: int, weapon: String, _position: Vector3, _direction: Vector3) -> void:
	_shot_count += 1
	if weapon == "shotgun":
		_shotgun_shot_count += 1


func _on_player_damaged(amount: int, _new_hp: int, _source: String) -> void:
	_player_damaged_count += 1
	_damage_amounts.append(amount)


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
