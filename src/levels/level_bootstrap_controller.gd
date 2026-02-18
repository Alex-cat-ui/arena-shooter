extends RefCounted
class_name LevelBootstrapController

const ENEMY_SCENE = preload("res://scenes/entities/enemy.tscn")
const ROOM_ENEMY_SPAWNER_SCRIPT = preload("res://src/systems/room_enemy_spawner.gd")
const NAVIGATION_SERVICE_SCRIPT = preload("res://src/systems/navigation_service.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT = preload("res://src/systems/enemy_aggro_coordinator.gd")
const ENEMY_ALERT_SYSTEM_SCRIPT = preload("res://src/systems/enemy_alert_system.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT = preload("res://src/systems/enemy_squad_system.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT = preload("res://src/systems/layout_door_system.gd")
const LEVEL_RUNTIME_BUDGET_CONTROLLER_SCRIPT = preload("res://src/levels/level_runtime_budget_controller.gd")


func init_runtime_state(ctx, mission_index: int) -> void:
	if RuntimeState:
		RuntimeState.player_hp = GameConfig.player_max_hp if GameConfig else 100
		RuntimeState.is_level_active = true
		RuntimeState.is_frozen = false
		RuntimeState.time_elapsed = 0.0
		RuntimeState.kills = 0
		RuntimeState.damage_dealt = 0
		RuntimeState.damage_received = 0
		RuntimeState.mission_index = mission_index
		RuntimeState.layout_room_memory = []


func init_systems(
	ctx,
	layout_controller,
	transition_controller,
	camera_controller
) -> void:
	print("MAIN_BOOTSTRAP_v20260216")
	ctx.combat_system = CombatSystem.new()
	ctx.combat_system.name = "CombatSystem"
	ctx.combat_system.player_node = ctx.player
	ctx.level.add_child(ctx.combat_system)

	ctx.projectile_system = ProjectileSystem.new()
	ctx.projectile_system.name = "ProjectileSystem"
	ctx.projectile_system.projectiles_container = ctx.projectiles_container
	ctx.level.add_child(ctx.projectile_system)

	ctx.vfx_system = VFXSystem.new()
	ctx.vfx_system.name = "VFXSystem"
	ctx.level.add_child(ctx.vfx_system)
	ctx.vfx_system.initialize(ctx.decals_container, ctx.corpses_container)

	ctx.footprint_system = FootprintSystem.new()
	ctx.footprint_system.name = "FootprintSystem"
	ctx.level.add_child(ctx.footprint_system)
	ctx.footprint_system.initialize(ctx.footprints_container, ctx.vfx_system)

	ctx.ability_system = AbilitySystem.new()
	ctx.ability_system.name = "AbilitySystem"
	ctx.ability_system.projectile_system = ctx.projectile_system
	ctx.ability_system.combat_system = ctx.combat_system
	ctx.level.add_child(ctx.ability_system)

	ctx.camera_shake = CameraShake.new()
	ctx.camera_shake.name = "CameraShake"
	ctx.level.add_child(ctx.camera_shake)
	ctx.camera_shake.initialize(ctx.camera)

	ctx.arena_boundary = ArenaBoundary.new()
	ctx.arena_boundary.name = "ArenaBoundary"
	ctx.arena_boundary.z_index = -1
	ctx.arena_boundary.visible = false
	ctx.level.add_child(ctx.arena_boundary)
	if GameConfig and GameConfig.procedural_layout_enabled:
		var arena_rect = layout_controller.random_arena_rect()
		ctx.arena_min = arena_rect.position
		ctx.arena_max = arena_rect.end
		ctx.arena_boundary.initialize(ctx.arena_min, ctx.arena_max)
	else:
		ctx.arena_boundary.initialize(ctx.arena_min, ctx.arena_max)

	ctx.layout_walls = Node2D.new()
	ctx.layout_walls.name = "LayoutWalls"
	ctx.layout_walls.z_as_relative = false
	ctx.layout_walls.z_index = 20
	ctx.level.add_child(ctx.layout_walls)

	ctx.layout_doors = Node2D.new()
	ctx.layout_doors.name = "LayoutDoors"
	ctx.layout_doors.z_as_relative = false
	ctx.layout_doors.z_index = 26
	ctx.level.add_child(ctx.layout_doors)

	ctx.layout_debug = Node2D.new()
	ctx.layout_debug.name = "LayoutDebug"
	ctx.layout_debug.z_index = 100
	ctx.level.add_child(ctx.layout_debug)

	ctx.layout_door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	ctx.layout_door_system.name = "LayoutDoorSystem"
	ctx.level.add_child(ctx.layout_door_system)
	if ctx.layout_door_system and ctx.layout_door_system.has_method("initialize"):
		ctx.layout_door_system.initialize(ctx.layout_doors)

	var mission = transition_controller.current_mission_index(ctx)
	layout_controller.initialize_layout(ctx, mission)

	ctx.room_enemy_spawner = ROOM_ENEMY_SPAWNER_SCRIPT.new()
	ctx.room_enemy_spawner.name = "RoomEnemySpawner"
	ctx.level.add_child(ctx.room_enemy_spawner)
	ctx.room_enemy_spawner.initialize(ENEMY_SCENE, ctx.entities_container)
	ctx.room_enemy_spawner.rebuild_for_layout(ctx.layout)

	ctx.navigation_service = NAVIGATION_SERVICE_SCRIPT.new()
	ctx.navigation_service.name = "NavigationService"
	ctx.level.add_child(ctx.navigation_service)
	if ctx.navigation_service and ctx.navigation_service.has_method("initialize"):
		ctx.navigation_service.initialize(ctx.layout, ctx.entities_container, ctx.player)
	if ctx.navigation_service and ctx.navigation_service.has_method("build_from_layout"):
		ctx.navigation_service.build_from_layout(ctx.layout, ctx.level)

	ctx.enemy_alert_system = ENEMY_ALERT_SYSTEM_SCRIPT.new()
	ctx.enemy_alert_system.name = "EnemyAlertSystem"
	ctx.level.add_child(ctx.enemy_alert_system)
	if ctx.enemy_alert_system and ctx.enemy_alert_system.has_method("initialize"):
		ctx.enemy_alert_system.initialize(ctx.navigation_service)

	ctx.enemy_squad_system = ENEMY_SQUAD_SYSTEM_SCRIPT.new()
	ctx.enemy_squad_system.name = "EnemySquadSystem"
	ctx.level.add_child(ctx.enemy_squad_system)
	if ctx.enemy_squad_system and ctx.enemy_squad_system.has_method("initialize"):
		ctx.enemy_squad_system.initialize(ctx.player, ctx.navigation_service, ctx.entities_container)

	if ctx.navigation_service and ctx.navigation_service.has_method("bind_tactical_systems"):
		ctx.navigation_service.bind_tactical_systems(ctx.enemy_alert_system, ctx.enemy_squad_system)

	ctx.enemy_aggro_coordinator = ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	ctx.enemy_aggro_coordinator.name = "EnemyAggroCoordinator"
	ctx.level.add_child(ctx.enemy_aggro_coordinator)
	if ctx.enemy_aggro_coordinator and ctx.enemy_aggro_coordinator.has_method("initialize"):
		ctx.enemy_aggro_coordinator.initialize(ctx.entities_container, ctx.navigation_service, ctx.player)

	ctx.runtime_budget_controller = LEVEL_RUNTIME_BUDGET_CONTROLLER_SCRIPT.new()
	if ctx.runtime_budget_controller and ctx.runtime_budget_controller.has_method("bind"):
		ctx.runtime_budget_controller.bind(ctx)

	transition_controller.setup_north_transition_trigger(ctx)
	camera_controller.reset_follow(ctx)
	layout_controller.ensure_player_runtime_ready(ctx)

	if ctx.player and ctx.player is CharacterBody2D:
		if not (ctx.player.collision_mask & 1):
			ctx.player.collision_mask |= 1

	print("[LevelMVP] Systems initialized (Weapons + Arena Polish)")


func init_visual_polish(ctx, hud_controller) -> void:
	ctx.shadow_system = ShadowSystem.new()
	ctx.shadow_system.name = "ShadowSystem"
	ctx.shadow_system.z_index = -2
	ctx.level.add_child(ctx.shadow_system)
	ctx.shadow_system.initialize(ctx.player, ctx.entities_container)

	ctx.combat_feedback_system = CombatFeedbackSystem.new()
	ctx.combat_feedback_system.name = "CombatFeedbackSystem"
	ctx.level.add_child(ctx.combat_feedback_system)
	ctx.combat_feedback_system.initialize(ctx.hud)

	ctx.atmosphere_system = AtmosphereSystem.new()
	ctx.atmosphere_system.name = "AtmosphereSystem"
	ctx.level.add_child(ctx.atmosphere_system)
	var particle_container = Node2D.new()
	particle_container.name = "AtmosphereParticles"
	ctx.level.add_child(particle_container)
	var decal_layer = Node2D.new()
	decal_layer.name = "FloorDecals"
	decal_layer.z_index = -9
	ctx.level.add_child(decal_layer)
	ctx.atmosphere_system.initialize(particle_container, decal_layer, ctx.arena_min, ctx.arena_max)

	hud_controller.create_vignette(ctx)
	hud_controller.create_floor_overlay(ctx)
	hud_controller.create_debug_overlay(ctx)
	hud_controller.style_hud_labels(ctx)
	hud_controller.create_momentum_placeholder(ctx)
	print("[LevelMVP] Visual polish initialized")
