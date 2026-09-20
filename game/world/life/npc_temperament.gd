class_name NpcTemperament
extends RefCounted

## A procedural identity is rolled once per save; daily variation never rerolls personality.
const TRAITS: Array[String] = ["sociability", "discretion", "patience", "courage", "curiosity"]
const DESCRIPTIONS: Dictionary = {
	"sociability": ["Prefers a little distance and a few familiar companions.",
		"Enjoys company but also values time alone.", "Readily approaches people and enjoys exchanging news."],
	"discretion": ["Often passes on interesting news before considering who should hear it.",
		"Shares ordinary news but thinks twice about personal matters.", "Protects confidences and avoids spreading uncertain accusations."],
	"patience": ["Gets impatient with interruptions and repeated questions.",
		"Usually gives people a fair hearing, within reason.", "Listens patiently, even when someone struggles to explain."],
	"courage": ["Avoids confrontation and seeks company when frightened.",
		"Weighs danger carefully before getting involved.", "Stands their ground and may speak up when others stay quiet."],
	"curiosity": ["Pays most attention to familiar concerns and practical necessities.",
		"Takes an interest in news that touches their daily life.", "Often asks questions and seeks out unfamiliar people and places."],
}
const VOICES: Array[String] = ["Plain and economical; comfortable with a short answer.",
	"Easygoing and conversational, with occasional dry humor.",
	"Careful, direct wording; asks a specific question when unsure.",
	"Lively and candid, with short, informal sentences.",
	"Soft-spoken and thoughtful; leaves some opinions unspoken.",
	"Frank and practical, occasionally teasing people they know well."]

static func generate(seed_value: int, id: String) -> Dictionary:
	var random := NpcRoutinePlan.random_for(seed_value, id + ":personality")
	var traits: Dictionary = {}
	var sentences: PackedStringArray = []
	for tendency: String in TRAITS:
		var value: float = random.randf_range(0.05, 0.95)
		traits[tendency] = value
		sentences.append(DESCRIPTIONS[tendency][mini(2, int(value * 3))])
	return {"traits": traits, "personality": " ".join(sentences),
		"speech_style": VOICES[random.randi_range(0, VOICES.size() - 1)]}

static func apply(profile: NpcProfile, temperament: Dictionary) -> void:
	profile.personality = temperament.personality
	profile.speech_style = temperament.speech_style
	profile.social_traits = temperament.traits.duplicate(true)
	profile.cognition = profile.get_cognition().duplicate()
	profile.cognition.verbal_reactivity = lerpf(0.2, 0.9, temperament.traits.sociability)

static func is_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("personality") is String \
		or value.personality.length() > 2000 or not value.get("speech_style") is String \
		or value.speech_style.length() > 500 or not value.get("traits") is Dictionary:
		return false
	for tendency: String in TRAITS:
		if not NpcMemory.is_unit(value.traits.get(tendency)):
			return false
	return true
