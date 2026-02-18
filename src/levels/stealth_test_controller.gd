## stealth_test_controller.gd
## Isolated vertical-slice controller for one-room stealth testing.
extends Node

const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ENEMY_ALERT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_alert_system.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")
const STEALTH_TEST_LAYOUT_SCRIPT := preload("res://src/levels/stealth_test_layout.gd")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")
const COMBAT_SYSTEM_SCRIPT := preload("res://src/systems/combat_system.gd")
const PROJECTILE_SYSTEM_SCRIPT := preload("res://src/systems/projectile_system.gd")
const ABILITY_SYSTEM_SCRIPT := preload("res://src/systems/ability_system.gd")
const STEALTH_RUNTIME_MARKER := "STEALTH_TEST_ACTIVE v5765ce6"

@export var room_rect: Rect2 = Rect2(-560.0, -320.0, 1120.0, 640.0)
@export var default_player_spawn: Vector2 = Vector2(-320.0, 90.0)
@export var default_enemy_spawn: Vector2 = Vector2(260.0, -40.0)
@export var debug_overlay_enabled: bool = true

var _layout_stub = null
var _enemy: Enemy = null
var _enemy_id_counter: int = 9300
var _test_config: Dictionary = {}
var _suspicion_profile: Dictionary = {}

var _navigation_service: Node = null
var _enemy_alert_system: Node = null
var _enemy_squad_system: Node = null
var _enemy_aggro_coordinator: Node = null
var _combat_system: Node = null
var _projectile_system: Node = null
var _ability_system: Node = null
var _projectiles_container: Node2D = null

var _navigation_service_from_autoload: bool = false
var _enemy_alert_from_autoload: bool = false
var _enemy_squad_from_autoload: bool = false
var _enemy_aggro_from_autoload: bool = false

var _debug_refresh_accum: float = 0.0

@onready var _room_root := get_parent() as Node2D
@onready var _entities := _room_root.get_node("Entities") as Node2D
@onready var _player := _room_root.get_node("Entities/Player") as CharacterBody2D
@onready var _player_spawn := _room_root.get_node_or_null("PlayerSpawn") as Node2D
@onready var _enemy_spawn := _room_root.get_node_or_null("EnemySpawn") as Node2D
@onready var _camera := _room_root.get_node_or_null("Camera2D") as Camera2D
@onready var _debug_layer := _room_root.get_node_or_null("DebugUI") as CanvasLayer
@onready var _debug_label := _room_root.get_node_or_null("DebugUI/DebugLabel") as Label
@onready var _hint_label := _room_root.get_node_or_null("DebugUI/HintLabel") as Label
@onready var _shadow_zone := _room_root.get_node_or_null("ShadowZone")


func _ready() -> void:
	print("STEALTH_TEST_BOOTSTRAP_v20260216")
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0

	_test_config = STEALTH_TEST_CONFIG_SCRIPT.values()
	_suspicion_profile = STEALTH_TEST_CONFIG_SCRIPT.suspicion_profile()
	_layout_stub = STEALTH_TEST_LAYOUT_SCRIPT.new(room_rect)
	_ensure_player_ready()
	_ensure_combat_pipeline_ready()
	_apply_scene_tuning()
	await _bind_tactical_systems()
	_spawn_or_reset_enemy()
	_update_hint_text()
	_set_overlay_visible(debug_overlay_enabled)
	_refresh_debug_label(true)


