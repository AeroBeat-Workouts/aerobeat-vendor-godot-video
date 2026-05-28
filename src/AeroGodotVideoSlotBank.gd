## Vendor-local multi-slot helper for managing multiple independent Godot video managers.
##
## This stays below the shared tool-video-player facade by composing one
## AeroVideoPlayerManager per slot, mirroring the multi-slot pattern used by the
## image loader without redefining the stable playback contract.
class_name AeroGodotVideoSlotBank
extends Node

signal slot_manager_created(slot_name: String, manager: Node)
signal slot_surface_changed(slot_name: String, descriptor: Dictionary)
signal slot_state_changed(slot_name: String, state: String, detail: Dictionary)
signal slot_position_changed(slot_name: String, seconds: float, normalized: float)
signal slot_media_loaded(slot_name: String, info: Dictionary)
signal slot_playback_finished(slot_name: String)
signal slot_error_raised(slot_name: String, error_info: Dictionary)

const DEFAULT_SLOT := "primary"
const ManagerScript := preload("res://addons/aerobeat-tool-video-player/src/AeroVideoPlayerManager.gd")
const BackendScript := preload("AeroGodotVideoBackend.gd")

var _factory: AeroGodotVideoBackendFactory = null
var _player_factory: Callable = Callable()
var _slot_entries: Dictionary = {}

func _init(factory: AeroGodotVideoBackendFactory = null, player_factory: Callable = Callable()) -> void:
	_factory = factory
	_player_factory = player_factory

func set_factory(factory: AeroGodotVideoBackendFactory) -> void:
	_factory = factory

func set_player_factory(player_factory: Callable) -> void:
	_player_factory = player_factory

func create_slot_manager(slot_name: String = DEFAULT_SLOT, surface: Node = null, source: Dictionary = {}) -> Node:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := get_slot_manager(normalized_slot)
	if manager == null:
		manager = _build_slot_manager(normalized_slot)
	if surface != null:
		attach_slot_surface(normalized_slot, surface)
	if not source.is_empty():
		load_slot(normalized_slot, source)
	return manager

func get_slot_manager(slot_name: String = DEFAULT_SLOT) -> Node:
	var normalized_slot := _normalize_slot_name(slot_name)
	var entry: Dictionary = _slot_entries.get(normalized_slot, {})
	var manager: Node = entry.get("manager", null)
	if manager != null and is_instance_valid(manager):
		return manager
	return null

func get_slot_names() -> PackedStringArray:
	return PackedStringArray(_slot_entries.keys())

func has_slot(slot_name: String) -> bool:
	return get_slot_manager(slot_name) != null

func attach_slot_surface(slot_name: String, surface: Node) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	if surface == null:
		return _fail(normalized_slot, "video_invalid_surface", "Cannot attach a null output surface.")
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.attach_surface(surface, normalized_slot)
	var entry: Dictionary = _slot_entries.get(normalized_slot, {}).duplicate(true)
	entry["surface"] = surface
	_slot_entries[normalized_slot] = entry
	var result := _snapshot_slot_result(normalized_slot)
	var descriptor := get_slot_descriptor(normalized_slot)
	slot_surface_changed.emit(normalized_slot, descriptor.duplicate(true))
	return result

