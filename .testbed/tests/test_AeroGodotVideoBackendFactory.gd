extends GutTest

const FACTORY_SCRIPT := preload("res://addons/aerobeat-vendor-godot-video/src/AeroGodotVideoBackendFactory.gd")
const FAKE_PLAYER_SCRIPT := preload("res://tests/helpers/FakeVideoStreamPlayer.gd")
const SAMPLE_VIDEO_PATH := "res://assets/videos/calm_blue_sea_1.ogv"
const STATE_IDLE := "idle"
const STATE_READY := "ready"
const STATE_PLAYING := "playing"
const STATE_PAUSED := "paused"
const COVER_MODE_STRETCH := "stretch"
const COVER_MODE_CONTAIN := "contain"
const COVER_MODE_COVER := "cover"

var _factory: AeroGodotVideoBackendFactory
var _backend: AeroGodotVideoBackend
var _manager: Node
var _external_tmp_dir: String = ""
var _external_sample_path: String = ""

func _make_fake_player() -> Node:
	return FAKE_PLAYER_SCRIPT.new()

func before_each() -> void:
	_factory = FACTORY_SCRIPT.new()
	_backend = _factory.create_backend(Callable(self, "_make_fake_player"))
	_manager = _factory.create_manager(Callable(self, "_make_fake_player"))
	add_child_autofree(_manager)
	_manager._initialize()
	_prepare_external_sample()

func after_each() -> void:
	if not _external_sample_path.is_empty() and FileAccess.file_exists(_external_sample_path):
		DirAccess.remove_absolute(_external_sample_path)
	if not _external_tmp_dir.is_empty() and DirAccess.dir_exists_absolute(_external_tmp_dir):
		DirAccess.remove_absolute(_external_tmp_dir)
	_external_sample_path = ""
	_external_tmp_dir = ""

func _prepare_external_sample() -> void:
	_external_tmp_dir = OS.get_cache_dir().path_join("aerobeat-vendor-godot-video-external-%s" % str(Time.get_unix_time_from_system()))
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_external_tmp_dir)
	assert_eq(mkdir_error, OK, "Should create a temporary directory for external-file playback coverage")
	_external_sample_path = _external_tmp_dir.path_join("external-sample.ogv")
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(SAMPLE_VIDEO_PATH), _external_sample_path)
	assert_eq(copy_error, OK, "Should copy the proven sample outside the project tree for external-file playback coverage")

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
	assert_true(class_names.has("AeroGodotVideoSlotBank"), "Repo should export the vendor-local multi-slot helper class")
	assert_eq(AeroGodotVideoBackendFactory.VERSION, "0.4.0", "Factory version should reflect parity + cover/audio-level support")

func test_factory_can_create_a_prewired_video_player_manager_and_slot_bank() -> void:
	assert_true(_manager is AeroVideoPlayerManager, "Factory should create the stable tool-facing manager")
	assert_true(_manager.get_backend() is AeroGodotVideoBackend, "Factory-created manager should be wired to the Godot backend")
	assert_eq(str(_manager.get_state().get("state", "")), STATE_IDLE, "Fresh manager should begin idle")
	var slot_bank := _factory.create_slot_bank(Callable(self, "_make_fake_player"))
	add_child_autofree(slot_bank)
	assert_true(slot_bank is AeroGodotVideoSlotBank, "Factory should create the vendor-local multi-slot helper")
	assert_true(bool(slot_bank.get_capabilities().get("supports_slots", false)), "Slot bank capabilities should advertise slot support")
	assert_true(bool(slot_bank.get_capabilities().get("supports_independent_cover_mode_control", false)), "Slot bank should advertise independent cover-mode support")
	assert_true(bool(slot_bank.get_capabilities().get("supports_independent_audio_level_control", false)), "Slot bank should advertise independent audio-level support")

func test_backend_loads_the_real_ogv_sample_and_reports_verified_media() -> void:
	var surface := Control.new()
	surface.name = "VideoSurface"
	surface.custom_minimum_size = Vector2(640, 360)
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container")

	var result := _backend.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"cover_mode": COVER_MODE_COVER,
		"audio_level": 0.35,
		"metadata": {"source": "vendor_testbed", "real_sample": true},
	})
	assert_true(bool(result.get("success", false)), "Backend should load the real sample asset")
	var media_info := _backend.get_media_info()
	assert_eq(str(media_info.get("path", "")), SAMPLE_VIDEO_PATH, "Media info should retain the sample path")
	assert_eq(str(media_info.get("format_status", "")), "verified", "OGV should remain the verified format")
	assert_eq(str(media_info.get("vendor", "")), AeroGodotVideoBackend.VENDOR_NAME, "Media info should identify the Godot vendor")
	assert_true(bool(media_info.get("audio", {}).has("muted")), "Media info should include audio-state reporting")
	assert_eq(str(media_info.get("cover_mode", "")), COVER_MODE_COVER, "Media info should expose the current cover mode")
	assert_eq(str(_backend.get_state().get("vendor_state", "")), AeroGodotVideoBackend.STATE_READY, "Successful load should leave the backend ready")

