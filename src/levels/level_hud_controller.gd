extends RefCounted
class_name LevelHUDController

const RIGHT_DEBUG_HINT_BASE = "ESC - Pause | F1 - Game Over\nF2 - Level Complete | F3 - Debug\nF4 - Regenerate | F8 - Test Scene\nLMB - Shoot | 1-2 Weapons | Wheel\nE/У - Door Interact | Q - Door Kick"
const OVERLAY_META_KEY := "overlay_type"
const OVERLAY_VIGNETTE := "vignette"
const OVERLAY_DEBUG := "debug_overlay"


func create_vignette(ctx) -> void:
	if not ctx.hud:
		return
	var vignette := _find_overlay_control(ctx.hud, "Vignette", OVERLAY_VIGNETTE) as ColorRect
	if vignette == null:
		vignette = ColorRect.new()
		vignette.name = "Vignette"
		vignette.set_meta(OVERLAY_META_KEY, OVERLAY_VIGNETTE)
		ctx.hud.add_child(vignette)
	_prune_overlay_duplicates(ctx.hud, OVERLAY_VIGNETTE, vignette)
	ctx.vignette_rect = vignette
	ctx.vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx.vignette_rect.anchors_preset = Control.PRESET_FULL_RECT
	ctx.vignette_rect.anchor_right = 1.0
	ctx.vignette_rect.anchor_bottom = 1.0
	var alpha = GameConfig.vignette_alpha if GameConfig else 0.3
	ctx.vignette_rect.color = Color(0, 0, 0, alpha * 0.3)
	ctx.hud.move_child(ctx.vignette_rect, 0)


func create_floor_overlay(ctx) -> void:
	ctx.floor_overlay = null


func create_debug_overlay(ctx) -> void:
	if not ctx.hud:
		return
	if ctx.level and ctx.level.get_node_or_null("DebugUI"):
		ctx.debug_container = null
		return
	var debug_container := _find_overlay_control(ctx.hud, "DebugOverlay", OVERLAY_DEBUG) as VBoxContainer
	if debug_container == null:
		debug_container = VBoxContainer.new()
		debug_container.name = "DebugOverlay"
		debug_container.set_meta(OVERLAY_META_KEY, OVERLAY_DEBUG)
		ctx.hud.add_child(debug_container)
	_prune_overlay_duplicates(ctx.hud, OVERLAY_DEBUG, debug_container)
	ctx.debug_container = debug_container
	ctx.debug_container.anchors_preset = Control.PRESET_BOTTOM_LEFT
	ctx.debug_container.anchor_bottom = 1.0
	ctx.debug_container.offset_left = 10.0
	ctx.debug_container.offset_bottom = -10.0
	ctx.debug_container.offset_top = -145.0
	ctx.debug_container.offset_right = 400.0
	ctx.debug_container.visible = ctx.debug_overlay_visible

	_add_debug_label_if_missing(ctx, "FPSLabel")
	_add_debug_label_if_missing(ctx, "EntitiesLabel")
	_add_debug_label_if_missing(ctx, "DecalsLabel")
	_add_debug_label_if_missing(ctx, "FloorLabel")
	_add_debug_label_if_missing(ctx, "LayoutLabel")
	_add_debug_label_if_missing(ctx, "RoomTypesLabel")
	_add_debug_label_if_missing(ctx, "MusicLabel")


func _add_debug_label_if_missing(ctx, name: String) -> void:
	if not ctx.debug_container:
		return
	if ctx.debug_container.get_node_or_null(name):
		return
	_add_debug_label(ctx, name)


func _add_debug_label(ctx, name: String) -> void:
	var label = Label.new()
	label.name = name
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	ctx.debug_container.add_child(label)


