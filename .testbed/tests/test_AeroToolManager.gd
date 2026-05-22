extends GutTest

const BACKEND_SCRIPT := preload("res://src/AeroGodotVideoBackend.gd")
const FAKE_PLAYER_SCRIPT := preload("res://tests/helpers/FakeVideoStreamPlayer.gd")

var _manager: AeroToolManager
var _backend: AeroGodotVideoBackend

func _make_fake_player() -> Node:
	return FAKE_PLAYER_SCRIPT.new()

func before_each() -> void:
	_manager = AeroToolManager.new()
	_backend = BACKEND_SCRIPT.new()
	_backend.set_player_factory(Callable(self, "_make_fake_player"))
	_manager.set_backend(_backend)
	add_child_autofree(_manager)
	_manager._initialize()

func test_vendor_manager_exposes_wrapper_shell_surface() -> void:
	assert_eq(AeroToolManager.VERSION, "0.1.0", "Version should reflect the first vendor-wrapper shell slice")
	assert_true(_manager.has_method("create_backend"), "Vendor manager should expose backend creation")
	assert_true(_manager.has_method("prepare_source"), "Vendor manager should expose source preparation")
	assert_true(_manager.has_method("get_capabilities"), "Vendor manager should expose capabilities")
	assert_true(_manager.has_method("attach_surface"), "Vendor manager should expose surface attachment")
	assert_true(_manager.has_method("detach_surface"), "Vendor manager should expose surface detachment")
	assert_true(_manager.has_method("translate_backend_error"), "Vendor manager should expose backend error translation")
	assert_same(_manager.get_backend(), _backend, "Manager should use the injected backend for deterministic tests")

func test_normalize_source_coerces_local_file_inputs() -> void:
	var normalized := _manager.normalize_source({
		"path": " file:///tmp/demo.ogv ",
		"metadata": "not-a-dictionary",
	})
	assert_eq(String(normalized.get("path", "")), "/tmp/demo.ogv", "file:// URIs should normalize to a local absolute path")
	assert_eq(String(normalized.get("kind", "")), AeroGodotVideoBackend.SOURCE_KIND_FILE, "Source kind should normalize to file")
	assert_true(bool(normalized.get("is_local_file", false)), "Normalized file:// path should be treated as local")
	assert_eq(String(normalized.get("locality", "")), "absolute_path", "Normalized file:// URI should be tagged as absolute_path")
	assert_eq(String(normalized.get("extension", "")), "ogv", "Normalized metadata should include the file extension")
	assert_eq(normalized.get("metadata", {}), {}, "Non-dictionary metadata should coerce to an empty dictionary")

func test_prepare_source_surfaces_vendor_media_metadata_without_tool_owned_lifecycle() -> void:
	var result := _manager.prepare_source({
		"path": "res://videos/example.ogv",
		"duration_hint": 42.5,
		"start_time": 4.0,
		"loop": true,
		"metadata": {"label": "demo"},
	})
	assert_true(bool(result.get("success", false)), "Local res:// source should prepare successfully")
	var media_info := _manager.get_media_info()
	assert_eq(String(media_info.get("vendor", "")), AeroGodotVideoBackend.VENDOR_NAME, "Media info should stay vendor-local")
	assert_eq(String(media_info.get("backend_family", "")), AeroGodotVideoBackend.BACKEND_FAMILY, "Media info should expose backend family")
	assert_eq(String(media_info.get("format_status", "")), "verified", "OGV should be marked as the verified format in this first slice")
	assert_eq(float(media_info.get("duration", 0.0)), 42.5, "Duration hint should carry through vendor media metadata")
	assert_eq(float(media_info.get("position", 0.0)), 4.0, "Start time should surface through vendor media metadata")
	assert_eq(media_info.get("metadata", {}), {"label": "demo"}, "Vendor metadata should preserve caller metadata")
	assert_eq(String(_manager.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_READY, "Prepare should stop at vendor ready state, not invent tool lifecycle ownership")

func test_attach_and_detach_surface_bind_a_player_child_deterministically() -> void:
	var surface := Node.new()
	surface.name = "VideoSurface"
	add_child_autofree(surface)

	var attach_result := _manager.attach_surface(surface)
	assert_true(bool(attach_result.get("success", false)), "Surface attachment should succeed with a valid Node")
	assert_eq(surface.get_child_count(), 1, "Backend should create and attach one player child to the surface container")
	assert_true(bool(_manager.get_state().get("surface_attached", false)), "Surface attachment should be reflected in backend state")

	var detach_result := _manager.detach_surface()
	assert_true(bool(detach_result.get("success", false)), "Surface detachment should succeed")
	assert_eq(surface.get_child_count(), 0, "Detaching the surface should remove the player child from the container")
	assert_false(bool(_manager.get_state().get("surface_attached", true)), "Detached state should clear the surface binding flag")

func test_backend_transport_hooks_translate_local_state_without_claiming_tool_contract() -> void:
	var surface := Node.new()
	add_child_autofree(surface)
	assert_true(bool(_manager.attach_surface(surface).get("success", false)), "Surface should attach before transport hooks run")
	assert_true(bool(_manager.prepare_source({"path": "res://videos/example.webm", "duration_hint": 10.0}).get("success", false)), "Unverified but local formats should still prepare in the thin vendor shell")
	assert_eq(String(_manager.get_media_info().get("format_status", "")), "unverified", "Non-OGV local files should be surfaced as unverified rather than falsely promised")

	assert_true(bool(_backend.play().get("success", false)), "Vendor backend should allow play transport after load")
	assert_eq(String(_backend.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_PLAYING, "Vendor state translation should surface playing")
	assert_true(bool(_backend.pause().get("success", false)), "Vendor backend should allow pause transport after play")
	assert_eq(String(_backend.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_PAUSED, "Vendor state translation should surface paused")
	assert_true(bool(_backend.seek(8.0).get("success", false)), "Vendor backend should allow deterministic seek")
	assert_eq(float(_backend.get_position()), 8.0, "Seek should update vendor-local playback position")
	assert_true(bool(_backend.stop().get("success", false)), "Vendor backend should allow deterministic stop")
	assert_eq(String(_backend.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_READY, "Stop should return to vendor ready without defining the shared tool contract")

func test_invalid_remote_source_returns_translated_vendor_error() -> void:
	var result := _manager.prepare_source({"path": "https://example.com/demo.ogv"})
	assert_false(bool(result.get("success", true)), "Remote URL should be rejected in the local-file-only slice")
	var last_error := _manager.get_last_error()
	assert_eq(String(last_error.get("code", "")), "backend_source_not_local", "Remote URL should fail through the local-file-only boundary")
	assert_eq(String(last_error.get("category", "")), "source", "Translated error should be categorized as a source issue")
	assert_eq(String(_manager.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_ERROR, "Rejected source should move the backend into vendor error state")

func test_capabilities_surface_stays_honest_about_verified_and_unverified_formats() -> void:
	var capabilities := _manager.get_capabilities()
	assert_eq(String(capabilities.get("vendor", "")), AeroGodotVideoBackend.VENDOR_NAME, "Capabilities should identify the vendor")
	assert_eq(capabilities.get("supported_source_kinds", []), [AeroGodotVideoBackend.SOURCE_KIND_FILE], "Capabilities should promise local file sources only in this slice")
	assert_eq(capabilities.get("verified_extensions", []), ["ogv"], "Capabilities should only claim verified support for OGV")
	assert_true(capabilities.get("unverified_extensions", []).has("webm"), "Capabilities should explicitly mark WEBM as unverified rather than supported")
