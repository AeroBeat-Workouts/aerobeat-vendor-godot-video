extends Control

const FACTORY_SCRIPT := preload("res://addons/aerobeat-vendor-godot-video/src/AeroGodotVideoBackendFactory.gd")
const SAMPLE_VIDEO_PATH := "res://assets/videos/calm_blue_sea_1.ogv"
const SAMPLE_VIDEO_PROJECT_PATH := "assets/videos/calm_blue_sea_1.ogv"
const SAMPLE_DURATION_SECONDS := 28.693313
const SAMPLE_REMOTE_URL := "https://example.com/path/to/video.ogv"
const BAD_VIDEO_PATH := "res://assets/videos/does_not_exist.ogv"
const SLOT_NAMES := ["primary", "secondary"]
const COVER_MODES := [
	AeroVideoPlayerManager.COVER_MODE_STRETCH,
	AeroVideoPlayerManager.COVER_MODE_CONTAIN,
	AeroVideoPlayerManager.COVER_MODE_COVER,
]
const SLOT_DEFAULTS := {
	"primary": {
		"start_time": 0.0,
		"duration_hint": SAMPLE_DURATION_SECONDS,
		"loop": false,
		"cover_mode": AeroVideoPlayerManager.COVER_MODE_CONTAIN,
		"audio_level": 1.0,
		"label": "Primary slot",
	},
	"secondary": {
		"start_time": 3.0,
		"duration_hint": SAMPLE_DURATION_SECONDS,
		"loop": true,
		"cover_mode": AeroVideoPlayerManager.COVER_MODE_COVER,
		"audio_level": 0.6,
		"label": "Secondary slot",
	},
}

var _factory: AeroGodotVideoBackendFactory
var _slot_bank: AeroGodotVideoSlotBank
var _slot_widgets: Dictionary = {}
var _summary_label: Label
var _slots_grid: GridContainer
var _cover_syncing := {}
var _audio_syncing := {}
var _seek_syncing := {}
var _external_sample_dir: String = ""
var _external_sample_path: String = ""

func _ready() -> void:
	_prepare_external_sample()
	_build_ui()
	_factory = FACTORY_SCRIPT.new()
	_slot_bank = _factory.create_slot_bank()
	add_child(_slot_bank)
	_slot_bank.slot_state_changed.connect(_on_slot_state_changed)
	_slot_bank.slot_media_loaded.connect(_on_slot_media_loaded)
	_slot_bank.slot_error_raised.connect(_on_slot_error_raised)
	_slot_bank.slot_position_changed.connect(_on_slot_position_changed)
	for slot_name in SLOT_NAMES:
		_cover_syncing[slot_name] = false
		_audio_syncing[slot_name] = false
		_seek_syncing[slot_name] = false
		var surface: Control = _slot_widgets[slot_name]["surface"]
		_slot_bank.create_slot_manager(slot_name, surface)
		_apply_slot_defaults(slot_name)
		_load_slot_project_path(slot_name)
	resized.connect(_on_testbed_resized)
	set_process(true)
	_refresh_all_labels()

func _exit_tree() -> void:
	if not _external_sample_path.is_empty() and FileAccess.file_exists(_external_sample_path):
		DirAccess.remove_absolute(_external_sample_path)
	if not _external_sample_dir.is_empty() and DirAccess.dir_exists_absolute(_external_sample_dir):
		DirAccess.remove_absolute(_external_sample_dir)

func _process(_delta: float) -> void:
	_refresh_responsive_layout()
	_refresh_all_labels()

