## level_mvp.gd
## MVP level controller - Phase 1-4 + Visual Polish Pass.
## CANON: Camera is TOP-DOWN ORTHOGRAPHIC, no rotation.
## CANON: ESC toggles pause, F1/F2 for debug state changes, F3 debug overlay.
## CANON: StartDelaySec - player CAN move, enemies MUST NOT spawn.
extends Node2D

## Arena shape presets
enum ArenaPreset { SQUARE, LANDSCAPE, PORTRAIT }

## Scene references
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/entities/boss.tscn")
const PROCEDURAL_LAYOUT_V2_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")
const ROOM_ENEMY_SPAWNER_SCRIPT := preload("res://src/systems/room_enemy_spawner.gd")
const ROOM_NAV_SYSTEM_SCRIPT := preload("res://src/systems/room_nav_system.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")

## Node references
@onready var player: CharacterBody2D = $Entities/Player
@onready var camera: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var hp_label: Label = $HUD/HUDContainer/HPLabel
@onready var state_label: Label = $HUD/HUDContainer/StateLabel
@onready var wave_label: Label = $HUD/HUDContainer/WaveLabel
@onready var time_label: Label = $HUD/HUDContainer/TimeLabel
@onready var boss_hp_label: Label = $HUD/HUDContainer/BossHPLabel
@onready var weapon_label: Label = $HUD/HUDContainer/WeaponLabel
@onready var floor_root: Node2D = $Floor
@onready var floor_sprite: Sprite2D = $Floor/FloorSprite
@onready var debug_hint_label: Label = $HUD/DebugHint

## Container nodes
@onready var entities_container: Node2D = $Entities
@onready var projectiles_container: Node2D = $Projectiles
@onready var decals_container: Node2D = $Decals
@onready var corpses_container: Node2D = $Corpses
@onready var footprints_container: Node2D = $Footprints

## Systems (Phase 1-2)
var wave_manager: WaveManager = null
var combat_system: CombatSystem = null
var projectile_system: ProjectileSystem = null
var vfx_system: VFXSystem = null
var footprint_system: FootprintSystem = null
var room_enemy_spawner = null
var room_nav_system = null
var enemy_aggro_coordinator = null
var layout_door_system = null

## Systems (Phase 3: Arena Polish + Weapons)
var ability_system: AbilitySystem = null
var camera_shake: CameraShake = null
var wave_overlay: WaveOverlay = null
var arena_boundary: ArenaBoundary = null

## Systems (Phase 4: Katana / Melee)
var melee_system: MeleeSystem = null

## Systems (Visual Polish Pass)
var melee_arc_system: MeleeArcSystem = null
var shadow_system: ShadowSystem = null
var combat_feedback_system: CombatFeedbackSystem = null
var atmosphere_system: AtmosphereSystem = null

## Procedural layout
var layout_walls: Node2D = null
var layout_doors: Node2D = null
var layout_debug: Node2D = null
var _layout = null
var _walkable_floor: Node2D = null
var _non_walkable_floor_bg: Sprite2D = null
var _layout_room_memory: Array = []
var _north_transition_rect: Rect2 = Rect2()
var _north_transition_enabled: bool = false
var _north_transition_cooldown: float = 0.0
var _mission_cycle: Array[int] = [3, 1, 2]
var _mission_cycle_pos: int = 0

## Start delay timer
var _start_delay_timer: float = 0.0
var _start_delay_finished: bool = false

## Arena bounds
var _arena_min := Vector2(-500, -500)
var _arena_max := Vector2(500, 500)

## Debug overlay state
var _debug_overlay_visible: bool = false

## HUD overlay nodes (created dynamically)
var _vignette_rect: ColorRect = null
var _floor_overlay: ColorRect = null
var _debug_container: VBoxContainer = null
var _momentum_label: Label = null
var _music_system_ref: MusicSystem = null
var _camera_follow_pos: Vector2 = Vector2.ZERO
var _camera_follow_initialized: bool = false
var _cached_white_pixel_tex: ImageTexture = null
var _cached_black_pixel_tex: ImageTexture = null
var _layout_room_stats: Dictionary = {
	"corridors": 0,
	"interior_rooms": 0,
	"exterior_rooms": 0,
	"closets": 0,
}
var _enemy_weapons_enabled: bool = false

const CAMERA_FOLLOW_LERP_MOVING := 2.5
const CAMERA_FOLLOW_LERP_STOPPING := 1.0
const CAMERA_VELOCITY_EPSILON := 6.0
const V2_FLOOR_FILL_COLOR := Color(0.58, 0.58, 0.58, 1.0)
const PLAYER_NORTH_SPAWN_OFFSET := 100.0
const WAVES_RUNTIME_ENABLED := false
const RIGHT_DEBUG_HINT_BASE := "ESC - Pause | F1 - Game Over\nF2 - Level Complete | F3 - Debug\nF4 - Regenerate | F7 - Enemy Guns | F8 - God Mode\nLMB - Shoot | 1-6 Weapons | Wheel\nQ - Katana | RMB - Heavy | Space - Dash"


func _ready() -> void:
	print("[LevelMVP] Ready - Visual Polish Pass")

	# CANON: Camera must not rotate
	camera.rotation = 0
	camera.enabled = true
	camera.make_current()

	# Initialize RuntimeState
	_init_runtime_state()

	# Initialize systems
	_init_systems()

	# Initialize visual polish
	_init_visual_polish()

	# Connect player to systems
	if player and projectile_system:
		player.projectile_system = projectile_system
	if player and ability_system:
		player.ability_system = ability_system

	# Start the start delay timer
	_start_delay_timer = GameConfig.start_delay_sec if GameConfig else 1.5

	# Subscribe to events
	_subscribe_to_events()
	_bind_enemy_toggle_hook()
	_apply_enemy_weapon_toggle_to_all()
	_cache_music_system_ref()
	_refresh_right_debug_hint()

	_update_hud()

	print("[LevelMVP] Level bootstrap complete, start delay: %.1f sec" % _start_delay_timer)


