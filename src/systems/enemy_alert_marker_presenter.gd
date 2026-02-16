## enemy_alert_marker_presenter.gd
## Pure visual presenter for alert marker state above enemy.
class_name EnemyAlertMarkerPresenter
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

const SUSPICIOUS_TEXTURE_PATH := "res://assets/textures/ui/markers/enemy_q_suspicious.png"
const ALERT_TEXTURE_PATH := "res://assets/textures/ui/markers/enemy_q_alert.png"
const COMBAT_TEXTURE_PATH := "res://assets/textures/ui/markers/enemy_q_combat.png"

var _marker_sprite: Sprite2D = null
var _current_level: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM
var _suspicious_texture: Texture2D = null
var _alert_texture: Texture2D = null
var _combat_texture: Texture2D = null


func setup(marker_sprite: Sprite2D) -> void:
	_marker_sprite = marker_sprite
	_ensure_textures_loaded()
	if _marker_sprite:
		_marker_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_level()


func set_alert_level(level: int) -> void:
	if _current_level == level:
		return
	_current_level = level
	_apply_level()


func update(_delta: float) -> void:
	pass


func _apply_level() -> void:
	if not _marker_sprite:
		return
	match _current_level:
		ENEMY_ALERT_LEVELS_SCRIPT.CALM:
			_marker_sprite.visible = false
			_marker_sprite.texture = null
		ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:
			_marker_sprite.texture = _suspicious_texture
			_marker_sprite.visible = true
		ENEMY_ALERT_LEVELS_SCRIPT.ALERT:
			_marker_sprite.texture = _alert_texture
			_marker_sprite.visible = true
		ENEMY_ALERT_LEVELS_SCRIPT.COMBAT:
			_marker_sprite.texture = _combat_texture
			_marker_sprite.visible = true
		_:
			_marker_sprite.visible = false
			_marker_sprite.texture = null


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
		push_warning("[EnemyAlertMarkerPresenter] Failed to load marker image: %s" % path)
		return null
	return ImageTexture.create_from_image(image)
