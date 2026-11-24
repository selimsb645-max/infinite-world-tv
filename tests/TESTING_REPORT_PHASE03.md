# Testing Report — Phase 03 (Infinite Procedural Level Generator)

**Date:** 2026-11-24
**Engine:** Godot **4.3.stable.official** (same local binary as Phase 02,
`~/workspace/tools/godot/Godot_v4.3-stable_linux.x86_64`). All numbers
below are from actual runs — full output in `tests/generation_output.txt`
and `tests/smoke_output.txt`.

## Generation test suite

`game/tests/generation_test.gd` (scene `game/tests/GenerationTest.tscn`):

```bash
godot --headless --path game res://tests/GenerationTest.tscn
```

**Result: 45 / 45 checks PASS, `GEN_DONE failures=0`, exit code 0.**

### The 1,000-level run (actual GEN_STATS line)

```
GEN_STATS levels=1000 distinct_fingerprints=1000 worlds=8 mixed=1000
char_segments=4228 vehicle_segments=4213 fallbacks=0 attempts=1003
validation_rejections=3 dup_rejected=0 sim_rejected=0 elapsed_ms=3729
```

- 1,000 levels generated and **independently re-validated: all valid**.
- **1,000 distinct structural fingerprints — zero exact duplicates.**
- All **8 worlds** used; **1,000/1,000 levels contain both** character
  and vehicle sections (4,228 character + 4,213 vehicle segments).
- 1,003 attempts for 1,000 levels: 3 candidates were rejected by the
  validator and regenerated; 0 fallbacks were needed.
- Wall time 3.7 s for 1,000 levels (~3.7 ms/level) on this VM.

### Coverage by spec area

| Spec test area | Result |
|---|---|
| 8 worlds registered, themes exist, distinct skies | ✅ PASS (8 distinct sky colours) |
| Seed reproducibility (same seed → same fingerprint + layout) | ✅ PASS |
| Distinct seeds → distinct levels | ✅ PASS (20/20) |
| Duplicate detection (exact + reseeded/recolored copy) | ✅ PASS (both rejected) |
| Structural similarity (near-copy, 1 token changed) | ✅ PASS (sim 0.920 ≥ 0.80, rejected) |
| Regeneration after rejection | ✅ PASS (attempts=2, different fingerprint) |
| Difficulty progression + cap + performance easing | ✅ PASS (0.00 → 0.47 → 1.00, capped) |
| Invalid level rejection: spawn obstacle / tight spacing / long gap / high platform / blocked vehicle corridor / collectible inside obstacle | ✅ PASS (6 crafted cases, each rejected with the expected error) |
| Fallback template when retries exhausted (threshold forced to 0) | ✅ PASS (fallback served, counted, and itself validates) |
| Generation recovery after fallback | ✅ PASS |
| Memory cleanup: history bounded at capacity, eviction drops old fingerprints | ✅ PASS (300 adds → size 50 at cap 50) |
| Generation queue budget | ✅ PASS (process 2 of 5, then drain) |
| Chunk retention: transition manager holds ≤2 levels over 31 advances | ✅ PASS |
| Object pooling in the real scene | ✅ PASS (11 obstacle nodes reused on the second generated build) |
| Integration: endless mode in the real Main scene, generated level builds (107 nodes), theme applies, finish advances to pregenerated level 2, handcrafted mode still works afterwards | ✅ PASS |

## Phase 02 regression

```bash
godot --headless --path game res://tests/SmokeTest.tscn
```

**Result: 26 / 26 checks PASS, `SMOKE_DONE failures=0`, exit code 0** —
identical check names to the Phase 02 run. Project import
(`godot --headless --path game --import`) also completes with no
script errors.

## Honest limitations

- Headless only (dummy renderer), same as Phase 02: no visual/FPS
  verification on a real display.
- The 1,000-level run validates level *data* against the validator;
  only a sample of generated levels was actually built and run in the
  scene (the integration checks), not all 1,000.
- Anti-repetition similarity is enforced against the recent 60-level
  window by design; exact duplicates are checked against the full
  retained 250-entry history. The run still produced 1,000/1,000
  distinct fingerprints.
