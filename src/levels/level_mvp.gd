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
var layout_debug: Node2D = null
var _layout: ProceduralLayout = null
var _walkable_floor: Node2D = null

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


func _ready() -> void:
	print("[LevelMVP] Ready - Visual Polish Pass")

	# CANON: Camera must not rotate
	camera.rotation = 0

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


func _random_arena_rect() -> Rect2:
	var preset := randi() % 3
	var cx := 0.0
	var cy := 0.0
	if preset == ArenaPreset.SQUARE:
		var s := randf_range(2100.0, 2700.0)
		return Rect2(cx - s * 0.5, cy - s * 0.5, s, s)
	elif preset == ArenaPreset.LANDSCAPE:
		var h := randf_range(1650.0, 2100.0)
		var w := h * randf_range(1.3, 1.6)
		return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)
	else:  # PORTRAIT
		var w := randf_range(1650.0, 2100.0)
		var h := w * randf_range(1.3, 1.6)
		return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)


func _init_systems() -> void:
	# Create WaveManager
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	wave_manager.enemy_scene = ENEMY_SCENE
	wave_manager.boss_scene = BOSS_SCENE  # Phase 2: boss scene
	wave_manager.entities_container = entities_container
	# Set arena bounds based on floor size
	wave_manager.arena_min = _arena_min
	wave_manager.arena_max = _arena_max
	add_child(wave_manager)

	# Initialize WaveManager with waves count from config
	var total_waves: int = GameConfig.waves_per_level if GameConfig else 3
	wave_manager.initialize(total_waves)

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

	# Phase 3: Create WaveOverlay
	wave_overlay = WaveOverlay.new()
	wave_overlay.name = "WaveOverlay"
	add_child(wave_overlay)

	# Phase 3: Create ArenaBoundary (added before Entities for z-ordering)
	arena_boundary = ArenaBoundary.new()
	arena_boundary.name = "ArenaBoundary"
	arena_boundary.z_index = -1  # Behind entities
	add_child(arena_boundary)
	# Random arena shape
	if GameConfig and GameConfig.procedural_layout_enabled:
		var arena_rect := _random_arena_rect()
		_arena_min = arena_rect.position
		_arena_max = arena_rect.end
		arena_boundary.initialize(_arena_min, _arena_max)
		wave_manager.arena_min = _arena_min
		wave_manager.arena_max = _arena_max
	else:
		arena_boundary.initialize(_arena_min, _arena_max)

	# Procedural layout
	layout_walls = Node2D.new()
	layout_walls.name = "LayoutWalls"
	add_child(layout_walls)
	layout_debug = Node2D.new()
	layout_debug.name = "LayoutDebug"
	layout_debug.z_index = 100
	add_child(layout_debug)
	_ensure_walkable_floor_node()

	if GameConfig and GameConfig.procedural_layout_enabled:
		var arena_rect := Rect2(_arena_min, _arena_max - _arena_min)
		var s: int = GameConfig.layout_seed
		if s == 0:
			s = int(Time.get_ticks_msec()) % 999999
		_layout = ProceduralLayout.generate_and_build(arena_rect, s, layout_walls, layout_debug, player)
	_rebuild_walkable_floor()

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
	for child in _walkable_floor.get_children():
		child.queue_free()


func _rebuild_walkable_floor() -> void:
	if not floor_sprite:
		return
	_ensure_walkable_floor_node()
	_clear_walkable_floor()

	if not _layout or not _layout.valid:
		floor_sprite.visible = true
		return

	if not floor_sprite.texture:
		floor_sprite.visible = true
		return

	floor_sprite.visible = false
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
			patch.texture = floor_sprite.texture
			patch.texture_filter = floor_sprite.texture_filter
			patch.texture_repeat = floor_sprite.texture_repeat
			patch.scale = floor_sprite.scale
			patch.centered = true
			patch.region_enabled = true
			patch.position = r.get_center()
			patch.region_rect = Rect2(
				r.position.x / sx,
				r.position.y / sy,
				r.size.x / sx,
				r.size.y / sy
			)
			_walkable_floor.add_child(patch)


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
	# Subtle dark overlay on floor for readability
	_floor_overlay = ColorRect.new()
	_floor_overlay.name = "FloorOverlay"
	_floor_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_alpha := GameConfig.floor_overlay_alpha if GameConfig else 0.15
	_floor_overlay.color = Color(0, 0, 0, overlay_alpha)
	# Position over arena floor (world space)
	_floor_overlay.position = _arena_min
	_floor_overlay.size = _arena_max - _arena_min
	# Add as Node2D child (not CanvasLayer) so it's in world space
	var overlay_node := Node2D.new()
	overlay_node.name = "FloorOverlayNode"
	overlay_node.z_index = -8  # Above floor decals, below blood
	add_child(overlay_node)
	# Use a Sprite2D with generated texture instead for world-space overlay
	var overlay_sprite := Sprite2D.new()
	var arena_w := int(_arena_max.x - _arena_min.x)
	var arena_h := int(_arena_max.y - _arena_min.y)
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, overlay_alpha))
	overlay_sprite.texture = ImageTexture.create_from_image(img)
	overlay_sprite.scale = Vector2(arena_w, arena_h)
	overlay_sprite.position = (_arena_min + _arena_max) / 2.0
	overlay_node.add_child(overlay_sprite)
	# Remove the ColorRect since we're using world-space sprite
	_floor_overlay.queue_free()
	_floor_overlay = null


func _create_debug_overlay() -> void:
	_debug_container = VBoxContainer.new()
	_debug_container.name = "DebugOverlay"
	_debug_container.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_debug_container.anchor_bottom = 1.0
	_debug_container.offset_left = 10.0
	_debug_container.offset_bottom = -10.0
	_debug_container.offset_top = -120.0
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
	if time_label:
		time_label.add_theme_color_override("font_color", dim_color)
	if boss_hp_label:
		boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0, 1.0))
	if weapon_label:
		weapon_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.9))


func _subscribe_to_events() -> void:
	if EventBus:
		EventBus.wave_started.connect(_on_wave_started)
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.player_died.connect(_on_player_died)
		EventBus.all_waves_completed.connect(_on_all_waves_completed)
		# Phase 2: Boss events
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
			print("[LevelMVP] Start delay finished, waves beginning")
			if EventBus:
				EventBus.emit_start_delay_finished()

	# Update systems
	if wave_manager and (GameConfig.waves_enabled if GameConfig else true):
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
		camera.position = player.position
		camera.rotation = 0  # Ensure no rotation
		# Phase 3: Apply camera shake
		if camera_shake:
			camera_shake.update(delta)

	# Update HUD
	_update_hud()

	# Update debug overlay
	if _debug_overlay_visible and _debug_container:
		_update_debug_overlay()


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
		var wave_text := "Wave: %d" % RuntimeState.current_wave
		if wave_manager:
			wave_text += " / %d" % (GameConfig.waves_per_level if GameConfig else 3)
			if RuntimeState.current_wave > 0:
				wave_text += " (Alive: %d)" % wave_manager.alive_total
		wave_label.text = wave_text

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


## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_wave_started(wave_index: int, wave_size: int) -> void:
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
	# Phase 2: Don't trigger LEVEL_COMPLETE here - boss must be killed first
	print("[LevelMVP] All waves completed! Waiting for boss...")


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
	for child in layout_walls.get_children():
		child.queue_free()
	for child in layout_debug.get_children():
		child.queue_free()
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
	_layout = ProceduralLayout.generate_and_build(arena_rect, s, layout_walls, layout_debug, player)
	_rebuild_walkable_floor()


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