func _init_runtime_state() -> void:
	if RuntimeState:
		RuntimeState.player_hp = GameConfig.player_max_hp if GameConfig else 100
		RuntimeState.is_level_active = true
		RuntimeState.is_frozen = false
		RuntimeState.time_elapsed = 0.0
		RuntimeState.current_wave = 0
		RuntimeState.kills = 0
		RuntimeState.damage_dealt = 0
		RuntimeState.damage_received = 0
		RuntimeState.mission_index = _current_mission_index()
		RuntimeState.layout_room_memory = []


func _random_arena_rect() -> Rect2:
	# Stable runtime envelope (no random presets) to keep generation deterministic.
	var cx := 0.0
	var cy := 0.0
	var w := 2200.0
	var h := 1500.0
	return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)


func _init_systems() -> void:
	# Wave flow is currently disabled by design; static room enemies are used.
	if _waves_runtime_enabled():
		wave_manager = WaveManager.new()
		wave_manager.name = "WaveManager"
		wave_manager.enemy_scene = ENEMY_SCENE
		wave_manager.boss_scene = BOSS_SCENE
		wave_manager.entities_container = entities_container
		wave_manager.arena_min = _arena_min
		wave_manager.arena_max = _arena_max
		add_child(wave_manager)
		var total_waves: int = GameConfig.waves_per_level if GameConfig else 3
		wave_manager.initialize(total_waves)
	else:
		wave_manager = null

	# Create CombatSystem
	combat_system = CombatSystem.new()
	combat_system.name = "CombatSystem"
	combat_system.player_node = player
	add_child(combat_system)

	# Create ProjectileSystem
	projectile_system = ProjectileSystem.new()
	projectile_system.name = "ProjectileSystem"
	projectile_system.projectiles_container = projectiles_container
	add_child(projectile_system)

	# Create VFXSystem (Phase 2)
	vfx_system = VFXSystem.new()
	vfx_system.name = "VFXSystem"
	add_child(vfx_system)
	vfx_system.initialize(decals_container, corpses_container)

	# Create FootprintSystem (Phase 2 - rewritten for visual polish)
	footprint_system = FootprintSystem.new()
	footprint_system.name = "FootprintSystem"
	add_child(footprint_system)
	footprint_system.initialize(footprints_container, vfx_system)

	# Phase 3: Create AbilitySystem
	ability_system = AbilitySystem.new()
	ability_system.name = "AbilitySystem"
	ability_system.projectile_system = projectile_system
	ability_system.combat_system = combat_system
	add_child(ability_system)

	# Phase 3: Create CameraShake
	camera_shake = CameraShake.new()
	camera_shake.name = "CameraShake"
	add_child(camera_shake)
	camera_shake.initialize(camera)

	if _waves_runtime_enabled():
		wave_overlay = WaveOverlay.new()
		wave_overlay.name = "WaveOverlay"
		add_child(wave_overlay)
	else:
		wave_overlay = null

	# Phase 3: Create ArenaBoundary (added before Entities for z-ordering)
	arena_boundary = ArenaBoundary.new()
	arena_boundary.name = "ArenaBoundary"
	arena_boundary.z_index = -1  # Behind entities
	# Disabled by default: rectangular dark silhouette conflicts with irregular HM-style shapes.
	arena_boundary.visible = false
	add_child(arena_boundary)
	# Random arena shape
	if GameConfig and GameConfig.procedural_layout_enabled:
		var arena_rect := _random_arena_rect()
		_arena_min = arena_rect.position
		_arena_max = arena_rect.end
		arena_boundary.initialize(_arena_min, _arena_max)
		if wave_manager:
			wave_manager.arena_min = _arena_min
			wave_manager.arena_max = _arena_max
	else:
		arena_boundary.initialize(_arena_min, _arena_max)

	# Procedural layout
	layout_walls = Node2D.new()
	layout_walls.name = "LayoutWalls"
	layout_walls.z_as_relative = false
	layout_walls.z_index = 20
	add_child(layout_walls)
	layout_doors = Node2D.new()
	layout_doors.name = "LayoutDoors"
	layout_doors.z_as_relative = false
	layout_doors.z_index = 26
	add_child(layout_doors)
	layout_debug = Node2D.new()
	layout_debug.name = "LayoutDebug"
	layout_debug.z_index = 100
	add_child(layout_debug)
	layout_door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	layout_door_system.name = "LayoutDoorSystem"
	add_child(layout_door_system)
	if layout_door_system and layout_door_system.has_method("initialize"):
		layout_door_system.initialize(layout_doors)
	_ensure_walkable_floor_node()

	if GameConfig and GameConfig.procedural_layout_enabled:
		var arena_rect := Rect2(_arena_min, _arena_max - _arena_min)
		var s: int = GameConfig.layout_seed
		if s == 0:
			s = int(Time.get_ticks_msec()) % 999999
		_layout = _generate_layout(arena_rect, s)
		_ensure_layout_recovered(arena_rect, s)
	if layout_door_system and layout_door_system.has_method("rebuild_for_layout"):
		layout_door_system.rebuild_for_layout(_layout)
	_rebuild_walkable_floor()
	_update_layout_room_stats()
	_sync_layout_runtime_memory()
	room_enemy_spawner = ROOM_ENEMY_SPAWNER_SCRIPT.new()
	room_enemy_spawner.name = "RoomEnemySpawner"
	add_child(room_enemy_spawner)
	room_enemy_spawner.initialize(ENEMY_SCENE, entities_container)
	if room_enemy_spawner:
		room_enemy_spawner.rebuild_for_layout(_layout)
	room_nav_system = ROOM_NAV_SYSTEM_SCRIPT.new()
	room_nav_system.name = "RoomNavSystem"
	add_child(room_nav_system)
	if room_nav_system and room_nav_system.has_method("initialize"):
		room_nav_system.initialize(_layout, entities_container, player)
	enemy_aggro_coordinator = ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	enemy_aggro_coordinator.name = "EnemyAggroCoordinator"
	add_child(enemy_aggro_coordinator)
	if enemy_aggro_coordinator and enemy_aggro_coordinator.has_method("initialize"):
		enemy_aggro_coordinator.initialize(entities_container, room_nav_system, player)
	_setup_north_transition_trigger()
	_reset_camera_follow()
	_ensure_player_runtime_ready()

	# Ensure player collision_mask includes bit 1 (walls)
	if player and player is CharacterBody2D:
		if not (player.collision_mask & 1):
			player.collision_mask |= 1

	# Phase 4: Create MeleeSystem (Katana)
	if GameConfig and GameConfig.katana_enabled:
		melee_system = MeleeSystem.new()
		melee_system.name = "MeleeSystem"
		melee_system.player_node = player
		melee_system.entities_container = entities_container
		add_child(melee_system)

	print("[LevelMVP] Systems initialized (Phase 4: Weapons + Arena Polish + Katana)")


