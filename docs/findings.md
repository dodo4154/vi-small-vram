# Measurements, 2026-11-26 (raw record)

The working log behind `README.md`: every run of the day, in the order they were
taken, with what each one eliminated. Trees are named as on the machine they ran
on (`verify` the stable base, `port1` a copy for experiments); `<tree>\` stands
for the local checkout.

# GTA VI / VIctory — 2026-11-26 08:30 UTC: what the leader fork's levers actually do here

Machine: the test machine — Ryzen 7 5700X, RX 7600 8 GB (RDNA3), 24 GB, Win 11 26300.
Trees: `<tree>\verify` (best build, untouched) and `<tree>\port1`
(a copy of `verify` with avatarmanz/VIctory-7900XTX `b8b30d1` — *"Submissions are prepared and
sent by a thread of ours"*, `VICTORY_ASYNC_SUBMIT` — applied and built to `port1-target\diag`).

Method, every run: `<tree>\play-ztrx.ps1 -Exe <binary> -LogLevel info -Seconds 300
-Log <file>`, read the `fps, N ms/frame (...)` lines from `<file>.err`, 3–4 min of keys to reach
the world. All runs below are in-world, not menus.

## Measured (medians of the in-world lines)

| config | frame ms | preparing | copies | GPU | copy-back |
|---|---|---|---|---|---|
| port1, async off (baseline) | 340–349 | 100–106 | 71–76 | 235–240 | 78–80 |
| port1, `VICTORY_ASYNC_SUBMIT=1` | 348–362 | 110–116 | 70–75 | 226–229 | 73–75 |
| port1, `LATE_WAIT=3 RELAY=2 WIDE_REFRESH=1 WIDE_MERGE=1` | **801–4,636** | 120–166 | 83–125 | 669–4,486 | 76–296 |
| port1, `VICTORY_BARRIER_TEST=indirect` | 366–378 | 130–139 | 68–73 | 226–233 | 92–96 |
| port1, `VICTORY_BARRIER_TEST=groups` (timing only, image corrupts) | 346–726 | 90–119 | 57–76 | 188–230 | 68–78 |
| port1, `CARD_BUFFERS_MIN_MB=4 CARD_BUFFERS_MB=2560` | crash `0xc0000005` at `victory-image+0x23cf683` after ~5 min | | | | |
| port1, `CARD_BUFFERS_MIN_MB=8 CARD_BUFFERS_MB=1024` | 344–355 | 114–118 | 69–71 | 223–233 | 79–86 |
| port1, `VICTORY_WIDE_REFRESH=1` | 326–344 | 97–104 | 68–75 | 222–233 | 74–77 |
| port1, `TEXTURE_BUDGET_MB=2048` | 325–336 | 95–103 | 67–70 | 222–228 | 73–75 |
| port1, `WINDOW_KB=256` | 380–607 (short run, still streaming) | 111–222 | 63–115 | 132–206 | 47–117 |
| port1, `WINDOW_KB=256` (full run) | 363–376 | 125–134 | 86–92 (423–428 MB) | 232–237 | 74–78 |
| port1, `WINDOW_KB=256` + `LATE_WAIT=3` (pipeline) | 352–361 | 123–127 | 81–85 (410–425 MB) | 223–231 | 72–74 |
| port1, `LATE_WAIT=3` alone (default windows) | 330–342 | 97–102 | 66–73 (206–213 MB) | 228–234 | 74–77 |
| port1, `LATE_WAIT=3` + `TEXTURE_CAP_MB=3400` (new `let_go_under_cap`) | 330–342 | 97–102 | 67–73 | 228–234 | 74–77 |
| port1, `LATE_WAIT=3` confirmed (second run, 300 s, no crash) | 331–343 (median ~336) | 96–102 | 68–74 (208–215 MB) | 228–236 | 74–78 |
| port1, `LATE_WAIT=3` + `WINDOW_KB=1024` | 342–350 | 107–112 | 74–78 (281–294 MB) | 227–234 | 73–76 |

So the day's best is `VICTORY_LATE_WAIT=3` on its own: median ~336 ms against the baseline's ~344 ms,
i.e. about 2.5% and 3.0 → 3.05 fps — real and stable (two 300 s runs, no crash), but nowhere near the
200 ms that 5 fps needs. The remaining 100 ms is GPU work that neither barriers, resolution, placement
nor the pipeline touches, and the 100 ms of CPU prepare that the pipeline only partly hides because the
title still waits for its present to be shown.

**Correction to an earlier verdict.** `LATE_WAIT=3` on its own is not the trap: it runs at 330–342 ms,
the best of the day. What exploded to 801–4,636 ms was `LATE_WAIT=3` **together with `RELAY=2` and the
`WIDE_*` switches** — that combination fills memory (private 20.6 GB, free RAM ~500 MB, DXGI's local
budget collapsing to 4,590 MB). Keep `RELAY=1` (the default) with late present.

**The texture cap did not bite.** `VICTORY_TEXTURE_CAP_MB=3400` (new `resource::let_go_under_cap`, in
port1 only) left host textures at 5,145 MB: every one of them is still referenced by a list or a
descriptor slot, so nothing was a candidate. Capping this memory for real means evicting textures a
slot still shows (or shrinking the slots), which is a design change, not a sweep.
| verify (handoff baseline, same method) | 316–328 | 95–105 | 65–75 | 217–225 | 70–77 |

Verdicts:
- **`VICTORY_ASYNC_SUBMIT` does not help here** — it costs 8–12 ms. Its own line says why: "28.0
  submissions prepared by a thread of ours, per frame in 1.0 presents … that thread worked 348.2
  ms; threads of the title waited 227.7 ms at presents". The preparing does not shrink or move off
  the critical path; it only moves to another thread, and the title still waits at present.
- **`LATE_WAIT=3` + `RELAY=2` + `WIDE_*` is catastrophic on this machine** (up to 4.6 s/frame).
  Do not use it.
- **The two global UAV barriers per indirect command are not the GPU wall.** With
  `VICTORY_BARRIER_TEST=indirect` (both waits left out) the GPU term is 226–233 ms, i.e. unchanged
  from 235–240.
- **The title's own 716 barrier groups cost about 30–50 ms of the GPU term**, and they are
  load-bearing: `VICTORY_BARRIER_TEST=groups` drops the GPU term to 188–230 ms but the image
  corrupts immediately (the code says as much: without the waits a shader reads what another has
  not finished writing). So the GPU ceiling is ~190 ms of real work plus ~40 ms of required global
  barriers, not 236 ms of barrier overhead.
- **`CARD_BUFFERS_MIN_MB=4 CARD_BUFFERS_MB=2560` (the "put the hot shadow buffers in VRAM" test)
  crashes the title** with `0xc0000005` (write to 0x0) at `victory-image+0x23cf683` after ~5 minutes,
  after the guard-fault rate climbed from ~1 to ~190 per frame. The default 16 MiB / 512 MB is stable.

## Where the 236 ms of GPU time is spent, as far as the counters go
- 5,000 draws/frame, 2,548 indirect commands/frame, 272,375 indirect mesh groups/frame.
- 716 "waits for every earlier shader write" per frame from the title's own barrier groups.
- 720p internal resolution does not change the GPU term (already established): it is not pixel-bound.
- **VRAM is over budget every run**: "the card: 7,228 MB in use of a budget of 7,010 MB, 6,048 MB
  of the PC's memory shared with it in use". ~6 GB of the card's visible data lives in system memory
  (the CPU-writable shadow copies by design: 5,647 shared buffers, 6,797 MB made), so per-frame
  vertex/argument traffic crosses PCIe 4.0 x8.
- The 70 ms of copies move ~210 MB → **3.0 GB/s**, far below what a Ryzen 5700X can do: the copy is
  not bandwidth-bound, it is thousands of scattered ranges into upload/shared buffers.
- The copy path is `ReadProcessMemory` through the kernel by design (`copy_mapped`, "the source is
  read through the kernel, which reports an unmapped page instead of faulting"); a plain SEH `memcpy`
  was already tried in the bench fork and measured **worse** (127–205 ms against 104–147 ms of copies,
  because one missing page fails the whole range). So the copies are near the floor of this design,
  and `VICTORY_WIDE_REFRESH=1` does not change them (68–75 ms, measured today).

## What the GPU term is NOT sensitive to (measured today)
- Resolution (720p: unchanged, from the previous session).
- The clamp's two UAV barriers per indirect command (unchanged when removed).
- How much of the shadow memory sits in VRAM rather than system RAM: raising the card-buffer
  pool to 1,024 MB moved nothing (223–233 ms, same as 235–240), and the local budget stayed equally
  exceeded (7,152 / 7,000 MB) — so "move buffers to VRAM" is not a free win either, at least not by
  size alone.
- The only GPU term that moved was the title's own 716 barrier groups (~30–50 ms), and those are
  required: without them the image corrupts and the GPU term climbs to 700–4,700 ms as the run goes on.

That leaves per-command cost (5,000 draws, 2,548 indirect executes at ~90 µs each) and shader
translation quality as the untested suspects. The cleanest next measurement is a frame capture in
AMD Radeon GPU Profiler (not installed on this machine) — it shows wave stalls and PCIe read
bandwidth per frame without a code change.

## Next steps, in the order the evidence supports
1. **Fence-exact frame pipelining** (the only lever that touches the 100 ms of preparing that is
   serial with the GPU): shadow ring of 2 generations freed on GPU completion, title fences signalled
   only after the GPU and the merged copy-back, present blitted to a swapchain image with a presenter
   thread, and a canary that hashes dirty pages at copy-in and again at completion to catch an
   overwrite of in-flight data. Expected 340 → ~245 ms (4.1–4.3 fps) if it holds.
2. **Tiled parallel copy** of the 210 MB/frame (the texture path already does this), 70 ms → ~20 ms.
3. **A per-draw scaling test** (skip one big world pipeline with `VICTORY_SKIP_PIPELINES` and see how
   the GPU term scales) or an RGP capture, to decide between per-command overhead and shader cost.
4. Not worth it yet: `VICTORY_THIN` (list-call translation) — the CPU term is mostly memcpy, so
   its ceiling is ~20 ms; `VICTORY_INPLACE` — puts GPU reads on PCIe.

Nothing was changed in `<tree>\verify`; `port1` exists only for these measurements.

## Why the pipeline can only give ~2% here, and what that implies
The card's own clock says it: with late present on, "the card idle behind us" is still **89–91 ms a
frame**, exactly the baseline's 89–91 ms. The toolchain's late present releases the *present*, but the
title's own frame ends by waiting on a fence of its own, which our fence simulation satisfies only when
the card has run the frame. So the CPU prepare cannot hide behind the GPU from the title's side; the
frame stays `prepare + GPU` however the presents are arranged.

That closes the frame-pipelining route for a in-tree change: 5 fps (≤200 ms) needs the GPU term itself
below ~200 ms, since the CPU's 100 ms cannot be hidden and the GPU term is 228–236 ms of which ~130 ms
is real work (the card is ~58% busy). The levers that remain are the ones that make the card's work
smaller — shader translation quality and command count — not scheduling.
## How to run the best of the day (no rebuild needed)
```
powershell -ExecutionPolicy Bypass -NoProfile -File <tree>\play-ztrx.ps1 `
  -Exe <tree>\port1-target\diag\victory.exe -LogLevel info -Seconds 300 `
  -Log <tree>\run.log -Extra "VICTORY_LATE_WAIT=3"
