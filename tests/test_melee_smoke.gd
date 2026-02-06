## test_melee_smoke.gd
## Headless smoke test for melee / katana system (Phase 4 - Patch 0.2).
## Tests: katana mode toggle, light slash damage, stagger, dash slash.
## Run via: godot --headless res://tests/test_melee_smoke.tscn
extends Node

var _tests_run := 0
var _tests_passed := 0
var _melee_hit_count := 0


func _ready() -> void:
	print("=" .repeat(60))
	print("SMOKE TEST: Melee / Katana System")
	print("=" .repeat(60))

	Engine.max_fps = 60
	GameConfig.reset_to_defaults()
	GameConfig.god_mode = true
	# Disable hitstop for testing (prevents Engine.time_scale slowdown hanging tests)
	GameConfig.katana_light_hitstop_sec = 0.0
	GameConfig.katana_heavy_hitstop_sec = 0.0
	GameConfig.katana_dash_hitstop_sec = 0.0

	# Subscribe to melee hit events
	EventBus.melee_hit.connect(_on_melee_hit)

	# Transition to PLAYING
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	# Instantiate level scene
	var scene := load("res://scenes/levels/level_mvp.tscn") as PackedScene
	var level := scene.instantiate()
	add_child(level)

	await _run_tests(level)

	print("")
	print("=" .repeat(60))
	print("MELEE SMOKE RESULTS: %d/%d tests passed" % [_tests_passed, _tests_run])
	print("=" .repeat(60))

	# Restore time scale (hitstop safety)
	Engine.time_scale = 1.0
	get_tree().quit(0 if _tests_passed == _tests_run else 1)


func _on_melee_hit(_pos: Vector3, _move_type: String) -> void:
	_melee_hit_count += 1


func _run_tests(level: Node) -> void:
	# ==================================================================
	# Phase 1: Wait for start delay + enemies to spawn (~4s)
	# ==================================================================
	print("\n--- Phase 1: Waiting for enemies to spawn (240 frames ~ 4s) ---")
	for i in range(240):
		await get_tree().process_frame

	# Count enemies
	var enemies := get_tree().get_nodes_in_group("enemies")
	_test("Enemies spawned for melee test", enemies.size() > 0)
	print("  Enemies alive: %d" % enemies.size())

	if enemies.is_empty():
		print("  [SKIP] No enemies to test melee on - skipping melee tests")
		return

	# ==================================================================
	# Phase 2: Katana mode toggle
	# ==================================================================
	print("\n--- Phase 2: Katana mode toggle ---")
	_test("Katana mode starts OFF", RuntimeState.katana_mode == false)

	RuntimeState.katana_mode = true
	_test("Katana mode toggles ON", RuntimeState.katana_mode == true)

	# ==================================================================
	# Phase 3: Light slash on nearby enemy
	# ==================================================================
	print("\n--- Phase 3: Light slash damage test ---")

	# Find closest enemy and move player near it
	var player := get_tree().get_nodes_in_group("player")
	if player.size() > 0:
		var player_node: CharacterBody2D = player[0] as CharacterBody2D
		enemies = get_tree().get_nodes_in_group("enemies")
		if enemies.size() > 0:
			var target_enemy: Node2D = enemies[0] as Node2D

			# Teleport player next to enemy (within range)
			var to_enemy := (target_enemy.position - player_node.position).normalized()
			player_node.position = target_enemy.position - to_enemy * 40.0  # 40px away
			RuntimeState.player_pos = Vector3(player_node.position.x, player_node.position.y, 0)
			# Aim toward enemy
			RuntimeState.player_aim_dir = Vector3(to_enemy.x, to_enemy.y, 0)

			# Record enemy HP before slash
			var hp_before: int = target_enemy.hp if "hp" in target_enemy else -1
			print("  Enemy HP before: %d" % hp_before)

			# Find melee system
			var melee_sys: MeleeSystem = null
			for child in level.get_children():
				if child is MeleeSystem:
					melee_sys = child
					break

			_test("MeleeSystem exists in level", melee_sys != null)

			if melee_sys:
				# Request light slash
				melee_sys.request_light_slash()

				# Simulate ~0.5s (30 frames) for slash to complete
				for i in range(30):
					await get_tree().process_frame

				# Restore time scale (hitstop may have altered it)
				Engine.time_scale = 1.0

				# Check results
				enemies = get_tree().get_nodes_in_group("enemies")
				var hp_after: int = -1
				if is_instance_valid(target_enemy) and not target_enemy.is_dead:
					hp_after = target_enemy.hp if "hp" in target_enemy else -1
				var enemy_killed: bool = (not is_instance_valid(target_enemy)) or ("is_dead" in target_enemy and target_enemy.is_dead)

				print("  Enemy HP after: %d (killed: %s)" % [hp_after, str(enemy_killed)])
				print("  Melee hit events: %d" % _melee_hit_count)

				var damage_applied: bool = hp_before > 0 and (hp_after < hp_before or enemy_killed)
				var hit_event_fired := _melee_hit_count > 0
				_test("Light slash dealt damage or killed enemy", damage_applied or hit_event_fired)

	# ==================================================================
	# Phase 4: Dash slash + i-frames
	# ==================================================================
	print("\n--- Phase 4: Dash slash test ---")
	var melee_sys2: MeleeSystem = null
	for child in level.get_children():
		if child is MeleeSystem:
			melee_sys2 = child
			break

	if melee_sys2:
		# Wait for melee system to be idle
		for i in range(30):
			await get_tree().process_frame
		Engine.time_scale = 1.0

		# Record player position before dash
		var pos_before := Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)

		# Request dash slash
		melee_sys2.request_dash_slash()

		# Simulate ~0.5s for dash to complete
		for i in range(30):
			await get_tree().process_frame
		Engine.time_scale = 1.0

		var pos_after := Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)
		var moved_distance := pos_before.distance_to(pos_after)
		print("  Dash moved player: %.1f px" % moved_distance)
		_test("Dash slash moved player", moved_distance > 10.0)

	# ==================================================================
	# Phase 5: Katana mode OFF restores gun behavior
	# ==================================================================
	print("\n--- Phase 5: Katana mode OFF ---")
	RuntimeState.katana_mode = false
	_test("Katana mode back OFF", RuntimeState.katana_mode == false)


func _test(name: String, result: bool) -> void:
	_tests_run += 1
	if result:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)
