extends Control

const FACTORY_SCRIPT := preload("res://src/AeroGodotVideoBackendFactory.gd")
const SAMPLE_VIDEO_PATH := "res://assets/videos/calm_blue_sea_1.ogv"
const BAD_VIDEO_PATH := "res://assets/videos/does_not_exist.ogv"
const SLOT_NAMES := ["primary", "secondary"]
const SLOT_DEFAULTS := {
	"primary": {
		"start_time": 0.0,
		"duration_hint": 12.0,
		"loop": false,
		"label": "Primary slot",
	},
	"secondary": {
		"start_time": 3.0,
		"duration_hint": 24.0,
		"loop": true,
		"label": "Secondary slot",
	},
}

var _factory: AeroGodotVideoBackendFactory
var _slot_bank: AeroGodotVideoSlotBank
var _slot_widgets: Dictionary = {}
var _summary_label: Label

func _ready() -> void:
	_build_ui()
	_factory = FACTORY_SCRIPT.new()
	_slot_bank = _factory.create_slot_bank()
	add_child(_slot_bank)
	_slot_bank.slot_state_changed.connect(_on_slot_state_changed)
	_slot_bank.slot_media_loaded.connect(_on_slot_media_loaded)
	_slot_bank.slot_error_raised.connect(_on_slot_error_raised)
	_slot_bank.slot_position_changed.connect(_on_slot_position_changed)
	for slot_name in SLOT_NAMES:
		var surface: Control = _slot_widgets[slot_name]["surface"]
		_slot_bank.create_slot_manager(slot_name, surface)
		_load_slot_sample(slot_name)
	set_process(true)
	_refresh_all_labels()

func _process(_delta: float) -> void:
	_refresh_all_labels()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "AeroGodotVideoBackend multi-slot + loop proving surface"
	root.add_child(title)

	_summary_label = Label.new()
	_summary_label.text = "Two independent video slots, shared sample asset, separate loop/audio/playback controls."
	root.add_child(_summary_label)

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 16)
	slots_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(slots_row)

	for slot_name in SLOT_NAMES:
		slots_row.add_child(_build_slot_panel(slot_name))

func _build_slot_panel(slot_name: String) -> Control:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 680)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = str(config.get("label", slot_name.capitalize()))
	column.add_child(title)

	var path_label := Label.new()
	path_label.text = SAMPLE_VIDEO_PATH
	column.add_child(path_label)

	var status_label := Label.new()
	status_label.text = "State: idle"
	column.add_child(status_label)

	var detail_label := Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.text = "Position: 0.00 / 0.00 | Loop: false | Format: unknown | Surface: false"
	column.add_child(detail_label)

	var audio_label := Label.new()
	audio_label.text = "Audio: unmuted"
	column.add_child(audio_label)

	var surface_panel := PanelContainer.new()
	surface_panel.custom_minimum_size = Vector2(480, 270)
	surface_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(surface_panel)

	var surface := Control.new()
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_panel.add_child(surface)

	var row_one := HBoxContainer.new()
	row_one.add_theme_constant_override("separation", 8)
	column.add_child(row_one)
	row_one.add_child(_make_button(slot_name, "Load sample", "load_sample"))
	row_one.add_child(_make_button(slot_name, "Load bad path", "load_bad"))
	row_one.add_child(_make_button(slot_name, "Play", "play"))
	row_one.add_child(_make_button(slot_name, "Pause", "pause"))
	row_one.add_child(_make_button(slot_name, "Resume", "resume"))

	var row_two := HBoxContainer.new()
	row_two.add_theme_constant_override("separation", 8)
	column.add_child(row_two)
	row_two.add_child(_make_button(slot_name, "Seek +5s", "seek"))
	row_two.add_child(_make_button(slot_name, "Stop", "stop"))
	var mute_button := _make_button(slot_name, "Mute", "mute")
	row_two.add_child(mute_button)
	var loop_button := _make_button(slot_name, "Loop: off", "loop")
	row_two.add_child(loop_button)

	_slot_widgets[slot_name] = {
		"path_label": path_label,
		"status_label": status_label,
		"detail_label": detail_label,
		"audio_label": audio_label,
		"surface": surface,
		"mute_button": mute_button,
		"loop_button": loop_button,
	}
	return panel

func _make_button(slot_name: String, text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_on_slot_button_pressed.bind(slot_name, action))
	return button

