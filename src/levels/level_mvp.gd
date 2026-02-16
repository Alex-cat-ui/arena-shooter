## level_mvp.gd
## Orchestrator for level runtime; gameplay logic is delegated to controllers.
extends Node2D

const LEVEL_CONTEXT_SCRIPT = preload("res://src/levels/level_context.gd")
const LEVEL_RUNTIME_GUARD_SCRIPT = preload("res://src/levels/level_runtime_guard.gd")
const LEVEL_INPUT_CONTROLLER_SCRIPT = preload("res://src/levels/level_input_controller.gd")
const LEVEL_HUD_CONTROLLER_SCRIPT = preload("res://src/levels/level_hud_controller.gd")
const LEVEL_CAMERA_CONTROLLER_SCRIPT = preload("res://src/levels/level_camera_controller.gd")
const LEVEL_LAYOUT_CONTROLLER_SCRIPT = preload("res://src/levels/level_layout_controller.gd")
const LEVEL_TRANSITION_CONTROLLER_SCRIPT = preload("res://src/levels/level_transition_controller.gd")
const LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT = preload("res://src/levels/level_enemy_runtime_controller.gd")
const LEVEL_EVENTS_CONTROLLER_SCRIPT = preload("res://src/levels/level_events_controller.gd")
const LEVEL_BOOTSTRAP_CONTROLLER_SCRIPT = preload("res://src/levels/level_bootstrap_controller.gd")
const STEALTH_TEST_SCENE_PATH = "res://src/levels/stealth_test_room.tscn"

# Scene refs
@onready var player: CharacterBody2D = $Entities/Player
@onready var camera: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var hp_label: Label = $HUD/HUDContainer/HPLabel
@onready var state_label: Label = $HUD/HUDContainer/StateLabel
@onready var time_label: Label = $HUD/HUDContainer/TimeLabel
@onready var weapon_label: Label = $HUD/HUDContainer/WeaponLabel
@onready var floor_root: Node2D = $Floor
@onready var floor_sprite: Sprite2D = $Floor/FloorSprite
@onready var debug_hint_label: Label = $HUD/DebugHint

# Container refs
@onready var entities_container: Node2D = $Entities
@onready var projectiles_container: Node2D = $Projectiles
@onready var decals_container: Node2D = $Decals
@onready var corpses_container: Node2D = $Corpses
@onready var footprints_container: Node2D = $Footprints

var _ctx = null

var _runtime_guard = LEVEL_RUNTIME_GUARD_SCRIPT.new()
var _input_controller = LEVEL_INPUT_CONTROLLER_SCRIPT.new()
var _hud_controller = LEVEL_HUD_CONTROLLER_SCRIPT.new()
var _camera_controller = LEVEL_CAMERA_CONTROLLER_SCRIPT.new()
var _layout_controller = LEVEL_LAYOUT_CONTROLLER_SCRIPT.new()
var _transition_controller = LEVEL_TRANSITION_CONTROLLER_SCRIPT.new()
var _enemy_runtime_controller = LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT.new()
var _events_controller = LEVEL_EVENTS_CONTROLLER_SCRIPT.new()
var _bootstrap_controller = LEVEL_BOOTSTRAP_CONTROLLER_SCRIPT.new()

# Thin compatibility proxies for legacy tests during migration.
var _mission_cycle_pos: int:
	get:
		return _ctx.mission_cycle_pos if _ctx else 0
	set(value):
		if _ctx:
			_ctx.mission_cycle_pos = value

var _north_transition_enabled: bool:
	get:
		return _ctx.north_transition_enabled if _ctx else false
	set(value):
		if _ctx:
			_ctx.north_transition_enabled = value

var _north_transition_rect: Rect2:
	get:
		return _ctx.north_transition_rect if _ctx else Rect2()
	set(value):
		if _ctx:
			_ctx.north_transition_rect = value

var _north_transition_cooldown: float:
	get:
		return _ctx.north_transition_cooldown if _ctx else 0.0
	set(value):
		if _ctx:
			_ctx.north_transition_cooldown = value