func _ensure_walkable_floor_node() -> void:
	if not floor_root:
		return
	if _walkable_floor:
		return
	_walkable_floor = Node2D.new()
	_walkable_floor.name = "WalkableFloor"
	floor_root.add_child(_walkable_floor)


func _clear_walkable_floor() -> void:
	if not _walkable_floor:
		return
	_non_walkable_floor_bg = null
	_clear_node_children_detached(_walkable_floor)


func _ensure_non_walkable_background() -> void:
	if not _walkable_floor:
		return
	var bg_bounds := _compute_layout_render_bounds()
	if _non_walkable_floor_bg and is_instance_valid(_non_walkable_floor_bg):
		_non_walkable_floor_bg.position = bg_bounds.get_center()
		_non_walkable_floor_bg.scale = bg_bounds.size
		return

	var bg := Sprite2D.new()
	bg.name = "NonWalkableBlack"
	bg.texture = _solid_black_texture()
	bg.centered = true
	bg.position = bg_bounds.get_center()
	bg.scale = bg_bounds.size
	bg.z_index = -50
	_walkable_floor.add_child(bg)
	_non_walkable_floor_bg = bg


func _compute_layout_render_bounds() -> Rect2:
	var bounds := Rect2(_arena_min, _arena_max - _arena_min)
	if not _layout or not _layout.valid:
		return bounds

	var has_rect := false
	var merged := Rect2()
	for i in range(_layout.rooms.size()):
		if i in _layout._void_ids:
			continue
		var room: Dictionary = _layout.rooms[i]
		for rect_variant in (room["rects"] as Array):
			var r := rect_variant as Rect2
			if not has_rect:
				merged = r
				has_rect = true
			else:
				merged = merged.merge(r)

	if not has_rect:
		return bounds
	return bounds.merge(merged).grow(220.0)


func _rebuild_walkable_floor() -> void:
	if not floor_sprite:
		return
	_ensure_walkable_floor_node()
	_clear_walkable_floor()

	if not _layout or not _layout.valid:
		floor_sprite.visible = true
		return

	var v2_fill_mode := _is_layout_v2(_layout)
	if not v2_fill_mode and not floor_sprite.texture:
		floor_sprite.visible = true
		return

	floor_sprite.visible = false
	_ensure_non_walkable_background()
	var sx := floor_sprite.scale.x
	var sy := floor_sprite.scale.y
	if absf(sx) < 0.0001:
		sx = 1.0
	if absf(sy) < 0.0001:
		sy = 1.0

	for i in range(_layout.rooms.size()):
		if i in _layout._void_ids:
			continue
		var room: Dictionary = _layout.rooms[i]
		for rect_variant in (room["rects"] as Array):
			var r := rect_variant as Rect2
			if r.size.x < 2.0 or r.size.y < 2.0:
				continue
			var patch := Sprite2D.new()
			patch.centered = true
			patch.position = r.get_center()
			if v2_fill_mode:
				patch.texture = _solid_white_texture()
				patch.modulate = V2_FLOOR_FILL_COLOR
				patch.scale = r.size
			else:
				patch.texture = floor_sprite.texture
				patch.texture_filter = floor_sprite.texture_filter
				patch.texture_repeat = floor_sprite.texture_repeat
				patch.scale = floor_sprite.scale
				patch.region_enabled = true
				patch.region_rect = Rect2(
					r.position.x / sx,
					r.position.y / sy,
					r.size.x / sx,
					r.size.y / sy
				)
			patch.z_index = -40
			_walkable_floor.add_child(patch)


func _solid_white_texture() -> ImageTexture:
	if _cached_white_pixel_tex and is_instance_valid(_cached_white_pixel_tex):
		return _cached_white_pixel_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_cached_white_pixel_tex = ImageTexture.create_from_image(img)
	return _cached_white_pixel_tex


func _solid_black_texture() -> ImageTexture:
	if _cached_black_pixel_tex and is_instance_valid(_cached_black_pixel_tex):
		return _cached_black_pixel_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.BLACK)
	_cached_black_pixel_tex = ImageTexture.create_from_image(img)
	return _cached_black_pixel_tex


func _clear_node_children_detached(parent: Node) -> void:
	if not parent:
		return
	var children := parent.get_children()
	for child in children:
		parent.remove_child(child)
		child.queue_free()


func _init_visual_polish() -> void:
	# Create MeleeArcSystem
	melee_arc_system = MeleeArcSystem.new()
	melee_arc_system.name = "MeleeArcSystem"
	add_child(melee_arc_system)
	# Create container for arcs (above entities)
	var arc_container := Node2D.new()
	arc_container.name = "MeleeArcs"
	arc_container.z_index = 10
	add_child(arc_container)
	melee_arc_system.initialize(arc_container, player)

	# Create ShadowSystem (below entities)
	shadow_system = ShadowSystem.new()
	shadow_system.name = "ShadowSystem"
	shadow_system.z_index = -2  # Below entities, above floor
	add_child(shadow_system)
	shadow_system.initialize(player, entities_container)

	# Create CombatFeedbackSystem
	combat_feedback_system = CombatFeedbackSystem.new()
	combat_feedback_system.name = "CombatFeedbackSystem"
	add_child(combat_feedback_system)
	combat_feedback_system.initialize(hud)

	# Create AtmosphereSystem
	atmosphere_system = AtmosphereSystem.new()
	atmosphere_system.name = "AtmosphereSystem"
	add_child(atmosphere_system)
	# Create containers for atmosphere
	var particle_container := Node2D.new()
	particle_container.name = "AtmosphereParticles"
	add_child(particle_container)
	var decal_layer := Node2D.new()
	decal_layer.name = "FloorDecals"
	decal_layer.z_index = -9
	add_child(decal_layer)
	atmosphere_system.initialize(particle_container, decal_layer, _arena_min, _arena_max)

	# Create vignette overlay
	_create_vignette()

	# Create floor dark overlay
	_create_floor_overlay()

	# Create debug overlay (hidden by default)
	_create_debug_overlay()

	# Style HUD labels
	_style_hud_labels()

	# Create hidden momentum placeholder
	_momentum_label = Label.new()
	_momentum_label.name = "MomentumLabel"
	_momentum_label.text = "Momentum: 0"
	_momentum_label.visible = false
	$HUD/HUDContainer.add_child(_momentum_label)

	# Subscribe to melee events for arc visuals
	if EventBus:
		EventBus.melee_hit.connect(_on_melee_hit_vfx)

	print("[LevelMVP] Visual polish initialized")


