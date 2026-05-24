extends Control

const FACTORY_SCRIPT := preload("res://src/AeroGodotVideoBackendFactory.gd")
const SAMPLE_VIDEO_PATH := "res://assets/videos/calm_blue_sea_1.ogv"
const BAD_VIDEO_PATH := "res://assets/videos/does_not_exist.ogv"

@onready var path_label: Label = %PathLabel
@onready var status_label: Label = %StatusLabel
@onready var detail_label: Label = %DetailLabel
@onready var audio_label: Label = %AudioLabel
@onready var surface: Control = %Surface
@onready var mute_button: Button = %MuteButton

var _factory: AeroGodotVideoBackendFactory
var _manager: Node

func _ready() -> void:
	path_label.text = SAMPLE_VIDEO_PATH
	_factory = FACTORY_SCRIPT.new()
	_manager = _factory.create_manager()
	add_child(_manager)
	_manager.state_changed.connect(_on_state_changed)
	_manager.media_loaded.connect(_on_media_loaded)
	_manager.error_raised.connect(_on_error_raised)
	_manager.position_changed.connect(_on_position_changed)
	_manager.attach_surface(surface)
	_on_load_button_pressed()
	set_process(true)

func _process(_delta: float) -> void:
	_refresh_labels()

func _refresh_labels() -> void:
	if _manager == null:
		return
	var state: Dictionary = _manager.get_state()
	var media_info: Dictionary = _manager.get_media_info()
	var backend: Variant = _manager.get_backend()
	var audio_state: Dictionary = backend.get_audio_state() if backend != null and backend.has_method("get_audio_state") else {"muted": false}
	status_label.text = "State: %s" % str(state.get("state", "idle"))
	detail_label.text = "Position: %.2f / %.2f | Format: %s | Surface: %s" % [
		float(state.get("position", 0.0)),
		float(state.get("duration", 0.0)),
		str(media_info.get("format_status", "unknown")),
		str(state.get("surface_attached", false)),
	]
	audio_label.text = "Audio: %s" % ("muted" if bool(audio_state.get("muted", false)) else "unmuted")
	mute_button.text = "Unmute" if bool(audio_state.get("muted", false)) else "Mute"

func _on_state_changed(_state: String, _detail: Dictionary) -> void:
	_refresh_labels()

func _on_media_loaded(info: Dictionary) -> void:
	status_label.text = "Loaded %s" % str(info.get("path", ""))
	_refresh_labels()

func _on_error_raised(error_info: Dictionary) -> void:
	status_label.text = "Error: %s" % str(error_info.get("message", "Unknown error"))
	_refresh_labels()

func _on_position_changed(_seconds: float, _normalized: float) -> void:
	_refresh_labels()

func _on_load_button_pressed() -> void:
	_manager.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"metadata": {"source": "vendor_backend_testbed", "real_sample": true},
	})

func _on_load_bad_button_pressed() -> void:
	_manager.load({"path": BAD_VIDEO_PATH})

func _on_play_button_pressed() -> void:
	_manager.play()

func _on_pause_button_pressed() -> void:
	_manager.pause()

func _on_resume_button_pressed() -> void:
	_manager.play()

func _on_seek_button_pressed() -> void:
	_manager.seek(5.0)

func _on_stop_button_pressed() -> void:
	_manager.stop()

func _on_mute_button_pressed() -> void:
	var backend: Variant = _manager.get_backend()
	if backend != null and backend.has_method("get_audio_state") and backend.has_method("set_muted"):
		var muted := bool(backend.get_audio_state().get("muted", false))
		backend.set_muted(not muted)
	_refresh_labels()