func _prepare_external_sample() -> void:
	_external_sample_dir = OS.get_cache_dir().path_join("aerobeat-vendor-godot-video-testbed")
	DirAccess.make_dir_recursive_absolute(_external_sample_dir)
	_external_sample_path = _external_sample_dir.path_join("calm_blue_sea_1.ogv")
	if not FileAccess.file_exists(_external_sample_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAMPLE_VIDEO_PATH), _external_sample_path)

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = "AeroGodotVideoBackend multi-slot + arbitrary-source + timeline proving surface"
	root.add_child(title)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.text = "Two independent video slots, package/device/URL source inputs, clickable seek timelines, and preserved unload/clipping behavior."
	root.add_child(_summary_label)

	_slots_grid = GridContainer.new()
	_slots_grid.columns = 2
	_slots_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots_grid.add_theme_constant_override("h_separation", 16)
	_slots_grid.add_theme_constant_override("v_separation", 16)
	root.add_child(_slots_grid)

	for slot_name in SLOT_NAMES:
		_slots_grid.add_child(_build_slot_panel(slot_name))

	call_deferred("_refresh_responsive_layout")

func _build_slot_panel(slot_name: String) -> Control:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 640)
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
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.text = SAMPLE_VIDEO_PROJECT_PATH
	column.add_child(path_label)

	var source_row := HBoxContainer.new()
	source_row.add_theme_constant_override("separation", 8)
	column.add_child(source_row)

	var source_input := LineEdit.new()
	source_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_input.placeholder_text = "Package path, device path, or URL"
	source_input.text = SAMPLE_VIDEO_PROJECT_PATH
	source_row.add_child(source_input)

	var duration_spin := SpinBox.new()
	duration_spin.custom_minimum_size = Vector2(110, 0)
	duration_spin.min_value = 0.0
	duration_spin.max_value = 36000.0
	duration_spin.step = 0.01
	duration_spin.value = float(config.get("duration_hint", SAMPLE_DURATION_SECONDS))
	source_row.add_child(duration_spin)

	var load_button := Button.new()
	load_button.text = "Load path"
	load_button.pressed.connect(_load_slot_from_input.bind(slot_name))
	source_row.add_child(load_button)

	var preset_row := HFlowContainer.new()
	preset_row.add_theme_constant_override("h_separation", 8)
	preset_row.add_theme_constant_override("v_separation", 8)
	preset_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(preset_row)
	preset_row.add_child(_make_button(slot_name, "Packaged", "use_project_source"))
	preset_row.add_child(_make_button(slot_name, "Device file", "use_external_source"))
	preset_row.add_child(_make_button(slot_name, "URL", "use_url_source"))
	preset_row.add_child(_make_button(slot_name, "Load bad path", "load_bad"))

	var status_label := Label.new()
	status_label.text = "State: idle"
	column.add_child(status_label)

	var detail_label := Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.text = "Position: 0.00 / 0.00 | Loop: false | Cover: contain | Format: unknown | Surface: false"
	column.add_child(detail_label)

	var audio_label := Label.new()
	audio_label.text = "Audio: 100% | unmuted"
	column.add_child(audio_label)

	var surface_panel := PanelContainer.new()
	surface_panel.custom_minimum_size = Vector2(320, 180)
	surface_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(surface_panel)

	var surface := Control.new()
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_panel.add_child(surface)

	var config_row := HFlowContainer.new()
	config_row.add_theme_constant_override("h_separation", 8)
	config_row.add_theme_constant_override("v_separation", 8)
	config_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(config_row)

	var cover_label := Label.new()
	cover_label.text = "Cover"
	config_row.add_child(cover_label)

	var cover_option := OptionButton.new()
	cover_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for cover_mode in COVER_MODES:
		cover_option.add_item(_cover_mode_label(cover_mode))
	cover_option.item_selected.connect(_on_cover_selected.bind(slot_name))
	config_row.add_child(cover_option)

	var audio_caption := Label.new()
	audio_caption.text = "Audio"
	config_row.add_child(audio_caption)

	var audio_slider := HSlider.new()
	audio_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_slider.min_value = 0.0
	audio_slider.max_value = 1.0
	audio_slider.step = 0.01
	audio_slider.value_changed.connect(_on_audio_slider_changed.bind(slot_name))
	config_row.add_child(audio_slider)

	var audio_value_label := Label.new()
	audio_value_label.text = "100%"
	config_row.add_child(audio_value_label)

	var timeline_row := HBoxContainer.new()
	timeline_row.add_theme_constant_override("separation", 8)
	column.add_child(timeline_row)

	var seek_back_button := _make_button(slot_name, "-5s", "seek_back")
	timeline_row.add_child(seek_back_button)

	var seek_slider := HSlider.new()
	seek_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seek_slider.min_value = 0.0
	seek_slider.max_value = 1.0
	seek_slider.step = 0.01
	seek_slider.editable = false
	seek_slider.value_changed.connect(_on_seek_slider_value_changed.bind(slot_name))
	seek_slider.drag_ended.connect(_on_seek_slider_drag_ended.bind(slot_name))
	timeline_row.add_child(seek_slider)

	var seek_forward_button := _make_button(slot_name, "+5s", "seek_forward")
	timeline_row.add_child(seek_forward_button)

	var seek_value_label := Label.new()
	seek_value_label.text = _format_seconds(0.0)
	timeline_row.add_child(seek_value_label)

	var timeline_hint := Label.new()
	timeline_hint.text = "Timeline: click or drag to seek"
	column.add_child(timeline_hint)

	var row_two := HFlowContainer.new()
	row_two.add_theme_constant_override("h_separation", 8)
	row_two.add_theme_constant_override("v_separation", 8)
	row_two.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(row_two)
	row_two.add_child(_make_button(slot_name, "Play", "play"))
	row_two.add_child(_make_button(slot_name, "Pause", "pause"))
	row_two.add_child(_make_button(slot_name, "Resume", "resume"))
	row_two.add_child(_make_button(slot_name, "Stop", "stop"))
	row_two.add_child(_make_button(slot_name, "Unload", "unload"))
	var mute_button := _make_button(slot_name, "Mute", "mute")
	row_two.add_child(mute_button)
	var loop_button := _make_button(slot_name, "Loop: off", "loop")
	row_two.add_child(loop_button)

	_slot_widgets[slot_name] = {
		"path_label": path_label,
		"source_input": source_input,
		"duration_spin": duration_spin,
		"status_label": status_label,
		"detail_label": detail_label,
		"audio_label": audio_label,
		"surface": surface,
		"cover_option": cover_option,
		"audio_slider": audio_slider,
		"audio_value_label": audio_value_label,
		"seek_slider": seek_slider,
		"seek_value_label": seek_value_label,
		"mute_button": mute_button,
		"loop_button": loop_button,
	}
	return panel