func _create_vignette() -> void:
	# Soft vignette overlay on HUD layer
	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "Vignette"
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.anchors_preset = Control.PRESET_FULL_RECT
	_vignette_rect.anchor_right = 1.0
	_vignette_rect.anchor_bottom = 1.0
	# Dark edges vignette via gradient shader would be ideal, but
	# for lightweight approach, use a simple border darkening
	var alpha := GameConfig.vignette_alpha if GameConfig else 0.3
	_vignette_rect.color = Color(0, 0, 0, alpha * 0.3)  # Very subtle
	hud.add_child(_vignette_rect)
	# Move to back so it doesn't cover HUD text
	hud.move_child(_vignette_rect, 0)


func _create_floor_overlay() -> void:
	# Disabled: full-rect dark overlay reintroduces the "box silhouette" behind layout.
	_floor_overlay = null


func _create_debug_overlay() -> void:
	_debug_container = VBoxContainer.new()
	_debug_container.name = "DebugOverlay"
	_debug_container.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_debug_container.anchor_bottom = 1.0
	_debug_container.offset_left = 10.0
	_debug_container.offset_bottom = -10.0
	_debug_container.offset_top = -145.0
	_debug_container.offset_right = 400.0
	_debug_container.visible = _debug_overlay_visible
	hud.add_child(_debug_container)

	# Debug labels
	var fps_label := Label.new()
	fps_label.name = "FPSLabel"
	fps_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(fps_label)

	var entities_label := Label.new()
	entities_label.name = "EntitiesLabel"
	entities_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(entities_label)

	var decals_label := Label.new()
	decals_label.name = "DecalsLabel"
	decals_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(decals_label)

	var floor_label := Label.new()
	floor_label.name = "FloorLabel"
	floor_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(floor_label)

	var layout_label := Label.new()
	layout_label.name = "LayoutLabel"
	layout_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(layout_label)

	var room_types_label := Label.new()
	room_types_label.name = "RoomTypesLabel"
	room_types_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(room_types_label)

	var music_label := Label.new()
	music_label.name = "MusicLabel"
	music_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_debug_container.add_child(music_label)


func _style_hud_labels() -> void:
	# HP emphasized (larger color)
	if hp_label:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))

	# Secondary text dimmed
	var dim_color := Color(0.6, 0.6, 0.6, 0.8)
	if state_label:
		state_label.add_theme_color_override("font_color", dim_color)
	if wave_label:
		wave_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5, 0.9))
		wave_label.visible = _waves_runtime_enabled()
	if time_label:
		time_label.add_theme_color_override("font_color", dim_color)
	if boss_hp_label:
		boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0, 1.0))
		boss_hp_label.visible = _waves_runtime_enabled()
	if weapon_label:
		weapon_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.9))


func _subscribe_to_events() -> void:
	if EventBus:
		if _waves_runtime_enabled():
			EventBus.wave_started.connect(_on_wave_started)
			EventBus.all_waves_completed.connect(_on_all_waves_completed)
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.player_died.connect(_on_player_died)
		# Phase 2: Boss events
		if _waves_runtime_enabled():
			EventBus.boss_spawned.connect(_on_boss_spawned)
			EventBus.boss_killed.connect(_on_boss_killed)
			EventBus.boss_damaged.connect(_on_boss_damaged)
		# Phase 3: Rocket explosion -> camera shake
		EventBus.rocket_exploded.connect(_on_rocket_exploded)


func _process(delta: float) -> void:
	# Handle input
	_handle_input()

	# Skip updates if frozen
	if RuntimeState and RuntimeState.is_frozen:
		return

	# Update time
	if RuntimeState:
		RuntimeState.time_elapsed += delta

	# Handle start delay
	if not _start_delay_finished:
		_start_delay_timer -= delta
		if _start_delay_timer <= 0:
			_start_delay_finished = true
			if _waves_runtime_enabled():
				print("[LevelMVP] Start delay finished, waves beginning")
			else:
				print("[LevelMVP] Start delay finished (waves disabled)")
			if EventBus and _waves_runtime_enabled():
				EventBus.emit_start_delay_finished()

	# Update systems
	if wave_manager:
		wave_manager.update(delta)
	if combat_system:
		combat_system.update(delta)
	if melee_system:
		melee_system.update(delta)
	if footprint_system:
		footprint_system.update(delta)

	# Visual polish updates
	if vfx_system:
		vfx_system.update_aging(delta)
	if melee_arc_system:
		melee_arc_system.update(delta)
	if shadow_system:
		shadow_system.update(delta)
	if combat_feedback_system:
		combat_feedback_system.update(delta)
	if atmosphere_system:
		atmosphere_system.update(delta)

	# Camera follows player (CANON: no rotation)
	if player and camera:
		if not _camera_follow_initialized:
			_camera_follow_pos = player.position
			_camera_follow_initialized = true
		var speed := player.velocity.length()
		var follow_speed := CAMERA_FOLLOW_LERP_MOVING if speed > CAMERA_VELOCITY_EPSILON else CAMERA_FOLLOW_LERP_STOPPING
		var w := clampf(1.0 - exp(-follow_speed * delta), 0.0, 1.0)
		_camera_follow_pos = _camera_follow_pos.lerp(player.position, w)
		camera.position = _camera_follow_pos
		camera.rotation = 0  # Ensure no rotation
		# Phase 3: Apply camera shake
		if camera_shake:
			camera_shake.update(delta)

	# Update HUD
	_update_hud()

	# Update debug overlay
	if _debug_overlay_visible and _debug_container:
		_update_debug_overlay()

	if _north_transition_cooldown > 0.0:
		_north_transition_cooldown = maxf(0.0, _north_transition_cooldown - delta)
	_check_north_transition()


