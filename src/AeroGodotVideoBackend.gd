class_name AeroGodotVideoBackend
extends "res://src/AeroVideoVendorBackend.gd"

const VENDOR_NAME := "godot_video"
const BACKEND_FAMILY := "godot_builtin_video"
const SOURCE_KIND_FILE := "file"
const SOURCE_KIND_URL := "url"
const SUPPORTED_SOURCE_KINDS := [SOURCE_KIND_FILE]
const VERIFIED_EXTENSIONS := ["ogv"]
const UNVERIFIED_EXTENSIONS := ["mp4", "webm", "mov", "mkv", "avi"]

const STATE_IDLE := "idle"
const STATE_ATTACHED := "attached"
const STATE_READY := "ready"
const STATE_PLAYING := "playing"
const STATE_PAUSED := "paused"
const STATE_ERROR := "error"

var _surface: Node = null
var _player: Node = null
var _player_factory: Callable = Callable()
var _loaded_source: Dictionary = {}
var _media_info: Dictionary = {}
var _last_error: Dictionary = {}
var _vendor_state: String = STATE_IDLE
var _position_seconds: float = 0.0
var _duration_seconds: float = 0.0
var _loop_enabled: bool = false
var _rate: float = 1.0

func set_player_factory(factory: Callable) -> void:
	_player_factory = factory

func set_player_node(node: Node) -> void:
	_player = node
	_sync_player_binding()

func normalize_source(source: Dictionary) -> Dictionary:
	var normalized := {
		"path": "",
		"kind": SOURCE_KIND_FILE,
		"loop": false,
		"autoplay": false,
		"start_time": 0.0,
		"rate": 1.0,
		"metadata": {},
	}
	for key in source.keys():
		normalized[key] = source[key]

	var original_path := String(normalized.get("path", "")).strip_edges()
	var inferred_kind := String(normalized.get("kind", "")).strip_edges().to_lower()
	if inferred_kind.is_empty():
		inferred_kind = _infer_source_kind(original_path)
	if original_path.to_lower().begins_with("file://"):
		normalized["path"] = _normalize_file_uri(original_path)
	else:
		normalized["path"] = original_path
	normalized["original_path"] = original_path
	normalized["kind"] = inferred_kind if not inferred_kind.is_empty() else SOURCE_KIND_FILE
	normalized["loop"] = bool(normalized.get("loop", false))
	normalized["autoplay"] = bool(normalized.get("autoplay", false))
	normalized["start_time"] = maxf(0.0, float(normalized.get("start_time", 0.0)))
	normalized["rate"] = float(normalized.get("rate", 1.0))
	if typeof(normalized.get("metadata", {})) != TYPE_DICTIONARY:
		normalized["metadata"] = {}
	normalized["vendor"] = VENDOR_NAME
	normalized["backend_family"] = BACKEND_FAMILY
	normalized["locality"] = _detect_locality(String(normalized.get("path", "")))
	normalized["is_local_file"] = normalized["kind"] == SOURCE_KIND_FILE and String(normalized.get("locality", "")) != "remote"
	normalized["extension"] = String(normalized.get("path", "")).get_extension().to_lower()
	return normalized