func _find_overlay_control(parent: Node, node_name: String, overlay_type: String) -> Control:
	if not parent:
		return null
	var node_by_name := parent.get_node_or_null(node_name)
	if node_by_name and node_by_name is Control:
		var control := node_by_name as Control
		control.set_meta(OVERLAY_META_KEY, overlay_type)
		return control
	for child_variant in parent.get_children():
		var child := child_variant as Node
		if child == null or not (child is Control):
			continue
		if String(child.get_meta(OVERLAY_META_KEY, "")) == overlay_type:
			var control := child as Control
			control.name = node_name
			return control
	return null


func _prune_overlay_duplicates(parent: Node, overlay_type: String, keep_node: Control) -> void:
	if not parent or not keep_node:
		return
	for child_variant in parent.get_children():
		var child := child_variant as Node
		if child == null or child == keep_node:
			continue
		if String(child.get_meta(OVERLAY_META_KEY, "")) == overlay_type:
			child.queue_free()


func create_momentum_placeholder(ctx) -> void:
	if not ctx.hud:
		return
	var hud_container = ctx.hud.get_node_or_null("HUDContainer") as VBoxContainer
	if not hud_container:
		return
	ctx.momentum_label = Label.new()
	ctx.momentum_label.name = "MomentumLabel"
	ctx.momentum_label.text = "Momentum: 0"
	ctx.momentum_label.visible = false
	hud_container.add_child(ctx.momentum_label)


func style_hud_labels(ctx) -> void:
	if ctx.hp_label:
		ctx.hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))

	var dim_color = Color(0.6, 0.6, 0.6, 0.8)
	if ctx.state_label:
		ctx.state_label.add_theme_color_override("font_color", dim_color)
	if ctx.time_label:
		ctx.time_label.add_theme_color_override("font_color", dim_color)
	if ctx.weapon_label:
		ctx.weapon_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.9))


func update_hud(ctx) -> void:
	if not RuntimeState:
		return

	if ctx.hp_label:
		ctx.hp_label.text = "HP: %d / %d" % [RuntimeState.player_hp, GameConfig.player_max_hp if GameConfig else 100]

	if ctx.state_label and StateManager:
		var state_text = GameState.state_to_string(StateManager.current_state)
		if not ctx.start_delay_finished and StateManager.is_playing():
			state_text += " (%.1f)" % ctx.start_delay_timer
		ctx.state_label.text = "State: %s" % state_text

	if ctx.time_label:
		ctx.time_label.text = "Time: %.1f | Kills: %d" % [RuntimeState.time_elapsed, RuntimeState.kills]

	if ctx.weapon_label and ctx.ability_system:
		var weapon_count := 0
		if ctx.ability_system.has_method("get_weapon_list"):
			weapon_count = (ctx.ability_system.get_weapon_list() as Array).size()
		weapon_count = maxi(weapon_count, 1)
		ctx.weapon_label.text = "GUN %s [%d/%d]" % [
			ctx.ability_system.get_current_weapon().to_upper(),
			ctx.ability_system.current_weapon_index + 1,
			weapon_count
		]


