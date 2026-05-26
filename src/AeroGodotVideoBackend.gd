class_name AeroGodotVideoBackend
extends "AeroVideoVendorBackend.gd"

const VENDOR_NAME := "godot_video"
const BACKEND_FAMILY := "godot_builtin_video"
const SOURCE_KIND_FILE := CoreContract.SOURCE_KIND_FILE
const SOURCE_KIND_URL := CoreContract.SOURCE_KIND_URL
const SUPPORTED_SOURCE_KINDS := [SOURCE_KIND_FILE]
const VERIFIED_EXTENSIONS := ["ogv"]
const UNVERIFIED_EXTENSIONS := ["mp4", "webm", "mov", "mkv", "avi"]

const STATE_IDLE := "idle"
const STATE_ATTACHED := "attached"
const STATE_READY := "ready"
const STATE_PLAYING := "playing"
const STATE_PAUSED := "paused"
const STATE_ERROR := "error"

const DEFAULT_MUTED_VOLUME := 0.0
const DEFAULT_UNMUTED_VOLUME := 1.0
const DEFAULT_MUTED_VOLUME_DB := -80.0
const DEFAULT_UNMUTED_VOLUME_DB := 0.0

var _surface: Node = null
var _player: Node = null
var _player_factory: Callable = Callable()
var _stream_resource: Variant = null
var _loaded_source: Dictionary = {}
var _media_info: Dictionary = {}
var _last_error: Dictionary = {}
var _vendor_state: String = STATE_IDLE
var _position_seconds: float = 0.0
var _duration_seconds: float = 0.0
var _loop_enabled: bool = false
var _rate: float = 1.0
var _muted: bool = false

func set_player_factory(factory: Callable) -> void:
	_player_factory = factory

func set_player_node(node: Node) -> void:
	_player = node
	_sync_player_binding()
	_sync_player_configuration()

func normalize_source(source: Dictionary) -> Dictionary:
	var normalized := CoreContract.normalize_source(source)
	var original_path := str(normalized.get("path", "")).strip_edges()
	var inferred_kind := str(normalized.get("kind", "")).strip_edges().to_lower()
	if inferred_kind.is_empty():
		inferred_kind = _infer_source_kind(original_path)
	if original_path.to_lower().begins_with("file://"):
		normalized["path"] = _normalize_file_uri(original_path)
	else:
		normalized["path"] = original_path
	normalized["original_path"] = original_path
	normalized["kind"] = inferred_kind if not inferred_kind.is_empty() else SOURCE_KIND_FILE
	normalized["vendor"] = VENDOR_NAME
	normalized["backend_family"] = BACKEND_FAMILY
	normalized["locality"] = _detect_locality(str(normalized.get("path", "")))
	normalized["is_local_file"] = normalized["kind"] == SOURCE_KIND_FILE and str(normalized.get("locality", "")) != "remote"
	normalized["extension"] = str(normalized.get("path", "")).get_extension().to_lower()
	return normalized

func validate_source(source: Dictionary) -> Dictionary:
	if str(source.get("path", "")).is_empty():
		return {
			"code": "backend_source_missing_path",
			"message": "Video source path must be a non-empty local file path.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	if str(source.get("kind", SOURCE_KIND_FILE)) != SOURCE_KIND_FILE:
		return {
			"code": "backend_source_kind_unsupported",
			"message": "Godot vendor backend currently supports only local file sources.",
			"detail": {"field": "kind", "source": source.duplicate(true), "supported": SUPPORTED_SOURCE_KINDS.duplicate()},
		}
	if str(source.get("locality", "remote")) == "remote":
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
		"audio_controls": ["mute_toggle"],
		"metadata_known_fields": ["path", "kind", "vendor", "backend_family", "extension", "locality", "duration", "position", "surface_attached", "format_status", "audio"],
	}

