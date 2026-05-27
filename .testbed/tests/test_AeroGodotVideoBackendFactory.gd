extends GutTest

const FACTORY_SCRIPT := preload("res://src/AeroGodotVideoBackendFactory.gd")
const FAKE_PLAYER_SCRIPT := preload("res://tests/helpers/FakeVideoStreamPlayer.gd")
const SAMPLE_VIDEO_PATH := "res://assets/videos/calm_blue_sea_1.ogv"

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
	assert_eq(AeroGodotVideoBackendFactory.VERSION, "0.3.0", "Factory version should reflect the multi-slot vendor helper slice")

func test_factory_can_create_a_prewired_video_player_manager_and_slot_bank() -> void:
	assert_true(_manager is AeroVideoPlayerManager, "Factory should create the stable tool-facing manager")
	assert_true(_manager.get_backend() is AeroGodotVideoBackend, "Factory-created manager should be wired to the Godot backend")
	assert_eq(str(_manager.get_state().get("state", "")), AeroVideoPlayerManager.STATE_IDLE, "Fresh manager should begin idle")
	var slot_bank := _factory.create_slot_bank(Callable(self, "_make_fake_player"))
	add_child_autofree(slot_bank)
	assert_true(slot_bank is AeroGodotVideoSlotBank, "Factory should create the vendor-local multi-slot helper")
	assert_true(bool(slot_bank.get_capabilities().get("supports_slots", false)), "Slot bank capabilities should advertise slot support")

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

func test_backend_loads_an_external_absolute_ogv_file_outside_the_project_tree() -> void:
	var surface := Node.new()
	surface.name = "ExternalVideoSurface"
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

func test_backend_applies_and_updates_loop_state_on_the_player() -> void:
	var surface := Node.new()
	surface.name = "LoopSurface"
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container for loop coverage")
	assert_true(bool(_backend.load({
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"loop": true,
		"metadata": {"real_sample": true, "scenario": "loop"},
	}).get("success", false)), "Backend should load the sample with loop enabled")
	var player := surface.get_child(0)
	assert_true(bool(player.get("loop")), "Fake player should receive loop=true from the initial load")
	assert_true(bool(_backend.get_state().get("loop", false)), "Backend state should report loop=true after load")
	assert_true(bool(_backend.set_loop(false).get("success", false)), "Backend should allow loop to be disabled after load")
	assert_false(bool(player.get("loop")), "Fake player should reflect loop=false after toggling loop off")
	assert_false(bool(_backend.get_state().get("loop", true)), "Backend state should report loop=false after toggle")

func test_slot_bank_supports_multiple_independent_video_slots() -> void:
	var slot_bank := _factory.create_slot_bank(Callable(self, "_make_fake_player"))
	add_child_autofree(slot_bank)

	var primary_surface := Node.new()
	primary_surface.name = "PrimarySurface"
	add_child_autofree(primary_surface)
	var secondary_surface := Node.new()
	secondary_surface.name = "SecondarySurface"
	add_child_autofree(secondary_surface)

	assert_true(bool(slot_bank.attach_slot_surface("primary", primary_surface).get("success", false)), "Primary slot should attach a surface")
	assert_true(bool(slot_bank.attach_slot_surface("secondary", secondary_surface).get("success", false)), "Secondary slot should attach a surface")
	assert_true(bool(slot_bank.load_slot("primary", {
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 12.0,
		"start_time": 1.0,
		"loop": false,
		"metadata": {"slot": "primary", "real_sample": true},
	}).get("success", false)), "Primary slot should load the sample")
	assert_true(bool(slot_bank.load_slot("secondary", {
		"path": SAMPLE_VIDEO_PATH,
		"duration_hint": 24.0,
		"start_time": 4.0,
		"loop": true,
		"metadata": {"slot": "secondary", "real_sample": true},
	}).get("success", false)), "Secondary slot should load the sample independently")

	var primary_manager := slot_bank.get_slot_manager("primary")
	var secondary_manager := slot_bank.get_slot_manager("secondary")
	assert_not_null(primary_manager, "Primary slot should expose its manager")
	assert_not_null(secondary_manager, "Secondary slot should expose its manager")
	assert_false(primary_manager == secondary_manager, "Each slot should receive an independent manager instance")
	assert_eq(slot_bank.get_slot_names().size(), 2, "Slot bank should track both created slots")

	var primary_state := slot_bank.get_slot_state("primary")
	var secondary_state := slot_bank.get_slot_state("secondary")
	assert_eq(float(primary_state.get("position", 0.0)), 1.0, "Primary slot should preserve its own start_time")
	assert_eq(float(secondary_state.get("position", 0.0)), 4.0, "Secondary slot should preserve its own start_time")
	assert_false(bool(primary_state.get("loop", true)), "Primary slot should keep loop disabled from its source")
	assert_true(bool(secondary_state.get("loop", false)), "Secondary slot should keep loop enabled from its source")

	assert_true(bool(slot_bank.play_slot("primary").get("success", false)), "Primary slot should play independently")
	assert_eq(str(slot_bank.get_slot_state("primary").get("state", "")), AeroVideoPlayerManager.STATE_PLAYING, "Primary slot should enter playing state")
	assert_eq(str(slot_bank.get_slot_state("secondary").get("state", "")), AeroVideoPlayerManager.STATE_READY, "Secondary slot should remain ready when only primary plays")

	assert_true(bool(slot_bank.set_slot_loop("primary", true).get("success", false)), "Primary slot should support loop toggles")
	assert_true(bool(slot_bank.set_slot_loop("secondary", false).get("success", false)), "Secondary slot should support independent loop toggles")
	var primary_player := primary_surface.get_child(0)
	var secondary_player := secondary_surface.get_child(0)
	assert_true(bool(primary_player.get("loop")), "Primary player should now have loop enabled")
	assert_false(bool(secondary_player.get("loop")), "Secondary player should now have loop disabled")
	assert_true(bool(slot_bank.get_slot_state("primary").get("loop", false)), "Primary state should report its updated loop value")
	assert_false(bool(slot_bank.get_slot_state("secondary").get("loop", true)), "Secondary state should report its updated loop value")

	assert_true(bool(slot_bank.set_slot_muted("secondary", true).get("success", false)), "Secondary slot should expose vendor-local mute control")
	var primary_backend: Variant = primary_manager.get_backend()
	var secondary_backend: Variant = secondary_manager.get_backend()
	assert_false(bool(primary_backend.get_audio_state().get("muted", true)), "Muting secondary should not affect primary audio state")
	assert_true(bool(secondary_backend.get_audio_state().get("muted", false)), "Secondary slot should report muted after its independent mute toggle")

func test_backend_failure_cases_surface_honest_errors() -> void:
	var remote_result := _backend.load({"path": "https://example.com/demo.ogv"})
	assert_false(bool(remote_result.get("success", true)), "Remote URLs should be rejected in the Godot local-file slice")
	assert_eq(str(_backend.get_last_error().get("code", "")), "backend_source_not_local", "Remote rejection should use the local-file error code")

	var missing_result := _backend.load({"path": "res://assets/videos/does_not_exist.ogv"})
	assert_false(bool(missing_result.get("success", true)), "Missing sample path should fail honestly")
	assert_eq(str(_backend.get_last_error().get("code", "")), "backend_stream_load_failed", "Missing sample should fail through the real stream-loading path")