func _process(delta: float) -> void:
	if _combat_system and is_instance_valid(_combat_system) and _combat_system.has_method("update"):
		_combat_system.update(delta)

	if _camera and _player and is_instance_valid(_player):
		_camera.global_position = _player.global_position

	_debug_refresh_accum += maxf(delta, 0.0)
	if _debug_refresh_accum >= 0.1:
		_debug_refresh_accum = 0.0
		_refresh_debug_label(false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if not key.pressed or key.echo:
		return

	match key.physical_keycode:
		KEY_1:
			_force_enemy_calm()
		KEY_2:
			_force_enemy_alert()
		KEY_3:
			_force_enemy_combat()
		KEY_TAB:
			_set_overlay_visible(not debug_overlay_enabled)
		KEY_R:
			_reset_positions()
		_:
			return
	_refresh_debug_label(true)


func debug_get_system_summary() -> Dictionary:
	return {
		"navigation_service_from_autoload": _navigation_service_from_autoload,
		"enemy_alert_from_autoload": _enemy_alert_from_autoload,
		"enemy_squad_from_autoload": _enemy_squad_from_autoload,
		"enemy_aggro_from_autoload": _enemy_aggro_from_autoload,
		"local_navigation_service_exists": get_node_or_null("NavigationService") != null,
		"local_enemy_alert_exists": get_node_or_null("EnemyAlertSystem") != null,
		"local_enemy_squad_exists": get_node_or_null("EnemySquadSystem") != null,
		"local_enemy_aggro_exists": get_node_or_null("EnemyAggroCoordinator") != null,
	}


func debug_get_test_config() -> Dictionary:
	return _test_config.duplicate(true)


func debug_get_combat_pipeline_summary() -> Dictionary:
	var player_has_projectile := false
	var player_has_ability := false
	if _player:
		player_has_projectile = "projectile_system" in _player and _player.projectile_system != null
		player_has_ability = "ability_system" in _player and _player.ability_system != null
	var ability_has_projectile := false
	var ability_has_combat := false
	if _ability_system:
		ability_has_projectile = "projectile_system" in _ability_system and _ability_system.projectile_system != null
		ability_has_combat = "combat_system" in _ability_system and _ability_system.combat_system != null
	return {
		"combat_system_exists": _combat_system != null and is_instance_valid(_combat_system),
		"projectile_system_exists": _projectile_system != null and is_instance_valid(_projectile_system),
		"ability_system_exists": _ability_system != null and is_instance_valid(_ability_system),
		"player_projectile_wired": player_has_projectile,
		"player_ability_wired": player_has_ability,
		"ability_projectile_wired": ability_has_projectile,
		"ability_combat_wired": ability_has_combat,
	}


func _bind_tactical_systems() -> void:
	var nav_service := _resolve_system("NavigationService", NAVIGATION_SERVICE_SCRIPT)
	_navigation_service = nav_service.node
	_navigation_service_from_autoload = nav_service.from_autoload

	var alert := _resolve_system("EnemyAlertSystem", ENEMY_ALERT_SYSTEM_SCRIPT)
	_enemy_alert_system = alert.node
	_enemy_alert_from_autoload = alert.from_autoload

	var squad := _resolve_system("EnemySquadSystem", ENEMY_SQUAD_SYSTEM_SCRIPT)
	_enemy_squad_system = squad.node
	_enemy_squad_from_autoload = squad.from_autoload

	var aggro := _resolve_system("EnemyAggroCoordinator", ENEMY_AGGRO_COORDINATOR_SCRIPT)
	_enemy_aggro_coordinator = aggro.node
	_enemy_aggro_from_autoload = aggro.from_autoload

	if _navigation_service and _navigation_service.has_method("initialize"):
		_navigation_service.initialize(_layout_stub, _entities, _player)
	# Build navmesh only after current tree setup finishes.
	# Running build_from_layout during _ready can trigger parent-busy add_child errors.
	if _navigation_service and _navigation_service.has_method("build_from_layout"):
		_navigation_service.call_deferred("build_from_layout", _layout_stub, _room_root)
		await get_tree().process_frame
		await get_tree().physics_frame

	if _enemy_alert_system:
		if _enemy_alert_system.has_method("initialize"):
			_enemy_alert_system.initialize(_navigation_service)
		elif _enemy_alert_system.has_method("bind_room_nav"):
			_enemy_alert_system.bind_room_nav(_navigation_service)
			if _enemy_alert_system.has_method("reset_all"):
				_enemy_alert_system.reset_all()

	if _enemy_squad_system and _enemy_squad_system.has_method("initialize"):
		_enemy_squad_system.initialize(_player, _navigation_service, _entities)

	if _navigation_service and _navigation_service.has_method("bind_tactical_systems"):
		_navigation_service.bind_tactical_systems(_enemy_alert_system, _enemy_squad_system)

	if _enemy_aggro_coordinator:
		if _enemy_aggro_coordinator.has_method("initialize"):
			_enemy_aggro_coordinator.initialize(_entities, _navigation_service, _player)
		elif _enemy_aggro_coordinator.has_method("bind_context"):
			_enemy_aggro_coordinator.bind_context(_entities, _navigation_service, _player)


func _resolve_system(node_name: String, script: Script) -> Dictionary:
	var root := get_tree().root
	var autoload_node := root.get_node_or_null("/root/%s" % node_name)
	if autoload_node and _is_node_usable(autoload_node, node_name):
		return {"node": autoload_node, "from_autoload": true}

	var local_node := get_node_or_null(node_name)
	if local_node == null:
		local_node = script.new()
		local_node.name = node_name
		add_child(local_node)
	return {"node": local_node, "from_autoload": false}


func _is_node_usable(node: Node, node_name: String) -> bool:
	match node_name:
		"NavigationService":
			return node.has_method("initialize") and node.has_method("bind_tactical_systems")
		"EnemyAlertSystem":
			return node.has_method("initialize") or node.has_method("bind_room_nav")
		"EnemySquadSystem":
			return node.has_method("initialize")
		"EnemyAggroCoordinator":
			return node.has_method("initialize") or node.has_method("bind_context")
		_:
			return false


func _apply_scene_tuning() -> void:
	if _shadow_zone:
		_shadow_zone.set("shadow_multiplier", _shadow_multiplier_default())


func _flashlight_angle_deg() -> float:
	return float(_test_config.get("flashlight_angle_deg", 55.0))


func _flashlight_distance_px() -> float:
	return float(_test_config.get("flashlight_distance_px", 1000.0))


func _flashlight_bonus() -> float:
	return float(_test_config.get("flashlight_bonus", 2.5))


func _shadow_multiplier_default() -> float:
	return float(_test_config.get("shadow_multiplier_default", 0.35))


func _resolve_sandbox_door_system() -> Node:
	if _room_root:
		var room_door_system := _room_root.get_node_or_null("LayoutDoorSystem")
		if room_door_system:
			return room_door_system
	var local_door_system := get_node_or_null("LayoutDoorSystem")
	if local_door_system:
		return local_door_system
	return null


func _spawn_or_reset_enemy() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		_enemy = ENEMY_SCENE.instantiate() as Enemy
		if _enemy == null:
			push_error("[StealthTestController] Failed to instantiate enemy scene")
			return
		_entities.add_child(_enemy)

	_enemy.global_position = _enemy_spawn_position()
	_enemy.velocity = Vector2.ZERO
	_enemy.initialize(_enemy_id_counter, "zombie")
	# Ensure nav/tactical wiring is ready immediately for same-tick COMBAT/latch tests.
	if _navigation_service and _navigation_service.has_method("_configure_enemy"):
		_navigation_service.call("_configure_enemy", _enemy)
	if _enemy.has_method("configure_stealth_test_flashlight"):
		_enemy.configure_stealth_test_flashlight(_flashlight_angle_deg(), _flashlight_distance_px(), _flashlight_bonus())
	if _enemy.has_method("enable_suspicion_test_profile"):
		_enemy.enable_suspicion_test_profile(_suspicion_profile)
	if _enemy.has_method("set_flashlight_hit_for_detection"):
		_enemy.set_flashlight_hit_for_detection(false)
	if _enemy.has_method("set_stealth_test_debug_logging"):
		_enemy.set_stealth_test_debug_logging(true)
	var door_system := _resolve_sandbox_door_system()
	if door_system:
		_enemy.set_meta("door_system", door_system)
	_enemy.set_runtime_budget_scheduler_enabled(false)
	if _enemy.has_method("set_physics_process"):
		_enemy.set_physics_process(true)


func _ensure_player_ready() -> void:
	if not _player:
		return
	_player.global_position = _player_spawn_position()
	_player.velocity = Vector2.ZERO
	if not _player.is_in_group("player"):
		_player.add_to_group("player")
	if (_player.collision_mask & 1) == 0:
		_player.collision_mask |= 1
	if RuntimeState:
		RuntimeState.player_pos = Vector3(_player.global_position.x, _player.global_position.y, 0.0)


func _ensure_combat_pipeline_ready() -> void:
	if not _room_root or not _player:
		return
	if _projectiles_container == null or not is_instance_valid(_projectiles_container):
		_projectiles_container = _room_root.get_node_or_null("Projectiles") as Node2D
		if _projectiles_container == null:
			_projectiles_container = Node2D.new()
			_projectiles_container.name = "Projectiles"
			_room_root.add_child(_projectiles_container)
	if _combat_system == null or not is_instance_valid(_combat_system):
		var combat_node := _room_root.get_node_or_null("CombatSystem")
		if combat_node == null:
			combat_node = COMBAT_SYSTEM_SCRIPT.new()
			combat_node.name = "CombatSystem"
			_room_root.add_child(combat_node)
		_combat_system = combat_node
	if _projectile_system == null or not is_instance_valid(_projectile_system):
		var projectile_node := _room_root.get_node_or_null("ProjectileSystem")
		if projectile_node == null:
			projectile_node = _room_root.get_node_or_null("StealthTestProjectileSystem")
		if projectile_node == null:
			projectile_node = PROJECTILE_SYSTEM_SCRIPT.new()
			projectile_node.name = "ProjectileSystem"
			_room_root.add_child(projectile_node)
		elif projectile_node.name != "ProjectileSystem":
			projectile_node.name = "ProjectileSystem"
		_projectile_system = projectile_node
	if _ability_system == null or not is_instance_valid(_ability_system):
		var ability_node := _room_root.get_node_or_null("AbilitySystem")
		if ability_node == null:
			ability_node = _room_root.get_node_or_null("StealthTestAbilitySystem")
		if ability_node == null:
			ability_node = ABILITY_SYSTEM_SCRIPT.new()
			ability_node.name = "AbilitySystem"
			_room_root.add_child(ability_node)
		elif ability_node.name != "AbilitySystem":
			ability_node.name = "AbilitySystem"
		_ability_system = ability_node
	if _combat_system and "player_node" in _combat_system:
		_combat_system.player_node = _player
	if _projectile_system and "projectiles_container" in _projectile_system:
		_projectile_system.projectiles_container = _projectiles_container
	if _ability_system and "projectile_system" in _ability_system:
		_ability_system.projectile_system = _projectile_system
	if _ability_system and "combat_system" in _ability_system:
		_ability_system.combat_system = _combat_system
	if "projectile_system" in _player:
		_player.projectile_system = _projectile_system
	if "ability_system" in _player:
		_player.ability_system = _ability_system


func _reset_positions() -> void:
	_ensure_player_ready()
	_ensure_combat_pipeline_ready()
	_apply_scene_tuning()
	if _enemy and is_instance_valid(_enemy):
		_enemy.global_position = _enemy_spawn_position()
		_enemy.velocity = Vector2.ZERO
		if _enemy.has_method("set_flashlight_hit_for_detection"):
			_enemy.set_flashlight_hit_for_detection(false)
	_force_enemy_calm()
	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0


func _player_spawn_position() -> Vector2:
	if _player_spawn:
		return _player_spawn.global_position
	return default_player_spawn


func _enemy_spawn_position() -> Vector2:
	if _enemy_spawn:
		return _enemy_spawn.global_position
	return default_enemy_spawn


func _force_enemy_calm() -> void:
	_force_enemy_state("CALM")


func _force_enemy_alert() -> void:
	_force_enemy_state("ALERT")


func _force_enemy_combat() -> void:
	_force_enemy_state("COMBAT")


func _force_enemy_state(target_state: String) -> void:
	if not _enemy or not is_instance_valid(_enemy):
		return
	if _enemy.has_method("debug_force_awareness_state"):
		_enemy.debug_force_awareness_state(target_state)


func _set_overlay_visible(visible: bool) -> void:
	debug_overlay_enabled = visible
	if _debug_layer:
		_debug_layer.visible = visible


func _update_hint_text() -> void:
	if not _hint_label:
		return
	_hint_label.set_text("%s\nControls: 1 CALM | 2 ALERT | 3 COMBAT | TAB Debug | R Reset\nA1/A2: CALM -> stand in shadow (slow suspicion), then behind box (LOS blocked, no gain).\nA3/A4: ALERT -> step into flashlight cone (fast gain), then behind box (flashlight blocked by LOS).\nA5/A6: break LOS and watch suspicion decay; after COMBAT verify normal escalation/combat flow.\nTuning: shadow %.2f | flash %.0fdeg / %.0fpx / x%.2f" % [
		STEALTH_RUNTIME_MARKER,
		_shadow_multiplier_default(),
		_flashlight_angle_deg(),
		_flashlight_distance_px(),
		_flashlight_bonus(),
	])


func _refresh_debug_label(force: bool) -> void:
	if not _debug_label:
		return
	if not force and not debug_overlay_enabled:
		return

	var enemy_state := "NONE"
	var enemy_alert := "CALM"
	var suspicion := 0.0
	var has_los := false
	var distance_to_player := INF
	var distance_factor := 0.0
	var shadow_mul := 1.0
	var visibility_factor := 0.0
	var flashlight_active := false
	var flashlight_in_cone := false
	var los_to_player := false
	var flashlight_hit := false
	var flashlight_bonus_raw := 1.0
	var effective_visibility_pre_clamp := 0.0
	var effective_visibility_post_clamp := 0.0
	var confirmed := false
	var intent_type := -1
	var last_seen_age := INF
	var room_effective := "CALM"
	var room_transient := "CALM"
	var latch_count := 0
	var flashlight_inactive_reason := ""
	var target_is_last_seen := false
	var last_seen_grace_left := 0.0
	if _enemy and is_instance_valid(_enemy):
		enemy_state = String(_enemy.get_meta("awareness_state", "CALM"))
		if _enemy.has_method("get_current_alert_level"):
			enemy_alert = ENEMY_ALERT_LEVELS_SCRIPT.level_name(int(_enemy.get_current_alert_level()))
		if _enemy.has_method("get_debug_detection_snapshot"):
			var snapshot := _enemy.get_debug_detection_snapshot() as Dictionary
			suspicion = float(snapshot.get("suspicion", 0.0))
			has_los = bool(snapshot.get("has_los", false))
			distance_to_player = float(snapshot.get("distance_to_player", INF))
			distance_factor = float(snapshot.get("distance_factor", 0.0))
			shadow_mul = float(snapshot.get("shadow_mul", 1.0))
			visibility_factor = float(snapshot.get("visibility_factor", 0.0))
			flashlight_active = bool(snapshot.get("flashlight_active", false))
			flashlight_in_cone = bool(snapshot.get("in_cone", false))
			los_to_player = bool(snapshot.get("los_to_player", has_los))
			flashlight_hit = bool(snapshot.get("flashlight_hit", false))
			flashlight_bonus_raw = float(snapshot.get("flashlight_bonus_raw", 1.0))
			effective_visibility_pre_clamp = float(snapshot.get("effective_visibility_pre_clamp", visibility_factor))
			effective_visibility_post_clamp = float(snapshot.get("effective_visibility_post_clamp", visibility_factor))
			confirmed = bool(snapshot.get("confirmed", false))
			intent_type = int(snapshot.get("intent_type", -1))
			last_seen_age = float(snapshot.get("last_seen_age", INF))
			room_effective = ENEMY_ALERT_LEVELS_SCRIPT.level_name(int(snapshot.get("room_alert_effective", 0)))
			room_transient = ENEMY_ALERT_LEVELS_SCRIPT.level_name(int(snapshot.get("room_alert_transient", 0)))
			latch_count = int(snapshot.get("room_latch_count", 0))
			flashlight_inactive_reason = String(snapshot.get("flashlight_inactive_reason", ""))
			target_is_last_seen = bool(snapshot.get("target_is_last_seen", false))
			last_seen_grace_left = float(snapshot.get("last_seen_grace_left", 0.0))

	var visibility_mul := RuntimeState.player_visibility_mul if RuntimeState else 1.0
	var fl_reason := flashlight_inactive_reason if flashlight_inactive_reason != "" else "ok"
	_debug_label.set_text(
		"state=%s | room_eff=%s room_trans=%s latch=%d | intent=%s | fire_gate=ON\n" % [
			enemy_state, room_effective, room_transient, latch_count,
			_intent_name(intent_type)] +
		"LOS=%s | suspicion=%.3f | vis=%.3f | dist=%.1f | last_seen=%.2f | grace=%.2f | target_lkp=%s | confirmed=%s\n" % [
			str(has_los), suspicion, visibility_factor, distance_to_player,
			last_seen_age, last_seen_grace_left, str(target_is_last_seen), str(confirmed)] +
		"flash: active=%s reason=%s cone=%s hit=%s bonus=%.2f | vis_pre=%.3f vis_post=%.3f | shadow=%.3f dist_f=%.3f plr_mul=%.3f" % [
			str(flashlight_active), fl_reason,
			str(flashlight_in_cone), str(flashlight_hit), flashlight_bonus_raw,
			effective_visibility_pre_clamp, effective_visibility_post_clamp,
			shadow_mul, distance_factor, visibility_mul]
	)


func _intent_name(intent_type: int) -> String:
	match intent_type:
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL:
			return "PATROL"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE:
			return "INVESTIGATE"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH:
			return "SEARCH"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.MOVE_TO_SLOT:
			return "MOVE_TO_SLOT"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE:
			return "HOLD_RANGE"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH:
			return "PUSH"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETREAT:
			return "RETREAT"
		ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.RETURN_HOME:
			return "RETURN_HOME"
		_:
			return "UNKNOWN(%d)" % intent_type


func _vec2_compact(value: Vector2) -> String:
	return "(%.2f,%.2f)" % [value.x, value.y]