func validate_source(source: Dictionary) -> Dictionary:
	if String(source.get("path", "")).is_empty():
		return {
			"code": "backend_source_missing_path",
			"message": "Video source path must be a non-empty local file path.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	if String(source.get("kind", SOURCE_KIND_FILE)) != SOURCE_KIND_FILE:
		return {
			"code": "backend_source_kind_unsupported",
			"message": "Godot vendor backend currently supports only local file sources.",
			"detail": {"field": "kind", "source": source.duplicate(true), "supported": SUPPORTED_SOURCE_KINDS.duplicate()},
		}
	if String(source.get("locality", "remote")) == "remote":
		return {
			"code": "backend_source_not_local",
			"message": "Godot vendor backend only accepts local file playback in this slice.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	if float(source.get("rate", 1.0)) <= 0.0:
		return {
			"code": "backend_invalid_rate",
			"message": "Playback rate must be greater than zero.",
			"detail": {"field": "rate", "source": source.duplicate(true)},
		}
	return {}

func get_capabilities() -> Dictionary:
	return {
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"supported_source_kinds": SUPPORTED_SOURCE_KINDS.duplicate(),
		"verified_extensions": VERIFIED_EXTENSIONS.duplicate(),
		"unverified_extensions": UNVERIFIED_EXTENSIONS.duplicate(),
		"remote_sources_supported": false,
		"surface_attach_mode": "direct_or_container_child",
		"surface_types": ["VideoStreamPlayer", "Node", "CanvasItem", "Control"],
		"metadata_known_fields": ["path", "kind", "vendor", "backend_family", "extension", "locality", "duration", "position", "surface_attached", "format_status"],
	}

func load(source: Dictionary) -> Dictionary:
	var normalized := normalize_source(source)
	var validation_error := validate_source(normalized)
	if not validation_error.is_empty():
		return _fail(
			String(validation_error.get("code", "backend_invalid_source")),
			String(validation_error.get("message", "Invalid source.")),
			validation_error.get("detail", {})
		)

	_loaded_source = normalized.duplicate(true)
	_loop_enabled = bool(_loaded_source.get("loop", false))
	_rate = float(_loaded_source.get("rate", 1.0))
	_position_seconds = float(_loaded_source.get("start_time", 0.0))
	_duration_seconds = maxf(_position_seconds, float(_loaded_source.get("duration_hint", 0.0)))
	_media_info = _build_media_info(_loaded_source)
	_sync_player_configuration()
	_last_error = {}
	_vendor_state = STATE_READY
	if bool(_loaded_source.get("autoplay", false)):
		_vendor_state = STATE_PLAYING
	return _ok({
		"source": _loaded_source.duplicate(true),
		"media_info": _media_info.duplicate(true),
		"vendor_state": _vendor_state,
	})

func play() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot start playback before a source is loaded.")
	_vendor_state = STATE_PLAYING
	if _player != null and _player.has_method("play"):
		_player.call("play")
	elif _player != null and _player.has_method("set"):
		_player.set("playing", true)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func pause() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot pause playback before a source is loaded.")
	_vendor_state = STATE_PAUSED
	if _player != null and _player.has_method("pause"):
		_player.call("pause")
	elif _player != null and _player.has_method("set"):
		_player.set("playing", false)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func stop() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot stop playback before a source is loaded.")
	_vendor_state = STATE_READY
	_position_seconds = 0.0
	if _player != null and _player.has_method("stop"):
		_player.call("stop")
	elif _player != null and _player.has_method("set"):
		_player.set("playing", false)
		_player.set("stream_position", 0.0)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func seek(seconds: float) -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot seek before a source is loaded.")
	_position_seconds = maxf(0.0, seconds)
	if _duration_seconds > 0.0:
		_position_seconds = minf(_position_seconds, _duration_seconds)
	if _player != null and _player.has_method("set"):
		_player.set("stream_position", _position_seconds)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func set_loop(enabled: bool) -> Dictionary:
	_loop_enabled = enabled
	if not _loaded_source.is_empty():
		_loaded_source["loop"] = enabled
	if _player != null and _player.has_method("set"):
		_player.set("loop", enabled)
	_last_error = {}
	return _ok({"loop": _loop_enabled})

func set_rate(rate: float) -> Dictionary:
	if rate <= 0.0:
		return _fail("backend_invalid_rate", "Playback rate must be greater than zero.", {"rate": rate})
	_rate = rate
	if not _loaded_source.is_empty():
		_loaded_source["rate"] = rate
	if _player != null and _player.has_method("set"):
		_player.set("playback_speed", rate)
	_last_error = {}
	return _ok({"rate": _rate})

func get_state() -> Dictionary:
	return translate_backend_state(_snapshot_player_state())

func get_position() -> float:
	return float(get_state().get("position", _position_seconds))

func get_duration() -> float:
	return float(get_state().get("duration", _duration_seconds))

func get_media_info() -> Dictionary:
	return _media_info.duplicate(true)

func attach_surface(node: Node) -> Dictionary:
	if node == null:
		return _fail("backend_invalid_surface", "Cannot attach a null output surface.")
	_surface = node
	var player_result := _ensure_player()
	if not bool(player_result.get("success", false)):
		return player_result
	_sync_player_binding()
	_sync_player_configuration()
	_last_error = {}
	if _loaded_source.is_empty():
		_vendor_state = STATE_ATTACHED
	return _ok({
		"surface_attached": true,
		"surface_path": str(node.get_path()) if node.is_inside_tree() else node.name,
		"player_present": _player != null,
	})

func detach_surface() -> Dictionary:
	if _player != null and _surface != null and _player != _surface and _player.get_parent() == _surface:
		_surface.remove_child(_player)
		if _player.has_method("queue_free"):
			_player.call("queue_free")
		_player = null
	_surface = null
	if _loaded_source.is_empty():
		_vendor_state = STATE_IDLE
	_last_error = {}
	return _ok({"surface_attached": false})

func get_last_error() -> Dictionary:
	return _last_error.duplicate(true)

func translate_backend_error(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	var category := "runtime"
	var recoverable := true
	match code:
		"backend_source_missing_path", "backend_source_not_local", "backend_source_kind_unsupported":
			category = "source"
		"backend_invalid_surface", "backend_player_unavailable":
			category = "surface"
		"backend_invalid_rate", "backend_not_loaded":
			category = "state"
		_:
			category = "runtime"
	if code == "backend_player_unavailable":
		recoverable = false
	return {
		"code": code,
		"message": message,
		"category": category,
		"recoverable": recoverable,
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"detail": detail.duplicate(true),
	}

func translate_backend_state(raw_state: Dictionary = {}) -> Dictionary:
	var translated := {
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"vendor_state": _vendor_state,
		"surface_attached": _surface != null,
		"player_present": _player != null,
		"media_loaded": not _loaded_source.is_empty(),
		"position": _position_seconds,
		"duration": _duration_seconds,
		"loop": _loop_enabled,
		"rate": _rate,
		"last_error": _last_error.duplicate(true),
		"source": _loaded_source.duplicate(true),
		"raw": raw_state.duplicate(true),
	}
	for key in raw_state.keys():
		translated[key] = raw_state[key]
	if bool(raw_state.get("playing", false)):
		translated["vendor_state"] = STATE_PLAYING
	elif translated["media_loaded"] and bool(raw_state.get("paused", false)):
		translated["vendor_state"] = STATE_PAUSED
	elif translated["media_loaded"] and translated["vendor_state"] == STATE_ATTACHED:
		translated["vendor_state"] = STATE_READY
	if not _last_error.is_empty():
		translated["vendor_state"] = STATE_ERROR
	return translated

func _infer_source_kind(path: String) -> String:
	var lowered := path.to_lower()
	if lowered.begins_with("http://") or lowered.begins_with("https://"):
		return SOURCE_KIND_URL
	return SOURCE_KIND_FILE

func _normalize_file_uri(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed.to_lower().begins_with("file://localhost/"):
		return "/%s" % trimmed.substr(17)
	if trimmed.to_lower().begins_with("file:///"):
		return "/%s" % trimmed.substr(8)
	if trimmed.to_lower().begins_with("file://"):
		return trimmed.substr(7)
	return trimmed

func _detect_locality(path: String) -> String:
	if path.begins_with("res://"):
		return "project_resource"
	if path.begins_with("user://"):
		return "user_data"
	if path.begins_with("/"):
		return "absolute_path"
	if path.to_lower().begins_with("http://") or path.to_lower().begins_with("https://"):
		return "remote"
	return "relative_path"

func _build_media_info(source: Dictionary) -> Dictionary:
	var extension := String(source.get("extension", "")).to_lower()
	var format_status := "unknown"
	if VERIFIED_EXTENSIONS.has(extension):
		format_status = "verified"
	elif UNVERIFIED_EXTENSIONS.has(extension):
		format_status = "unverified"
	return {
		"path": String(source.get("path", "")),
		"kind": String(source.get("kind", SOURCE_KIND_FILE)),
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"locality": String(source.get("locality", "")),
		"extension": extension,
		"format_status": format_status,
		"duration": _duration_seconds,
		"position": _position_seconds,
		"surface_attached": _surface != null,
		"loop": _loop_enabled,
		"rate": _rate,
		"metadata": source.get("metadata", {}).duplicate(true),
	}

func _ensure_player() -> Dictionary:
	if _player != null:
		return _ok({"player_present": true})
	if _player_factory.is_valid():
		_player = _player_factory.call()
	elif ClassDB.can_instantiate("VideoStreamPlayer"):
		_player = ClassDB.instantiate("VideoStreamPlayer")
	if _player == null:
		return _fail("backend_player_unavailable", "Unable to create a Godot video player node for the attached surface.")
	if String(_player.name).is_empty():
		_player.name = "AeroGodotVideoPlayer"
	return _ok({"player_present": true})

func _sync_player_binding() -> void:
	if _surface == null or _player == null:
		return
	if _player == _surface:
		return
	if _player.get_parent() != _surface:
		if _player.get_parent() != null:
			_player.get_parent().remove_child(_player)
		_surface.add_child(_player)

func _sync_player_configuration() -> void:
	if _player == null:
		return
	if _player.has_method("set"):
		_player.set("loop", _loop_enabled)
		_player.set("autoplay", bool(_loaded_source.get("autoplay", false)))
		_player.set("playback_speed", _rate)
		_player.set("stream_position", _position_seconds)
	if _player.has_method("apply_source_descriptor") and not _loaded_source.is_empty():
		_player.call("apply_source_descriptor", _loaded_source.duplicate(true))

func _snapshot_player_state() -> Dictionary:
	var raw := {
		"surface_attached": _surface != null,
		"player_present": _player != null,
		"position": _position_seconds,
		"duration": _duration_seconds,
		"loop": _loop_enabled,
		"rate": _rate,
	}
	if _player != null and _player.has_method("get"):
		raw["playing"] = bool(_player.get("playing"))
		raw["paused"] = not bool(raw.get("playing", false)) and _vendor_state == STATE_PAUSED
		raw["stream_position"] = float(_player.get("stream_position"))
		raw["loop"] = bool(_player.get("loop"))
		raw["playback_speed"] = float(_player.get("playback_speed"))
		raw["autoplay"] = bool(_player.get("autoplay"))
		raw["player_name"] = String(_player.name)
		raw["position"] = float(raw.get("stream_position", _position_seconds))
		raw["rate"] = float(raw.get("playback_speed", _rate))
	return raw

func _ok(detail: Dictionary = {}) -> Dictionary:
	return {
		RESULT_SUCCESS: true,
		RESULT_DETAIL: detail.duplicate(true),
	}

func _fail(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	_last_error = translate_backend_error(code, message, detail)
	_vendor_state = STATE_ERROR
	return {
		RESULT_SUCCESS: false,
		RESULT_CODE: code,
		RESULT_MESSAGE: message,
		RESULT_DETAIL: detail.duplicate(true),
	}
