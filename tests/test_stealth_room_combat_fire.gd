extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const COMBAT_FIRST_ATTACK_AND_TELEGRAPH_MIN_FRAMES := 76 # 1.2s + 0.10s @ 60 FPS with frame tolerance
const COMBAT_FIRST_ATTACK_AND_TELEGRAPH_MAX_FRAMES := 150 # 2.0s + 0.18s + queue/frame tolerance

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _shot_count: int = 0
var _shotgun_shot_count: int = 0
var _player_damaged_count: int = 0
var _first_fire_frame: int = -1
var _damage_amounts: Array[int] = []
var _saved_ai_fire_profile_mode: String = "auto"


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
	if GameConfig:
		_saved_ai_fire_profile_mode = String(GameConfig.ai_fire_profile_mode)
		GameConfig.ai_fire_profile_mode = "production"
	if EventBus and EventBus.has_signal("enemy_shot") and not EventBus.enemy_shot.is_connected(_on_enemy_shot):
		EventBus.enemy_shot.connect(_on_enemy_shot)
	if EventBus and EventBus.has_signal("player_damaged") and not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)

	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("stealth fire: controller exists", controller != null)
	_t.run_test("stealth fire: player exists", player != null)
	_t.run_test("stealth fire: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		if GameConfig:
			GameConfig.ai_fire_profile_mode = _saved_ai_fire_profile_mode
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

	# Keep player in the same room and within reliable LOS/fire range for 3-zone scene.
	player.global_position = enemy.global_position + Vector2(260.0, 0.0)
	player.velocity = Vector2.ZERO
	await get_tree().physics_frame

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")
	var armed_delay_sec := float(enemy.get("_combat_first_attack_delay_timer"))
	_t.run_test(
		"stealth fire: first-attack delay is not armed before first valid firing solution",
		not bool(enemy.get("_combat_first_shot_delay_armed")) and armed_delay_sec <= 0.0
	)

	# Face enemy toward player for deterministic first contact.
	var pursuit = enemy.get("_pursuit")
	if pursuit:
		pursuit.set("facing_dir", Vector2.RIGHT)
		pursuit.set("_target_facing_dir", Vector2.RIGHT)

	var fired_too_early := false
	for i in range(300):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _first_fire_frame < 0 and float(enemy.get("_shot_cooldown")) > 0.0:
			_first_fire_frame = i + 1
		if _first_fire_frame > 0 and _first_fire_frame < COMBAT_FIRST_ATTACK_AND_TELEGRAPH_MIN_FRAMES:
			fired_too_early = true
		if _shot_count > 0 and _player_damaged_count > 0:
			break

	_t.run_test("stealth fire: enemy fires at least once in COMBAT", _shot_count >= 1)
	_t.run_test("stealth fire: production weapon event is shotgun", _shotgun_shot_count >= 1)
	var player_hp_dropped := RuntimeState != null and RuntimeState.player_hp < 100
	_t.run_test(
		"stealth fire: combat system applies enemy shot damage to player",
		_player_damaged_count >= 1 and player_hp_dropped
	)
	_t.run_test(
		"stealth fire: enemy can fire in COMBAT without extra test toggles",
		_shot_count >= 1
	)
	_t.run_test(
		"stealth fire: first combat shot honors first-shot timer + telegraph window",
		not fired_too_early
		and _first_fire_frame >= COMBAT_FIRST_ATTACK_AND_TELEGRAPH_MIN_FRAMES
		and _first_fire_frame <= COMBAT_FIRST_ATTACK_AND_TELEGRAPH_MAX_FRAMES
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
	if GameConfig:
		GameConfig.ai_fire_profile_mode = _saved_ai_fire_profile_mode
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
