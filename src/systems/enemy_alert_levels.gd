## enemy_alert_levels.gd
## Shared alert level constants for room/global alert logic and visuals.
class_name EnemyAlertLevels
extends RefCounted

enum Level {
	CALM,
	SUSPICIOUS,
	ALERT,
	COMBAT,
}

const CALM := Level.CALM
const SUSPICIOUS := Level.SUSPICIOUS
const ALERT := Level.ALERT
const COMBAT := Level.COMBAT

## Visual defaults for systems/UI using room alert level.
const COLOR_CALM := Color(0.70, 0.70, 0.70, 1.0)
const COLOR_SUSPICIOUS := Color(1.00, 1.00, 1.00, 1.0)
const COLOR_ALERT := Color(1.00, 0.86, 0.24, 1.0)
const COLOR_COMBAT := Color(0.90, 0.20, 0.15, 1.0)

## Decay timings (seconds) for each non-calm level.
const SUSPICIOUS_TTL_SEC := 18.0
const ALERT_TTL_SEC := 24.0
const COMBAT_TTL_SEC := 30.0


static func ttl_for_level(level: int) -> float:
	match level:
		COMBAT:
			return _alert_cfg_float("combat_ttl_sec", COMBAT_TTL_SEC)
		ALERT:
			return _alert_cfg_float("alert_ttl_sec", ALERT_TTL_SEC)
		SUSPICIOUS:
			return _alert_cfg_float("suspicious_ttl_sec", SUSPICIOUS_TTL_SEC)
		_:
			return 0.0


static func level_name(level: int) -> String:
	match level:
		CALM:
			return "CALM"
		SUSPICIOUS:
			return "SUSPICIOUS"
		ALERT:
			return "ALERT"
		COMBAT:
			return "COMBAT"
		_:
			return "UNKNOWN"


static func visibility_decay_sec() -> float:
	return _alert_cfg_float("visibility_decay_sec", 6.0)


static func _alert_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("alert"):
		var section := GameConfig.ai_balance["alert"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
