# AeroBeat Vendor Godot Video — Vendor Wrapper Shell Slice

**Date:** 2026-05-21  
**Status:** In Progress  
**Agent:** Cookie 🍪

---

## Goal

Create the first execution-ready repo-local plan for the Godot video vendor wrapper so vendor-specific playback behavior can sit behind the future `aerobeat-tool-video-player` contract without duplicating tool-owned playback lifecycle semantics.

---

## Overview

This repo is still in fresh template shape. The sharable package surface currently contains only `src/AeroToolManager.gd`, `plugin.cfg`, and template-safe GUT tests under `.testbed/tests/`. There was no repo-local `.plans/` entry yet, and `.beads/` existed only as scaffolding until this planning pass initialized the local Beads database.

The first safe implementation slice here should stay deliberately thin and vendor-owned: define the Godot backend-side wrapper boundary, vendor capability/error metadata, surface attachment behavior, and source/media-info normalization for the Godot-native playback path. This repo should *not* become the place where generic `load/play/pause/stop/seek` lifecycle truth is invented; that belongs in `aerobeat-tool-video-player`. The vendor slice should instead expose implementation details the tool layer can call into, while keeping backend quirks, format realities, and node/surface behavior local to this repo.

The proving surface remains `.testbed/`; sharable code stays at the repo root; `/addons/` is not an editing surface. If dependency hydration or local cross-repo proving needs refreshes, use the normal GodotEnv flow or `/home/derrick/.openclaw/workspace/scripts/godotenv-sync` guidance rather than patching mirrored addon payloads. Cross-repo coordination with `aerobeat-tool-video-player` should remain explicit: the tool repo owns lifecycle/state/error vocabulary, while this vendor repo owns how Godot-native playback actually fulfills that contract.

---

## REFERENCES

| ID | Description | Path |
| --- | --- | --- |
| `REF-01` | Repo bootstrap + `.testbed` / GodotEnv conventions | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/README.md` |
| `REF-02` | Current fresh template singleton stub in the vendor repo | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/src/AeroToolManager.gd` |
| `REF-03` | Tool-side contract shell planning that this vendor wrapper must serve | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-tool-video-player/.plans/2026-05-21-video-player-contract-shell-slice.md` |
| `REF-04` | First-pass `VideoPlayer` singleton contract assumptions | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-tool-video-player/.plans/bootstrap-architecture/VIDEO-PLAYER-API.md` |
| `REF-05` | Product-wide repo ownership boundary for vendor-vs-tool video responsibilities | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-docs/.plans/bootstrap-architecture/BOUNDARIES-AND-ASSUMPTIONS.md` |
| `REF-06` | Camera-tracking replay assumptions that will eventually consume tool-side playback | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-tool-camera-tracking/.plans/bootstrap-architecture/CAMERA-TRACKING-API.md` |
| `REF-07` | Current template-safe repo-local tests proving only bootstrap behavior | `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/.testbed/tests/test_AeroToolManager.gd` |

Use these reference IDs in implementation notes, QA evidence, and audit findings.

---

## First Safe Implementation Slice Boundaries

The first coder slice in this repo should include only vendor-local work needed to make the future tool contract implementable and testable:

### In scope
- A Godot-native backend/wrapper class boundary that the future `tool-video-player` service can call into.
- Vendor-local source normalization limited to safe initial cases, preferably local file playback only.
- Vendor-local media/capability metadata reporting for Godot-native playback realities.
- Surface attach/detach behavior and node expectations for the Godot backend.
- Backend-local state/detail/error translation needed to report what the Godot layer is doing.
- Deterministic `.testbed` coverage for the backend wrapper shell and its vendor-local helpers.

### Out of scope for this slice
- Owning the generic `VideoPlayer` singleton lifecycle contract.
- Inventing tool-wide `play/pause/stop/seek/load` semantics independent of the tool repo.
- Replay/tracking orchestration logic.
- Editing anything under `/addons/`.
- Broad format-support promises beyond what the first Godot-native wrapper can honestly surface as supported/unverified.

---

## Repo Conventions

