## Public vendor entrypoint for AeroBeat Godot-native video playback.
##
## This repo deliberately stays vendor-local: source normalization, capability
## reporting, surface binding, and backend-specific state/error translation live
## here. The generic playback lifecycle contract remains owned by
## aerobeat-tool-video-player.
class_name AeroToolManager
extends Node

signal initialized

const VERSION: String = "0.1.0"
const VENDOR_NAME := "godot_video"
const SOURCE_KIND_FILE := "file"

const ERROR_INVALID_SOURCE := "backend_invalid_source"
const ERROR_INVALID_SURFACE := "backend_invalid_surface"
const ERROR_BACKEND_REJECTED := "backend_rejected"

const GodotBackendScript := preload("res://src/AeroGodotVideoBackend.gd")

@export var is_active: bool = true

var _is_initialized: bool = false
var _backend: AeroVideoVendorBackend = null

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	if _is_initialized:
		return
	if _backend == null:
		_backend = GodotBackendScript.new()
	_is_initialized = true
	initialized.emit()

func set_backend(backend: AeroVideoVendorBackend) -> void:
	_backend = backend if backend != null else GodotBackendScript.new()

func create_backend() -> AeroVideoVendorBackend:
	return GodotBackendScript.new()

func get_backend() -> AeroVideoVendorBackend:
	_initialize()
	return _backend

func get_default_source_config() -> Dictionary:
	return {
		"path": "",
		"kind": SOURCE_KIND_FILE,
		"loop": false,
		"autoplay": false,
		"start_time": 0.0,
		"rate": 1.0,
		"metadata": {},
	}

func normalize_source(source: Dictionary) -> Dictionary:
	_initialize()
	return _backend.normalize_source(source)

func validate_source(source: Dictionary) -> Dictionary:
	_initialize()
	return _backend.validate_source(normalize_source(source))

func can_prepare_source(source: Dictionary) -> bool:
	return validate_source(source).is_empty()

func prepare_source(source: Dictionary) -> Dictionary:
	_initialize()
	if not is_active:
		return {
			"success": false,
			"code": ERROR_BACKEND_REJECTED,
			"message": "AeroToolManager is inactive.",
		}
	return _backend.load(source)

func get_capabilities() -> Dictionary:
	_initialize()
	return _backend.get_capabilities()

func attach_surface(node: Node) -> Dictionary:
	_initialize()
	return _backend.attach_surface(node)

func detach_surface() -> Dictionary:
	_initialize()
	return _backend.detach_surface()

func get_state() -> Dictionary:
	_initialize()
	return _backend.get_state()

func get_media_info() -> Dictionary:
	_initialize()
	return _backend.get_media_info()

func get_last_error() -> Dictionary:
	_initialize()
	return _backend.get_last_error()

func translate_backend_error(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	_initialize()
	return _backend.translate_backend_error(code, message, detail)
