extends GutTest

const FACTORY_SCRIPT := preload("res://src/AeroGodotVideoBackendFactory.gd")
const FAKE_PLAYER_SCRIPT := preload("res://tests/helpers/FakeVideoStreamPlayer.gd")
const SAMPLE_VIDEO_PATH := "res://assets/videos/calm_blue_sea_1.ogv"

var _factory: AeroGodotVideoBackendFactory
var _backend: AeroGodotVideoBackend
var _manager: Node

func _make_fake_player() -> Node:
	return FAKE_PLAYER_SCRIPT.new()

func before_each() -> void:
	_factory = FACTORY_SCRIPT.new()
	_backend = _factory.create_backend(Callable(self, "_make_fake_player"))
	_manager = _factory.create_manager(Callable(self, "_make_fake_player"))
	add_child_autofree(_manager)
	_manager._initialize()

func _global_class_names() -> Array[String]:
	var names: Array[String] = []
	for class_info in ProjectSettings.get_global_class_list():
		names.append(str(class_info.get("class", "")))
	return names

func test_public_surface_is_vendor_specific_and_collision_safe() -> void:
	var class_names := _global_class_names()
	assert_false(class_names.has("AeroToolManager"), "Repo should no longer export a generic AeroToolManager global class")
	assert_true(class_names.has("AeroGodotVideoBackend"), "Repo should export the vendor-specific backend class")
	assert_true(class_names.has("AeroGodotVideoBackendFactory"), "Repo should export the vendor-specific factory class")
	assert_eq(AeroGodotVideoBackendFactory.VERSION, "0.2.0", "Factory version should reflect the backend/factory refactor")

func test_factory_can_create_a_prewired_video_player_manager() -> void:
	assert_true(_manager is AeroVideoPlayerManager, "Factory should create the stable tool-facing manager")
	assert_true(_manager.get_backend() is AeroGodotVideoBackend, "Factory-created manager should be wired to the Godot backend")
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_IDLE, "Fresh manager should begin idle")

func test_backend_loads_the_real_ogv_sample_and_reports_verified_media() -> void:
	var surface := Node.new()
	surface.name = "VideoSurface"
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container")

	var result := _backend.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"metadata": {"source": "vendor_testbed", "real_sample": true},
	})
	assert_true(bool(result.get("success", false)), "Backend should load the real sample asset")
	var media_info := _backend.get_media_info()
	assert_eq(str(media_info.get("path", "")), SAMPLE_VIDEO_PATH, "Media info should retain the sample path")
	assert_eq(str(media_info.get("format_status", "")), "verified", "OGV should remain the verified format")
	assert_eq(str(media_info.get("vendor", "")), AeroGodotVideoBackend.VENDOR_NAME, "Media info should identify the Godot vendor")
	assert_true(bool(media_info.get("audio", {}).has("muted")), "Media info should include audio-state reporting")
	assert_eq(str(_backend.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_READY, "Successful load should leave the backend ready")

func test_manager_path_supports_load_play_pause_resume_seek_stop_and_audio_state() -> void:
	var surface := Node.new()
	surface.name = "ManagedSurface"
	add_child_autofree(surface)
	_manager.attach_surface(surface)
	_manager.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 20.0,
		"start_time": 2.0,
		"metadata": {"real_sample": true},
	})
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_READY, "Manager should become ready after load")
	assert_eq(_manager.get_position(), 2.0, "Manager should honor start_time")

	_manager.play()
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_PLAYING, "play should transition into playing")
	_manager.pause()
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_PAUSED, "pause should transition into paused")
	_manager.play()
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_PLAYING, "resume should reuse play on the stable manager")
	_manager.seek(5.0)
	assert_eq(_manager.get_position(), 5.0, "seek should update the manager position")
	_manager.stop()
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_READY, "stop should return the manager to ready")
	assert_eq(_manager.get_position(), 0.0, "stop should reset playback position")

	var backend: Variant = _manager.get_backend()
	assert_true(bool(backend.set_muted(true).get("success", false)), "Vendor backend should support muting for proving coverage")
	assert_true(bool(backend.get_audio_state().get("muted", false)), "Audio state should report muted after mute toggle")
	assert_true(bool(backend.set_muted(false).get("success", false)), "Vendor backend should support unmuting")
	assert_false(bool(backend.get_audio_state().get("muted", true)), "Audio state should report unmuted after restoring audio")

func test_backend_failure_cases_surface_honest_errors() -> void:
	var remote_result := _backend.load({"path": "https://example.com/demo.ogv"})
	assert_false(bool(remote_result.get("success", true)), "Remote URLs should be rejected in the Godot local-file slice")
	assert_eq(str(_backend.get_last_error().get("code", "")), "backend_source_not_local", "Remote rejection should use the local-file error code")

	var missing_result := _backend.load({"path": "res://assets/videos/does_not_exist.ogv"})
	assert_false(bool(missing_result.get("success", true)), "Missing sample path should fail honestly")
	assert_eq(str(_backend.get_last_error().get("code", "")), "backend_stream_load_failed", "Missing sample should fail through the real stream-loading path")
