class_name AeroGodotVideoBackend
extends "AeroVideoVendorBackend.gd"

const VENDOR_NAME := "godot_video"
const BACKEND_FAMILY := "godot_builtin_video"
const SOURCE_KIND_FILE := CoreContract.SOURCE_KIND_FILE
const SOURCE_KIND_URL := CoreContract.SOURCE_KIND_URL
const SOURCE_KIND_PACKAGE := CoreContract.SOURCE_KIND_PACKAGE
const SUPPORTED_SOURCE_KINDS := [SOURCE_KIND_FILE, SOURCE_KIND_URL, SOURCE_KIND_PACKAGE]
const VERIFIED_EXTENSIONS := ["ogv"]
const UNVERIFIED_EXTENSIONS := ["mp4", "webm", "mov", "mkv", "avi"]
const COVER_MODE_STRETCH := "stretch"
const COVER_MODE_CONTAIN := "contain"
const COVER_MODE_COVER := "cover"
const COVER_MODES := [COVER_MODE_STRETCH, COVER_MODE_CONTAIN, COVER_MODE_COVER]

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
const DEFAULT_AUDIO_LEVEL := 1.0
const DEFAULT_COVER_MODE := COVER_MODE_CONTAIN
const DEFAULT_VIDEO_WIDTH := 1920
const DEFAULT_VIDEO_HEIGHT := 1080

var _surface: Node = null
var _player: Node = null
var _player_factory: Callable = Callable()
var _remote_source_resolver: Callable = Callable()
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
var _audio_level: float = DEFAULT_AUDIO_LEVEL
var _cover_mode: String = DEFAULT_COVER_MODE

func set_player_factory(factory: Callable) -> void:
	_player_factory = factory

func set_remote_source_resolver(resolver: Callable) -> void:
	_remote_source_resolver = resolver

func set_player_node(node: Node) -> void:
	_player = node
	_sync_player_binding()
	_sync_player_configuration()

func _is_live_object(value: Variant) -> bool:
	return value != null and typeof(value) == TYPE_OBJECT and is_instance_valid(value)

func _live_surface() -> Node:
	if not _is_live_object(_surface):
		_surface = null
		return null
	return _surface

func _live_player() -> Node:
	if not _is_live_object(_player):
		_player = null
		return null
	return _player

func _surface_as_control(surface: Variant) -> Control:
	if not _is_live_object(surface):
		return null
	if not (surface is Control):
		return null
	return surface as Control

func normalize_source(source: Dictionary) -> Dictionary:
	var normalized := CoreContract.normalize_source(source)
	var original_path := str(normalized.get("path", "")).strip_edges()
	var inferred_kind := str(normalized.get("kind", "")).strip_edges().to_lower()
	var path_inferred_kind := _infer_source_kind(original_path)
	if inferred_kind.is_empty() or path_inferred_kind == SOURCE_KIND_URL:
		inferred_kind = path_inferred_kind
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
	normalized["cover_mode"] = _normalize_cover_mode(normalized.get("cover_mode", DEFAULT_COVER_MODE))
	normalized["audio_level"] = _normalize_audio_level(normalized.get("audio_level", DEFAULT_AUDIO_LEVEL))
	normalized["width"] = max(1, int(normalized.get("width", DEFAULT_VIDEO_WIDTH)))
	normalized["height"] = max(1, int(normalized.get("height", DEFAULT_VIDEO_HEIGHT)))
	return normalized

