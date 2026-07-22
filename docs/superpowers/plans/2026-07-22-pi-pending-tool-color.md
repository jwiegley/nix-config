# Pi Pending Tool Brown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set Pi's pending-tool background to earthy brown `#080604`, approximately half the linear-sRGB luminance of the preceding `#100c08`, while preserving the completed purple and every other theme field.

**Architecture:** Change one JSON value in the live custom theme. A temporary verifier demonstrates the prior value, proves that the new-to-old luminance ratio lies between 0.47 and 0.53, and confirms that no other semantic field changed.

**Tech Stack:** Pi 0.81.1 theme JSON, Python standard library.

## Global Constraints

- Modify only `/Users/johnw/.pi/agent/themes/dark-tool-backgrounds.json`.
- Set `vars.toolPendingBg` to `#080604`.
- Keep `vars.toolSuccessBg` at `#180526`.
- Preserve every other JSON field byte-for-semantics.
- Do not restart Pi; the active theme hot-reloads.
- Keep no temporary verifier or baseline after successful verification.

---

### Task 1: Halve the pending brown's luminance

**Files:**
- Modify: `/Users/johnw/.pi/agent/themes/dark-tool-backgrounds.json`
- Temporary test: `/tmp/verify-pi-pending-half.py`
- Temporary baseline: `/tmp/dark-tool-backgrounds.before-half.json`

**Interfaces:**
- Consumes: the active custom Pi theme with pending background `#100c08`.
- Produces: pending background `#080604`, completed background `#180526`, and a measured luminance ratio of `0.488024`, with no other semantic change.

- [x] Copy the current theme to `/tmp/dark-tool-backgrounds.before-half.json`.
- [x] Write a Python verifier that expects `#080604`, expects `#180526`, measures linear-sRGB luminance, and asserts a new-to-old ratio between 0.47 and 0.53.
- [x] Run the verifier and confirm it fails because the live pending value is `#100c08`.
- [x] Replace only `"toolPendingBg": "#100c08"` with `"toolPendingBg": "#080604"`.
- [x] Run the verifier and confirm `luminance_ratio=0.488024`.
- [x] Parse the live JSON and verify that only `toolPendingBg` changed.
- [x] Remove both temporary files after final semantic verification.
