# Centipede (Atari 7800) disassembly

A byte-identical disassembly and memory-map investigation of *Centipede*
(NTSC, Atari, 1987), built with
[a7800-toolkit](https://github.com/) and MAME as a live-verification
instrument, not just a static reader.

**This repo does not contain the ROM.** Supply your own legally-owned dump
(`Centipede (NTSC) (Atari) (1987) (020EFE25).a78`, alongside a 7800 BIOS) to
reproduce anything here. The disassembly listing itself (`src/rom.asm`)
isn't committed either -- it's fully generated from
[`annotations.json`](annotations.json) plus the ROM, and regenerating it is
one command (below).

## Start here

[`docs/FINDINGS.md`](docs/FINDINGS.md) is the real deliverable: a
narrative of what's been confirmed live in MAME (with the exact recording
cited), what was ruled out and why, and what's still open.
[`annotations.json`](annotations.json) is the machine-readable form of the
same knowledge -- the memory map, entry points, and labels that actually
drive the disassembler.

Working discipline, if you're picking this up: every claim about what a
byte range does is checked live (a MAME Lua write/read tap, PC-tagged to
tell a real reader apart from MARIA's shared-bus DMA getting misattributed
to whatever the CPU's PC happens to be -- see `docs/pitfalls.md` in the
toolkit) rather than asserted from static reading or a guessed render width
alone. Every `annotations.json` change is followed by JSON validation,
`disasm.py` regeneration, and a `verify.py` byte-identical round-trip
check.

## Reproducing it

```
# from this directory, with the toolkit checked out as a sibling (adjust
# the path below to wherever you have it) and your own ROM copy dropped in:

python3 ../a7800-toolkit/tools/disasm.py "Centipede (NTSC) (Atari) (1987) (020EFE25).a78" -c annotations.json -o src
python3 ../a7800-toolkit/tools/verify.py "Centipede (NTSC) (Atari) (1987) (020EFE25).a78" -d src
# -> ROUND-TRIP PASSED
```

`src/rom.asm` is then a full listing, byte-identical when reassembled.

Add `--gaps` for a text report of every byte reached as neither code nor a
declared data block, or `--map` for the same picture as a heatmap (green
code, blue declared data, red gap -- needs Pillow):

```
python3 ../a7800-toolkit/tools/disasm.py "Centipede (NTSC) (Atari) (1987) (020EFE25).a78" -c annotations.json -o src --gaps --map
```

![Coverage map](docs/img/coverage-map.png)

The remaining gap (bottom, red) is mostly the sparsely-touched graphics
tail at `$F4F2`-`$FFFF` plus a handful of small unreached-branch residues
scattered through the code -- see `docs/FINDINGS.md` for the investigation
that ruled out "missed code" for the large one.

## Reproducing the live findings

`run-01.inp` is a MAME input recording -- a deterministic button-press log,
not video, and not copyrighted content -- covering a standard and a novice
game, all enemy types, poison-mushroom erratic movement, extra lives, and
the bottom-of-screen looping/multi-head-spawn mechanic (not 2-player mode).
Replay it with:

```
./"Play Recording.command" run-01
```

or drive it headless with a Lua probe the way the findings do:

```
mame a7800 -rompath /path/to/bios -input_directory . \
  -cart "Centipede (NTSC) (Atari) (1987) (020EFE25).a78" \
  -playback run-01.inp -autoboot_script your-probe.lua \
  -video none -sound none -nothrottle -str 600
```

`tools/` holds this project's own probe scripts (`live-slots.lua` walks the
live display list to confirm graphics addresses; `probe-gap-readers.lua`
PC-tags reads into a byte range to tell a real reader from a DMA
misattribution artifact) -- generic instrument code lives in the toolkit
itself, these are specific to questions this particular game raised.

## Layout

| | |
|---|---|
| `annotations.json` | The recipe. Feed it to `disasm.py` to get the listing. |
| `docs/FINDINGS.md` | The narrative -- read this first. |
| `docs/img/` | `coverage-map.png` (regenerate with `disasm.py --map`). |
| `run-01.inp` | The MAME input recording the live findings were checked against. |
| `tools/` | This project's own probe scripts. |
| `Play Recording.command`, `Record Session.command` | Double-click launchers for replaying/recording a session (macOS + MAME on `PATH`). |

Not committed (see `.gitignore`): the ROM, the generated `src/rom.asm` and
`build/`, the boot screenshot in `snap/`, and the two probe scripts'
regeneratable output manifests -- all reproducible from the ROM and the
recording above.