func update_debug_overlay(ctx) -> void:
	if not ctx.debug_container:
		return

	var fps_label = ctx.debug_container.get_node_or_null("FPSLabel") as Label
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	var entities_label = ctx.debug_container.get_node_or_null("EntitiesLabel") as Label
	if entities_label:
		var enemy_count = ctx.level.get_tree().get_nodes_in_group("enemies").size() if ctx.level and ctx.level.get_tree() else 0
		var projectile_count = ctx.projectiles_container.get_child_count() if ctx.projectiles_container else 0
		entities_label.text = "Enemies: %d | Projectiles: %d" % [enemy_count, projectile_count]

	var decals_label = ctx.debug_container.get_node_or_null("DecalsLabel") as Label
	if decals_label:
		var blood = ctx.decals_container.get_child_count() if ctx.decals_container else 0
		var corpses = ctx.vfx_system.get_total_corpse_count() if ctx.vfx_system else 0
		var fp_total: int = ctx.footprint_system.get_spawned_total() if ctx.footprint_system else 0
		var fp_charges: int = ctx.footprint_system.get_blood_charges() if ctx.footprint_system else 0
		var fp_on_blood: bool = ctx.footprint_system.last_on_blood if ctx.footprint_system else false
		var fp_on_corpse: bool = ctx.footprint_system.last_on_corpse if ctx.footprint_system else false
		decals_label.text = "Blood: %d | Corpses: %d | FP tot=%d blood=%d corpse=%d charges=%d" % [blood, corpses, fp_total, int(fp_on_blood), int(fp_on_corpse), fp_charges]

	var floor_label = ctx.debug_container.get_node_or_null("FloorLabel") as Label
	if floor_label:
		var atmo_particles = 0
		if ctx.atmosphere_system and ctx.atmosphere_system.has_method("get_particle_count"):
			atmo_particles = ctx.atmosphere_system.get_particle_count()
		var atmo_decals = 0
		if ctx.atmosphere_system and ctx.atmosphere_system.has_method("get_decal_count"):
			atmo_decals = ctx.atmosphere_system.get_decal_count()
		floor_label.text = "Floor: dirt_grass_01 | Particles: %d | Decals: %d" % [atmo_particles, atmo_decals]

	if GameConfig and GameConfig.layout_debug_text:
		var layout_label = ctx.debug_container.get_node_or_null("LayoutLabel") as Label
		if layout_label:
			if ctx.layout and ctx.layout.valid:
				layout_label.text = "Layout: seed=%d rooms=%d corr=%d doors=%d mode=%s hubs=%d voids=%d avg_deg=%.1f max_d=%d loops=%d iso=%d [F4=regen]" % [
					ctx.layout.layout_seed,
					ctx.layout.rooms.size(),
					ctx.layout.corridors.size(),
					ctx.layout.doors.size(),
					ctx.layout.layout_mode_name,
					ctx.layout._hub_ids.size(),
					ctx.layout._void_ids.size(),
					ctx.layout.avg_degree,
					ctx.layout.max_doors_stat,
					ctx.layout.extra_loops,
					ctx.layout.isolated_fixed,
				]
			elif ctx.layout:
				layout_label.text = "Layout: INVALID [F4=regen]"
			else:
				layout_label.text = "Layout: disabled"

	var room_types_label = ctx.debug_container.get_node_or_null("RoomTypesLabel") as Label
	if room_types_label:
		room_types_label.text = "RoomTypes: corr=%d | inner=%d | outer=%d | closet=%d" % [
			int(ctx.layout_room_stats["corridors"]),
			int(ctx.layout_room_stats["interior_rooms"]),
			int(ctx.layout_room_stats["exterior_rooms"]),
			int(ctx.layout_room_stats["closets"]),
		]

	var music_label = ctx.debug_container.get_node_or_null("MusicLabel") as Label
	if music_label:
		var music_system = cache_music_system_ref(ctx)
		if music_system:
			music_label.text = "Music: %s | %s" % [
				music_system.get_current_context_name(),
				music_system.get_current_track_name(),
			]
		else:
			music_label.text = "Music: offline"


func refresh_right_debug_hint(ctx) -> void:
	if not ctx.debug_hint_label:
		return
	ctx.debug_hint_label.text = "%s\nGod Mode: %s" % [
		RIGHT_DEBUG_HINT_BASE,
		("ON" if GameConfig and GameConfig.god_mode else "OFF"),
	]


func cache_music_system_ref(ctx) -> MusicSystem:
	if ctx.music_system_ref and is_instance_valid(ctx.music_system_ref):
		return ctx.music_system_ref
	if not ctx.level or not ctx.level.get_tree():
		return null
	var root = ctx.level.get_tree().root
	if not root:
		return null
	ctx.music_system_ref = root.find_child("MusicSystem", true, false) as MusicSystem
	return ctx.music_system_ref
