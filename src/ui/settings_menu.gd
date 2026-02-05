## settings_menu.gd
## Settings menu screen.
## CANON: UI changes ONLY GameConfig.
## CANON: Settings only modifiable when NOT in PLAYING state.
extends Control

@onready var god_mode_check: CheckBox = $VBoxContainer/GodModeContainer/GodModeCheck
@onready var music_slider: HSlider = $VBoxContainer/MusicContainer/MusicSlider
@onready var music_value_label: Label = $VBoxContainer/MusicContainer/MusicValue
@onready var sfx_slider: HSlider = $VBoxContainer/SFXContainer/SFXSlider
@onready var sfx_value_label: Label = $VBoxContainer/SFXContainer/SFXValue


func _ready() -> void:
	print("[SettingsMenu] Ready")
	_load_current_values()


func _load_current_values() -> void:
	if GameConfig:
		god_mode_check.button_pressed = GameConfig.god_mode
		music_slider.value = GameConfig.music_volume
		sfx_slider.value = GameConfig.sfx_volume
		_update_music_label()
		_update_sfx_label()


func _update_music_label() -> void:
	music_value_label.text = "%.0f%%" % (music_slider.value * 100)


func _update_sfx_label() -> void:
	sfx_value_label.text = "%.0f%%" % (sfx_slider.value * 100)


func _on_god_mode_check_toggled(toggled_on: bool) -> void:
	if GameConfig:
		GameConfig.god_mode = toggled_on
		print("[SettingsMenu] God mode: %s" % toggled_on)


func _on_music_slider_value_changed(value: float) -> void:
	if GameConfig:
		GameConfig.music_volume = value
		_update_music_label()


func _on_sfx_slider_value_changed(value: float) -> void:
	if GameConfig:
		GameConfig.sfx_volume = value
		_update_sfx_label()


func _on_back_button_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.MAIN_MENU)
