class_name TownPopulation
extends RefCounted

## Stable identities and kinship, separate from mutable feelings and scene instances.
const FOUNDERS: Dictionary = {
	"alchemist": "mirelle_voss", "jeweller": "cassian_vale", "tailor": "maris_bell",
	"blacksmith": "garrin_holt", "cooker": "sella_rowan", "carpenter": "elara_finch",
	"dyer": "ione_mercer", "butcher": "bram_edevane", "furrier": "tovan_reed",
}
# ID, household, surname, age, sex, occupation. IDs never depend on generated names.
const MEMBERS: Array[Array] = [
	["bell_partner", "maris_bell", "Bell", 43, "Male", "bookkeeper"],
	["bell_aunt", "maris_bell", "Bell", 72, "Female", "retired seamstress"],
	["holt_partner", "garrin_holt", "Holt", 42, "Female", "cooper"],
	["holt_child_a", "garrin_holt", "Holt", 12, "Female", "child"],
	["holt_child_b", "garrin_holt", "Holt", 8, "Male", "child"],
	["finch_grandfather", "elara_finch", "Finch", 76, "Male", "retired wheelwright"],
	["finch_cousin", "elara_finch", "Finch", 19, "Male", "apprentice carpenter"],
	["mercer_sister", "ione_mercer", "Mercer", 40, "Female", "weaver"],
	["edevane_mother", "bram_edevane", "Edevane", 67, "Female", "retired market seller"],
	["edevane_brother", "bram_edevane", "Edevane", 34, "Male", "delivery worker"],
	["reed_partner", "tovan_reed", "Reed", 46, "Female", "leatherworker"],
	["rowan_father", "rowan_farm", "Rowan", 66, "Male", "farmer"],
	["rowan_mother", "rowan_farm", "Rowan", 63, "Female", "farmer"],
	["rowan_sibling_a", "rowan_farm", "Rowan", 39, "Female", "miller"],
	["rowan_sibling_b", "rowan_farm", "Rowan", 36, "Male", "fisher"],
	["rowan_sibling_c", "rowan_farm", "Rowan", 33, "Female", "teacher"],
	["rowan_sibling_d", "rowan_farm", "Rowan", 30, "Male", "farmhand"],
	["voss_nephew", "voss_house", "Voss", 27, "Male", "herb gatherer"],
	["voss_guard", "voss_house", "Voss", 29, "Female", "guard"],
	["voss_child", "voss_house", "Voss", 6, "Female", "child"],
	["vale_guard", "watch_house", "Ash", 36, "Male", "guard"],
	["ash_partner", "watch_house", "Ash", 35, "Female", "baker"],
	["ash_child_a", "watch_house", "Ash", 11, "Male", "child"],
	["ash_child_b", "watch_house", "Ash", 8, "Female", "child"],
]
const FIRST_NAMES: Dictionary = {
	"Female": ["Ada", "Nessa", "Lina", "Wren", "Mara", "Tess", "Orla", "Fern", "Dara", "Runa", "Vera", "Faye"],
	"Male": ["Alden", "Corin", "Edric", "Jory", "Nolan", "Oren", "Perrin", "Rafe", "Silas", "Torren", "Wes", "Bennet"],
}
var people: Dictionary = {}

func ensure_population(seed_value: int) -> void:
	if not people.is_empty():
		return
	var used: Array[String] = []
	for job: String in FOUNDERS:
		var profile: NpcProfile = load("res://game/resources/actors/humans/%s_npc_profile.tres" % job)
		people[FOUNDERS[job]] = _record(FOUNDERS[job], FOUNDERS[job], profile.profile_name,
			profile.age, profile.sex, job, seed_value)
		used.append(profile.profile_name)
	for member: Array in MEMBERS:
		var random := NpcRoutinePlan.random_for(seed_value, member[0] + ":identity")
		var names: Array = FIRST_NAMES[member[4]]
		var start: int = random.randi_range(0, names.size() - 1)
		var display_name: String = ""
		for index: int in range(names.size()):
			display_name = names[(start + index) % names.size()] + " " + member[2]
			if not display_name in used:
				break
		used.append(display_name)
		people[member[0]] = _record(member[0], member[1], display_name, member[3], member[4], member[5], seed_value)
	_pair("maris_bell", "bell_partner", "partner", "partner")
	_pair("maris_bell", "bell_aunt", "aunt", "nibling")
	_parents("garrin_holt", "holt_partner", ["holt_child_a", "holt_child_b"])
	_pair("elara_finch", "finch_grandfather", "grandfather", "granddaughter")
	_pair("elara_finch", "finch_cousin", "cousin", "cousin")
	_pair("ione_mercer", "mercer_sister", "sister", "sister")
	for child: String in ["bram_edevane", "edevane_brother"]:
		_pair("edevane_mother", child, "son", "mother")
	_pair("bram_edevane", "edevane_brother", "brother", "brother")
	_pair("tovan_reed", "reed_partner", "spouse", "spouse")
	_parents("rowan_father", "rowan_mother", ["sella_rowan", "rowan_sibling_a", "rowan_sibling_b", "rowan_sibling_c", "rowan_sibling_d"])
	_parents("voss_nephew", "voss_guard", ["voss_child"])
	_pair("mirelle_voss", "voss_nephew", "nephew", "aunt")
	_parents("vale_guard", "ash_partner", ["ash_child_a", "ash_child_b"])

