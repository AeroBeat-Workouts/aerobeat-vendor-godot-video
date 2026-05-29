extends Control

var playing: bool = false
var paused: bool = false
var loop: bool = false
var autoplay: bool = false
var playback_speed: float = 1.0
var stream_position: float = 0.0
var volume: float = 1.0
var volume_db: float = 0.0
var stream: Variant = null
var cover_mode: String = "contain"
var expand: bool = false
var last_source_descriptor: Dictionary = {}

func play() -> void:
	playing = true
	paused = false

func pause() -> void:
	playing = false
	paused = true

func stop() -> void:
	playing = false
	paused = false
	stream_position = 0.0

func is_playing() -> bool:
	return playing

func apply_source_descriptor(source: Dictionary) -> void:
	last_source_descriptor = source.duplicate(true)
