class_name BloodEvidenceSystem
extends Node

const DEFAULT_BLOOD_EVIDENCE_TTL_SEC := 90.0
const DEFAULT_BLOOD_EVIDENCE_DETECTION_RADIUS_PX := 150.0

var entities_container: Node = null
var _evidence_entries: Array[Dictionary] = []


func initialize(p_entities_container: Node) -> void:
	entities_container = p_entities_container


func _ready() -> void:
	if not EventBus or not EventBus.has_signal("blood_spawned"):
		return
	if EventBus.blood_spawned.is_connected(_on_blood_spawned):
		return
	EventBus.blood_spawned.connect(_on_blood_spawned)


func _on_blood_spawned(position: Vector3, _size: float) -> void:
	var ttl_sec := float(GameConfig.blood_evidence_ttl_sec) if GameConfig else DEFAULT_BLOOD_EVIDENCE_TTL_SEC
	_evidence_entries.append({
		"pos_x": position.x,
		"pos_y": position.y,
		"age_sec": 0.0,
		"ttl_sec": ttl_sec,
		"triggered_ids": {},
	})


func _process(delta: float) -> void:
	if _evidence_entries.is_empty():
		return
	var dt := maxf(delta, 0.0)
	for i in range(_evidence_entries.size()):
		var entry := _evidence_entries[i] as Dictionary
		entry["age_sec"] = float(entry.get("age_sec", 0.0)) + dt
	for i in range(_evidence_entries.size() - 1, -1, -1):
		var entry := _evidence_entries[i] as Dictionary
		if float(entry.get("age_sec", 0.0)) >= float(entry.get("ttl_sec", 0.0)):
			_evidence_entries.remove_at(i)
	for entry_variant in _evidence_entries:
		_notify_nearby_enemies(entry_variant as Dictionary)


func _notify_nearby_enemies(entry: Dictionary) -> void:
	if entities_container == null:
		return
	var evidence_pos := Vector2(float(entry.get("pos_x", 0.0)), float(entry.get("pos_y", 0.0)))
	var radius := float(GameConfig.blood_evidence_detection_radius_px) if GameConfig else DEFAULT_BLOOD_EVIDENCE_DETECTION_RADIUS_PX
	var triggered_ids_variant: Variant = entry.get("triggered_ids", {})
	var triggered_ids: Dictionary = triggered_ids_variant as Dictionary if triggered_ids_variant is Dictionary else {}
	if not (triggered_ids_variant is Dictionary):
		entry["triggered_ids"] = triggered_ids
	for child_variant in entities_container.get_children():
		var child := child_variant as Node
		if child == null or not child.is_in_group("enemies"):
			continue
		var entity_id := int(child.get("entity_id")) if "entity_id" in child else -1
		if entity_id <= 0:
			continue
		if triggered_ids.has(entity_id):
			continue
		if not ("global_position" in child):
			continue
		var child_pos: Vector2 = child.get("global_position") as Vector2
		if child_pos.distance_to(evidence_pos) > radius:
			continue
		if not child.has_method("apply_blood_evidence"):
			continue
		var triggered := bool(child.call("apply_blood_evidence", evidence_pos))
		if not triggered:
			continue
		triggered_ids[entity_id] = true
		if EventBus and EventBus.has_method("emit_blood_evidence_detected"):
			EventBus.emit_blood_evidence_detected(entity_id, evidence_pos)
