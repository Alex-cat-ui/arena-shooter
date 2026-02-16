## level_setup.gd
## Level setup screen - configure level parameters before starting.
## CANON: UI changes ONLY GameConfig. Cannot start if validation fails.
extends Control

@onready var delay_spinbox: SpinBox = $VBoxContainer/DelayContainer/DelaySpinBox
@onready var max_enemies_spinbox: SpinBox = $VBoxContainer/MaxEnemiesContainer/MaxEnemiesSpinBox
@onready var start_button: Button = $VBoxContainer/ButtonContainer/StartButton
@onready var validation_label: Label = $VBoxContainer/ValidationLabel


func _ready() -> void:
	print("[LevelSetup] Ready")
	_load_current_values()
	_validate_config()


func _load_current_values() -> void:
	if GameConfig:
		delay_spinbox.value = GameConfig.start_delay_sec
		max_enemies_spinbox.value = GameConfig.max_alive_enemies


func _validate_config() -> void:
	var result := ConfigValidator.validate()

	if result.is_valid:
		validation_label.text = "Configuration OK"
		validation_label.modulate = Color.GREEN
		start_button.disabled = false
	else:
		validation_label.text = "Errors: " + ", ".join(result.errors)
		validation_label.modulate = Color.RED
		start_button.disabled = true

	# Show warnings even if valid
	if result.warnings.size() > 0 and result.is_valid:
		validation_label.text += "\nWarnings: " + ", ".join(result.warnings)
		validation_label.modulate = Color.YELLOW


func _on_delay_spin_box_value_changed(value: float) -> void:
	if GameConfig:
		GameConfig.start_delay_sec = value
		_validate_config()


func _on_max_enemies_spin_box_value_changed(value: float) -> void:
	if GameConfig:
		GameConfig.max_alive_enemies = int(value)
		_validate_config()


func _on_start_button_pressed() -> void:
	# Final validation before start
	var result := ConfigValidator.validate()
	if not result.is_valid:
		# Clamp values and retry
		ConfigValidator.clamp_values()
		_load_current_values()
		_validate_config()
		return

	if StateManager:
		StateManager.change_state(GameState.State.PLAYING)


func _on_back_button_pressed() -> void:
	if StateManager:
		StateManager.change_state(GameState.State.MAIN_MENU)


func _on_reset_button_pressed() -> void:
	if GameConfig:
		GameConfig.reset_to_defaults()
		_load_current_values()
		_validate_config()