func validate_source(source: Dictionary) -> Dictionary:
	if str(source.get("path", "")).is_empty():
		return {
			"code": "backend_source_missing_path",
			"message": "Video source path must be a non-empty package path, local file path, or URL.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	var kind := str(source.get("kind", SOURCE_KIND_FILE))
	if not SUPPORTED_SOURCE_KINDS.has(kind):
		return {
			"code": "backend_source_kind_unsupported",
			"message": "Godot vendor backend currently supports package paths, local files, and direct URLs.",
			"detail": {"field": "kind", "source": source.duplicate(true), "supported": SUPPORTED_SOURCE_KINDS.duplicate()},
		}
	if kind == SOURCE_KIND_URL:
		var lowered_path := str(source.get("path", "")).to_lower()
		if not (lowered_path.begins_with("http://") or lowered_path.begins_with("https://")):
			return {
				"code": "backend_source_url_invalid",
				"message": "Remote URL playback requires an http:// or https:// source.",
				"detail": {"field": "path", "source": source.duplicate(true)},
			}
	elif str(source.get("locality", "remote")) == "remote":
		return {
			"code": "backend_source_not_local",
			"message": "Local file playback requires a project path, user path, relative package path, or absolute device path.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	if float(source.get("rate", 1.0)) <= 0.0:
		return {
			"code": "backend_invalid_rate",
			"message": "Playback rate must be greater than zero.",
			"detail": {"field": "rate", "source": source.duplicate(true)},
		}
	if not COVER_MODES.has(_normalize_cover_mode(source.get("cover_mode", DEFAULT_COVER_MODE))):
		return {
			"code": "backend_invalid_cover_mode",
			"message": "Cover mode must be stretch, contain, or cover.",
			"detail": {"field": "cover_mode", "source": source.duplicate(true), "supported": COVER_MODES.duplicate()},
		}
	var audio_level := float(source.get("audio_level", DEFAULT_AUDIO_LEVEL))
	if audio_level < 0.0 or audio_level > 1.0:
		return {
			"code": "backend_invalid_audio_level",
			"message": "Audio level must stay within 0.0 and 1.0.",
			"detail": {"field": "audio_level", "source": source.duplicate(true)},
		}
	return {}

func get_capabilities() -> Dictionary:
	return {
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"supported_source_kinds": SUPPORTED_SOURCE_KINDS.duplicate(),
		"verified_extensions": VERIFIED_EXTENSIONS.duplicate(),
		"unverified_extensions": UNVERIFIED_EXTENSIONS.duplicate(),
		"remote_sources_supported": true,
		"surface_attach_mode": "direct_or_container_child",
		"surface_types": ["VideoStreamPlayer", "Node", "CanvasItem", "Control"],
		"audio_controls": ["mute_toggle", "audio_level"],
		"cover_modes": COVER_MODES.duplicate(),
		"metadata_known_fields": ["path", "kind", "vendor", "backend_family", "extension", "locality", "duration", "position", "surface_attached", "format_status", "audio", "cover_mode"],
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

	var resolved_source := _resolve_source_for_loading(normalized)
	if resolved_source.is_empty():
		return _fail(
			"backend_stream_load_failed",
			"Godot could not resolve the requested video stream source.",
			{"path": normalized.get("path", ""), "source": normalized.duplicate(true)}
		)

	var playback_path := str(resolved_source.get("path", "")).strip_edges()
	var stream_resource: Variant = _load_stream_resource(playback_path)
	if stream_resource == null:
		return _fail(
			"backend_stream_load_failed",
			"Godot could not load the requested video stream resource.",
			{"path": normalized.get("path", ""), "resolved_path": playback_path, "source": normalized.duplicate(true)}
		)

	_stream_resource = stream_resource
	_loaded_source = normalized.duplicate(true)
	_loaded_source["resolved_path"] = playback_path
	for key in resolved_source.keys():
		if key == "path":
			continue
		_loaded_source[key] = resolved_source[key]
	_loop_enabled = bool(_loaded_source.get("loop", false))
	_rate = float(_loaded_source.get("rate", 1.0))
	_cover_mode = _normalize_cover_mode(_loaded_source.get("cover_mode", DEFAULT_COVER_MODE))
	_audio_level = _normalize_audio_level(_loaded_source.get("audio_level", DEFAULT_AUDIO_LEVEL))
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
	var player := _live_player()
	if player != null:
		if player.has_method("play"):
			player.call("play")
		_set_player_property("paused", false)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func pause() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot pause playback before a source is loaded.")
	_vendor_state = STATE_PAUSED
	var player := _live_player()
	if player != null:
		if player.has_method("pause"):
			player.call("pause")
		elif player.has_method("set"):
			_set_player_property("playing", false)
		_set_player_property("paused", true)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func stop() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot stop playback before a source is loaded.")
	_vendor_state = STATE_READY
	_position_seconds = 0.0
	var player := _live_player()
	if player != null:
		if player.has_method("stop"):
			player.call("stop")
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

func set_cover_mode(cover_mode: String) -> Dictionary:
	_cover_mode = _normalize_cover_mode(cover_mode)
	if not _loaded_source.is_empty():
		_loaded_source["cover_mode"] = _cover_mode
	_apply_cover_layout()
	_last_error = {}
	return _ok({"cover_mode": _cover_mode, "surface_attached": _live_surface() != null})

func set_audio_level(audio_level: float) -> Dictionary:
	_audio_level = _normalize_audio_level(audio_level)
	if not _loaded_source.is_empty():
		_loaded_source["audio_level"] = _audio_level
	var applied := _apply_audio_state()
	_last_error = {}
	return _ok({"audio": get_audio_state(), "applied_to_player": applied})

func set_muted(muted: bool) -> Dictionary:
	_muted = muted
	var applied := _apply_audio_state()
	_last_error = {}
	return _ok({"audio": get_audio_state(), "applied_to_player": applied})

func get_audio_state() -> Dictionary:
	var player := _live_player()
	var effective_audio_level := 0.0 if _muted else _audio_level
	var audio := {
		"muted": _muted,
		"audio_level": _audio_level,
		"effective_audio_level": effective_audio_level,
		"player_present": player != null,
		"volume": effective_audio_level,
		"volume_db": _audio_level_to_db(effective_audio_level),
	}
	if player != null:
		if _player_supports_property("volume"):
			audio["volume"] = float(player.get("volume"))
		if _player_supports_property("volume_db"):
			audio["volume_db"] = float(player.get("volume_db"))
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
	info["cover_mode"] = _cover_mode
	return info

func attach_surface(node: Node) -> Dictionary:
	if node == null:
		return _fail("backend_invalid_surface", "Cannot attach a null output surface.")
	_unbind_surface_resize(_surface)
	_surface = node
	_bind_surface_resize()
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
		"player_present": _live_player() != null,
	})

func detach_surface() -> Dictionary:
	var surface := _live_surface()
	var player := _live_player()
	_unbind_surface_resize(surface)
	if player != null and surface != null and player != surface and player.get_parent() == surface:
		surface.remove_child(player)
		if player.has_method("queue_free"):
			player.call("queue_free")
		_player = null
	_surface = null
	if _loaded_source.is_empty():
		_vendor_state = STATE_IDLE
	_last_error = {}
	return _ok({"surface_attached": false})

func unload() -> Dictionary:
	var player := _live_player()
	var surface := _live_surface()
	if player != null:
		if player.has_method("stop"):
			player.call("stop")
		_set_player_property("paused", false)
		_set_player_property("playing", false)
		_set_player_property("stream_position", 0.0)
		_set_player_property("stream", null)
	_stream_resource = null
	_loaded_source = {}
	_media_info = {}
	_position_seconds = 0.0
	_duration_seconds = 0.0
	_loop_enabled = false
	_rate = 1.0
	_last_error = {}
	_vendor_state = STATE_ATTACHED if surface != null else STATE_IDLE
	_apply_cover_layout()
	return _ok({
		"surface_attached": surface != null,
		"media_loaded": false,
		"vendor_state": _vendor_state,
	})

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
		"backend_invalid_rate", "backend_not_loaded", "backend_invalid_cover_mode", "backend_invalid_audio_level":
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
		"cover_mode": _cover_mode,
		"audio_level": _audio_level,
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
	if lowered.begins_with("res://") or lowered.begins_with("./") or lowered.begins_with("../"):
		return SOURCE_KIND_PACKAGE
	if lowered.begins_with("user://") or path.begins_with("/"):
		return SOURCE_KIND_FILE
	if not path.contains("://"):
		return SOURCE_KIND_PACKAGE
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

func _resolve_source_for_loading(source: Dictionary) -> Dictionary:
	var kind := str(source.get("kind", SOURCE_KIND_FILE))
	var requested_path := str(source.get("path", "")).strip_edges()
	if kind == SOURCE_KIND_URL:
		var remote_path := _resolve_remote_stream_source(requested_path)
		if remote_path.is_empty():
			return {}
		return {
			"path": remote_path,
			"resolved_kind": SOURCE_KIND_FILE,
			"resolved_locality": "remote_cache",
			"cache_path": remote_path,
		}
	var local_path := _resolve_local_stream_source(requested_path)
	if local_path.is_empty():
		return {}
	return {
		"path": local_path,
		"resolved_kind": SOURCE_KIND_FILE if kind != SOURCE_KIND_PACKAGE else SOURCE_KIND_PACKAGE,
		"resolved_locality": _detect_locality(local_path),
	}

func _resolve_local_stream_source(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("res://") or trimmed.begins_with("user://") or trimmed.begins_with("/"):
		return trimmed
	var normalized_relative := trimmed
	if normalized_relative.begins_with("./"):
		normalized_relative = normalized_relative.substr(2)
	while normalized_relative.begins_with("/"):
		normalized_relative = normalized_relative.substr(1)
	if normalized_relative.is_empty():
		return ""
	var res_candidate := "res://%s" % normalized_relative
	if ResourceLoader.exists(res_candidate) or FileAccess.file_exists(ProjectSettings.globalize_path(res_candidate)):
		return res_candidate
	var user_candidate := "user://%s" % normalized_relative
	if FileAccess.file_exists(ProjectSettings.globalize_path(user_candidate)):
		return user_candidate
	return trimmed

func _resolve_remote_stream_source(url: String) -> String:
	if _remote_source_resolver.is_valid():
		var resolved: Variant = _remote_source_resolver.call(url)
		if typeof(resolved) == TYPE_DICTIONARY:
			return str((resolved as Dictionary).get("path", "")).strip_edges()
		return str(resolved).strip_edges()
	return _download_remote_stream_to_cache(url)

func _download_remote_stream_to_cache(url: String) -> String:
	var request := _parse_http_url(url)
	if request.is_empty():
		return ""
	var client := HTTPClient.new()
	var use_tls := bool(request.get("tls", false))
	var connect_error := client.connect_to_host(str(request.get("host", "")), int(request.get("port", 0)), TLSOptions.client() if use_tls else null)
	if connect_error != OK:
		return ""
	if not _http_client_wait_for(client, [HTTPClient.STATUS_CONNECTED]):
		return ""
	var request_error := client.request(HTTPClient.METHOD_GET, str(request.get("request_path", "/")), ["User-Agent: AeroBeatVendorGodotVideo/0.5.0", "Accept: application/ogg, application/octet-stream"])
	if request_error != OK:
		return ""
	var body := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() <= deadline:
		var poll_error := client.poll()
		if poll_error != OK:
			return ""
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			var chunk := client.read_response_body_chunk()
			if not chunk.is_empty():
				body.append_array(chunk)
		elif status == HTTPClient.STATUS_CONNECTED:
			if client.has_response():
				var response_code := client.get_response_code()
				if response_code < 200 or response_code >= 300:
					return ""
				if body.is_empty():
					return ""
				return _write_remote_cache_file(url, body)
		elif status in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR, HTTPClient.STATUS_DISCONNECTED]:
			return ""
		OS.delay_msec(10)
	return ""

func _http_client_wait_for(client: HTTPClient, statuses: Array) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() <= deadline:
		var poll_error := client.poll()
		if poll_error != OK:
			return false
		if statuses.has(client.get_status()):
			return true
		if client.get_status() in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR, HTTPClient.STATUS_DISCONNECTED]:
			return false
		OS.delay_msec(10)
	return false