func detach_slot_surface(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := get_slot_manager(normalized_slot)
	if manager == null:
		return _ok(normalized_slot, {"attached": false})
	manager.set_active_slot(normalized_slot)
	manager.detach_surface(normalized_slot)
	var entry: Dictionary = _slot_entries.get(normalized_slot, {}).duplicate(true)
	entry["surface"] = null
	_slot_entries[normalized_slot] = entry
	var result := _snapshot_slot_result(normalized_slot)
	var descriptor := get_slot_descriptor(normalized_slot)
	slot_surface_changed.emit(normalized_slot, descriptor.duplicate(true))
	return result

func load_slot(slot_name: String, source: Dictionary) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.load(source, normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func play_slot(slot_name: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.play(normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func pause_slot(slot_name: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.pause(normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func stop_slot(slot_name: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.stop(normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func unload_slot(slot_name: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := get_slot_manager(normalized_slot)
	if manager == null:
		return _ok(normalized_slot, {"unloaded": true, "created": false})
	manager.set_active_slot(normalized_slot)
	manager.unload(normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func seek_slot(slot_name: String, seconds: float) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.seek(seconds, normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func set_slot_loop(slot_name: String, enabled: bool) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.set_loop(enabled, normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func set_slot_rate(slot_name: String, rate: float) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.set_rate(rate, normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func set_slot_cover_mode(slot_name: String, cover_mode: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.set_cover_mode(cover_mode, normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func set_slot_audio_level(slot_name: String, audio_level: float) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	manager.set_audio_level(audio_level, normalized_slot)
	return _snapshot_slot_result(normalized_slot)

func set_slot_muted(slot_name: String, muted: bool) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := _ensure_slot_manager(normalized_slot)
	manager.set_active_slot(normalized_slot)
	var backend: Variant = manager.get_backend(normalized_slot) if manager.has_method("get_backend") else null
	if backend == null or not backend.has_method("set_muted"):
		return _fail(normalized_slot, "backend_audio_control_unavailable", "Slot backend does not expose vendor-local mute control.")
	var result: Dictionary = backend.set_muted(muted)
	if bool(result.get("success", false)):
		return _ok(normalized_slot, {
			"muted": muted,
			"audio": backend.get_audio_state() if backend.has_method("get_audio_state") else {},
			"state": manager.get_state(normalized_slot) if manager.has_method("get_state") else {},
			"media_info": manager.get_media_info(normalized_slot) if manager.has_method("get_media_info") else {},
		})
	return _fail(normalized_slot, str(result.get("code", "backend_audio_control_failed")), str(result.get("message", "Slot backend failed to update mute state.")), result.get("detail", {}))

func get_slot_state(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := get_slot_manager(normalized_slot)
	if manager == null:
		return {}
	manager.set_active_slot(normalized_slot)
	return manager.get_state(normalized_slot).duplicate(true)

func get_slot_media_info(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := get_slot_manager(normalized_slot)
	if manager == null:
		return {}
	manager.set_active_slot(normalized_slot)
	return manager.get_media_info(normalized_slot).duplicate(true)

func get_slot_descriptor(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager: Node = get_slot_manager(normalized_slot)
	var entry: Dictionary = _slot_entries.get(normalized_slot, {})
	var surface: Node = entry.get("surface", null)
	var state: Dictionary = manager.get_state(normalized_slot).duplicate(true) if manager != null else {}
	var media_info: Dictionary = manager.get_media_info(normalized_slot).duplicate(true) if manager != null else {}
	return {
		"slot": normalized_slot,
		"created": manager != null,
		"attached": surface != null and is_instance_valid(surface),
		"surface_path": str(surface.get_path()) if surface != null and is_instance_valid(surface) and surface.is_inside_tree() else (surface.name if surface != null and is_instance_valid(surface) else ""),
		"state": state,
		"media_info": media_info,
	}

func get_capabilities() -> Dictionary:
	return {
		"vendor": AeroGodotVideoBackend.VENDOR_NAME,
		"backend_family": AeroGodotVideoBackend.BACKEND_FAMILY,
		"supports_slots": true,
		"supports_independent_loop_control": true,
		"supports_independent_rate_control": true,
		"supports_independent_cover_mode_control": true,
		"supports_independent_audio_level_control": true,
		"supports_independent_audio_control": true,
		"slot_names": get_slot_names(),
	}

func reset() -> void:
	for slot_name in _slot_entries.keys():
		var normalized_slot := str(slot_name)
		var manager := get_slot_manager(normalized_slot)
		if manager != null and manager.has_method("reset"):
			manager.set_active_slot(normalized_slot)
			manager.reset(normalized_slot)

func unload_all() -> void:
	for slot_name in _slot_entries.keys():
		var normalized_slot := str(slot_name)
		var manager := get_slot_manager(normalized_slot)
		if manager != null and manager.has_method("unload"):
			manager.set_active_slot(normalized_slot)
			manager.unload(normalized_slot)

func _ensure_slot_manager(slot_name: String) -> Node:
	var manager := get_slot_manager(slot_name)
	if manager != null:
		return manager
	return _build_slot_manager(slot_name)

func _build_slot_manager(slot_name: String) -> Node:
	var manager: Node
	if _factory != null:
		manager = _factory.create_manager(_player_factory)
	else:
		manager = ManagerScript.new()
		var backend := BackendScript.new()
		if _player_factory.is_valid():
			backend.set_player_factory(_player_factory)
		manager.set_backend_factory(func() -> AeroVideoPlayerBackend:
			var created_backend := BackendScript.new()
			if _player_factory.is_valid():
				created_backend.set_player_factory(_player_factory)
			return created_backend
		)
		manager.set_backend(backend)
	manager.name = "VideoManager_%s" % slot_name.capitalize()
	add_child(manager)
	manager.set_active_slot(slot_name)
	_slot_entries[slot_name] = {
		"manager": manager,
		"surface": null,
	}
	_connect_manager_signals(slot_name, manager)
	slot_manager_created.emit(slot_name, manager)
	return manager

func _connect_manager_signals(slot_name: String, manager: Node) -> void:
	if manager.has_signal("state_changed"):
		manager.state_changed.connect(_on_slot_state_changed.bind(slot_name))
	if manager.has_signal("position_changed"):
		manager.position_changed.connect(_on_slot_position_changed.bind(slot_name))
	if manager.has_signal("media_loaded"):
		manager.media_loaded.connect(_on_slot_media_loaded.bind(slot_name))
	if manager.has_signal("playback_finished"):
		manager.playback_finished.connect(_on_slot_playback_finished.bind(slot_name))
	if manager.has_signal("error_raised"):
		manager.error_raised.connect(_on_slot_error_raised.bind(slot_name))

func _snapshot_slot_result(slot_name: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	var manager := get_slot_manager(normalized_slot)
	if manager == null:
		return _fail(normalized_slot, "video_slot_missing", "Requested slot does not exist.")
	manager.set_active_slot(normalized_slot)
	var error_info: Dictionary = manager.get_last_error(normalized_slot).duplicate(true) if manager.has_method("get_last_error") else {}
	if not error_info.is_empty():
		return _fail(normalized_slot, str(error_info.get("code", "video_slot_operation_failed")), str(error_info.get("message", "Video slot operation failed.")), error_info.get("detail", {}))
	return _ok(normalized_slot, {
		"state": manager.get_state(normalized_slot).duplicate(true) if manager.has_method("get_state") else {},
		"media_info": manager.get_media_info(normalized_slot).duplicate(true) if manager.has_method("get_media_info") else {},
		"attached": bool(get_slot_descriptor(normalized_slot).get("attached", false)),
		"slot_names": get_slot_names(),
	})

func _ok(slot_name: String, detail: Dictionary = {}) -> Dictionary:
	var payload := detail.duplicate(true)
	payload["slot"] = slot_name
	return AeroVideoPlayerBackend.CoreContract.ok(payload)

func _fail(slot_name: String, code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	var payload := detail.duplicate(true)
	payload["slot"] = slot_name
	return AeroVideoPlayerBackend.CoreContract.fail(code, message, payload)

func _on_slot_state_changed(state: String, detail: Dictionary, slot_name: String) -> void:
	slot_state_changed.emit(slot_name, state, detail.duplicate(true))

func _on_slot_position_changed(seconds: float, normalized: float, slot_name: String) -> void:
	slot_position_changed.emit(slot_name, seconds, normalized)

func _on_slot_media_loaded(info: Dictionary, slot_name: String) -> void:
	slot_media_loaded.emit(slot_name, info.duplicate(true))

func _on_slot_playback_finished(slot_name: String) -> void:
	slot_playback_finished.emit(slot_name)

func _on_slot_error_raised(error_info: Dictionary, slot_name: String) -> void:
	slot_error_raised.emit(slot_name, error_info.duplicate(true))

static func _normalize_slot_name(slot_name: String) -> String:
	var normalized := slot_name.strip_edges().to_lower()
	return normalized if not normalized.is_empty() else DEFAULT_SLOT