func _handle_input() -> void:
	# ESC - toggle pause
	if Input.is_action_just_pressed("pause"):
		if StateManager:
			if StateManager.is_playing():
				StateManager.change_state(GameState.State.PAUSED)
			elif StateManager.is_paused():
				StateManager.change_state(GameState.State.PLAYING)

	# Debug: F1 - force game over
	if Input.is_action_just_pressed("debug_game_over"):
		if StateManager and StateManager.is_playing():
			print("[LevelMVP] Debug: Forcing GAME_OVER")
			StateManager.change_state(GameState.State.GAME_OVER)

	# Debug: F2 - force level complete
	if Input.is_action_just_pressed("debug_level_complete"):
		if StateManager and StateManager.is_playing():
			print("[LevelMVP] Debug: Forcing LEVEL_COMPLETE")
			StateManager.change_state(GameState.State.LEVEL_COMPLETE)

	# Debug: F3 - toggle debug overlay
	if Input.is_action_just_pressed("debug_toggle"):
		_debug_overlay_visible = not _debug_overlay_visible
		if _debug_container:
			_debug_container.visible = _debug_overlay_visible
		if GameConfig:
			GameConfig.debug_overlay_visible = _debug_overlay_visible
		print("[LevelMVP] Debug overlay: %s" % ("ON" if _debug_overlay_visible else "OFF"))


## Part 9: F4 - regenerate layout
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			print("[LevelMVP] F4: Regenerating layout")
			regenerate_layout(0)
		elif event.keycode == KEY_F7:
			_enemy_weapons_enabled = not _enemy_weapons_enabled
			_apply_enemy_weapon_toggle_to_all()
			_refresh_right_debug_hint()
			print("[LevelMVP] Enemy weapons: %s" % ("ON" if _enemy_weapons_enabled else "OFF"))
		elif event.keycode == KEY_F8 and GameConfig:
			GameConfig.god_mode = not GameConfig.god_mode
			_refresh_right_debug_hint()
			print("[LevelMVP] God mode: %s" % ("ON" if GameConfig.god_mode else "OFF"))


func _update_hud() -> void:
	if not RuntimeState:
		return

	if hp_label:
		hp_label.text = "HP: %d / %d" % [RuntimeState.player_hp, GameConfig.player_max_hp if GameConfig else 100]

	if state_label and StateManager:
		var state_text := GameState.state_to_string(StateManager.current_state)
		if not _start_delay_finished and StateManager.is_playing():
			state_text += " (%.1f)" % _start_delay_timer
		state_label.text = "State: %s" % state_text

	if wave_label:
		if _waves_runtime_enabled():
			var wave_text := "Wave: %d" % RuntimeState.current_wave
			if wave_manager:
				wave_text += " / %d" % (GameConfig.waves_per_level if GameConfig else 3)
				if RuntimeState.current_wave > 0:
					wave_text += " (Alive: %d)" % wave_manager.alive_total
			wave_label.text = wave_text
		else:
			wave_label.text = "Wave: OFF"

	if time_label:
		time_label.text = "Time: %.1f | Kills: %d" % [RuntimeState.time_elapsed, RuntimeState.kills]

	# Phase 2: Boss HP display
	if boss_hp_label and wave_manager:
		if wave_manager.boss_spawned and wave_manager.boss_node and is_instance_valid(wave_manager.boss_node):
			var boss := wave_manager.boss_node
			if "hp" in boss and "max_hp" in boss:
				boss_hp_label.text = "BOSS: %d / %d" % [boss.hp, boss.max_hp]
			else:
				boss_hp_label.text = "BOSS ACTIVE"
		elif wave_manager._boss_phase and not wave_manager.boss_spawned:
			boss_hp_label.text = "Boss incoming..."
		else:
			boss_hp_label.text = ""

	# Weapon display (compact readable layout)
	if weapon_label and ability_system:
		var mode_str := "KATANA" if RuntimeState.katana_mode else "GUN"
		if RuntimeState.katana_mode:
			var melee_state := ""
			if melee_system and melee_system.is_busy():
				melee_state = " [SLASH]"
			weapon_label.text = "%s%s | Q=switch" % [mode_str, melee_state]
		else:
			weapon_label.text = "%s %s [%d/6]" % [
				mode_str,
				ability_system.get_current_weapon().to_upper(),
				ability_system.current_weapon_index + 1
			]


