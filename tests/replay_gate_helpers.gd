class_name ReplayGateHelpers
extends RefCounted

const REQUIRED_KEYS := [
	"tick",
	"enemy_id",
	"state",
	"intent_type",
	"mode",
	"path_status",
	"target_context_exists",
	"position_x",
	"position_y",
]


static func save_jsonl(path: String, records: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	for rec_variant in records:
		var rec := rec_variant as Dictionary
		file.store_line(JSON.stringify(rec))
	return true


static func load_jsonl(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed as Dictionary)
		else:
			out.append({"__schema_invalid__": true, "raw_line": line})
	return out


static func validate_trace_record(record: Dictionary) -> Dictionary:
	for key_variant in REQUIRED_KEYS:
		var key := String(key_variant)
		if not record.has(key):
			return {"ok": false, "reason": "missing_key:%s" % key}
	if not _is_int_like(record.get("tick", null)):
		return {"ok": false, "reason": "tick"}
	if not _is_int_like(record.get("enemy_id", null)):
		return {"ok": false, "reason": "enemy_id"}
	if not (record.get("state", null) is String):
		return {"ok": false, "reason": "state"}
	if not (record.get("intent_type", null) is String):
		return {"ok": false, "reason": "intent_type"}
	if not (record.get("mode", null) is String):
		return {"ok": false, "reason": "mode"}
	if not (record.get("path_status", null) is String):
		return {"ok": false, "reason": "path_status"}
	if not (record.get("target_context_exists", null) is bool):
		return {"ok": false, "reason": "target_context_exists"}
	if not _is_finite_number(record.get("position_x", null)):
		return {"ok": false, "reason": "position_x"}
	if not _is_finite_number(record.get("position_y", null)):
		return {"ok": false, "reason": "position_y"}
	return {"ok": true}


static func validate_trace_records(records: Array) -> Dictionary:
	for i in range(records.size()):
		var rec := records[i] as Dictionary
		var check := validate_trace_record(rec)
		if not bool(check.get("ok", false)):
			return {"ok": false, "index": i, "reason": String(check.get("reason", "schema_invalid"))}
	return {"ok": true}


static func compare_trace_to_baseline(
	scenario_name: String,
	baseline_path: String,
	candidate_records: Array,
	warmup_sec: float,
	position_tolerance_px: float,
	drift_budget_percent: float
) -> Dictionary:
	var result := {
		"scenario_name": scenario_name,
		"gate_status": "FAIL",
		"gate_reason": "baseline_missing",
		"sample_count": 0,
		"record_count_match": false,
		"discrete_mismatch_after_warmup_count": 0,
		"position_tolerance_violation_count": 0,
		"position_drift_percent": 0.0,
		"baseline_path": baseline_path,
	}
	if not FileAccess.file_exists(baseline_path):
		return result
	var baseline_records := load_jsonl(baseline_path)
	var baseline_schema := validate_trace_records(baseline_records)
	if not bool(baseline_schema.get("ok", false)):
		result["gate_reason"] = "schema_invalid"
		return result
	var cand_schema := validate_trace_records(candidate_records)
	if not bool(cand_schema.get("ok", false)):
		result["gate_reason"] = "schema_invalid"
		return result
	if baseline_records.size() != candidate_records.size():
		result["sample_count"] = candidate_records.size()
		result["gate_reason"] = "record_count_mismatch"
		return result
	result["record_count_match"] = true
	result["sample_count"] = candidate_records.size()
	var discrete_mismatch_after_warmup_count := 0
	var position_tolerance_violation_count := 0
	for i in range(candidate_records.size()):
		var base_rec := baseline_records[i] as Dictionary
		var cand_rec := candidate_records[i] as Dictionary
		var base_tick := int(base_rec.get("tick", -1))
		var cand_tick := int(cand_rec.get("tick", -2))
		var base_enemy_id := int(base_rec.get("enemy_id", -1))
		var cand_enemy_id := int(cand_rec.get("enemy_id", -2))
		if base_tick != cand_tick or base_enemy_id != cand_enemy_id:
			result["gate_reason"] = "record_count_mismatch"
			return result
		var record_time_sec := float(cand_tick) / 60.0
		var in_warmup := record_time_sec <= warmup_sec
		var discrete_mismatch := (
			String(base_rec.get("state", "")) != String(cand_rec.get("state", ""))
			or String(base_rec.get("intent_type", "")) != String(cand_rec.get("intent_type", ""))
			or String(base_rec.get("mode", "")) != String(cand_rec.get("mode", ""))
			or String(base_rec.get("path_status", "")) != String(cand_rec.get("path_status", ""))
			or bool(base_rec.get("target_context_exists", false)) != bool(cand_rec.get("target_context_exists", false))
		)
		if discrete_mismatch and not in_warmup:
			discrete_mismatch_after_warmup_count += 1
		var dx := absf(float(cand_rec.get("position_x", 0.0)) - float(base_rec.get("position_x", 0.0)))
		var dy := absf(float(cand_rec.get("position_y", 0.0)) - float(base_rec.get("position_y", 0.0)))
		if dx > position_tolerance_px or dy > position_tolerance_px:
			position_tolerance_violation_count += 1
	result["discrete_mismatch_after_warmup_count"] = discrete_mismatch_after_warmup_count
	result["position_tolerance_violation_count"] = position_tolerance_violation_count
	result["position_drift_percent"] = (float(position_tolerance_violation_count) * 100.0) / float(maxi(candidate_records.size(), 1))
	if discrete_mismatch_after_warmup_count > 0:
		result["gate_status"] = "FAIL"
		result["gate_reason"] = "discrete_mismatch_after_warmup"
	elif float(result.get("position_drift_percent", 0.0)) > drift_budget_percent:
		result["gate_status"] = "FAIL"
		result["gate_reason"] = "position_drift_budget_exceeded"
	else:
		result["gate_status"] = "PASS"
		result["gate_reason"] = "ok"
	return result


static func aggregate_pack_report(scenario_results: Array, alert_combat_bad_patrol_count: int) -> Dictionary:
	var pack_sample_count := 0
	var pack_discrete_mismatch_after_warmup_count := 0
	var pack_position_tolerance_violation_count := 0
	for item_variant in scenario_results:
		var item := item_variant as Dictionary
		pack_sample_count += int(item.get("sample_count", 0))
		pack_discrete_mismatch_after_warmup_count += int(item.get("discrete_mismatch_after_warmup_count", 0))
		pack_position_tolerance_violation_count += int(item.get("position_tolerance_violation_count", 0))
	return {
		"scenario_results": scenario_results,
		"pack_sample_count": pack_sample_count,
		"pack_discrete_mismatch_after_warmup_count": pack_discrete_mismatch_after_warmup_count,
		"pack_position_tolerance_violation_count": pack_position_tolerance_violation_count,
		"alert_combat_bad_patrol_count": alert_combat_bad_patrol_count,
	}


static func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var v := float(value)
		return is_finite(v) and is_equal_approx(v, round(v))
	return false


static func _is_finite_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value))
	return false
