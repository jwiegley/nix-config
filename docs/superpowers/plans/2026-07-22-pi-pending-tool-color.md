# Pi Pending Tool Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set Pi's pending-tool background to the user-selected brown `#291B04` while preserving the completed purple and every other theme field.

**Architecture:** Change one JSON value in the live custom theme. A temporary verifier demonstrates the prior value and confirms the exact replacement without any other semantic change.

**Tech Stack:** Pi 0.81.1 theme JSON, Python standard library.

## Global Constraints

- Modify only `/Users/johnw/.pi/agent/themes/dark-tool-backgrounds.json`.
- Set `vars.toolPendingBg` to `#291B04`.
- Keep `vars.toolSuccessBg` at `#180526`.
- Preserve every other JSON field byte-for-semantics.
- Keep no temporary verifier or baseline after successful verification.

---

### Task 1: Apply the selected pending color

**Files:**
- Modify: `/Users/johnw/.pi/agent/themes/dark-tool-backgrounds.json`
- Temporary test: `/tmp/verify-pi-pending-291b04.py`
- Temporary baseline: `/tmp/dark-tool-backgrounds.before-291b04.json`

**Interfaces:**
- Consumes: the active custom Pi theme with pending background `#321205`.
- Produces: pending background `#291B04`, completed background `#180526`, with no other semantic change.

- [x] Copy the current theme to `/tmp/dark-tool-backgrounds.before-291b04.json`.
- [x] Write a Python verifier that expects `#291B04`, expects `#180526`, and compares all remaining fields.
- [x] Run the verifier and confirm it fails because the live pending value is `#321205`.
- [x] Replace only `"toolPendingBg": "#321205"` with `"toolPendingBg": "#291B04"`.
- [x] Run the verifier and confirm `pending_color_291B04=passed`.
- [x] Parse the live JSON and verify that only `toolPendingBg` changed.
- [x] Remove both temporary files after final semantic verification.