func _make_button(slot_name: String, text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_on_slot_button_pressed.bind(slot_name, action))
	return button

func _apply_slot_defaults(slot_name: String) -> void:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var cover_option: OptionButton = widget.get("cover_option", null)
	var audio_slider: HSlider = widget.get("audio_slider", null)
	var duration_spin: SpinBox = widget.get("duration_spin", null)
	if cover_option != null:
		_cover_syncing[slot_name] = true
		cover_option.select(_cover_mode_index(String(config.get("cover_mode", AeroVideoPlayerManager.DEFAULT_COVER_MODE))))
		_cover_syncing[slot_name] = false
	if audio_slider != null:
		_audio_syncing[slot_name] = true
		audio_slider.value = float(config.get("audio_level", 1.0))
		_audio_syncing[slot_name] = false
	if duration_spin != null:
		duration_spin.value = float(config.get("duration_hint", SAMPLE_DURATION_SECONDS))
	_set_slot_source_input(slot_name, SAMPLE_VIDEO_PROJECT_PATH, float(config.get("duration_hint", SAMPLE_DURATION_SECONDS)))
	_slot_bank.set_slot_cover_mode(slot_name, String(config.get("cover_mode", AeroVideoPlayerManager.DEFAULT_COVER_MODE)))
	_slot_bank.set_slot_audio_level(slot_name, float(config.get("audio_level", 1.0)))