func _ready() -> void:
	print("[LevelMVP] Ready - Visual Polish Pass")

	camera.rotation = 0
	camera.enabled = true
	camera.make_current()

	_ctx = _build_context()
	_layout_controller.set_dependencies(_transition_controller, _camera_controller, _enemy_runtime_controller, _runtime_guard)

	_bootstrap_controller.init_runtime_state(_ctx, _transition_controller.current_mission_index(_ctx))
	_runtime_guard.enforce_on_start(_ctx)
	_bootstrap_controller.init_systems(
		_ctx,
		_layout_controller,
		_transition_controller,
		_camera_controller
	)
	_bootstrap_controller.init_visual_polish(_ctx, _hud_controller)

	if _ctx.player and _ctx.projectile_system:
		_ctx.player.projectile_system = _ctx.projectile_system
	if _ctx.player and _ctx.ability_system:
		_ctx.player.ability_system = _ctx.ability_system

	_ctx.start_delay_timer = GameConfig.start_delay_sec if GameConfig else 1.5
	_ctx.start_delay_finished = false

	_events_controller.bind(_ctx)
	_enemy_runtime_controller.bind_enemy_toggle_hook(_ctx)
	_enemy_runtime_controller.apply_enemy_weapon_toggle_to_all(_ctx)
	_hud_controller.cache_music_system_ref(_ctx)
	_hud_controller.refresh_right_debug_hint(_ctx)
	_hud_controller.update_hud(_ctx)

	_input_controller.configure_callbacks(
		Callable(self, "_on_regenerate_layout_requested"),
		Callable(self, "_on_toggle_enemy_weapons_requested"),
		Callable(self, "_on_toggle_god_mode_requested"),
		Callable(self, "_on_open_stealth_test_scene_requested")
	)

	print("[LevelMVP] Level bootstrap complete, start delay: %.1f sec" % _ctx.start_delay_timer)


func _build_context():
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.level = self

	ctx.player = player
	ctx.camera = camera
	ctx.hud = hud
	ctx.hp_label = hp_label
	ctx.state_label = state_label
	ctx.time_label = time_label
	ctx.weapon_label = weapon_label
	ctx.floor_root = floor_root
	ctx.floor_sprite = floor_sprite
	ctx.debug_hint_label = debug_hint_label

	ctx.entities_container = entities_container
	ctx.projectiles_container = projectiles_container
	ctx.decals_container = decals_container
	ctx.corpses_container = corpses_container
	ctx.footprints_container = footprints_container

	return ctx


func _exit_tree() -> void:
	_events_controller.unbind()
	if _ctx and _ctx.runtime_budget_controller and _ctx.runtime_budget_controller.has_method("unbind"):
		_ctx.runtime_budget_controller.unbind()
	_enemy_runtime_controller.unbind_enemy_toggle_hook()


func _process(delta: float) -> void:
	if not _ctx:
		return

	_input_controller.handle_input(_ctx)

	if RuntimeState and RuntimeState.is_frozen:
		return

	if RuntimeState:
		RuntimeState.time_elapsed += delta

	if not _ctx.start_delay_finished:
		_ctx.start_delay_timer -= delta
		if _ctx.start_delay_timer <= 0:
			_ctx.start_delay_finished = true
			print("[LevelMVP] Start delay finished")

	if _ctx.runtime_budget_controller and _ctx.runtime_budget_controller.has_method("process_frame"):
		_ctx.runtime_budget_controller.process_frame(_ctx, delta)

	if _ctx.combat_system:
		_ctx.combat_system.update(delta)
	if _ctx.footprint_system:
		_ctx.footprint_system.update(delta)

	if _ctx.vfx_system:
		_ctx.vfx_system.update_aging(delta)
	if _ctx.shadow_system:
		_ctx.shadow_system.update(delta)
	if _ctx.combat_feedback_system:
		_ctx.combat_feedback_system.update(delta)
	if _ctx.atmosphere_system:
		_ctx.atmosphere_system.update(delta)

	_camera_controller.update_follow(_ctx, delta)
	_hud_controller.update_hud(_ctx)

	if _ctx.debug_overlay_visible and _ctx.debug_container:
		_hud_controller.update_debug_overlay(_ctx)

	if _ctx.north_transition_cooldown > 0.0:
		_ctx.north_transition_cooldown = maxf(0.0, _ctx.north_transition_cooldown - delta)
	_transition_controller.check_north_transition(_ctx, Callable(self, "_on_transition_regenerate_layout"))