func _on_slot_button_pressed(slot_name: String, action: String) -> void:
	match action:
		"load_sample":
			_load_slot_sample(slot_name)
		"load_bad":
			var widget: Dictionary = _slot_widgets.get(slot_name, {})
			var path_label: Label = widget.get("path_label", null)
			if path_label != null:
				path_label.text = BAD_VIDEO_PATH
			_slot_bank.load_slot(slot_name, {"path": BAD_VIDEO_PATH})
		"play", "resume":
			_slot_bank.play_slot(slot_name)
		"pause":
			_slot_bank.pause_slot(slot_name)
		"seek":
			var state := _slot_bank.get_slot_state(slot_name)
			var target_seconds := float(state.get("position", 0.0)) + 5.0
			_slot_bank.seek_slot(slot_name, target_seconds)
		"stop":
			_slot_bank.stop_slot(slot_name)
		"mute":
			var backend: Variant = _get_slot_backend(slot_name)
			var audio_state: Dictionary = backend.get_audio_state() if backend != null and backend.has_method("get_audio_state") else {"muted": false}
			_slot_bank.set_slot_muted(slot_name, not bool(audio_state.get("muted", false)))
		"loop":
			var state := _slot_bank.get_slot_state(slot_name)
			_slot_bank.set_slot_loop(slot_name, not bool(state.get("loop", false)))
	_refresh_slot_labels(slot_name)

func _load_slot_sample(slot_name: String) -> void:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var path_label: Label = widget.get("path_label", null)
	if path_label != null:
		path_label.text = SAMPLE_VIDEO_PATH
	_slot_bank.load_slot(slot_name, {
		"path": SAMPLE_VIDEO_PATH,
		"start_time": float(config.get("start_time", 0.0)),
		"duration_hint": float(config.get("duration_hint", 12.0)),
		"loop": bool(config.get("loop", false)),
		"metadata": {
			"source": "vendor_backend_testbed",
			"slot": slot_name,
			"real_sample": true,
		},
	})

func _refresh_all_labels() -> void:
	for slot_name in SLOT_NAMES:
		_refresh_slot_labels(slot_name)
	_refresh_summary_label()

func _refresh_summary_label() -> void:
	var parts: Array[String] = []
	for slot_name in SLOT_NAMES:
		var state := _slot_bank.get_slot_state(slot_name) if _slot_bank != null else {}
		parts.append("%s=%s(loop=%s)" % [slot_name, str(state.get("state", "idle")), str(state.get("loop", false))])
	_summary_label.text = "Two independent video slots, shared sample asset, separate loop/audio/playback controls. %s" % " | ".join(parts)

func _refresh_slot_labels(slot_name: String) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	if widget.is_empty() or _slot_bank == null:
		return
	var state: Dictionary = _slot_bank.get_slot_state(slot_name)
	var media_info: Dictionary = _slot_bank.get_slot_media_info(slot_name)
	var backend: Variant = _get_slot_backend(slot_name)
	var audio_state: Dictionary = backend.get_audio_state() if backend != null and backend.has_method("get_audio_state") else {"muted": false}
	var status_label: Label = widget.get("status_label", null)
	var detail_label: Label = widget.get("detail_label", null)
	var audio_label: Label = widget.get("audio_label", null)
	var mute_button: Button = widget.get("mute_button", null)
	var loop_button: Button = widget.get("loop_button", null)
	if status_label != null:
		status_label.text = "State: %s" % str(state.get("state", "idle"))
	if detail_label != null:
		detail_label.text = "Position: %.2f / %.2f | Loop: %s | Format: %s | Surface: %s" % [
			float(state.get("position", 0.0)),
			float(state.get("duration", 0.0)),
			str(state.get("loop", false)),
			str(media_info.get("format_status", "unknown")),
			str(state.get("surface_attached", false)),
		]
	if audio_label != null:
		audio_label.text = "Audio: %s" % ("muted" if bool(audio_state.get("muted", false)) else "unmuted")
	if mute_button != null:
		mute_button.text = "Unmute" if bool(audio_state.get("muted", false)) else "Mute"
	if loop_button != null:
		loop_button.text = "Loop: %s" % ("on" if bool(state.get("loop", false)) else "off")

func _get_slot_backend(slot_name: String) -> Variant:
	var manager: Variant = _slot_bank.get_slot_manager(slot_name) if _slot_bank != null else null
	if manager == null or not manager.has_method("get_backend"):
		return null
	return manager.get_backend()

func _on_slot_state_changed(slot_name: String, _state: String, _detail: Dictionary) -> void:
	_refresh_slot_labels(slot_name)

func _on_slot_media_loaded(slot_name: String, info: Dictionary) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var status_label: Label = widget.get("status_label", null)
	if status_label != null:
		status_label.text = "%s loaded %s" % [slot_name, str(info.get("path", ""))]
	_refresh_slot_labels(slot_name)

func _on_slot_error_raised(slot_name: String, error_info: Dictionary) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var status_label: Label = widget.get("status_label", null)
	if status_label != null:
		status_label.text = "%s error: %s" % [slot_name, str(error_info.get("message", "Unknown error"))]
	_refresh_slot_labels(slot_name)

func _on_slot_position_changed(slot_name: String, _seconds: float, _normalized: float) -> void:
	_refresh_slot_labels(slot_name)