func _on_slot_button_pressed(slot_name: String, action: String) -> void:
	match action:
		"use_project_source":
			_load_slot_project_path(slot_name)
		"use_external_source":
			_load_slot_external_path(slot_name)
		"use_url_source":
			_load_slot_url(slot_name)
		"load_bad":
			_set_slot_source_input(slot_name, BAD_VIDEO_PATH, _selected_duration_hint(slot_name))
			_load_slot_source(slot_name, BAD_VIDEO_PATH, {"source_variant": "bad_path"})
		"play", "resume":
			_slot_bank.play_slot(slot_name)
		"pause":
			_slot_bank.pause_slot(slot_name)
		"seek_back":
			_seek_slot_by(slot_name, -5.0)
		"seek_forward":
			_seek_slot_by(slot_name, 5.0)
		"stop":
			_slot_bank.stop_slot(slot_name)
		"unload":
			_slot_bank.unload_slot(slot_name)
		"mute":
			var backend: Variant = _get_slot_backend(slot_name)
			var audio_state: Dictionary = backend.get_audio_state() if backend != null and backend.has_method("get_audio_state") else {"muted": false}
			_slot_bank.set_slot_muted(slot_name, not bool(audio_state.get("muted", false)))
		"loop":
			var state := _slot_bank.get_slot_state(slot_name)
			_slot_bank.set_slot_loop(slot_name, not bool(state.get("loop", false)))
	_refresh_slot_labels(slot_name)

func _load_slot_project_path(slot_name: String) -> void:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	_set_slot_source_input(slot_name, SAMPLE_VIDEO_PROJECT_PATH, float(config.get("duration_hint", SAMPLE_DURATION_SECONDS)))
	_load_slot_source(slot_name, SAMPLE_VIDEO_PROJECT_PATH, {"source_variant": "project_relative"})

func _load_slot_external_path(slot_name: String) -> void:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	_set_slot_source_input(slot_name, _external_sample_path, float(config.get("duration_hint", SAMPLE_DURATION_SECONDS)))
	_load_slot_source(slot_name, _external_sample_path, {"source_variant": "absolute_device_path"})

func _load_slot_url(slot_name: String) -> void:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	_set_slot_source_input(slot_name, SAMPLE_REMOTE_URL, float(config.get("duration_hint", SAMPLE_DURATION_SECONDS)))
	_load_slot_source(slot_name, SAMPLE_REMOTE_URL, {"source_variant": "url"})

func _load_slot_from_input(slot_name: String) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var source_input: LineEdit = widget.get("source_input", null)
	if source_input == null:
		return
	_load_slot_source(slot_name, source_input.text, {"source_variant": "manual"})

func _load_slot_source(slot_name: String, path: String, extra_metadata: Dictionary = {}) -> void:
	var config: Dictionary = SLOT_DEFAULTS.get(slot_name, {})
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var path_label: Label = widget.get("path_label", null)
	if path_label != null:
		path_label.text = path
	var metadata := {
		"source": "vendor_backend_testbed",
		"slot": slot_name,
		"real_sample": path in [SAMPLE_VIDEO_PATH, SAMPLE_VIDEO_PROJECT_PATH, _external_sample_path, SAMPLE_REMOTE_URL],
	}
	metadata.merge(extra_metadata, true)
	_slot_bank.load_slot(slot_name, {
		"path": path,
		"start_time": float(config.get("start_time", 0.0)),
		"duration_hint": _selected_duration_hint(slot_name),
		"loop": bool(config.get("loop", false)),
		"cover_mode": _selected_cover_mode(slot_name),
		"audio_level": _selected_audio_level(slot_name),
		"metadata": metadata,
	})

func _seek_slot_by(slot_name: String, delta_seconds: float) -> void:
	var state := _slot_bank.get_slot_state(slot_name)
	var duration := float(state.get("duration", 0.0))
	if duration <= 0.0:
		return
	var target_seconds := clampf(float(state.get("position", 0.0)) + delta_seconds, 0.0, duration)
	_slot_bank.seek_slot(slot_name, target_seconds)

func _refresh_all_labels() -> void:
	for slot_name in SLOT_NAMES:
		_refresh_slot_labels(slot_name)
	_refresh_summary_label()

