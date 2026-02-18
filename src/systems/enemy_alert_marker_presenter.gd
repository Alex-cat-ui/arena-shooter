## enemy_alert_marker_presenter.gd
## Pure visual presenter for alert marker state above enemy.
## Mapping: SUSPICIOUS -> ? (white), ALERT -> ! (yellow), COMBAT -> ! (red).
class_name EnemyAlertMarkerPresenter
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

const SUSPICIOUS_TEXTURE_PATH := "res://assets/textures/ui/markers/enemy_q_suspicious.png"
const ALERT_TEXTURE_PATH := "res://assets/textures/ui/markers/enemy_excl_alert.png"
const COMBAT_TEXTURE_PATH := "res://assets/textures/ui/markers/enemy_excl_combat.png"

var _marker_sprite: Sprite2D = null
var _current_level: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _suspicious_texture: Texture2D = null
var _alert_texture: Texture2D = null
var _combat_texture: Texture2D = null
var _warnings_enabled: bool = true


func set_warnings_enabled(enabled: bool) -> void:
	_warnings_enabled = enabled


func setup(marker_sprite: Sprite2D) -> void:
	_marker_sprite = marker_sprite
	_ensure_textures_loaded()
	if _marker_sprite:
		_marker_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_level(_current_level, _marker_sprite)


func set_alert_level(level: int) -> void:
	if _current_level == level:
		return
	_current_level = level
	_apply_level(_current_level, _marker_sprite)


func update(_delta: float) -> void:
	pass


func update_from_snapshot(snap: Dictionary, sprite_node: Sprite2D) -> void:
	if sprite_node == null:
		return
	_ensure_textures_loaded()
	var state: int = int(snap.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	var hostile_contact: bool = bool(snap.get("hostile_contact", false))
	var hostile_damaged: bool = bool(snap.get("hostile_damaged", false))
	var is_hostile := hostile_contact or hostile_damaged

	if is_hostile:
		# Always show "!" once hostile; never disappears until death/reset.
		_apply_hostile_marker(sprite_node)
		return

	# Normal state-based display.
	_apply_level(state, sprite_node)


func _apply_level(level: int, sprite_node: Sprite2D) -> void:
	if sprite_node == null:
		return
	match level:
		ENEMY_ALERT_LEVELS_SCRIPT.CALM:
			sprite_node.visible = false
			sprite_node.texture = null
		ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:
			_set_texture_safe(sprite_node, _suspicious_texture, "SUSPICIOUS")
		ENEMY_ALERT_LEVELS_SCRIPT.ALERT:
			_set_texture_safe(sprite_node, _alert_texture, "ALERT")
		ENEMY_ALERT_LEVELS_SCRIPT.COMBAT:
			_set_texture_safe(sprite_node, _combat_texture, "COMBAT")
		_:
			sprite_node.visible = false
			sprite_node.texture = null


func _apply_hostile_marker(sprite_node: Sprite2D) -> void:
	sprite_node.visible = true
	if _combat_texture != null:
		sprite_node.texture = _combat_texture
	else:
		sprite_node.texture = null
		sprite_node.visible = false
		_warn("[EnemyAlertMarkerPresenter] Missing texture for hostile marker")


func _set_texture_safe(sprite_node: Sprite2D, tex: Texture2D, level_name: String) -> void:
	if tex != null:
		sprite_node.texture = tex
		sprite_node.visible = true
	else:
		_warn("[EnemyAlertMarkerPresenter] Missing texture for %s — hiding marker" % level_name)
		sprite_node.visible = false
		sprite_node.texture = null


func _ensure_textures_loaded() -> void:
	if _suspicious_texture == null:
		_suspicious_texture = _load_texture(SUSPICIOUS_TEXTURE_PATH)
	if _alert_texture == null:
		_alert_texture = _load_texture(ALERT_TEXTURE_PATH)
	if _combat_texture == null:
		_combat_texture = _load_texture(COMBAT_TEXTURE_PATH)


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_warn("[EnemyAlertMarkerPresenter] Failed to load marker image: %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _warn(message: String) -> void:
	if _warnings_enabled:
		push_warning(message)