func test_backend_loads_an_external_absolute_ogv_file_outside_the_project_tree() -> void:
	var surface := Control.new()
	surface.name = "ExternalVideoSurface"
	surface.custom_minimum_size = Vector2(640, 360)
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container for external-file coverage")

	var result := _backend.load({
		"path": _external_sample_path,
		"metadata": {"source": "external_fixture", "outside_project_tree": true},
	})
	assert_true(bool(result.get("success", false)), "Backend should load an absolute local OGV path outside res:// and user://")
	var media_info := _backend.get_media_info()
	assert_eq(str(media_info.get("path", "")), _external_sample_path, "Media info should retain the external absolute path")
	assert_eq(str(media_info.get("locality", "")), "absolute_path", "External fixture should report absolute-path locality")
	assert_eq(str(media_info.get("format_status", "")), "verified", "External OGV should still report as verified")
	var player := surface.get_child(0)
	assert_not_null(player, "Backend should have created a player node for the attached surface")
	var stream: Variant = player.get("stream") if player != null and player.has_method("get") else null
	assert_not_null(stream, "Player should receive a VideoStream resource for the external file")
	assert_true(stream.has_method("get_file"), "External stream should be a file-backed VideoStream resource")
	assert_eq(str(stream.call("get_file")), _external_sample_path, "External stream resource should point at the outside-project absolute path")

func test_manager_path_supports_load_play_pause_resume_seek_stop_cover_and_audio_level() -> void:
	var surface := Control.new()
	surface.name = "ManagedSurface"
	surface.custom_minimum_size = Vector2(640, 360)
	add_child_autofree(surface)
	_manager.attach_surface(surface)
	_manager.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 20.0,
		"start_time": 2.0,
		"cover_mode": COVER_MODE_COVER,
		"audio_level": 0.45,
		"metadata": {"real_sample": true},
	})
	assert_eq(str(_manager.get_state().get("state", "")), STATE_READY, "Manager should become ready after load")
	assert_eq(_manager.get_position(), 2.0, "Manager should honor start_time")
	assert_eq(str(_manager.get_state().get("cover_mode", "")), COVER_MODE_COVER, "Manager should expose the current cover mode")
	assert_eq(float(_manager.get_state().get("audio_level", -1.0)), 0.45, "Manager should expose the current audio level")

	_manager.play()
	assert_eq(str(_manager.get_state().get("state", "")), STATE_PLAYING, "play should transition into playing")
	_manager.pause()
	assert_eq(str(_manager.get_state().get("state", "")), STATE_PAUSED, "pause should transition into paused")
	_manager.play()
	assert_eq(str(_manager.get_state().get("state", "")), STATE_PLAYING, "resume should reuse play on the stable manager")
	_manager.seek(5.0)
	assert_eq(_manager.get_position(), 5.0, "seek should update the manager position")
	_manager.set_cover_mode(COVER_MODE_STRETCH)
	assert_eq(str(_manager.get_state().get("cover_mode", "")), COVER_MODE_STRETCH, "Cover-mode updates should flow through the stable manager")
	_manager.set_audio_level(0.8)
	assert_eq(float(_manager.get_state().get("audio_level", -1.0)), 0.8, "Audio-level updates should flow through the stable manager")
	_manager.stop()
	assert_eq(str(_manager.get_state().get("state", "")), STATE_READY, "stop should return the manager to ready")
	assert_eq(_manager.get_position(), 0.0, "stop should reset playback position")

func test_backend_applies_and_updates_loop_cover_and_audio_state_on_the_player() -> void:
	var surface := Control.new()
	surface.name = "LoopSurface"
	surface.custom_minimum_size = Vector2(640, 360)
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container for loop coverage")
	assert_true(bool(_backend.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"loop": true,
		"cover_mode": COVER_MODE_CONTAIN,
		"audio_level": 0.5,
		"metadata": {"real_sample": true, "scenario": "loop"},
	}).get("success", false)), "Backend should load the sample with loop enabled")
	var player := surface.get_child(0)
	assert_true(bool(player.get("loop")), "Fake player should receive loop=true from the initial load")
	assert_eq(str(player.get("cover_mode")), COVER_MODE_CONTAIN, "Fake player should receive the initial cover mode")
	assert_eq(float(player.get("volume")), 0.5, "Fake player should receive the initial audio level")
	assert_true(bool(_backend.set_loop(false).get("success", false)), "Backend should allow loop to be disabled after load")
	assert_true(bool(_backend.set_cover_mode(COVER_MODE_COVER).get("success", false)), "Backend should allow cover mode to be changed after load")
	assert_true(bool(_backend.set_audio_level(0.2).get("success", false)), "Backend should allow audio level to be changed after load")
	assert_false(bool(player.get("loop")), "Fake player should reflect loop=false after toggling loop off")
	assert_eq(str(player.get("cover_mode")), COVER_MODE_COVER, "Fake player should reflect cover mode changes")
	assert_eq(float(player.get("volume")), 0.2, "Fake player should reflect audio-level changes")

