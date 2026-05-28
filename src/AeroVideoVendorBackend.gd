## Vendor-local backend base for AeroBeat Godot video playback.
##
## This repo plugs directly into the tool-video-player contract while keeping
## optional vendor-specific helpers for richer Godot-native inspection.
class_name AeroVideoVendorBackend
extends "res://addons/aerobeat-tool-video-player/src/AeroVideoPlayerBackend.gd"

func set_muted(_muted: bool) -> Dictionary:
	return CoreContract.fail(
		"backend_audio_control_unimplemented",
		"set_muted is not implemented on this backend.",
		{"method": "set_muted"}
	)

func set_audio_level(_audio_level: float) -> Dictionary:
	return CoreContract.fail(
		"backend_audio_control_unimplemented",
		"set_audio_level is not implemented on this backend.",
		{"method": "set_audio_level"}
	)

func set_cover_mode(_cover_mode: String) -> Dictionary:
	return CoreContract.fail(
		"backend_cover_mode_unimplemented",
		"set_cover_mode is not implemented on this backend.",
		{"method": "set_cover_mode"}
	)

func get_audio_state() -> Dictionary:
	return {
		"muted": false,
		"audio_level": 1.0,
		"effective_audio_level": 1.0,
		"player_present": false,
	}
