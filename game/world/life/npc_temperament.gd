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
const VOICE_AXES: Dictionary = {
	"register": ["FAMILIAR", "PLAIN", "PRECISE", "COURTEOUS"],
	"cadence": ["BRISK", "UNHURRIED", "MEASURED"],
	"verbosity": ["SPARE", "BALANCED", "EXPANSIVE"],
	"directness": ["BLUNT", "TACTFUL", "TENTATIVE"],
	"humor": ["EARNEST", "DRY", "PLAYFUL"],
	"disclosure": ["RESERVED", "SELECTIVE", "OPEN"],
	"questions": ["RARE", "PURPOSEFUL", "INQUISITIVE"],
}

static func generate(seed_value: int, id: String) -> Dictionary:
	var random := NpcRoutinePlan.random_for(seed_value, id + ":personality")
	var traits: Dictionary = {}
	var sentences: PackedStringArray = []
	for tendency: String in TRAITS:
		var value: float = random.randf_range(0.05, 0.95)
		traits[tendency] = value
		sentences.append(DESCRIPTIONS[tendency][mini(2, int(value * 3))])
	var result: Dictionary = {"traits": traits, "personality": " ".join(sentences)}
	ensure_voice(result, seed_value, id)
	return result

## Upgrade old saves once without rerolling temperament, identity or relationships.
static func ensure_voice(temperament: Dictionary, seed_value: int, id: String) -> void:
	if temperament.has("voice"):
		return
	var random := NpcRoutinePlan.random_for(seed_value, id + ":voice:1")
	var traits: Dictionary = temperament.traits
	var voice: Dictionary = {
		"register": VOICE_AXES.register[random.randi_range(0, 3)],
		"cadence": "BRISK" if traits.patience < 0.34 else
			("MEASURED" if traits.discretion > 0.66 else "UNHURRIED"),
		"verbosity": _band(traits.sociability, "SPARE", "BALANCED", "EXPANSIVE"),
		"directness": "BLUNT" if traits.courage > 0.66 and traits.discretion < 0.66 else
			("TENTATIVE" if traits.courage < 0.34 else "TACTFUL"),
		"humor": VOICE_AXES.humor[random.randi_range(0, 2)],
		"disclosure": _band(traits.discretion, "OPEN", "SELECTIVE", "RESERVED"),
		"questions": _band(traits.curiosity, "RARE", "PURPOSEFUL", "INQUISITIVE"),
	}
	temperament.voice = voice
	temperament.speech_style = "%s diction, %s pace, %s answers; %s, with %s humor. %s about personal matters." % [
		voice.register.to_lower(), voice.cadence.to_lower(), voice.verbosity.to_lower(),
		voice.directness.to_lower(), voice.humor.to_lower(), voice.disclosure.to_lower().capitalize()]

static func apply(profile: NpcProfile, temperament: Dictionary) -> void:
	if profile.personality.is_empty():
		profile.personality = temperament.personality
	if profile.speech_style.is_empty():
		profile.speech_style = temperament.speech_style
	profile.voice = temperament.get("voice", {}).duplicate(true)
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
	if value.has("voice"):
		if not value.voice is Dictionary:
			return false
		for axis: String in VOICE_AXES:
			if not value.voice.get(axis) in VOICE_AXES[axis]:
				return false
	return true

static func _band(value: float, low: String, middle: String, high: String) -> String:
	return low if value < 0.34 else (high if value > 0.66 else middle)