func test_slot_bank_supports_multiple_independent_video_slots_cover_and_audio_level() -> void:
	var slot_bank := _factory.create_slot_bank(Callable(self, "_make_fake_player"))
	add_child_autofree(slot_bank)

	var left_surface := Control.new()
	left_surface.name = "LeftSurface"
	left_surface.custom_minimum_size = Vector2(640, 360)
	add_child_autofree(left_surface)
	var right_surface := Control.new()
	right_surface.name = "RightSurface"
	right_surface.custom_minimum_size = Vector2(640, 360)
	add_child_autofree(right_surface)

	assert_true(bool(slot_bank.attach_slot_surface("left", left_surface).get("success", false)), "Left slot should attach a surface")
	assert_true(bool(slot_bank.attach_slot_surface("right", right_surface).get("success", false)), "Right slot should attach a surface")
	assert_true(bool(slot_bank.load_slot("left", {
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"start_time": 1.0,
		"loop": false,
		"cover_mode": COVER_MODE_CONTAIN,
		"audio_level": 0.4,
		"metadata": {"slot": "left", "real_sample": true},
	}).get("success", false)), "Left slot should load the sample")
	assert_true(bool(slot_bank.load_slot("right", {
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 24.0,
		"start_time": 4.0,
		"loop": true,
		"cover_mode": COVER_MODE_STRETCH,
		"audio_level": 0.9,
		"metadata": {"slot": "right", "real_sample": true},
	}).get("success", false)), "Right slot should load the sample independently")

	var left_manager := slot_bank.get_slot_manager("left")
	var right_manager := slot_bank.get_slot_manager("right")
	assert_not_null(left_manager, "Left slot should expose its manager")
	assert_not_null(right_manager, "Right slot should expose its manager")
	assert_false(left_manager == right_manager, "Each slot should receive an independent manager instance")
	assert_eq(slot_bank.get_slot_names().size(), 2, "Slot bank should track both created slots")

	var left_state := slot_bank.get_slot_state("left")
	var right_state := slot_bank.get_slot_state("right")
	assert_eq(float(left_state.get("position", 0.0)), 1.0, "Left slot should preserve its own start_time")
	assert_eq(float(right_state.get("position", 0.0)), 4.0, "Right slot should preserve its own start_time")
	assert_false(bool(left_state.get("loop", true)), "Left slot should preserve its own loop setting")
	assert_true(bool(right_state.get("loop", false)), "Right slot should preserve its own loop setting")
	assert_eq(str(left_state.get("cover_mode", "")), COVER_MODE_CONTAIN, "Left slot should keep its own cover mode")
	assert_eq(str(right_state.get("cover_mode", "")), COVER_MODE_STRETCH, "Right slot should keep its own cover mode")
	assert_eq(float(left_state.get("audio_level", -1.0)), 0.4, "Left slot should keep its own audio level")
	assert_eq(float(right_state.get("audio_level", -1.0)), 0.9, "Right slot should keep its own audio level")

	assert_true(bool(slot_bank.play_slot("left").get("success", false)), "Left slot should play independently")
	assert_eq(str(slot_bank.get_slot_state("left").get("state", "")), STATE_PLAYING, "Left slot should enter playing state")
	assert_eq(str(slot_bank.get_slot_state("right").get("state", "")), STATE_READY, "Right slot should remain ready when only left plays")

	assert_true(bool(slot_bank.set_slot_cover_mode("left", COVER_MODE_COVER).get("success", false)), "Left slot should support cover-mode toggles")
	assert_true(bool(slot_bank.set_slot_audio_level("right", 0.15).get("success", false)), "Right slot should support independent audio-level updates")
	var left_player := left_surface.get_child(0)
	var right_player := right_surface.get_child(0)
	assert_eq(str(left_player.get("cover_mode")), COVER_MODE_COVER, "Left player should now have cover mode enabled")
	assert_eq(float(right_player.get("volume")), 0.15, "Right player should now have its updated audio level")
	assert_eq(str(slot_bank.get_slot_state("left").get("cover_mode", "")), COVER_MODE_COVER, "Left state should report its updated cover mode")
	assert_eq(float(slot_bank.get_slot_state("right").get("audio_level", -1.0)), 0.15, "Right state should report its updated audio level")

func test_backend_failure_cases_surface_honest_errors() -> void:
	var remote_result := _backend.load({"path": "https://example.com/demo.ogv"})
	assert_false(bool(remote_result.get("success", true)), "Remote URLs should be rejected in the Godot local-file slice")
	assert_eq(str(_backend.get_last_error().get("code", "")), "backend_source_not_local", "Remote rejection should use the local-file error code")

	var missing_result := _backend.load({"path": "res://assets/videos/does_not_exist.ogv"})
	assert_false(bool(missing_result.get("success", true)), "Missing sample path should fail honestly")
	assert_eq(str(_backend.get_last_error().get("code", "")), "backend_stream_load_failed", "Missing sample should fail through the real stream-loading path")
