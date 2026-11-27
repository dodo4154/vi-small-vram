# Correction: the loop bound is not the wall

An earlier version of this document argued that the card term was lanes spinning
to `LOOP_LIMIT` and that the fix was to find the shaders that reach it. The
per-stage measurements in `README.md` refute that:

- the pixel bound (128 -> 64) changes nothing (225-233 ms, ~5,090 draws);
- the compute bound (4,096 -> 64) makes the frame three times slower (635-650 ms);
- the "all stages at 64" run that looked like a 2x win ran **291-444 draws a
  frame instead of ~5,000**: the shaders broke, the layer dropped the world, and
  a nearly empty frame is fast.

What the day does establish, and what a next session should not re-derive:

- the card term is 5,000 draws and 2,548 indirect commands a frame;
- it does not move with resolution, with the two UAV barriers per indirect
  command, with removing the title's own 716 barrier groups (they are needed),
  with moving shadow buffers into VRAM, or with the window grid;
- it moves only when the draws stop happening.

So the remaining question is per-draw cost, and the instrument for it is a GPU
capture (AMD Radeon GPU Profiler on this machine is not installed) or a working
per-pipeline timestamp path in the diagnostics build, which this driver did not
produce. Anything else is guessing.