func _refresh_summary_label() -> void:
	var parts: Array[String] = []
	for slot_name in SLOT_NAMES:
		var state := _slot_bank.get_slot_state(slot_name) if _slot_bank != null else {}
		parts.append("%s=%s(loop=%s cover=%s audio=%s path=%s)" % [
			slot_name,
			str(state.get("state", "idle")),
			str(state.get("loop", false)),
			str(state.get("cover_mode", AeroVideoPlayerManager.DEFAULT_COVER_MODE)),
			_format_audio_level(float(state.get("audio_level", 1.0))),
			str(state.get("source", {}).get("path", "")),
		])
	_summary_label.text = "Two independent video slots, package/device/URL source inputs, clickable seek timelines, and preserved unload/clipping behavior. %s" % " | ".join(parts)

func _refresh_slot_labels(slot_name: String) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	if widget.is_empty() or _slot_bank == null:
		return
	var state: Dictionary = _slot_bank.get_slot_state(slot_name)
	var media_info: Dictionary = _slot_bank.get_slot_media_info(slot_name)
	var backend: Variant = _get_slot_backend(slot_name)
	var audio_state: Dictionary = backend.get_audio_state() if backend != null and backend.has_method("get_audio_state") else {"muted": false, "audio_level": float(state.get("audio_level", 1.0))}
	var status_label: Label = widget.get("status_label", null)
	var detail_label: Label = widget.get("detail_label", null)
	var audio_label: Label = widget.get("audio_label", null)
	var mute_button: Button = widget.get("mute_button", null)
	var loop_button: Button = widget.get("loop_button", null)
	var cover_option: OptionButton = widget.get("cover_option", null)
	var audio_slider: HSlider = widget.get("audio_slider", null)
	var audio_value_label: Label = widget.get("audio_value_label", null)
	var seek_slider: HSlider = widget.get("seek_slider", null)
	var seek_value_label: Label = widget.get("seek_value_label", null)
	if status_label != null:
		status_label.text = "State: %s" % str(state.get("state", "idle"))
	if detail_label != null:
		detail_label.text = "Position: %.2f / %.2f | Loop: %s | Cover: %s | Format: %s | Surface: %s | Resolved: %s" % [
			float(state.get("position", 0.0)),
			float(state.get("duration", 0.0)),
			str(state.get("loop", false)),
			str(state.get("cover_mode", AeroVideoPlayerManager.DEFAULT_COVER_MODE)),
			str(media_info.get("format_status", "unknown")),
			str(state.get("surface_attached", false)),
			str(media_info.get("resolved_path", media_info.get("path", ""))),
		]
	var displayed_audio_level := float(audio_state.get("audio_level", state.get("audio_level", 1.0)))
	if audio_label != null:
		audio_label.text = "Audio: %s | %s" % [
			_format_audio_level(displayed_audio_level),
			"muted" if bool(audio_state.get("muted", false)) else "unmuted",
		]
	if mute_button != null:
		mute_button.text = "Unmute" if bool(audio_state.get("muted", false)) else "Mute"
	if loop_button != null:
		loop_button.text = "Loop: %s" % ("on" if bool(state.get("loop", false)) else "off")
	if cover_option != null:
		_cover_syncing[slot_name] = true
		cover_option.select(_cover_mode_index(String(state.get("cover_mode", AeroVideoPlayerManager.DEFAULT_COVER_MODE))))
		_cover_syncing[slot_name] = false
	if audio_slider != null:
		_audio_syncing[slot_name] = true
		audio_slider.value = float(state.get("audio_level", 1.0))
		_audio_syncing[slot_name] = false
	if audio_value_label != null:
		audio_value_label.text = _format_audio_level(float(state.get("audio_level", 1.0)))
	if seek_slider != null:
		_seek_syncing[slot_name] = true
		seek_slider.editable = float(state.get("duration", 0.0)) > 0.0
		seek_slider.max_value = maxf(float(state.get("duration", 0.0)), 0.0)
		seek_slider.value = clampf(float(state.get("position", 0.0)), 0.0, seek_slider.max_value)
		_seek_syncing[slot_name] = false
	if seek_value_label != null and seek_slider != null:
		seek_value_label.text = _format_seconds(seek_slider.value)

func _get_slot_backend(slot_name: String) -> Variant:
	var manager: Variant = _slot_bank.get_slot_manager(slot_name) if _slot_bank != null else null
	if manager == null or not manager.has_method("get_backend"):
		return null
	return manager.get_backend()