func _update_debug_overlay() -> void:
	if not _debug_container:
		return

	var fps_label := _debug_container.get_node_or_null("FPSLabel") as Label
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	var entities_label := _debug_container.get_node_or_null("EntitiesLabel") as Label
	if entities_label:
		var enemy_count := get_tree().get_nodes_in_group("enemies").size()
		entities_label.text = "Enemies: %d | Projectiles: %d" % [enemy_count, projectiles_container.get_child_count()]

	var decals_label := _debug_container.get_node_or_null("DecalsLabel") as Label
	if decals_label:
		var blood := decals_container.get_child_count()
		var corpses := vfx_system.get_total_corpse_count() if vfx_system else 0
		var footprints := footprint_system.get_footprint_count() if footprint_system else 0
		var fp_total: int = footprint_system.get_spawned_total() if footprint_system else 0
		var fp_charges: int = footprint_system.get_blood_charges() if footprint_system else 0
		var fp_on_blood: bool = footprint_system.last_on_blood if footprint_system else false
		var fp_on_corpse: bool = footprint_system.last_on_corpse if footprint_system else false
		decals_label.text = "Blood: %d | Corpses: %d | FP tot=%d blood=%d corpse=%d charges=%d" % [blood, corpses, fp_total, int(fp_on_blood), int(fp_on_corpse), fp_charges]

	var floor_label := _debug_container.get_node_or_null("FloorLabel") as Label
	if floor_label:
		var atmo_particles := 0
		if atmosphere_system and atmosphere_system.has_method("get_particle_count"):
			atmo_particles = atmosphere_system.get_particle_count()
		var atmo_decals := 0
		if atmosphere_system and atmosphere_system.has_method("get_decal_count"):
			atmo_decals = atmosphere_system.get_decal_count()
		floor_label.text = "Floor: dirt_grass_01 | Particles: %d | Decals: %d" % [atmo_particles, atmo_decals]

	if GameConfig and GameConfig.layout_debug_text:
		var layout_label := _debug_container.get_node_or_null("LayoutLabel") as Label
		if layout_label:
			if _layout and _layout.valid:
				layout_label.text = "Layout: seed=%d rooms=%d corr=%d doors=%d mode=%s hubs=%d voids=%d avg_deg=%.1f max_d=%d loops=%d iso=%d [F4=regen]" % [
					_layout.layout_seed, _layout.rooms.size(), _layout.corridors.size(), _layout.doors.size(),
					_layout.layout_mode_name, _layout._hub_ids.size(), _layout._void_ids.size(),
					_layout.avg_degree, _layout.max_doors_stat, _layout.extra_loops, _layout.isolated_fixed]
			elif _layout:
				layout_label.text = "Layout: INVALID [F4=regen]"
			else:
				layout_label.text = "Layout: disabled"

	var room_types_label := _debug_container.get_node_or_null("RoomTypesLabel") as Label
	if room_types_label:
		room_types_label.text = "RoomTypes: corr=%d | inner=%d | outer=%d | closet=%d | enemy_guns=%s" % [
			int(_layout_room_stats["corridors"]),
			int(_layout_room_stats["interior_rooms"]),
			int(_layout_room_stats["exterior_rooms"]),
			int(_layout_room_stats["closets"]),
			("ON" if _enemy_weapons_enabled else "OFF"),
		]

	var music_label := _debug_container.get_node_or_null("MusicLabel") as Label
	if music_label:
		var music_system := _cache_music_system_ref()
		if music_system:
			music_label.text = "Music: %s | %s" % [
				music_system.get_current_context_name(),
				music_system.get_current_track_name(),
			]
		else:
			music_label.text = "Music: offline"


## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_wave_started(wave_index: int, wave_size: int) -> void:
	if not _waves_runtime_enabled():
		return
	print("[LevelMVP] Wave %d started (size: %d)" % [wave_index, wave_size])
	# Phase 3: Show wave overlay
	if wave_overlay:
		wave_overlay.show_wave(wave_index)


func _on_player_damaged(amount: int, new_hp: int, source: String) -> void:
	print("[LevelMVP] Player damaged: %d (HP: %d, source: %s)" % [amount, new_hp, source])
	# Visual feedback on player
	if player and player.has_method("take_damage"):
		player.take_damage(amount)


func _on_player_died() -> void:
	print("[LevelMVP] Player died!")


func _on_all_waves_completed() -> void:
	var boss_enabled := GameConfig.spawn_boss_enabled if GameConfig else false
	if boss_enabled:
		print("[LevelMVP] All waves completed! Waiting for boss...")
	else:
		print("[LevelMVP] All waves completed (boss disabled). North transition unlocked after clear.")


## Phase 3: Rocket explosion -> camera shake
func _on_rocket_exploded(_pos: Vector3) -> void:
	if camera_shake:
		var amp: float = GameConfig.rocket_shake_amplitude if GameConfig else 3.0
		var dur: float = GameConfig.rocket_shake_duration if GameConfig else 0.15
		camera_shake.shake(amp, dur)


## Melee arc visual on hit
func _on_melee_hit_vfx(_pos: Vector3, move_type: String) -> void:
	if melee_arc_system:
		melee_arc_system.spawn_arc(move_type)


## ============================================================================
## BOSS EVENT HANDLERS (Phase 2)
## ============================================================================

func _on_boss_spawned(boss_id: int, pos: Vector3) -> void:
	print("[LevelMVP] BOSS SPAWNED at position (%d, %d)!" % [int(pos.x), int(pos.y)])


func _on_boss_damaged(boss_id: int, amount: int, new_hp: int) -> void:
	print("[LevelMVP] Boss damaged: %d (HP: %d)" % [amount, new_hp])


func _on_boss_killed(boss_id: int) -> void:
	print("[LevelMVP] BOSS DEFEATED! VICTORY!")

	# CANON: After boss death - stop gameplay, stop spawns, no damage, show LEVEL_COMPLETE
	if RuntimeState:
		RuntimeState.is_frozen = true
		RuntimeState.is_level_active = false

	if StateManager:
		StateManager.change_state(GameState.State.LEVEL_COMPLETE)


## ============================================================================
## LAYOUT REGENERATION
## ============================================================================

## Regenerate procedural layout. Called on New Game.
func regenerate_layout(new_seed: int = 0) -> void:
	if not layout_walls:
		return
	# Clear existing walls and debug
	_clear_node_children_detached(layout_walls)
	_clear_node_children_detached(layout_doors)
	_clear_node_children_detached(layout_debug)
	# Random arena shape on regeneration
	var arena_rect := _random_arena_rect()
	_arena_min = arena_rect.position
	_arena_max = arena_rect.end
	if arena_boundary:
		arena_boundary.initialize(_arena_min, _arena_max)
	if wave_manager:
		wave_manager.arena_min = _arena_min
		wave_manager.arena_max = _arena_max
	# Regenerate
	var s := new_seed
	if s == 0:
		s = int(Time.get_ticks_msec()) % 999999
	_layout = _generate_layout(arena_rect, s)
	_ensure_layout_recovered(arena_rect, s)
	if layout_door_system and layout_door_system.has_method("rebuild_for_layout"):
		layout_door_system.rebuild_for_layout(_layout)
	_rebuild_walkable_floor()
	_update_layout_room_stats()
	_sync_layout_runtime_memory()
	if room_enemy_spawner:
		room_enemy_spawner.rebuild_for_layout(_layout)
	if room_nav_system and room_nav_system.has_method("rebuild_for_layout"):
		room_nav_system.rebuild_for_layout(_layout)
	_rebind_enemy_aggro_context()
	_setup_north_transition_trigger()
	_reset_camera_follow()
	_ensure_player_runtime_ready()