- Use `.testbed/` as the canonical proving/workbench project.
- Keep sharable implementation code at the repo root under `src/`.
- Do not treat `.testbed/addons/` or any `/addons/` tree as an editing surface.
- If dependencies need refresh/sync, use the repo’s GodotEnv flow (`cd .testbed && godotenv addons install`) or `/home/derrick/.openclaw/workspace/scripts/godotenv-sync` guidance if that is the agreed local workflow.
- Prefer small repo-local abstractions that make Godot backend behavior testable without forcing downstream repos to know about concrete node wiring details.

---

## Tasks

### Task 1: Implement the Godot vendor wrapper shell slice

**Bead ID:** `aerobeat-vendor-godot-video-3b2`  
**SubAgent:** `primary` (for `coder`)  
**Role:** `coder`  
**References:** `REF-01`, `REF-02`, `REF-03`, `REF-04`, `REF-05`, `REF-07`  
**Prompt:** Serve the `coder` workflow role on the `primary` lane for `aerobeat-vendor-godot-video-3b2`. In `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video`, run `bd update aerobeat-vendor-godot-video-3b2 --status in_progress --json` when you start. Implement only the first safe vendor-wrapper slice for Godot-native playback behind the future `aerobeat-tool-video-player` contract: add vendor-local backend/wrapper classes, local-file source normalization as appropriate, media/capability metadata helpers, surface attach/detach behavior, and backend-local error/state translation. Keep generic playback lifecycle semantics owned by the tool repo rather than duplicating them here. Use `.testbed/` as the proving surface, keep sharable code at repo root, do not edit `/addons/`, and use GodotEnv / `godotenv-sync` guidance if dependencies need refresh. Run relevant repo-local validation, capture evidence, add useful bead notes, and hand off for QA.

**Folders Created/Deleted/Modified:**
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/src/`
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/.testbed/tests/`

