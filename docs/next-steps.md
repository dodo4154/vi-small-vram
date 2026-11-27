# Where the loop cost comes from, and how to chase it

The measurement in `README.md` (card term 228–236 ms → 130–153 ms with
`VICTORY_SHADER_LOOP_LIMIT=64`) has an explanation in the translator's own
source, in `crates/victory-shader/src/emit/lower.rs`:

> Per stage unless the switch names one: a loop that never meets its exit (a
> count read from a buffer the host has not got yet, say) runs to the limit in
> every lane. … (They were 1,024, 4,096 and 65,536: the opening cutscene then
> lost the card 14–25 frames in … Raise them again once shaders stop reading
> data that is not there yet.)

So the bound is a *safety net*, and the frame is paying for lanes that hit it:
a loop that should end after a few iterations spins to 128 (pixel), 256 (mesh)
or 4,096 (compute) because something it reads — a count, a descriptor, a
constant — is still zeros at the moment the shader runs. Halving the bound
halves the wasted work, which is exactly what the numbers show.

That reframes the work: not "make the bound cheaper", but **find the shaders
that reach the bound and fix what they read**. Three ways to find them, cheapest
first.

## 1. Image diff at two bounds (no code, ~20 minutes)

A loop cut short changes what is drawn. Capture the same frame with the default
bound and with `VICTORY_SHADER_LOOP_LIMIT=64`, and the differences are the
draws whose loops were running past 64 iterations.

```
scripts/play.ps1 -Exe victory.exe -Game game_scarlett_master.exe -Seconds 200 `
    -Log a.log -Extra "VICTORY_LATE_WAIT=3;VICTORY_CAPTURE=<dir>;VICTORY_CAPTURE_FRAMES=...;VICTORY_GPU_TIMING=1"
```

The caveat: `VICTORY_GPU_TIMING` turns late present off and changes the frame,
so capture both images without it, from the same place in the world (the camera
matters more than the settings).

## 2. Skip-list bisection by command time (needs a working per-pipeline timing)

`VICTORY_GPU_TIMING=1` sums commands by pipeline (`copystat::command_took`,
"the card's time by command (timing run)"). With the default bound and with 64,
the pipelines whose line drops the most are the ones paying the bound. On this
machine the diagnostics build never printed those lines (the per-list timestamp
path did not run on this driver), so this route needs the timestamps to work
first.

## 3. A counter in the abort block (the direct way)

`lower.rs::abort_block()` emits the block over-limit lanes leave through. A
`RWByteAddressBuffer` bound per pipeline, incremented there, and read back once
a frame, gives the exact count per shader. That is the honest instrument: it
costs one UAV binding and a tiny write per aborted lane, and it names the
shaders instead of inferring them. It is also the patch this repository would
take next.

## What to fix once a shader is named

- The console reads its own memory; on PC a view the host has not uploaded yet
  reads zeros, so counts come out 0 or huge. The fix is in the layer's
  mirroring/ordering (upload before the pass that reads it, or a wait), not in
  the shader.
- If the read is legitimate and simply long (a real 4,000-iteration loop), raise
  that stage's bound and leave the safety net for the rest.

Either way the win is the same shape as the 64-bound experiment: the card term
falls toward its real work, which on this machine is ~130 ms of the 236.
