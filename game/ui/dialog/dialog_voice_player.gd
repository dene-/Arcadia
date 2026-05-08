class_name DialogVoicePlayer
extends AudioStreamPlayer

const SPEECH_SOUND_RATE_DIVISOR: int = 2
const SPEECH_SOUND_MIX_RATE: float = 22050.0
const SPEECH_SOUND_DURATION: float = 0.025
const SPEECH_SOUND_BASE_HZ: float = 780.0
const SPEECH_SOUND_VARIANCE_HZ: float = 120.0
const SPEECH_SOUND_VOLUME: float = 0.08

var _generator_playback: AudioStreamGeneratorPlayback
var _speech_phase: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_ensure_generator_stream()

func ensure_started() -> void:
	_ensure_generator_stream()
	if not playing:
		play()
	_generator_playback = get_stream_playback() as AudioStreamGeneratorPlayback

func play_character(character: String, character_index: int) -> void:
	if character == " " or character == "\n" or character == "\t":
		return
	if character_index % SPEECH_SOUND_RATE_DIVISOR != 0:
		return

	ensure_started()
	if _generator_playback == null:
		return

	var frame_count := mini(
		int(SPEECH_SOUND_MIX_RATE * SPEECH_SOUND_DURATION),
		_generator_playback.get_frames_available()
	)
	if frame_count <= 0:
		return

	var frequency := SPEECH_SOUND_BASE_HZ + _rng.randf_range(-SPEECH_SOUND_VARIANCE_HZ, SPEECH_SOUND_VARIANCE_HZ)
	for frame in range(frame_count):
		var envelope := 1.0 - (float(frame) / float(frame_count))
		var sample := sin(_speech_phase) * SPEECH_SOUND_VOLUME * envelope
		_generator_playback.push_frame(Vector2(sample, sample))
		_speech_phase += TAU * frequency / SPEECH_SOUND_MIX_RATE

func _ensure_generator_stream() -> void:
	if stream != null:
		return

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SPEECH_SOUND_MIX_RATE
	generator.buffer_length = 0.08
	stream = generator
	bus = &"Master"
