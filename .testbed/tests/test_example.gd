extends GutTest

const README_PATH := "../README.md"
const PLUGIN_CFG_PATH := "../plugin.cfg"
const ADDONS_MANIFEST_PATH := "addons.jsonc"
const EXPECTED_PLUGIN_DESCRIPTION := "Collision-safe Godot video backend/factory layer for AeroVideoPlayerManager, with real .ogv proving coverage."

func _read_repo_file(relative_path: String) -> String:
	var absolute_path := ProjectSettings.globalize_path("res://%s" % relative_path)
	assert_true(FileAccess.file_exists(absolute_path), "Expected repo file to exist: %s" % absolute_path)
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	assert_true(file != null, "Expected repo file to open: %s" % absolute_path)
	return file.get_as_text()

func test_readme_describes_backend_and_factory_layering() -> void:
	var readme_text := _read_repo_file(README_PATH)
	assert_true(readme_text.contains("Godot-specific video backend/factory layer"), "README should describe the backend/factory role")
	assert_true(readme_text.contains("must not export a second generic `AeroToolManager`"), "README should document the collision-safety rule")
	assert_true(readme_text.contains("AeroVideoPlayerManager"), "README should point downstream consumers at the stable tool facade")
	assert_true(readme_text.contains("AeroGodotVideoBackendFactory"), "README should document the new factory entrypoint")
	assert_true(readme_text.contains("real `.ogv` proving surface"), "README should mention the real-sample proving surface")

func test_plugin_cfg_description_matches_vendor_backend_scope() -> void:
	var config := ConfigFile.new()
	var error := config.load(ProjectSettings.globalize_path("res://%s" % PLUGIN_CFG_PATH))
	assert_eq(error, OK, "plugin.cfg should parse cleanly")
	assert_eq(config.get_value("plugin", "name", ""), "AeroBeat Vendor Godot Video", "plugin.cfg name should match the repo role")
	assert_eq(
		config.get_value("plugin", "description", ""),
		EXPECTED_PLUGIN_DESCRIPTION,
		"plugin.cfg description should stay aligned with the backend/factory scope"
	)

func test_addons_manifest_pins_expected_video_stack_dependencies() -> void:
	var manifest_text := _read_repo_file(ADDONS_MANIFEST_PATH)
	assert_true(manifest_text.contains('"aerobeat-tool-core"'), "addons manifest should pin aerobeat-tool-core")
	assert_true(manifest_text.contains('"aerobeat-tool-video-player"'), "addons manifest should pin aerobeat-tool-video-player")
	assert_true(manifest_text.contains('"gut"'), "addons manifest should pin gut for repo-local tests")
	assert_false(manifest_text.contains('"aerobeat-core"'), "addons manifest should not reintroduce stale aerobeat-core drift")
