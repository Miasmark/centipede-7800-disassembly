# Centipede -- findings so far

`Centipede (NTSC) (Atari) (1987) (020EFE25).a78`, 16K linear, no banking, no
POKEY declared -- audio is the TIA's own two voices. Everything below is
reproducible with the [a7800-toolkit](../../a7800-toolkit/README.md) against
`annotations.json` in this folder, and the round-trip is checked after every
addition:

```
python3 ../a7800-toolkit/tools/disasm.py "Centipede (NTSC) (Atari) (1987) (020EFE25).a78" -c annotations.json -o src
python3 ../a7800-toolkit/tools/verify.py "Centipede (NTSC) (Atari) (1987) (020EFE25).a78" -d src
```

Static coverage is **45.1%** as traced code (7383/16384 bytes), plus
5945 bytes of declared data blocks (graphics sheets + the vector table) --
**81.3%** accounted for overall, 3056 bytes left as an honest, undivided
gap. Round-trip is byte-identical throughout everything documented here.

Vectors: `IRQ $C2AB` `NMI $D800` `RESET $D804`.

This pass focused on getting the memory map settled -- what's graphics,
what's code, what the ROM's tail actually is -- using one long recording
(`run-01.inp`, 53700 frames) rather than reading gameplay logic yet. The
recording covers a standard and a novice game, all enemy types shot, extra
lives, poison-mushroom erratic centipede movement, and the bottom-of-screen
centipede-looping / multi-head-spawn mechanic; it does **not** cover
2-player mode. That gap in coverage matters below.

## Graphics: two confirmed sheets, found by walking the live display list

Rather than trust `gfx.py`'s render at a guessed width (a known trap -- a
plausible-looking render at the wrong width is still noise, see
`docs/pitfalls.md` in the toolkit), every graphics claim here was checked
against what the game's own display list pointed at while `run-01.inp`
played, using `tools/live-slots.lua` -- a MAME Lua script that taps MARIA's
`DPPH`/`DPPL` register writes (otherwise write-only) each frame, walks the
DLL/DL chain it points at, and records every graphics address referenced
plus the widest object seen there.

| block | range | mode | how confirmed |
|---|---|---|---|
| `chr_rom_C000` | `$C000`-`$CEE4` | indirect | `CHARBASE` confirmed by code, not guess: both writers (`$D88D`, `$EC75`) load `#$C0` immediately before the write. Extent confirmed live -- the display list references addresses right up to `$CEE4`, touching `sub_CEE5` (real code) with no gap. |
| `GameSpritesB` | `$D000`-`$D7FF` | direct | A second sheet, referenced from all 8 line-planar pages (`$D000`, `$D100`, ... `$D700` -- the standard base+n*256 layout for an 8-line-tall object), real widths seen at every page. Sits between `chr_rom_C000` and `ENTRY_Nmi` (`$D800`) with no gap either side. |

Neither sheet's *content* (which enemy or effect belongs to which sprite)
is identified yet -- that needs a screenshot cross-check against a specific
frame's live display list, not attempted this pass.

## The `$F4F2`-`$FFFF` tail: data, not missed code

This was the ROM's one large remaining gap (2830 of the pre-this-pass 3140
gap bytes) and the thing this session actually spent its time on. Two
methods were tried; the second one settled it.

**Method 1 -- who reads it (failed to find a genuine reader).**
`tools/probe-gap-readers.lua` installs a PC-tagged read-tap across the
whole range and runs the full recording: 1,183,549 hits. Checking the
top-hit PCs against their own disassembly found every one of them was
either a busy-wait loop (`$D861`: `BIT ram_2108` / `BMI L_D861`), a bare
register op (`$DA4D`: `DEY`), or an address that falls *inside* the
already-confirmed `chr_rom_C000` block -- impossible as a real 6502 PC.
This is MARIA's shared display-bus DMA getting attributed to whatever the
CPU's PC happens to be at that instant, not a real reader -- the exact
pattern documented in the toolkit's `pitfalls.md`. Trying `rom:F900` and
`rom:F902` as trial entry points (per `method.md`'s "does the tracer
produce a sustained trace" test) both failed after 1-2 bytes.

**Method 2 -- the same live display-list walk used for the graphics sheets
above, pointed at this range.** It found three genuine, runtime-constructed
graphics-object references landing inside `$F4F2`-`$FFFF`:

| address | width | note |
|---|---|---|
| `$FE0C` | 31 | widest a single MARIA object entry can encode |
| `$FE64` | 30 | |
| `$FF24` | 17 | |

All three are declared as `gfx: true` blocks now. One of them (`$FE0C`)
contains a byte pair that reads as a plausible `JMP` into confirmed code if
you eyeball it as an instruction stream -- a coincidence, not a competing
claim: in a ROM this densely packed with real code, most 2-byte values land
inside `$C000`-`$FFFF` by chance, and the live, dynamic display-list
evidence is the stronger signal here, not the static shape of the bytes.
This is the flip side of the graphics-render trap above: don't trust a
render at a guessed width, but also don't trust an eyeballed opcode shape
over what the hardware actually did with the bytes.

**Conclusion**: `$F4F2`-`$FFFF` is a graphics region, not unreached code.
`run-01.inp` only exercised 3 confirmed starts out of 2830 bytes, so most
of the range is left as an honest, unconfirmed gap rather than guessed into
one big block -- unlike `chr_rom_C000`/`GameSpritesB`, there's no
multi-page or contiguous evidence here yet. A recording that reaches more
enemy/bonus varieties, or 2-player mode (**not** covered by `run-01.inp`),
would likely close more of it.

## The interrupt vector table

`$FFFA`-`$FFFF`, the standard 6502 NMI/RESET/IRQ vector table. Confirmed by
agreement, not guessed: the bytes read back as `$D800`/`$D804`/`$C2AB`,
matching `ENTRY_Nmi`/`ENTRY_Reset`/`ENTRY_Irq` exactly.

## What's still open

* Ten small scattered gaps remain, 226 bytes total (`$ED20`-`$EDAA` down to
  `$F168`-`$F16B`) -- ordinary unreached-branch-target residue, not
  investigated as a group this pass.
* No gameplay logic has been read yet. The mechanics the recording
  specifically demonstrates -- poison-mushroom erratic centipede movement,
  the bottom-of-screen looping/multi-head-spawn mechanic, extra-life
  awarding, per-enemy-type behavior, and novice-vs-standard differences --
  are all still to be traced to code.
* 2-player mode is entirely unexercised by any recording so far.
