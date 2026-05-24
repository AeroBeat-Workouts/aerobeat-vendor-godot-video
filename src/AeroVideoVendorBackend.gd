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

func get_audio_state() -> Dictionary:
	return {
		"muted": false,
		"player_present": false,
	}