func load(source: Dictionary) -> Dictionary:
	var normalized := normalize_source(source)
	var validation_error := validate_source(normalized)
	if not validation_error.is_empty():
		return _fail(
			str(validation_error.get("code", "backend_invalid_source")),
			str(validation_error.get("message", "Invalid source.")),
			validation_error.get("detail", {})
		)

	var stream_resource: Variant = _load_stream_resource(str(normalized.get("path", "")))
	if stream_resource == null:
		return _fail(
			"backend_stream_load_failed",
			"Godot could not load the requested video stream resource.",
			{"path": normalized.get("path", ""), "source": normalized.duplicate(true)}
		)

	_stream_resource = stream_resource
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
	if _player != null:
		if _player.has_method("play"):
			_player.call("play")
		_set_player_property("paused", false)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func pause() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot pause playback before a source is loaded.")
	_vendor_state = STATE_PAUSED
	if _player != null:
		if _player.has_method("pause"):
			_player.call("pause")
		elif _player.has_method("set"):
			_set_player_property("playing", false)
		_set_player_property("paused", true)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func stop() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot stop playback before a source is loaded.")
	_vendor_state = STATE_READY
	_position_seconds = 0.0
	if _player != null:
		if _player.has_method("stop"):
			_player.call("stop")
		_set_player_property("paused", false)
		_set_player_property("playing", false)
		_set_player_property("stream_position", 0.0)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func seek(seconds: float) -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot seek before a source is loaded.")
	_position_seconds = maxf(0.0, seconds)
	if _duration_seconds > 0.0:
		_position_seconds = minf(_position_seconds, _duration_seconds)
	_set_player_property("stream_position", _position_seconds)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func set_loop(enabled: bool) -> Dictionary:
	_loop_enabled = enabled
	if not _loaded_source.is_empty():
		_loaded_source["loop"] = enabled
	_set_player_property("loop", enabled)
	_last_error = {}
	return _ok({"loop": _loop_enabled})

func set_rate(rate: float) -> Dictionary:
	if rate <= 0.0:
		return _fail("backend_invalid_rate", "Playback rate must be greater than zero.", {"rate": rate})
	_rate = rate
	if not _loaded_source.is_empty():
		_loaded_source["rate"] = rate
	var applied_to_player := false
	if _player_supports_property("playback_speed"):
		applied_to_player = _set_player_property("playback_speed", rate)
	_last_error = {}
	return _ok({"rate": _rate, "applied_to_player": applied_to_player})

func set_muted(muted: bool) -> Dictionary:
	_muted = muted
	var applied := false
	if _player_supports_property("volume"):
		applied = _set_player_property("volume", DEFAULT_MUTED_VOLUME if muted else DEFAULT_UNMUTED_VOLUME)
	elif _player_supports_property("volume_db"):
		applied = _set_player_property("volume_db", DEFAULT_MUTED_VOLUME_DB if muted else DEFAULT_UNMUTED_VOLUME_DB)
	_last_error = {}
	return _ok({"audio": get_audio_state(), "applied_to_player": applied})

func get_audio_state() -> Dictionary:
	var audio := {
		"muted": _muted,
		"player_present": _player != null,
		"volume": DEFAULT_UNMUTED_VOLUME,
		"volume_db": DEFAULT_UNMUTED_VOLUME_DB,
	}
	if _player != null:
		if _player_supports_property("volume"):
			audio["volume"] = float(_player.get("volume"))
		if _player_supports_property("volume_db"):
			audio["volume_db"] = float(_player.get("volume_db"))
	return audio

func get_state() -> Dictionary:
	return translate_backend_state(_snapshot_player_state())

func get_position() -> float:
	return float(get_state().get("position", _position_seconds))

func get_duration() -> float:
	return float(get_state().get("duration", _duration_seconds))

func get_media_info() -> Dictionary:
	var info := _media_info.duplicate(true)
	if info.is_empty() and not _loaded_source.is_empty():
		info = _build_media_info(_loaded_source)
	info["audio"] = get_audio_state()
	return info

func attach_surface(node: Node) -> Dictionary:
	if node == null:
		return _fail("backend_invalid_surface", "Cannot attach a null output surface.")
	_surface = node
	var player_result := _ensure_player()
	if not bool(player_result.get(CoreContract.RESULT_SUCCESS, false)):
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
		"backend_source_missing_path", "backend_source_not_local", "backend_source_kind_unsupported", "backend_stream_load_failed":
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
		"audio": get_audio_state(),
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
	var extension := str(source.get("extension", "")).to_lower()
	var format_status := "unknown"
	if VERIFIED_EXTENSIONS.has(extension):
		format_status = "verified"
	elif UNVERIFIED_EXTENSIONS.has(extension):
		format_status = "unverified"
	return {
		"path": str(source.get("path", "")),
		"kind": str(source.get("kind", SOURCE_KIND_FILE)),
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"locality": str(source.get("locality", "")),
		"extension": extension,
		"format_status": format_status,
		"duration": _duration_seconds,
		"position": _position_seconds,
		"surface_attached": _surface != null,
		"loop": _loop_enabled,
		"rate": _rate,
		"audio": get_audio_state(),
		"metadata": source.get("metadata", {}).duplicate(true),
	}