```
330–342 ms in the world (the day's best; plain baseline on the same binary is 340–349). `RELAY` must
stay at its default 1: with `RELAY=2` plus `WIDE_*` the same pipeline collapses to 801–4,636 ms.

`port1` differs from `verify` in two things, both in `crates/victory-gpu`:
1. the leader fork's `b8b30d1` (`queue/behind.rs` + hooks in `queue.rs`, `fence.rs`, `host.rs`) for
   `VICTORY_ASYNC_SUBMIT` — measured 8–12 ms worse, off unless asked for;
2. `resource::let_go_under_cap` and its one call in `host.rs` (the `VICTORY_TEXTURE_CAP_MB` sweep) —
   measured no effect, because every host texture is still referenced by a list or a slot.

## What 5 fps (<=200 ms) would take, given today's numbers
- The card is busy only ~58% of the 236 ms it is waited for, so the real GPU work is ~130 ms and the
  rest is gaps while the CPU prepares. The pipeline releases the *present*, but the title's own frame
  still ends by waiting on its own fence, so the prepare cannot be hidden from the title's side
  (measured: "the card idle behind us" is 89-91 ms with and without late present).
- Therefore 5 fps cannot come from scheduling: it needs the GPU term itself under ~200 ms. Everything
  measured today that failed to move it: resolution, the clamp's barriers, buffer placement in VRAM,
  the texture budget, the window grid, the card-buffer pool, late present.
- What is left, in order of expected value:
  1. A per-draw scaling test (`VICTORY_SKIP_PIPELINES` with one big world pipeline) or an RGP capture,
     to split the 228-236 ms between per-command overhead (5,000 draws / 2,548 indirect executes at
     ~90 us each) and shader cost. RGP is not installed on this machine.
  2. Shader translation quality, if the scaling test says the work per draw is the cost.
  3. Command coalescing, if it says the number of commands is.
  4. Only then memory work: the 5.1 GB of host textures need a cap nothing currently enforces (the
     sweep finds no candidate: every copy is held by a list or a slot), and `WINDOW_KB=1024/256` trade
     copies for memory the wrong way round (210 MB / 70 ms becomes 281-425 MB at 76-92 ms).

## The one real gain of the day
`VICTORY_LATE_WAIT=3` alone (no RELAY, no WIDE_*): median ~336 ms against the baseline's ~344, two
300 s runs, no crash. About 2.5%, and it is free — an environment variable, no rebuild.

## The finding that matters (last run of the day)
`VICTORY_SHADER_LOOP_LIMIT` is the only switch that moved the GPU term, and it moved it hard:

| config | frame | GPU | copies |
|---|---|---|---|
| `LATE_WAIT=3`, default loop limit (2^20) | 331–343 | 228–236 | 68–74 ms |
| `LATE_WAIT=3` + `SHADER_LOOP_LIMIT=64` | **208–259 (median ~240)** | **130–153** | 56–61 ms |
| `LATE_WAIT=3` + `SHADER_LOOP_LIMIT=1024` | 143–251, then 1,436 / 6,779 (unstable) | 72–159 | 48–76 ms |

With the loop limit the copies fall too (120–141 MB against 210), because the shaders write less — so
the gain compounds. The image is wrong at 64 (loops are cut short), and 1024 is not stable, but the
measurement is unambiguous: **the 236 ms GPU term is translated-shader loop work, not draws, not
barriers, not memory placement.** Skipping one world mesh pipeline, or four at once, left the GPU term
at 220–228 ms; the title's own barrier groups are 30–50 ms of it; everything else measured today was
flat.

What that means for 5 fps: the work is in `victory-shader`'s loop emission (how a console loop becomes a
bounded PC loop, the `LOOP_LIMIT` of 2^20 per lane and entry, and what that costs per wave), not in
scheduling. That is the next investigation, and it is a code path, not a knob: measure a loop-heavy
pipeline with `VICTORY_SKIP_PIPELINES`, then read `crates/victory-shader/src/emit/lower.rs` for how
loops are emitted and whether the bound forces per-iteration work that RDNA's branches would not.

Everything below predates that finding and stands as the record of what was eliminated.


## GitHub survey, 2026-11-27 00:40 UTC (PortWatch + the four trees)
PortWatch data is at 2026-11-26T22:07Z. Board and news:

- **Kelvaroq** (stellarr-studio/kelvaroq) is #1: public, Rust on VIctory + victory-fork, tested on an
  RTX 5080, ~10 fps, "unified memory": 100% of the game's graphics memory shared with the GPU from
  allocation, 97.4% of GPU views fit in shared memory, 300x less bookkeeping per heavy frame
  (18 s -> 60 ms on that card), 0 GB left behind on exit. That is the in-place architecture; on an
  8 GB card with PCIe x8 the GPU would read that shared memory over the bus, which is why our tree
  refuses it. Its own blockers: CPU submission and synchronisation, missing pipelines, 7% dropped draws.
- **Belobug** is ~22 fps on a 7900 XTX with about 30 GB private and 12 GB VRAM (its README: 45 ms).
  Measured here today: 1,035-4,974 ms a frame, 25 GB private, 690 MB free, AMD driver timeout. Not
  usable on 24 GB / 8 GB. New PRs since: #324 (shader size query no longer reused; AMD's compiler
  crashed on 29 compute pipelines on RDNA4), #295 (keyboard/mouse), #354 (port 2 sync parts disjoint).
- **avatarmanz**: `VICTORY_PORT_RT` (a lane's wait for a constant buffer behind a copy at its place),
  `VICTORY_PORT_CONSTANTS_ORDER` (tree and lamp-lit room flicker), ambient fix for dark rooms.
- **fxceless** (2026-11-27 00:06) is shader work, on by default: wide raw loads guarded at a view's
  end, `ds_bpermute` within its half, pixel quadrant reads, helper-lane first-lane reads, NaN tests on
  the bits, `VICTORY_SHADER_FAST_BITS`, ray node tests answer no hit. This is the closest thing on the
  board to the wall measured yesterday (the GPU term is translated-shader work).
- **DexNom**: README only; 3.5-4 fps indoors on a 7900 XTX without ray tracing.
- **ZETTROX/ztrx** (our base) now returns HTTP 404; the fork we run is the copy on this machine.
- PortWatch news: GTA VI multiplayer at 25-30 fps on a private fork of CGBJ's build (TeK's group);
  several builds clear Lucia's prologue and reach Jason's first mission. New candidates it spotted:
  DesignWithTommy/i95, zsy-miao/ScarlettVI, JozefDeTremmerie/CCS03, deepdev237/victory-mac,
  ExCorvus/gta-pipeline-reconstruction.

**What that means for this machine.** Nothing on the board runs in 24 GB RAM / 8 GB VRAM except the
trees we already have; the leaders got their numbers on 64 GB / 24 GB. The portable work that matches
our measured wall is fxceless's shader commit (loops and wave reads), not another fork's whole tree.
