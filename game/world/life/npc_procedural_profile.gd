class_name NpcProceduralProfile
extends RefCounted

## Work and household context for residents without authored profile resources.
## Entries are background, values, goal, and conversational habit.
const ROLES: Dictionary = {
	"bookkeeper": ["Keeps household accounts and notices small discrepancies.",
		"Accuracy and keeping promises matter more than a pleasing story.",
		"Keep the accounts clear enough that others can rely on them.",
		"Asks what a number or promise actually means before agreeing."],
	"retired seamstress": ["Spent years fitting and mending clothes; no longer works a regular trade.",
		"Careful work and being useful to family still matter.",
		"Pass on what experience taught without directing everyone else's work.",
		"Notices when someone is uncomfortable before they say so."],
	"cooper": ["Makes and repairs wooden vessels that must hold together in use.",
		"Sound joints and work that lasts matter more than appearances.",
		"Finish dependable work while making time for the household.",
		"Tests a claim by asking how it would hold up in practice."],
	"child": ["Grows up among family and attends lessons in Rekala.",
		"Being included and taken seriously matters, alongside play.",
		"Learn enough to do more independently and find time with other children.",
		"Follows the immediate point of a conversation, not an adult's formal argument."],
	"retired wheelwright": ["Once made and repaired wheels; the trade remains familiar even in retirement.",
		"Useful knowledge should be shared, and old work should withstand scrutiny.",
		"Help family when asked without taking over their decisions.",
		"Compares a new problem with things that have actually worked before."],
	"apprentice carpenter": ["Learning carpentry through practice and correction.",
		"Improvement matters more than pretending to know a craft already.",
		"Become reliable enough to take on difficult work.",
		"Notices mistakes quickly, especially their own."],
	"weaver": ["Works with thread, pattern, and the time each piece takes.",
		"Patience and consistency keep work from unraveling.",
		"Complete good work without being hurried into careless shortcuts.",
		"Picks up on interruptions and loose ends in what people say."],
	"retired market seller": ["Spent years dealing with people at the market; now retired.",
		"A person's manner can matter as much as their words.",
		"Stay connected to neighbors and family without needing to run the market.",
		"Remembers how someone asked for a thing, not only what they asked for."],
	"delivery worker": ["Carries things between people and knows the cost of a missed errand.",
		"Reliability and clear directions matter.",
		"Get where needed without taking on promises that cannot be kept.",
		"Gets to the point when someone needs an answer."],
	"leatherworker": ["Cuts, stitches, and repairs leather for daily use.",
		"Durability and making the most of materials matter.",
		"Keep useful things in service instead of wasting them.",
		"Pays attention to wear and what caused it."],
	"farmer": ["Works the land around Rekala, where a day's effort has delayed results.",
		"Steady work and the household's needs matter.",
		"Keep the farm going through ordinary setbacks.",
		"Thinks about what can be done today before debating distant possibilities."],
	"miller": ["Works with grain and the routine that gets it ready for food.",
		"Regular work and fair dealing with neighbors matter.",
		"Keep the mill's work moving without cutting corners.",
		"Notices when a small delay will become someone else's problem."],
	"fisher": ["Earns a living from fishing and pays attention to conditions nearby.",
		"Judging conditions carefully matters more than showing off courage.",
		"Bring home enough while avoiding needless risk.",
		"Trusts what can be seen and checked over a dramatic account."],
	"teacher": ["Teaches local children and sees how differently they learn.",
		"Patience and giving a clear explanation matter.",
		"Help pupils understand, not merely repeat an answer.",
		"Notices the question someone is struggling to ask."],
	"farmhand": ["Helps with farm work that changes with the day's needs.",
		"Being counted on and doing a fair share matter.",
		"Finish the work in front of them and make room for a life beyond it.",
		"Prefers plain answers to grand claims."],
	"herb gatherer": ["Gathers useful plants and must distinguish them carefully.",
		"Careful identification matters; a guess can cause harm.",
		"Bring back useful plants without claiming to know every remedy.",
		"Asks for a description before offering an opinion."],
	"guard": ["Serves on the town watch and deals with incomplete reports.",
		"Protecting neighbors and judging evidence fairly both matter.",
		"Keep the peace while distinguishing witnessed acts from rumor.",
		"Asks what someone actually saw before deciding what to do."],
	"baker": ["Bakes for the household and works around the timing of dough and heat.",
		"Feeding people well and not wasting ingredients matter.",
		"Finish the day's baking without losing time with family.",
		"Speaks concretely about what can be done now."],
}

static func apply(profile: NpcProfile, person: Dictionary, temperament: Dictionary) -> void:
	var role: Array = ROLES.get(person.job, [])
	assert(not role.is_empty(), "Missing procedural profile for job %s" % person.job)
	if role.is_empty():
		return
	profile.background = String(role[0])
	profile.values = String(role[1])
	profile.goals = String(role[2])
	profile.personality = "%s %s" % [String(role[3]), _social_behavior(temperament.traits)]
	profile.fears = _pressure(temperament.traits)
	if person.age < 16:
		profile.personality += " %s" % _child_perspective(person.age)
		profile.voice.register = "FAMILIAR"
	elif person.age >= 65:
		profile.personality += " Experience makes them selective about which advice to offer."
	if person.kin.values().has("child"):
		profile.goals += " Make time for the children in the household."

static func _social_behavior(traits: Dictionary) -> String:
	var sociability: float = float(traits.sociability)
	var curiosity: float = float(traits.curiosity)
	var discretion: float = float(traits.discretion)
	if sociability > 0.66 and curiosity > 0.66:
		return "Drawn to people and their news, but asks about a particular detail rather than filling silence."
	if sociability < 0.34 and discretion > 0.66:
		return "Keeps company with a few people and does not offer private thoughts to strangers."
	if curiosity > 0.66:
		return "Asks about unfamiliar things, then weighs the answer against personal experience."
	if discretion < 0.34:
		return "Talks readily, sometimes realizing only afterward that a subject was private."
	if sociability < 0.34:
		return "Does not extend a conversation merely to be polite, but listens when something matters."
	return "Enjoys company in moderation and gives a fuller answer when the subject matters personally."

static func _pressure(traits: Dictionary) -> String:
	if float(traits.courage) < 0.34:
		return "Fears being drawn into a confrontation they cannot control."
	if float(traits.patience) < 0.34:
		return "Fears losing time to repeated demands when work or family needs attention."
	if float(traits.discretion) > 0.66:
		return "Fears betraying a confidence or accusing someone on weak evidence."
	return "Fears letting an avoidable mistake affect people who rely on them."

static func _child_perspective(age: int) -> String:
	if age < 9:
		return "Still expects adults to explain things plainly and may change subjects quickly."
	return "Wants adults to listen without treating every question as childish."