func _load_stream_resource(path: String) -> Variant:
	var candidate_path := path
	if path.begins_with("/"):
		var localized := ProjectSettings.localize_path(path)
		if localized.begins_with("res://") or localized.begins_with("user://"):
			candidate_path = localized
		else:
			return _load_external_stream_resource(path)
	if not (candidate_path.begins_with("res://") or candidate_path.begins_with("user://")):
		return null
	if not ResourceLoader.exists(candidate_path):
		return null
	return load(candidate_path)

func _load_external_stream_resource(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() != "ogv":
		return null
	if not ClassDB.can_instantiate("VideoStreamTheora"):
		return null
	var stream: Variant = ClassDB.instantiate("VideoStreamTheora")
	if stream == null:
		return null
	if stream.has_method("set_file"):
		stream.call("set_file", path)
	elif _object_supports_property(stream, "file"):
		stream.set("file", path)
	else:
		return null
	return stream

func _ensure_player() -> Dictionary:
	if _player != null:
		return _ok({"player_present": true})
	if _surface is VideoStreamPlayer:
		_player = _surface
	elif _player_factory.is_valid():
		_player = _player_factory.call()
	elif ClassDB.can_instantiate("VideoStreamPlayer"):
		_player = ClassDB.instantiate("VideoStreamPlayer")
	if _player == null:
		return _fail("backend_player_unavailable", "Unable to create a Godot video player node for the attached surface.")
	if str(_player.name).is_empty():
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
	if _stream_resource != null:
		if _player_supports_property("stream"):
			_set_player_property("stream", _stream_resource)
		elif _player.has_method("set_stream"):
			_player.call("set_stream", _stream_resource)
	_set_player_property("loop", _loop_enabled)
	_set_player_property("autoplay", bool(_loaded_source.get("autoplay", false)))
	_set_player_property("stream_position", _position_seconds)
	if _player_supports_property("playback_speed"):
		_set_player_property("playback_speed", _rate)
	if _muted:
		set_muted(_muted)
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
		"audio": get_audio_state(),
	}
	if _player != null:
		if _player_supports_property("stream_position"):
			raw["stream_position"] = float(_player.get("stream_position"))
			raw["position"] = float(raw.get("stream_position", _position_seconds))
		if _player_supports_property("loop"):
			raw["loop"] = bool(_player.get("loop"))
		if _player_supports_property("playback_speed"):
			raw["playback_speed"] = float(_player.get("playback_speed"))
			raw["rate"] = float(raw.get("playback_speed", _rate))
		if _player_supports_property("autoplay"):
			raw["autoplay"] = bool(_player.get("autoplay"))
		if _player_supports_property("paused"):
			raw["paused"] = bool(_player.get("paused"))
		raw["playing"] = _is_player_playing(raw)
		raw["player_name"] = str(_player.name)
	return raw

func _player_supports_property(property_name: String) -> bool:
	return _object_supports_property(_player, property_name)

func _object_supports_property(target: Variant, property_name: String) -> bool:
	if target == null or not (target is Object):
		return false
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false

func _set_player_property(property_name: String, value: Variant) -> bool:
	if _player == null or not _player_supports_property(property_name):
		return false
	_player.set(property_name, value)
	return true

func _is_player_playing(raw: Dictionary) -> bool:
	if _player == null:
		return false
	if _player.has_method("is_playing"):
		return bool(_player.call("is_playing"))
	if _player_supports_property("playing"):
		return bool(_player.get("playing"))
	if raw.has("paused"):
		return not bool(raw.get("paused", false)) and _vendor_state == STATE_PLAYING
	return _vendor_state == STATE_PLAYING

func _ok(detail: Dictionary = {}) -> Dictionary:
	return CoreContract.ok(detail)

func _fail(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	_last_error = translate_backend_error(code, message, detail)
	_vendor_state = STATE_ERROR
	return CoreContract.fail(code, message, detail)