func _cover_mode_index(cover_mode: String) -> int:
	var normalized := String(cover_mode).strip_edges().to_lower()
	var index := COVER_MODES.find(normalized)
	return index if index >= 0 else COVER_MODES.find(AeroVideoPlayerManager.DEFAULT_COVER_MODE)

func _cover_mode_label(cover_mode: String) -> String:
	match cover_mode:
		AeroVideoPlayerManager.COVER_MODE_STRETCH:
			return "Stretch"
		AeroVideoPlayerManager.COVER_MODE_COVER:
			return "Cover"
		_:
			return "Contain"

func _selected_cover_mode(slot_name: String) -> String:
	var option: OptionButton = _slot_widgets.get(slot_name, {}).get("cover_option", null)
	if option == null:
		return AeroVideoPlayerManager.DEFAULT_COVER_MODE
	var selected := option.selected
	if selected < 0 or selected >= COVER_MODES.size():
		return AeroVideoPlayerManager.DEFAULT_COVER_MODE
	return COVER_MODES[selected]

func _selected_audio_level(slot_name: String) -> float:
	var slider: HSlider = _slot_widgets.get(slot_name, {}).get("audio_slider", null)
	return float(slider.value) if slider != null else 1.0

func _selected_duration_hint(slot_name: String) -> float:
	var spin: SpinBox = _slot_widgets.get(slot_name, {}).get("duration_spin", null)
	return float(spin.value) if spin != null else SAMPLE_DURATION_SECONDS

func _set_slot_source_input(slot_name: String, path: String, duration_hint: float) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var source_input: LineEdit = widget.get("source_input", null)
	var duration_spin: SpinBox = widget.get("duration_spin", null)
	if source_input != null:
		source_input.text = path
	if duration_spin != null:
		duration_spin.value = duration_hint

func _on_testbed_resized() -> void:
	_refresh_responsive_layout()

func _refresh_responsive_layout() -> void:
	if _slots_grid == null:
		return
	var available_width := maxf(size.x, get_viewport_rect().size.x)
	var desired_columns := 2 if available_width >= 1180.0 else 1
	if _slots_grid.columns != desired_columns:
		_slots_grid.columns = desired_columns

func _format_audio_level(audio_level: float) -> String:
	return "%d%%" % int(round(clampf(audio_level, 0.0, 1.0) * 100.0))

func _format_seconds(seconds: float) -> String:
	var clamped := maxf(seconds, 0.0)
	var minutes := int(floor(clamped / 60.0))
	var remainder := clamped - float(minutes * 60)
	return "%02d:%05.2f" % [minutes, remainder]

func _on_cover_selected(_index: int, slot_name: String) -> void:
	if bool(_cover_syncing.get(slot_name, false)):
		return
	_slot_bank.set_slot_cover_mode(slot_name, _selected_cover_mode(slot_name))
	_refresh_slot_labels(slot_name)

func _on_audio_slider_changed(value: float, slot_name: String) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var audio_value_label: Label = widget.get("audio_value_label", null)
	if audio_value_label != null:
		audio_value_label.text = _format_audio_level(value)
	if bool(_audio_syncing.get(slot_name, false)):
		return
	_slot_bank.set_slot_audio_level(slot_name, value)
	_refresh_slot_labels(slot_name)

func _on_seek_slider_value_changed(value: float, slot_name: String) -> void:
	var widget: Dictionary = _slot_widgets.get(slot_name, {})
	var seek_value_label: Label = widget.get("seek_value_label", null)
	if seek_value_label != null:
		seek_value_label.text = _format_seconds(value)

func _on_seek_slider_drag_ended(value_changed: bool, slot_name: String) -> void:
	if not value_changed or bool(_seek_syncing.get(slot_name, false)):
		return
	var seek_slider: HSlider = _slot_widgets.get(slot_name, {}).get("seek_slider", null)
	if seek_slider == null:
		return
	_slot_bank.seek_slot(slot_name, seek_slider.value)

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
