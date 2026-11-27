# VIctory on a small AMD card: what actually moves the frame

Measured notes from running the leaked Xbox Series build of GTA VI through
[VIctory](https://github.com/Marvisak/VIctory)-based trees on **one** machine:
Ryzen 7 5700X, **Radeon RX 7600 8 GB (RDNA3)**, 24 GB DDR4, Windows 11 26300.
The point of this repository is the numbers, not another fork: which switches
help on 8 GB of video memory and 24 GB of RAM, which hurt, and where the frame
actually goes. Nothing here contains game files, assets or keys.

Everything below was measured with the same method, in the world (not menus),
from the `fps, N ms/frame (…)` lines the diagnostics build prints every 5 s.

## The frame, as this machine spends it

```
336 ms/frame  ≈  100 ms preparing  +  236 ms on the card
                 (copies 70 ms moving ~210 MB into shadow copies,
                  textures 3-7 ms)
                  copy-back 75 ms on its own thread, in parallel
```

The card is **busy only ~58 % of the time it is waited for**, so ~130 ms of what
the frame line calls "on the GPU" is real work and the rest is gaps while the CPU
prepares. 5,000 draws and 2,548 indirect commands a frame.

## What moved it, and what did not

| change | frame | verdict |
|---|---|---|
| baseline (ztrx tree + 5 patches) | 340–349 ms | — |
| `VICTORY_LATE_WAIT=3` alone | **331–343, median ~336** | the only gain: ~2.5 %, two 300 s runs, no crash |
| `VICTORY_ASYNC_SUBMIT=1` (leader fork b8b30d1, ported) | 348–362 | 8–12 ms **worse**: the work moves to another thread, the title still waits at its present |
| `LATE_WAIT=3` + `RELAY=2` + `WIDE_REFRESH` + `WIDE_MERGE` | 801–4,636 | unusable; memory explodes (20.6 GB private, ~500 MB free) and DXGI's local budget collapses 7,010 → 4,590 MB |
| `VICTORY_CARD_BUFFERS_MIN_KB=64` (fxceless c36971b, ported here) | 780–816 | 8 GB card overflows: 7,779 MB used of a 6,670 MB budget, GPU 650–680 ms. On a 24 GB card the same switch is reported as a win; on 8 GB it is the opposite |
| `CARD_BUFFERS_MIN_MB=8 CARD_BUFFERS_MB=1024` | 344–355 | no change |
| `CARD_BUFFERS_MIN_MB=4 CARD_BUFFERS_MB=2560` | crash | `0xc0000005` (write to 0x0) after ~5 min |
| `VICTORY_WIDE_REFRESH=1` | 326–344 | copies unchanged (68–75 ms) |
| `VICTORY_TEXTURE_BUDGET_MB=2048` | 325–336 | does not touch the 5.1 GB of host textures; they are all held by a list or a slot |
| `VICTORY_WINDOW_KB=1024 / 256` | 342–350 / 363–376 | trades memory for copies the wrong way: 210 MB/70 ms becomes 281–425 MB at 76–92 ms |
| `VICTORY_BARRIER_TEST=indirect` | 366–378 | the two UAV barriers per indirect command are **not** the GPU wall (226–233 ms either way) |
| `VICTORY_BARRIER_TEST=groups` | 346–726, image corrupt | the title's own 716 barrier groups cost 30–50 ms and are load-bearing |

## The loop-limit result, corrected

`VICTORY_SHADER_LOOP_LIMIT=64` appears to halve the card term (228-236 ms to
130-153 ms). It does not, and the same log says why: that run executed **291-444
draws a frame instead of ~5,000**. The shaders break, the layer drops the world,
and a mostly empty frame is fast. The first write-up of this repository called it
a finding; the per-stage runs below are what corrected it.

`VICTORY_LOOP_LIMIT_PIXEL`, `_VERTEX` and `_COMPUTE` (the switch this repository
adds, one stage at a time) separate the stages:

| stage lowered to 64 | frame | card term | draws |
|---|---|---|---|
| pixel (128 → 64) | 341-355 ms | 225-233 ms | ~5,090 |
| compute (4,096 → 64) | 746-783 ms | 635-650 ms | ~5,050 |
| all stages (previous section) | 208-259 ms | 130-153 ms | **291-444** |

So: the pixel stage's loop bound is irrelevant to the frame; the compute stage's
bound is load-bearing (cutting it makes the frame three times slower, because
every draw then paints garbage); and the "all stages" number is an artifact of
the picture collapsing. The card term is 5,000 draws and 2,548 indirect commands
doing real work, not lanes spinning on a safety net.

## The one setting worth trying on a small card: `--console series-s`

The Series S profile (1080p output, smaller textures) is the only configuration
that changed the frame by a lot:

| profile | frame | card term | copies | copy-back |
|---|---|---|---|---|
| series-x, `LATE_WAIT=3` | 331-343 ms | 228-236 ms | 68-74 ms / 210 MB | 74-78 ms |
| series-s, `LATE_WAIT=3` (run 1) | **219-232 ms** | 131-140 ms | 55-57 ms / 129 MB | 44-46 ms |
| series-s, `LATE_WAIT=3` (run 2, other spot in the world, streaming) | 281-518 ms | 97-158 ms | 62-86 ms / 158-206 MB | 36-66 ms |

Run 1 is 4.3-4.6 fps against 3.0-3.0 for series-x, with the card's term down by a
third and the copied bytes down by 40 %; run 2 was taken in a heavier, still
streaming stretch and does not confirm the size of the win. Treat series-s as the
first thing to try on 8 GB and the number as 20-35 % better, not as measured
twice.

## A cost model the runs support

Two points with very different draw counts:

| draws a frame | card term |
|---|---|
| ~5,000 (the normal world) | 228-236 ms |
| 291-444 (world dropped by broken shaders) | 130-153 ms |

Sixteen times fewer draws bought 1.7 times less card time, so the term has a
large part that does not scale with draws (~130 ms) and a part that does
(~100 ms over ~4,700 draws, about **21 us a draw**). The fixed part is not
pixel work either: 720p and native render to the same card term. What is left
in it is the work that happens whatever is drawn — the GPU-side copies of the
210 MB of shadow memory and the 80 MB read-back a frame, the hash and compare
passes, and the layer's own passes.

That is the shape of the problem on an 8 GB card: ~130 ms that only fewer
copied bytes can move, plus ~21 us a draw that only fewer or cheaper draws can.
Neither is reachable from the switches this repository measured.

## What the leaders on the board run on

The known builds on PortWatch that report 15–45 ms frames are measured on
**64 GB of RAM and 12–24 GB of video memory**. Belobug's AMD tree, built and run
here unchanged: **1,035–4,974 ms a frame, 25 GB private, 690 MB free**, then an
AMD driver timeout. On 24 GB / 8 GB, nothing on that board runs as it does there.
If you are on a small card, the useful work is shader-side, not another tree.

## Reproducing

```
scripts/play.ps1 -Exe <victory.exe> -Game <game_scarlett_master.exe> -Log run.log -Extra "VICTORY_LATE_WAIT=3"
scripts/measure.ps1 -Log run.log           # medians of the in-world ms/frame lines
```

`scripts/play.ps1` pins the title's audio, presses through the menus with
`VICTORY_KEYS` (diagnostics builds only) and stops after a fixed time.
`scripts/measure.ps1` prints the median frame, the split, and the median time
over the last third of the run, which is the part that matters.

`patches/0001-card-buffers-min-kb.patch` is fxceless's small-buffer card
placement ported onto the ztrx tree, kept here because its result on 8 GB is a
useful negative.

## Licence

Notes and scripts: CC0. The patch is a derivative of GPL-3.0-or-later code
(VIctory, fxceless/victory-fork) and stays under that licence.
