# AeroBeat Vendor Godot Video

This repo owns the **Godot-specific video backend/factory layer** for the current AeroBeat tool architecture.

It should be read against the locked product direction from `aerobeat-docs`:

- **Primary release target:** PC community first
- **Official v1 gameplay features:** Boxing and Flow
- **Official v1 gameplay input:** camera only
- **Layering stance:** this repo does not define the generic playback facade; it provides the Godot-native backend underneath the shared tool-side playback contract
- **Collision-safety stance:** this repo must not export a second generic `AeroToolManager` into Godot's flat global script namespace

## Current package surface

The public package surface now centers on two explicit Godot-specific entrypoints:

- `src/AeroGodotVideoBackend.gd` — the Godot-native backend implementation that plugs into `AeroVideoPlayerManager`
- `src/AeroGodotVideoBackendFactory.gd` — a small collision-safe factory that creates either the backend or a pre-wired `AeroVideoPlayerManager`

`aerobeat-tool-video-player` owns the stable playback facade. This vendor repo stays focused on:

- Godot-native `VideoStreamPlayer` creation and surface binding
- local-file source normalization and validation
- Godot stream loading for the verified `.ogv` path, including absolute local files that live outside the project tree
- vendor capability reporting and state translation
- vendor-local audio mute/state helpers for proving and inspection

## Ownership split

- `aerobeat-tool-core` owns the shared playback vocabulary (`AeroVideoPlaybackContract`)
- `aerobeat-tool-video-player` owns the stable public facade (`AeroVideoPlayerManager`) and generic playback lifecycle semantics
- `aerobeat-vendor-godot-video` owns the Godot backend/factory layer and should be injected beneath `AeroVideoPlayerManager`

## Downstream factory decision

Downstream repos should stop depending on any vendor-local generic manager name from this repo.

Use one of these two paths instead:

1. **Preferred explicit wiring**
   - instantiate `AeroVideoPlayerManager`
   - instantiate `AeroGodotVideoBackend`
   - inject the backend via `manager.set_backend(...)`

2. **Small convenience factory**
   - instantiate `AeroGodotVideoBackendFactory`
   - call `create_manager()` for a pre-wired `AeroVideoPlayerManager`

This keeps the public playback contract stable while avoiding class-name collisions in combined GodotEnv surfaces.

## Repo-local proving surface

The hidden `.testbed/` workbench now includes a real `.ogv` proving surface.

- `.testbed/assets/videos/calm_blue_sea_1.ogv` copies the proven environment-lane sample
- `.testbed/scenes/video_backend_testbed.tscn` provides a manual proving scene for load / play / pause / resume / seek / stop / mute / failure handling
- `.testbed/tests/test_AeroGodotVideoBackendFactory.gd` exercises the factory + backend contract path under GUT

## 📋 Repository Details

- **Type:** Vendor-specific Godot video backend package
- **License:** **Mozilla Public License 2.0 (MPL 2.0)**
- **Verified media target in this repo:** local `.ogv` playback through Godot's built-in video path

## GodotEnv development flow

This repo uses the AeroBeat GodotEnv package convention.

- Canonical dev/test manifest: `.testbed/addons.jsonc`
- Installed dev/test addons: `.testbed/addons/`
- GodotEnv cache: `.testbed/.addons/`
- Hidden workbench project: `.testbed/project.godot`
- Repo-local unit tests: `.testbed/tests/`

The repo root remains the package/published boundary for downstream consumers. Day-to-day development, debugging, and validation happen from the hidden `.testbed/` workbench using the pinned OpenClaw toolchain: Godot `4.6.2 stable standard`.

### Restore dev/test dependencies

From the repo root:

```bash
cd .testbed
godotenv addons install
```

If addon state gets noisy during AeroBeat polyrepo work, use the canonical helper instead of editing mirrored addon payloads directly:

```bash
/home/derrick/.openclaw/workspace/scripts/godotenv-sync --repo /home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video
```

### Open the workbench

From the repo root:

```bash
godot --editor --path .testbed
```

Use this `.testbed/` project as the canonical direct-development and bugfinding surface for backend/factory work.

### Import smoke check

From the repo root:

```bash
godot --headless --path .testbed --import
```

### Run unit tests

From the repo root:

```bash
godot --headless --path .testbed --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs \
  -gexit
```

### Validation notes

- `.testbed/addons.jsonc` is the committed dev/test dependency contract.
- The manifest intentionally includes `aerobeat-tool-core`, `aerobeat-tool-video-player`, and `gut`.
- The manual proving scene is repo-local and uses the real `.ogv` sample rather than introducing a new ad hoc fixture.
- This repo should not reintroduce a generic public manager name; the public tool-facing facade remains `AeroVideoPlayerManager` upstream.