func _record(id: String, household: String, display_name: String, age: int, sex: String,
		job: String, seed_value: int) -> Dictionary:
	return {"id": id, "household": household, "name": display_name, "age": age, "sex": sex,
		"job": job, "kin": {}, "appearance": NpcRoutinePlan.random_for(seed_value, id + ":looks").randi_range(0, 65535)}

func _pair(first: String, second: String, second_role: String, first_role: String) -> void:
	people[first].kin[second] = second_role
	people[second].kin[first] = first_role

func _parents(first: String, second: String, children: Array[String]) -> void:
	_pair(first, second, "spouse", "spouse")
	for child: String in children:
		_pair(first, child, "child", "father")
		_pair(second, child, "child", "mother")
		for sibling: String in children:
			if sibling != child:
				_pair(child, sibling, "sibling", "sibling")

func household_for(id: String) -> String:
	return people.get(id, {}).get("household", id)

func members_of(household: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in people:
		if people[id].household == household:
			result.append(id)
	result.sort()
	return result

func family_context(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for relative: String in people[id].kin:
		result.append({"id": relative, "name": people[relative].name,
			"relationship": people[id].kin[relative], "job": people[relative].job,
			"lives_with_me": people[relative].household == people[id].household})
	return result

func profile_for(id: String) -> NpcProfile:
	var person: Dictionary = people[id]
	var profile: NpcProfile
	if FOUNDERS.values().has(id):
		profile = load("res://game/resources/actors/humans/%s_npc_profile.tres" % person.job).duplicate(true)
	else:
		profile = NpcProfile.new()
		profile.npc_id = StringName(id)
		profile.profile_name = person.name
		profile.age = person.age
		profile.sex = person.sex
		profile.job = "Schoolchild" if person.job == "child" else String(person.job).capitalize()
		profile.background = "A longtime member of Rekala's small community."
		profile.values = "Keeping promises to family and making a place in the community."
		profile.goals = "Learn, play and spend time with family." if person.age < 16 else "Care for the household and fulfill daily obligations."
		profile.speech_style = "Speak in direct, everyday language appropriate to your age and experience."
		profile.knowledge_packs.append(preload("res://game/resources/actors/knowledge/rekala_common.tres"))
		if person.job == "guard":
			profile.values = "Protect neighbors; warn first when possible; stop violence and accept surrender."
	profile.home = person.household + " household in Rekala"
	for relative: Dictionary in family_context(id):
		profile.family += " %s is my %s, a %s; %s." % [relative.name, relative.relationship,
			relative.job, "we live together" if relative.lives_with_me else "we live in separate households"]
	return profile

func to_data() -> Dictionary:
	return {"version": 1, "people": people.duplicate(true)}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("people") is Dictionary:
		return false
	if not data.people.is_empty() and data.people.size() != FOUNDERS.size() + MEMBERS.size():
		return false
	var expected: Array = FOUNDERS.values()
	var homes: Dictionary = {}
	var jobs: Dictionary = {}
	for job: String in FOUNDERS:
		homes[FOUNDERS[job]] = FOUNDERS[job]
		jobs[FOUNDERS[job]] = job
	for member: Array in MEMBERS:
		expected.append(member[0])
		homes[member[0]] = member[1]
		jobs[member[0]] = member[5]
	for id: Variant in data.people:
		var person: Variant = data.people[id]
		if not id in expected or not person is Dictionary or person.get("id") != id:
			return false
		for field: String in ["household", "name", "sex", "job"]:
			if not person.get(field) is String or person[field].is_empty() or person[field].length() > 120:
				return false
		if person.household != homes[id] or person.job != jobs[id]:
			return false
		if not NpcMemory.is_integer(person.get("age")) or person.age < 1 or person.age > 120 \
			or not NpcMemory.is_integer(person.get("appearance")) or person.appearance < 0 or person.appearance > 65535 \
			or not person.get("kin") is Dictionary:
			return false
		for relative: Variant in person.kin:
			if relative == id or not data.people.has(relative) or not person.kin[relative] is String:
				return false
			if person.kin[relative].is_empty() or person.kin[relative].length() > 80:
				return false
	people = data.people.duplicate(true)
	return true