**Files Created/Deleted/Modified:**
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/src/AeroToolManager.gd` or renamed/replaced repo-root vendor entry-point file(s)
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/src/*.gd`
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/.testbed/tests/*.gd`
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/.testbed/addons.jsonc` only if a deliberate dev/test dependency addition is needed for local proving

**Status:** ✅ Complete

**Results:** Implemented the first vendor-wrapper shell slice in commit `59613e0` (`Implement Godot video vendor wrapper shell`). Added `src/AeroVideoVendorBackend.gd` as the vendor-local backend interface, `src/AeroGodotVideoBackend.gd` as the Godot-native implementation, and rewrote `src/AeroToolManager.gd` into the vendor entrypoint that exposes source normalization, source preparation, capability/media-info reporting, surface attach/detach, and backend-local state/error translation while leaving generic playback lifecycle ownership with `aerobeat-tool-video-player` (`REF-03`, `REF-04`, `REF-05`). Added deterministic `.testbed` coverage with `tests/helpers/FakeVideoStreamPlayer.gd` and expanded `tests/test_AeroToolManager.gd` to prove local-file normalization, vendor metadata surfacing, attach/detach behavior, transport hooks, and honest verified-vs-unverified format reporting (`REF-01`, `REF-07`). Repo-local validation was rerun successfully on 2026-05-22 with `cd .testbed && godotenv addons install`, `godot --headless --path .testbed --import`, and `godot --headless --path .testbed --script addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (10/10 tests passed; Godot/GUT emitted an orphan/leak warning tied to the fake player test helper, but the command exited 0).

---

### Task 2: QA the Godot vendor wrapper shell slice

**Bead ID:** `aerobeat-vendor-godot-video-tdy`  
**SubAgent:** `primary` (for `qa`)  
**Role:** `qa`  
**References:** `REF-01`, `REF-03`, `REF-04`, `REF-05`, `REF-07`  
**Prompt:** Serve the `qa` workflow role on the `primary` lane for `aerobeat-vendor-godot-video-tdy`. In `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video`, run `bd update aerobeat-vendor-godot-video-tdy --status in_progress --json` when you start. This bead is blocked on `aerobeat-vendor-godot-video-3b2`; once unblocked, independently verify the vendor-wrapper shell slice against the repo plan and tool-side contract references. Confirm the repo stayed vendor-specific: Godot backend behavior, source/media-info normalization, capability/error reporting, and surface binding live here, while generic playback lifecycle semantics still point back to `aerobeat-tool-video-player`. Use the highest-fidelity repo-local checks available in `.testbed/`, confirm no `/addons/` edits were used as an implementation surface, confirm sharable code stayed at repo root, and note whether any dev/test dependency refresh or local tool-repo dependency wiring was required.

**Folders Created/Deleted/Modified:**
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/.testbed/`
- `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video/src/`

**Files Created/Deleted/Modified:**
- Whatever Task 1 changed; QA should cite exact touched files in its evidence.

**Status:** ✅ Complete

**Results:** Independently QA-verified commit `59613e0` on 2026-05-22 against `REF-01`, `REF-03`, `REF-04`, `REF-05`, and `REF-07`. Exact commands/results: `git status --short` (clean working tree), `git show --stat --oneline --name-only 59613e0 --` (touched only `src/AeroVideoVendorBackend.gd`, `src/AeroGodotVideoBackend.gd`, `src/AeroToolManager.gd`, `.testbed/tests/test_AeroToolManager.gd`, `.testbed/tests/helpers/FakeVideoStreamPlayer.gd`), `git show --name-only --format='' 59613e0 | grep -E '(^|/)(addons)(/|$)|^\.testbed/addons/' || true` (no `/addons/` paths touched), `cd .testbed && godotenv addons install` (resolved/install-only refresh for `aerobeat-tool-core` and `gut`), `godot --headless --path . --import` (succeeded on Godot `4.6.2`), `godot --headless --path . --script addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (`10/10` tests passed, exit `0`). Source review confirmed vendor-local backend/wrapper classes, local-file normalization, media/capability helpers, surface attach/detach, and backend-local error/state translation all live in repo-root `src/`, while generic lifecycle verbs remain owned by `aerobeat-tool-video-player` and are not surfaced as the public vendor-manager contract here. `.testbed/` remained the proving surface and no addon mirror was treated as owned source. Non-blocking gap noted for audit visibility: GUT reported one orphan (`AeroGodotVideoPlayer` fake child) and Godot emitted an ObjectDB leak warning at exit during the detach test path, but the suite still passed and slice acceptance remains valid for QA.

---

### Task 3: Audit the Godot vendor wrapper shell slice

**Bead ID:** `aerobeat-vendor-godot-video-aek`  
**SubAgent:** `primary` (for `auditor`)  
**Role:** `auditor`  
**References:** `REF-01`, `REF-03`, `REF-04`, `REF-05`, `REF-06`, `REF-07`  
**Prompt:** Serve the `auditor` workflow role on the `primary` lane for `aerobeat-vendor-godot-video-aek`. In `/home/derrick/.openclaw/workspace/projects/aerobeat/aerobeat-vendor-godot-video`, run `bd update aerobeat-vendor-godot-video-aek --status in_progress --json` when you start. This bead is blocked on `aerobeat-vendor-godot-video-tdy`; once unblocked, independently truth-check the completed vendor-wrapper shell slice against this plan, the tool-side contract references, changed files, and coder/QA evidence. Confirm the repo conventions were respected: `.testbed/` proving surface, sharable code at repo root, no `/addons/` edits, and dependency refresh handled through normal GodotEnv/sync paths. Specifically audit the coordination boundary with `aerobeat-tool-video-player`: this repo may translate or expose Godot-native backend realities, but it must not quietly become the owner of generic playback lifecycle/time/surface semantics. If the bead passes, close `aerobeat-vendor-godot-video-aek` yourself with an explicit reason; if not, leave it open with gap notes.

**Folders Created/Deleted/Modified:**
- No new folders expected; auditor verifies final touched paths.

**Files Created/Deleted/Modified:**
- No new files expected unless audit notes/docs are needed.

**Status:** ✅ Complete

**Results:** Independently audited commit `59613e0` on 2026-05-22 against `REF-01`, `REF-03`, `REF-04`, `REF-05`, `REF-06`, and `REF-07`, plus the coordination context in `/home/derrick/.openclaw/workspace/projects/openclaw-cookie/.plans/aerobeat-architecture/2026-05-22-parallel-video-and-donor-lanes.md`. Exact commands/results: `bd show aerobeat-vendor-godot-video-tdy --json` (confirmed QA evidence/closure), `git show --stat --oneline --name-only 59613e0 --` (touched only `src/AeroVideoVendorBackend.gd`, `src/AeroGodotVideoBackend.gd`, `src/AeroToolManager.gd`, `.testbed/tests/test_AeroToolManager.gd`, `.testbed/tests/helpers/FakeVideoStreamPlayer.gd`), `git show --name-only --format='' 59613e0 | grep -E '(^|/)(addons)(/|$)|^\.testbed/addons/' || true` (no `/addons/` paths touched), `cd .testbed && godotenv addons install && godot --headless --path . --import && godot --headless --path . --script addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (import succeeded; `10/10` tests passed; exit `0`; reproduced one orphan plus `ObjectDB instances leaked at exit` warning). Source/diff review confirmed the planned vendor-local shell is present and bounded correctly: repo-root `src/` owns backend/wrapper classes, local-file source normalization, media/capability helpers, surface attach/detach behavior, and backend-local state/error translation; the public vendor manager exposes `prepare_source`, `attach_surface`, `detach_surface`, `get_state`, `get_media_info`, and error translation, but does not surface the tool-owned singleton lifecycle contract as this repo’s public ownership. `.testbed/` remained the proving surface, sharable code stayed at repo root, and no addon mirror was treated as owned source. Audit conclusion: the orphan/leak warning is real but non-blocking for this slice because it is confined to test cleanup timing around the fake player detach path and does not invalidate the claimed behavior or ownership boundary; it is worth a follow-up cleanup bead, not a failure of this scoped shell slice.

---

## Dependency Shape

- `aerobeat-vendor-godot-video-3b2` → first executable implementation bead.
- `aerobeat-vendor-godot-video-tdy` depends on `aerobeat-vendor-godot-video-3b2`.
- `aerobeat-vendor-godot-video-aek` depends on `aerobeat-vendor-godot-video-tdy`.

This creates a strict repo-local `coder → QA → auditor` chain.

---

## Coordination Notes with `aerobeat-tool-video-player`

1. **Tool repo owns lifecycle semantics.** `aerobeat-tool-video-player` remains the source of truth for generic `load/play/pause/stop/seek`, normalized state, normalized errors, and output-surface contract shape.
2. **Vendor repo owns backend reality.** This repo should own how Godot-native playback actually works: supported/unverified formats, backend quirks, node/surface expectations, metadata extraction limits, and failure modes.
3. **Keep adapter boundaries explicit.** If names or payloads are needed here before the tool contract fully lands, mirror the tool plan intentionally and document any temporary mismatch rather than inventing a competing contract.
4. **Prefer dependency wiring through normal repo mechanisms.** When the time comes to prove end-to-end integration locally, wire `aerobeat-tool-video-player` into `.testbed/addons.jsonc` intentionally instead of patching copied addons.
5. **Replay remains a downstream consumer concern.** Per the camera-tracking boundary, replay can consume `tool-video-player`, but this vendor repo should not absorb tracking/replay orchestration just because the backend is video.

---

## Final Results

**Status:** ✅ Complete

**What We Built:**
- Initialized repo-local planning/Beads for the vendor wrapper slice.
- Implemented the first Godot-native vendor wrapper shell behind the future tool contract.
- Added deterministic `.testbed` coverage for source normalization, vendor metadata surfacing, surface binding, and backend-local state/error translation.
- Completed independent QA and audit verification, including a fresh `.testbed` import/test rerun during audit.

**Reference Check:**
- `REF-01` remained the repo/`.testbed` proving convention.
- `REF-03` and `REF-04` stayed the contract boundary that generic playback lifecycle semantics belong to the tool repo.
- `REF-05` and `REF-06` remained the ownership boundary preventing replay/tool lifecycle scope creep into this vendor repo.
- `REF-07` was superseded by the expanded repo-local vendor-wrapper tests and independently revalidated by audit.

**Commits:**
- `59613e0` - Implement Godot video vendor wrapper shell

**Lessons Learned:**
- The vendor repo had `.beads/` scaffolding but no initialized database yet, so `bd init --quiet` was required before creating repo-local work items.
- The safest first slice is backend-wrapper stabilization and vendor-quirk surfacing, not generic playback service semantics.
- The current orphan/ObjectDB leak warning appears confined to test cleanup timing around the fake player detach path; it deserves follow-up cleanup, but it did not block truthful completion of this scoped vendor-wrapper shell.

---

*Updated on 2026-05-21*