func _unhandled_key_input(event: InputEvent) -> void:
	if not _ctx:
		return
	_input_controller.handle_unhandled_key_input(_ctx, event)


func _on_regenerate_layout_requested() -> void:
	regenerate_layout(0)


func _on_transition_regenerate_layout() -> void:
	regenerate_layout(0)


func _on_toggle_enemy_weapons_requested() -> void:
	if not _ctx:
		return
	var is_enabled = _enemy_runtime_controller.toggle_enemy_weapons(_ctx)
	_hud_controller.refresh_right_debug_hint(_ctx)
	print("[LevelMVP] Enemy weapons: %s" % ("ON" if is_enabled else "OFF"))


func _on_toggle_god_mode_requested() -> void:
	if not GameConfig:
		return
	GameConfig.god_mode = not GameConfig.god_mode
	if _ctx:
		_hud_controller.refresh_right_debug_hint(_ctx)
	print("[LevelMVP] God mode: %s" % ("ON" if GameConfig.god_mode else "OFF"))


func _on_open_stealth_test_scene_requested() -> void:
	if not ResourceLoader.exists(STEALTH_TEST_SCENE_PATH):
		push_warning("[LevelMVP] F8 requested test scene, but it is missing: %s" % STEALTH_TEST_SCENE_PATH)
		return
	if not get_tree():
		return
	print("[LevelMVP] F8: Loading stealth test scene")
	var err := get_tree().change_scene_to_file(STEALTH_TEST_SCENE_PATH)
	if err != OK:
		push_warning("[LevelMVP] Failed to open test scene (%s), err=%d" % [STEALTH_TEST_SCENE_PATH, err])


func _apply_enemy_weapon_toggle_to_node_deferred(node: Node) -> void:
	if not _ctx:
		return
	_enemy_runtime_controller.apply_enemy_weapon_toggle_to_node(_ctx, node)


func regenerate_layout(new_seed: int = 0) -> void:
	if not _ctx:
		return
	_layout_controller.regenerate_layout(_ctx, new_seed)


func pause() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = true
	print("[LevelMVP] Paused")


func resume() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
	print("[LevelMVP] Resumed")


# Legacy wrappers kept temporarily while tests migrate to controller APIs.
func _current_mission_index() -> int:
	return _transition_controller.current_mission_index(_ctx) if _ctx else 3


func _check_north_transition() -> void:
	if not _ctx:
		return
	_transition_controller.check_north_transition(_ctx, Callable(self, "_on_transition_regenerate_layout"))


func get_current_mission_index() -> int:
	return _transition_controller.current_mission_index(_ctx) if _ctx else 3


func set_mission_cycle_position(pos: int) -> void:
	if not _ctx:
		return
	_ctx.mission_cycle_pos = clampi(pos, 0, max(_ctx.mission_cycle.size() - 1, 0))


func set_north_transition_probe(rect: Rect2, enabled: bool = true, cooldown: float = 0.0) -> void:
	if not _ctx:
		return
	_ctx.north_transition_enabled = enabled
	_ctx.north_transition_rect = rect
	_ctx.north_transition_cooldown = cooldown


func check_north_transition_gate() -> void:
	_check_north_transition()


func alive_scene_enemies_count() -> int:
	return _transition_controller.alive_scene_enemies_count(_ctx) if _ctx else 0


func is_north_transition_unlocked() -> bool:
	return _transition_controller.is_north_transition_unlocked(_ctx) if _ctx else false