func _parse_http_url(url: String) -> Dictionary:
	var trimmed := url.strip_edges()
	if trimmed.is_empty() or not trimmed.contains("://"):
		return {}
	var scheme_split := trimmed.split("://", false, 1)
	if scheme_split.size() != 2:
		return {}
	var scheme := str(scheme_split[0]).to_lower()
	if scheme not in ["http", "https"]:
		return {}
	var remainder := str(scheme_split[1])
	var slash_index := remainder.find("/")
	var host_port := remainder if slash_index < 0 else remainder.substr(0, slash_index)
	var request_path := "/" if slash_index < 0 else remainder.substr(slash_index)
	if host_port.is_empty():
		return {}
	var host := host_port
	var port := 443 if scheme == "https" else 80
	if host_port.contains(":"):
		var port_split := host_port.rsplit(":", false, 1)
		if port_split.size() == 2 and str(port_split[1]).is_valid_int():
			host = str(port_split[0])
			port = int(port_split[1])
	return {
		"scheme": scheme,
		"host": host,
		"port": port,
		"request_path": request_path,
		"tls": scheme == "https",
	}

func _write_remote_cache_file(url: String, body: PackedByteArray) -> String:
	if body.is_empty():
		return ""
	var cache_dir := ProjectSettings.globalize_path("user://aero_godot_video_cache")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(cache_dir)
	if mkdir_error != OK and not DirAccess.dir_exists_absolute(cache_dir):
		return ""
	var lowered := url.to_lower()
	var extension := url.get_extension().to_lower()
	if extension.is_empty() and lowered.contains(".ogv?"):
		extension = "ogv"
	if extension != "ogv":
		return ""
	var cache_path := cache_dir.path_join("remote-%s.%s" % [str(abs(hash(url))), extension])
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(body)
	file.flush()
	return cache_path

