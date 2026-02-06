## wave_overlay.gd
## Full-screen overlay for "WAVE X" announcements.
## CANON: Triggered on EventBus.wave_started.
## CANON: Fade-in/out animation + optional screen flash.
class_name WaveOverlay
extends CanvasLayer

## Label for wave text
var _label: Label = null

## Flash rect for screen flash
var _flash_rect: ColorRect = null

## Active tween references
var _label_tween: Tween = null
var _flash_tween: Tween = null


func _ready() -> void:
	layer = 10  # Above HUD (layer 5)

	# Create full-screen flash rect
	_flash_rect = ColorRect.new()
	_flash_rect.name = "FlashRect"
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	# Create centered wave label
	_label = Label.new()
	_label.name = "WaveLabel"
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 48)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Show wave announcement with animation
func show_wave(wave_index: int) -> void:
	_label.text = "WAVE %d" % wave_index

	# Kill existing tweens
	if _label_tween and _label_tween.is_valid():
		_label_tween.kill()
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	# Label animation: fade in 0.3s, hold 0.8s, fade out 0.4s
	_label.modulate.a = 0.0
	_label.scale = Vector2(0.8, 0.8)
	_label_tween = create_tween()
	_label_tween.set_parallel(true)
	_label_tween.tween_property(_label, "modulate:a", 1.0, 0.3)
	_label_tween.tween_property(_label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_label_tween.set_parallel(false)
	_label_tween.tween_interval(0.8)
	_label_tween.tween_property(_label, "modulate:a", 0.0, 0.4)

	# Screen flash: subtle white flash
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.12, 0.05)
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, 0.25)
