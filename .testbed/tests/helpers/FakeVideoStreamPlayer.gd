extends Node

var playing: bool = false
var loop: bool = false
var autoplay: bool = false
var playback_speed: float = 1.0
var stream_position: float = 0.0
var last_source_descriptor: Dictionary = {}

func play() -> void:
	playing = true

func pause() -> void:
	playing = false

func stop() -> void:
	playing = false
	stream_position = 0.0

func apply_source_descriptor(source: Dictionary) -> void:
	last_source_descriptor = source.duplicate(true)