func _build_media_info(source: Dictionary) -> Dictionary:
	var extension := str(source.get("extension", "")).to_lower()
	var format_status := "unknown"
	if VERIFIED_EXTENSIONS.has(extension):
		format_status = "verified"
	elif UNVERIFIED_EXTENSIONS.has(extension):
		format_status = "unverified"
	return {
		"path": str(source.get("path", "")),
		"resolved_path": str(source.get("resolved_path", source.get("path", ""))),
		"kind": str(source.get("kind", SOURCE_KIND_FILE)),
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"locality": str(source.get("locality", "")),
		"extension": extension,
		"format_status": format_status,
		"width": int(source.get("width", DEFAULT_VIDEO_WIDTH)),
		"height": int(source.get("height", DEFAULT_VIDEO_HEIGHT)),
		"duration": _duration_seconds,
		"position": _position_seconds,
		"surface_attached": _surface != null,
		"loop": _loop_enabled,
		"rate": _rate,
		"cover_mode": _cover_mode,
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
	var player := _live_player()
	var surface := _live_surface()
	if player != null:
		return _ok({"player_present": true})
	if surface is VideoStreamPlayer:
		_player = surface
	elif _player_factory.is_valid():
		_player = _player_factory.call()
	elif ClassDB.can_instantiate("VideoStreamPlayer"):
		_player = ClassDB.instantiate("VideoStreamPlayer")
	player = _live_player()
	if player == null:
		return _fail("backend_player_unavailable", "Unable to create a Godot video player node for the attached surface.")
	if str(player.name).is_empty():
		player.name = "AeroGodotVideoPlayer"
	return _ok({"player_present": true})

func _sync_player_binding() -> void:
	var surface := _live_surface()
	var player := _live_player()
	if surface == null or player == null:
		return
	if player == surface:
		return
	if player.get_parent() != surface:
		if player.get_parent() != null:
			player.get_parent().remove_child(player)
		surface.add_child(player)

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
	_apply_audio_state()
	_apply_cover_layout()
	if _player.has_method("apply_source_descriptor") and not _loaded_source.is_empty():
		_player.call("apply_source_descriptor", _loaded_source.duplicate(true))

func _snapshot_player_state() -> Dictionary:
	var surface := _live_surface()
	var player := _live_player()
	var raw := {
		"surface_attached": surface != null,
		"player_present": player != null,
		"position": _position_seconds,
		"duration": _duration_seconds,
		"loop": _loop_enabled,
		"rate": _rate,
		"cover_mode": _cover_mode,
		"audio_level": _audio_level,
		"audio": get_audio_state(),
	}
	if player != null:
		if _player_supports_property("stream_position"):
			raw["stream_position"] = float(player.get("stream_position"))
			raw["position"] = float(raw.get("stream_position", _position_seconds))
		if _player_supports_property("loop"):
			raw["loop"] = bool(player.get("loop"))
		if _player_supports_property("playback_speed"):
			raw["playback_speed"] = float(player.get("playback_speed"))
			raw["rate"] = float(raw.get("playback_speed", _rate))
		if _player_supports_property("autoplay"):
			raw["autoplay"] = bool(player.get("autoplay"))
		if _player_supports_property("paused"):
			raw["paused"] = bool(player.get("paused"))
		if _player_supports_property("cover_mode"):
			raw["cover_mode"] = str(player.get("cover_mode"))
		raw["playing"] = _is_player_playing(raw)
		raw["player_name"] = str(player.name)
	return raw

func _player_supports_property(property_name: String) -> bool:
	return _object_supports_property(_live_player(), property_name)

func _object_supports_property(target: Variant, property_name: String) -> bool:
	if not _is_live_object(target):
		return false
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false

func _set_player_property(property_name: String, value: Variant) -> bool:
	var player := _live_player()
	if player == null or not _player_supports_property(property_name):
		return false
	player.set(property_name, value)
	return true

func _is_player_playing(raw: Dictionary) -> bool:
	var player := _live_player()
	if player == null:
		return false
	if player.has_method("is_playing"):
		return bool(player.call("is_playing"))
	if _player_supports_property("playing"):
		return bool(player.get("playing"))
	if raw.has("paused"):
		return not bool(raw.get("paused", false)) and _vendor_state == STATE_PLAYING
	return _vendor_state == STATE_PLAYING

func _apply_audio_state() -> bool:
	if _live_player() == null:
		return false
	var effective_audio_level := 0.0 if _muted else _audio_level
	var applied := false
	if _player_supports_property("volume"):
		applied = _set_player_property("volume", effective_audio_level) or applied
	if _player_supports_property("volume_db"):
		applied = _set_player_property("volume_db", _audio_level_to_db(effective_audio_level)) or applied
	return applied

func _bind_surface_resize() -> void:
	var control := _surface_as_control(_live_surface())
	if control == null:
		return
	var resized_callback := Callable(self, "_on_surface_resized")
	if not control.resized.is_connected(resized_callback):
		control.resized.connect(resized_callback)

func _unbind_surface_resize(surface: Variant) -> void:
	var control := _surface_as_control(surface)
	if control == null:
		return
	var resized_callback := Callable(self, "_on_surface_resized")
	if control.resized.is_connected(resized_callback):
		control.resized.disconnect(resized_callback)

func _on_surface_resized() -> void:
	_apply_cover_layout()

func _apply_cover_layout() -> void:
	var player := _live_player()
	var surface_control := _surface_as_control(_live_surface())
	if player == null:
		return
	if _player_supports_property("cover_mode"):
		_set_player_property("cover_mode", _cover_mode)
	if _player_supports_property("expand"):
		_set_player_property("expand", true)
	if surface_control != null:
		surface_control.clip_contents = true
	if surface_control == null or not (player is Control):
		return
	var player_control := player as Control
	player_control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	player_control.custom_minimum_size = Vector2.ZERO
	var surface_size := surface_control.size
	if surface_size.x <= 0.0 or surface_size.y <= 0.0:
		surface_size = surface_control.get_rect().size
	if surface_size.x <= 0.0 or surface_size.y <= 0.0:
		return
	var video_size := _get_video_size()
	var target_size := surface_size
	match _cover_mode:
		COVER_MODE_STRETCH:
			target_size = surface_size
		COVER_MODE_CONTAIN:
			target_size = _fit_video(video_size, surface_size, false)
		COVER_MODE_COVER:
			target_size = _fit_video(video_size, surface_size, true)
	player_control.position = (surface_size - target_size) * 0.5
	player_control.size = target_size

func _get_video_size() -> Vector2:
	var width := float(_loaded_source.get("width", _media_info.get("width", DEFAULT_VIDEO_WIDTH)))
	var height := float(_loaded_source.get("height", _media_info.get("height", DEFAULT_VIDEO_HEIGHT)))
	width = maxf(width, 1.0)
	height = maxf(height, 1.0)
	return Vector2(width, height)

func _fit_video(video_size: Vector2, container_size: Vector2, cover: bool) -> Vector2:
	var scale_x := container_size.x / video_size.x
	var scale_y := container_size.y / video_size.y
	var scale := maxf(scale_x, scale_y) if cover else minf(scale_x, scale_y)
	return video_size * scale

func _normalize_cover_mode(value: Variant) -> String:
	var normalized := str(value).strip_edges().to_lower()
	return normalized if COVER_MODES.has(normalized) else DEFAULT_COVER_MODE

func _normalize_audio_level(value: Variant) -> float:
	return clampf(float(value), 0.0, 1.0)

func _audio_level_to_db(level: float) -> float:
	if level <= 0.0:
		return DEFAULT_MUTED_VOLUME_DB
	if is_equal_approx(level, 1.0):
		return DEFAULT_UNMUTED_VOLUME_DB
	return linear_to_db(level)

func _ok(detail: Dictionary = {}) -> Dictionary:
	return CoreContract.ok(detail)

func _fail(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	_last_error = translate_backend_error(code, message, detail)
	_vendor_state = STATE_ERROR
	return CoreContract.fail(code, message, detail)
