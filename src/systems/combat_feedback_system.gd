## combat_feedback_system.gd
## CombatFeedbackSystem - visual hit/kill/damage feedback effects.
## CANON: Pure visual, no gameplay impact.
## CANON: Pooled nodes, spawn once per event, auto cleanup.
class_name CombatFeedbackSystem
extends Node

## Directional damage arc container (CanvasLayer child)
var _damage_arc_container: CanvasLayer = null

## Edge kill pulse container
var _edge_pulse_container: CanvasLayer = null

## Active feedback effects
var _active_effects: Array[Dictionary] = []

## Pool of ColorRect nodes for damage arcs
var _arc_pool: Array[ColorRect] = []

## Pool for edge pulse
var _pulse_pool: Array[ColorRect] = []

const ARC_POOL_SIZE := 4
const PULSE_POOL_SIZE := 4
const ARC_NAME_PREFIX := "CombatDamageArc_"
const PULSE_NAME_PREFIX := "CombatEdgePulse_"
const OVERLAY_META_KEY := "overlay_type"
const OVERLAY_ARC := "combat_feedback_arc"
const OVERLAY_PULSE := "combat_feedback_pulse"

var _initialized: bool = false


## Initialize
func initialize(hud_layer: CanvasLayer) -> void:
	if hud_layer == null:
		return
	_damage_arc_container = hud_layer
	_edge_pulse_container = hud_layer
	if _initialized:
		return
	_arc_pool.clear()
	_pulse_pool.clear()
	_active_effects.clear()

	# Create damage arc pool (directional red overlay)
	for i in range(ARC_POOL_SIZE):
		var rect_name := "%s%d" % [ARC_NAME_PREFIX, i]
		var rect := hud_layer.get_node_or_null(rect_name) as ColorRect
		if rect == null:
			rect = ColorRect.new()
			rect.name = rect_name
			hud_layer.add_child(rect)
		rect.set_meta(OVERLAY_META_KEY, OVERLAY_ARC)
		rect.color = Color(1.0, 0.0, 0.0, 0.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		rect.anchors_preset = Control.PRESET_FULL_RECT
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		_arc_pool.append(rect)
	_prune_overlay_duplicates(hud_layer, OVERLAY_ARC, ARC_NAME_PREFIX, _arc_pool)

	# Create edge pulse pool (kill flash)
	for i in range(PULSE_POOL_SIZE):
		var rect_name := "%s%d" % [PULSE_NAME_PREFIX, i]
		var rect := hud_layer.get_node_or_null(rect_name) as ColorRect
		if rect == null:
			rect = ColorRect.new()
			rect.name = rect_name
			hud_layer.add_child(rect)
		rect.set_meta(OVERLAY_META_KEY, OVERLAY_PULSE)
		rect.color = Color(1.0, 1.0, 1.0, 0.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		rect.anchors_preset = Control.PRESET_FULL_RECT
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		_pulse_pool.append(rect)
	_prune_overlay_duplicates(hud_layer, OVERLAY_PULSE, PULSE_NAME_PREFIX, _pulse_pool)

	# Subscribe to events
	if EventBus:
		if not EventBus.player_damaged.is_connected(_on_player_damaged):
			EventBus.player_damaged.connect(_on_player_damaged)
		if not EventBus.enemy_killed.is_connected(_on_enemy_killed):
			EventBus.enemy_killed.connect(_on_enemy_killed)
	_initialized = true

	print("[CombatFeedbackSystem] Initialized")


func _prune_overlay_duplicates(hud_layer: CanvasLayer, overlay_type: String, name_prefix: String, keep_nodes: Array[ColorRect]) -> void:
	for child_variant in hud_layer.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		var rect := child as ColorRect
		if rect == null:
			continue
		if keep_nodes.has(rect):
			continue
		var by_meta := String(rect.get_meta(OVERLAY_META_KEY, "")) == overlay_type
		var by_name := rect.name.begins_with(name_prefix)
		if by_meta or by_name:
			rect.queue_free()


## Update called each frame
func update(delta: float) -> void:
	var i := 0
	while i < _active_effects.size():
		var entry: Dictionary = _active_effects[i]
		entry["time_left"] -= delta
		if entry["time_left"] <= 0:
			var node: CanvasItem = entry["node"]
			node.visible = false
			_active_effects.remove_at(i)
			continue
		else:
			# Fade out
			var ratio: float = float(entry["time_left"]) / float(entry["max_time"])
			var node: CanvasItem = entry["node"]
			if node is ColorRect:
				(node as ColorRect).color.a = float(entry["base_alpha"]) * ratio
		i += 1


## Spawn directional damage arc overlay
func _on_player_damaged(_amount: int, _new_hp: int, _source: String) -> void:
	var duration := GameConfig.damage_arc_duration if GameConfig else 0.12
	var alpha := 0.2

	# Get a pooled arc
	var rect: ColorRect = null
	for r in _arc_pool:
		if not r.visible:
			rect = r
			break
	if not rect:
		return

	rect.color = Color(1.0, 0.0, 0.0, alpha)
	rect.visible = true

	_active_effects.append({
		"node": rect,
		"time_left": duration,
		"max_time": duration,
		"base_alpha": alpha,
	})


## Spawn subtle edge pulse on kill
func _on_enemy_killed(_enemy_id: int, _enemy_type: String) -> void:
	var alpha := GameConfig.kill_edge_pulse_alpha if GameConfig else 0.15
	var duration := GameConfig.kill_pop_duration if GameConfig else 0.1

	# Get a pooled pulse
	var rect: ColorRect = null
	for r in _pulse_pool:
		if not r.visible:
			rect = r
			break
	if not rect:
		return

	rect.color = Color(1.0, 1.0, 1.0, alpha)
	rect.visible = true

	_active_effects.append({
		"node": rect,
		"time_left": duration,
		"max_time": duration,
		"base_alpha": alpha,
	})