func _rebind_enemy_aggro_context() -> void:
	if not enemy_aggro_coordinator:
		return
	if enemy_aggro_coordinator.has_method("bind_context"):
		enemy_aggro_coordinator.bind_context(entities_container, room_nav_system, player)
		return
	if enemy_aggro_coordinator.has_method("initialize"):
		enemy_aggro_coordinator.initialize(entities_container, room_nav_system, player)


func _generate_layout(arena_rect: Rect2, seed_value: int):
	var mission := _current_mission_index()
	var attempts := 8
	var base_seed := seed_value
	var layout = null
	for i in range(attempts):
		var s := base_seed + i * 9973
		layout = PROCEDURAL_LAYOUT_V2_SCRIPT.generate_and_build(arena_rect, s, layout_walls, layout_debug, player, mission)
		if layout and layout.valid:
			if i > 0:
				print("[LevelMVP] Layout recovered on retry %d (seed=%d -> %d)" % [i + 1, seed_value, s])
			return layout
		# Cleanup failed attempt visuals before next retry.
		_clear_node_children_detached(layout_walls)
		_clear_node_children_detached(layout_debug)
	print("[LevelMVP][WARN] Layout failed after %d retries (seed=%d, mission=%d)" % [attempts, seed_value, mission])
	return layout


func _layout_has_wall_visuals() -> bool:
	if not layout_walls:
		return false
	var walls_visual := layout_walls.get_node_or_null("WallsVisual") as Node
	return walls_visual != null and walls_visual.get_child_count() > 0


func _ensure_layout_recovered(arena_rect: Rect2, seed_value: int) -> void:
	if _layout and _layout.valid and _layout_has_wall_visuals():
		return

	var recovery_seeds := [1337, 7331, 424242, seed_value + 131071]
	for recovery_seed_variant in recovery_seeds:
		var recovery_seed := int(recovery_seed_variant)
		_clear_node_children_detached(layout_walls)
		_clear_node_children_detached(layout_debug)
		var recovered: Variant = _generate_layout(arena_rect, recovery_seed)
		if recovered and recovered.valid and _layout_has_wall_visuals():
			_layout = recovered
			print("[LevelMVP] Layout recovery OK (seed=%d)" % recovery_seed)
			return

	print("[LevelMVP][WARN] Layout visuals missing after recovery; fallback floor will be shown.")


func _current_mission_index() -> int:
	if _mission_cycle.is_empty():
		return 3
	return int(_mission_cycle[clampi(_mission_cycle_pos, 0, _mission_cycle.size() - 1)])


func _sync_layout_runtime_memory() -> void:
	_layout_room_memory.clear()
	if _is_layout_v2(_layout):
		var room_memory_variant = _layout.get("room_generation_memory")
		if room_memory_variant is Array:
			_layout_room_memory = (room_memory_variant as Array).duplicate(true)
	if RuntimeState:
		RuntimeState.layout_room_memory = _layout_room_memory.duplicate(true)
		RuntimeState.mission_index = _current_mission_index()


func _is_layout_v2(layout_obj) -> bool:
	if not layout_obj:
		return false
	var script_obj: Script = layout_obj.get_script() as Script
	if not script_obj:
		return false
	return script_obj.resource_path == "res://src/systems/procedural_layout_v2.gd"


func _setup_north_transition_trigger() -> void:
	_north_transition_enabled = false
	_north_transition_rect = Rect2()
	if not _layout or not _layout.valid:
		return
	var bbox := _compute_layout_rooms_bbox()
	if bbox == Rect2():
		return
	var trigger_h := 100.0
	var trigger_y := bbox.position.y - 200.0 - trigger_h
	_north_transition_rect = Rect2(bbox.position.x, trigger_y, bbox.size.x, trigger_h)
	_north_transition_enabled = true
	print("[LevelMVP] Mission=%d transition trigger=%s" % [_current_mission_index(), str(_north_transition_rect)])


func _compute_layout_rooms_bbox() -> Rect2:
	if not _layout or not _layout.valid:
		return Rect2()
	var has_rect := false
	var bbox := Rect2()
	for i in range(_layout.rooms.size()):
		if i in _layout._void_ids:
			continue
		for rect_variant in (_layout.rooms[i]["rects"] as Array):
			var r := rect_variant as Rect2
			if not has_rect:
				bbox = r
				has_rect = true
			else:
				bbox = bbox.merge(r)
	return bbox if has_rect else Rect2()


func _check_north_transition() -> void:
	if not _north_transition_enabled:
		return
	if _north_transition_cooldown > 0.0:
		return
	if not player:
		return
	if not _is_north_transition_unlocked():
		return
	if _north_transition_rect.has_point(player.position):
		_north_transition_cooldown = 0.4
		_advance_mission_cycle()


func _is_north_transition_unlocked() -> bool:
	if not _waves_runtime_enabled():
		return _alive_scene_enemies_count() == 0
	if not wave_manager:
		return _alive_scene_enemies_count() == 0

	if wave_manager.alive_total > 0:
		return false
	if wave_manager.boss_spawned:
		return false
	if not wave_manager.wave_finished_spawning:
		return false

	var total_waves := GameConfig.waves_per_level if GameConfig else 3
	if total_waves < 1:
		total_waves = 1
	return wave_manager.wave_index >= total_waves


func _waves_runtime_enabled() -> bool:
	return WAVES_RUNTIME_ENABLED


func _alive_scene_enemies_count() -> int:
	if not get_tree():
		return 0
	var alive := 0
	for node_variant in get_tree().get_nodes_in_group("enemies"):
		var node := node_variant as Node
		if not node:
			continue
		if "is_dead" in node and bool(node.is_dead):
			continue
		alive += 1
	return alive


