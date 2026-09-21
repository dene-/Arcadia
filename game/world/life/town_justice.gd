class_name TownJustice
extends RefCounted

## An individual guard's evidence. Warnings never grant permission to harm bystanders.
var reports: Dictionary = {}

func notice(guard: String, suspect: String, kind: String, minute: float) -> Dictionary:
	var key: String = guard + ":" + suspect
	var report: Dictionary = reports.get(key, {})
	var recent: bool = not report.is_empty() and minute - float(report.minute) < 30
	# Breaking a recent surrender does not erase the violence the guard witnessed.
	var assaults: int = int(report.get("assaults", 0)) if recent else 0
	if kind in ["assault", "killing"]:
		assaults += 1
	var status: String = "combat" if kind == "killing" or assaults >= 2 else "warning"
	if recent and report.get("status") == "combat":
		status = "combat"
	report = {"guard": guard, "suspect": suspect, "kind": kind, "minute": minute,
		"assaults": assaults, "status": status, "until": minute + 30}
	reports[key] = report
	while reports.size() > 64:
		reports.erase(reports.keys()[0])
	return report.duplicate(true)

func surrender(guard: String, suspect: String, minute: float) -> bool:
	var key: String = guard + ":" + suspect
	if current(guard, suspect, minute).is_empty():
		return false
	reports[key].status = "surrendered"
	reports[key].minute = minute
	reports[key].until = minute
	return true

func current(guard: String, suspect: String, minute: float) -> Dictionary:
	var report: Dictionary = reports.get(guard + ":" + suspect, {})
	if report.is_empty() or report.until <= minute or report.status == "surrendered":
		return {}
	return report.duplicate(true)

func known_to(guard: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for report: Dictionary in reports.values():
		if report.guard == guard:
			result.append(report.duplicate(true))
	return result

func to_data() -> Dictionary:
	return {"version": 1, "reports": reports.duplicate(true)}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("reports") is Dictionary or data.reports.size() > 64:
		return false
	for key: Variant in data.reports:
		var report: Variant = data.reports[key]
		if not key is String or not report is Dictionary:
			return false
		for field: String in ["guard", "suspect", "kind", "status"]:
			if not report.get(field) is String or report[field].is_empty() or report[field].length() > 120:
				return false
		if key != report.guard + ":" + report.suspect or not report.status in ["warning", "combat", "surrendered"] \
			or not NpcMemory.is_integer(report.get("assaults")) or report.assaults < 0:
			return false
		for field: String in ["minute", "until"]:
			if not TownLifeState._number(report.get(field)) or report[field] < 0:
				return false
	reports = data.reports.duplicate(true)
	return true