func _advance_mission_cycle() -> void:
	if _mission_cycle.is_empty():
		return
	_mission_cycle_pos = (_mission_cycle_pos + 1) % _mission_cycle.size()
	var next_mission := _current_mission_index()
	print("[LevelMVP] Transition -> mission %d" % next_mission)
	regenerate_layout(0)
	if EventBus:
		EventBus.emit_mission_transitioned(next_mission)


func _reset_camera_follow() -> void:
	if not player or not camera:
		return
	camera.enabled = true
	camera.make_current()
	_camera_follow_pos = player.position
	_camera_follow_initialized = true
	camera.position = _camera_follow_pos


func _ensure_player_runtime_ready() -> void:
	if not player:
		return

	player.visible = true
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.visible = true
		if sprite.modulate.a < 0.99:
			sprite.modulate = Color.WHITE

	var cb := player as CharacterBody2D
	if not cb:
		return

	if (cb.collision_mask & 1) == 0:
		cb.collision_mask |= 1

	if _is_layout_v2(_layout):
		var room_id: int = int(_layout._room_id_at_point(cb.global_position))
		var near_north_spawn := _is_near_layout_north_spawn(cb.global_position)
		var outside_bad := room_id < 0 and not near_north_spawn
		var bad_spawn: bool = outside_bad or bool(_layout._is_closet_room(room_id)) or _is_player_stuck(cb)
		if bad_spawn:
			cb.global_position = _layout.player_spawn_pos
			if cb.test_move(cb.global_transform, Vector2.ZERO) or _is_player_stuck(cb):
				var spawn_room_id := int(_layout.player_room_id)
				if spawn_room_id >= 0 and spawn_room_id < _layout.rooms.size():
					var room := _layout.rooms[spawn_room_id] as Dictionary
					var rects := room.get("rects", []) as Array
					if not rects.is_empty():
						rects.sort_custom(func(a, b): return (a as Rect2).get_area() > (b as Rect2).get_area())
						cb.global_position = (rects[0] as Rect2).get_center()

	if RuntimeState:
		RuntimeState.player_pos = Vector3(cb.global_position.x, cb.global_position.y, 0)
	_reset_camera_follow()


func _bind_enemy_toggle_hook() -> void:
	if not entities_container:
		return
	if not entities_container.child_entered_tree.is_connected(_on_entity_child_entered_enemy_toggle):
		entities_container.child_entered_tree.connect(_on_entity_child_entered_enemy_toggle)


func _on_entity_child_entered_enemy_toggle(node: Node) -> void:
	call_deferred("_apply_enemy_weapon_toggle_to_node", node)


func _apply_enemy_weapon_toggle_to_all() -> void:
	if not entities_container:
		return
	for child in entities_container.get_children():
		_apply_enemy_weapon_toggle_to_node(child)


func _apply_enemy_weapon_toggle_to_node(node: Node) -> void:
	if not node:
		return
	if not node.is_in_group("enemies"):
		return
	if "weapons_enabled" in node:
		node.weapons_enabled = _enemy_weapons_enabled


func _refresh_right_debug_hint() -> void:
	if not debug_hint_label:
		return
	debug_hint_label.text = "%s\nEnemy Guns: %s\nGod Mode: %s" % [
		RIGHT_DEBUG_HINT_BASE,
		("ON" if _enemy_weapons_enabled else "OFF"),
		("ON" if GameConfig and GameConfig.god_mode else "OFF"),
	]


func _is_player_stuck(cb: CharacterBody2D) -> bool:
	var probes := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for dir_variant in probes:
		var dir := dir_variant as Vector2
		if not cb.test_move(cb.global_transform, dir * 4.0):
			return false
	return true


func _is_near_layout_north_spawn(pos: Vector2) -> bool:
	if not _is_layout_v2(_layout):
		return false
	if _layout._entry_gate == Rect2():
		return false
	var north_target := (_layout._entry_gate as Rect2).get_center() + Vector2(0.0, -PLAYER_NORTH_SPAWN_OFFSET)
	return pos.distance_to(north_target) <= 40.0


func _cache_music_system_ref() -> MusicSystem:
	if _music_system_ref and is_instance_valid(_music_system_ref):
		return _music_system_ref
	if not get_tree():
		return null
	var root := get_tree().root
	if not root:
		return null
	_music_system_ref = root.find_child("MusicSystem", true, false) as MusicSystem
	return _music_system_ref


func _update_layout_room_stats() -> void:
	_layout_room_stats["corridors"] = 0
	_layout_room_stats["interior_rooms"] = 0
	_layout_room_stats["exterior_rooms"] = 0
	_layout_room_stats["closets"] = 0

	if not _layout or not _layout.valid:
		print("[LevelMVP] Room stats: layout invalid or disabled")
		return

	for i in range(_layout.rooms.size()):
		if i in _layout._void_ids:
			continue
		var room: Dictionary = _layout.rooms[i]
		if room["is_corridor"] == true:
			_layout_room_stats["corridors"] = int(_layout_room_stats["corridors"]) + 1
			continue
		if _layout._is_closet_room(i):
			_layout_room_stats["closets"] = int(_layout_room_stats["closets"]) + 1
			continue
		if _layout._room_touch_perimeter(i):
			_layout_room_stats["exterior_rooms"] = int(_layout_room_stats["exterior_rooms"]) + 1
		else:
			_layout_room_stats["interior_rooms"] = int(_layout_room_stats["interior_rooms"]) + 1

	print("[LevelMVP] Room stats: corr=%d inner=%d outer=%d closet=%d" % [
		int(_layout_room_stats["corridors"]),
		int(_layout_room_stats["interior_rooms"]),
		int(_layout_room_stats["exterior_rooms"]),
		int(_layout_room_stats["closets"]),
	])


## ============================================================================
## PAUSE/RESUME
## ============================================================================

## Called by AppRoot when pausing
func pause() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = true
	print("[LevelMVP] Paused")


## Called by AppRoot when resuming
func resume() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
	print("[LevelMVP] Resumed")
