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

Static coverage is **50.9%** as traced code (8332/16384 bytes), plus
6315 bytes of declared data blocks -- **89.4%** accounted for overall, 3737
bytes left as an honest gap (this number has moved around across passes,
occasionally *up*, as wrong claims got caught and reverted -- see the
retraction below; treat "% accounted for" as a proxy for "well-understood",
not a monotonic score to chase). Round-trip is byte-identical throughout
everything documented here.

Vectors: `IRQ $C2AB` `NMI $D800` `RESET $D804`.

Three passes are folded into this document: the first settled the memory map
(what's graphics, what's code, what the ROM's tail is); the second, prompted
by an explicit request to start tracing gameplay logic, caught a real bug in
the first pass's own conclusions while doing that -- see the retraction
below before trusting anything about `chr_rom_C000` from an earlier reading
of this file; the third, a direct continuation ("keep going"), found and
fixed a *second* instance of the same underlying class of bug (a chunk of
real code, including a whole DLI handler chain, sitting unreached because a
RAM-vector target was never declared) and used the code it unlocked to
confirm the centipede's own position arrays and renderer. All three passes
use one long recording (`run-01.inp`, 53700 frames, of which only the first
26182 are real recorded input -- the rest is the game coasting under the
last held input). It covers a standard and a novice game, all enemy types
shot, extra lives, poison-mushroom erratic centipede movement, and the
bottom-of-screen centipede-looping / multi-head-spawn mechanic; it does
**not** cover 2-player mode. That gap in coverage matters below.

## Graphics: confirmed sheets, found by walking the live display list

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
| `chr_rom_C000` | `$C000`-`$C2AA` | indirect | `CHARBASE` confirmed by code, not guess: both writers (`$D88D`, `$EC75`) load `#$C0` immediately before the write. |
| `chr_rom_C2AC` | `$C2AC`-`$C797` | indirect | Continuation of the same sheet, resuming right after `ENTRY_Irq`'s single-byte `RTI` (see the retraction below for why this is two blocks, not one). |
| `gfx_C9A8`, `gfx_CEC6` | `$C9A8`+21, `$CEC6`+31 | indirect | Two small confirmed fragments in the otherwise-unclaimed `$C946`-`$CEE4` gap; `gfx_CEC6` runs exactly up to `sub_CEE5` (real code) with zero padding. |
| `GameSpritesB` | `$D000`-`$D7FF` | direct | A second sheet, referenced from all 8 line-planar pages (`$D000`, `$D100`, ... `$D700` -- the standard base+n*256 layout for an 8-line-tall object), real widths seen at every page. Sits between `chr_rom_C2AC` and `ENTRY_Nmi` (`$D800`) with no gap either side. |

Neither sheet's *content* (which enemy or effect belongs to which sprite)
is identified yet -- that needs a screenshot cross-check against a specific
frame's live display list, not attempted this pass.

## Retraction: `chr_rom_C000` was wrongly declared over a real entry point

An earlier pass (documented in an earlier version of this file, and visible
in `annotations.json`'s own header note for `rom:C000` if you want the blow
by blow) extended `chr_rom_C000` from a `C000`-`CEE5` claim -- "the display
list references addresses right up to `$CEE4`, touching `sub_CEE5` with no
gap, so it's one continuous sheet." That was accepted without checking
whether anything *inside* the claimed range was also a call target. It was:
`$C798`, `$C8AC`, `$C8D5` and `$C8F8` (a sound-effect dispatcher called from
13 places in the real game loop) are all real code, rendering as
`dat_`-prefixed labels under `JSR` instructions -- a dead giveaway, in
hindsight, that should have been checked before trusting the boundary.

The immediate fix (shrinking the block to end at `$C798`) was **itself
still wrong**, in a worse way: it left the block spanning `ENTRY_Irq`
(`$C2AB`), the ROM's own hardware-confirmed IRQ vector target. `disasm.py`'s
`forced_data` check (what a `blocks` entry populates) is tested *before* the
opcode is even read in the trace loop, and it wins unconditionally over an
`entries` seed -- so the declared block had been silently suppressing the
IRQ handler's own disassembly the whole time. The listing showed
`ENTRY_Irq:` followed by `.byte $40` instead of `RTI`, which should have
been the tell (a labeled entry point should never render as data), but
wasn't noticed until gameplay-logic tracing surfaced the `JSR dat_C8F8`
calls and prompted a closer look at the whole region.

Fixed by removing the block outright, letting the tracer run from the real
entry points with nothing suppressing it, and re-deriving boundaries only
from what the unblocked tracer and the live evidence actually agree on:
`ENTRY_Irq` is genuinely one byte (`RTI` -- this cartridge doesn't use
POKEY's IRQ features), an isolated code island in the middle of the
character sheet, which is why the sheet is now two blocks either side of it.
This is now a toolkit-level pitfall
(`a7800-toolkit/docs/pitfalls.md`, "A `gfx`/data block silently overrides
`entries`, even at a confirmed vector") since nothing about it is specific
to Centipede: any `blocks` entry can hide an entry point the same way.

## The `$F4F2`-`$FFFF` tail: data, not missed code

This was the ROM's largest gap and the thing an earlier pass spent its time
on. Two methods were tried; the second one settled it.

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

## The `$C946`-`$CEE4` gap

Same shape as `$F4F2`-`$FFFF`, found while re-deriving the `chr_rom_C000`
boundaries (above): the code interruption at `$C798`-`$C945` (real,
JSR-reached code) is followed by more unclaimed bytes, right up to
`sub_CEE5` (real code, reached from `rom:E2FC`). No `JSR`/`JMP` in the whole
listing targets anything inside it, but the live display-list walk found
two genuine graphics references landing in it -- `$C9A8` (width 21) and
`$CEC6` (width 31, running exactly to `sub_CEE5` with zero padding).
Declared only those two spans as `gfx` blocks; most of the rest stays an
honest, unconfirmed gap on the same reasoning as `$F4F2`-`$FFFF` (a later
pass, below, reclaimed `$CD16`-`$CEB5` of it as real code once a RAM-vector
bug was fixed elsewhere -- `$C946`-`$C9A7` and `$CEB6`-`$CEC5` are still
open).

## The interrupt vector table

`$FFFA`-`$FFFF`, the standard 6502 NMI/RESET/IRQ vector table. Confirmed by
agreement, not guessed: the bytes read back as `$D800`/`$D804`/`$C2AB`,
matching `ENTRY_Nmi`/`ENTRY_Reset`/`ENTRY_Irq` exactly.

## Gameplay logic: main loop, score, and the extra-life mechanism

Prompted by an explicit request to start tracing gameplay logic (rather than
just the memory map). Two tools were used together: static reading of the
now-larger traced-code region, and `tools/probe-ram-snapshots.lua` -- a new
MAME Lua script that snapshots every byte of the five RAM pages `ENTRY_Reset`
clears at boot (`$1E00`, `$1F00`, `$2000`, `$2100`, `$2700`) once a second
across the whole recording, keeping only bytes that ever changed, so a
specific RAM cell's value over time can be read off directly instead of
guessed from static code alone. (A first attempt logged every individual
write instead of periodic snapshots and produced an unworkable 2.9M-entry,
79MB file that didn't even finish the recording in the time available --
noted here because it's a real trap: on a ROM this write-heavy, per-write
logging doesn't scale the way it did for the sparser display-list taps used
elsewhere in this project.)

**Main loop.** `ENTRY_Reset` clears the five RAM pages above, runs a short
init chain (`sub_DED1`, `sub_D883`, `sub_D871`, `sub_D87A`), then enters
`sub_D840`: eleven subroutines called in a fixed order every frame
(`sub_E25E`, `sub_E4F6`, `sub_DA51`, `sub_DEFD`, `sub_DCFF`, `sub_EB74`,
`sub_EE3B`, `sub_F1D6`, `sub_F476`, `sub_F00F`, `sub_E8FF`), then waits on
`ram_2108` bit 7 (set by the loop, presumably cleared by the display-list
interrupt chain reached through `ram_00F4`/`ram_00F5`) before looping. This
is simpler than Ballblazer's cooperative task-table dispatcher -- a straight
ordered call list, not an indirect per-frame vector.

**Score.** `ScoreDigitsA`/`B`/`C`/`D` (`$0080`, `$0087`, `$008E`, `$0095`,
each `+X` for up to 3 slots) hold a 4-byte BCD score, confirmed by the
arithmetic itself: `sub_DDA9` sets the decimal flag (`SED`) and does
carry-chained `ADC`s across all four, doubling the add when `ram_2122==3`
(a bonus-multiplier state, not yet identified further).

**Extra lives -- CONFIRMED mechanism, partially confirmed live.**
`sub_DDA9` falls through into `sub_DE1C` after every score add:
`NextLifeThresholdLo`/`Hi` (`$210A`/`$210C`, `+X`) is subtracted from the
new score; if the score has reached it, the threshold advances by BCD
`$0120` and, if `ExtraLifeAwardCount` (`$210E`, `+X`) is still under 6 and a
per-slot "no more bonuses" flag (`ram_00DE,X` bit 6) isn't set, the award
counter increments -- the actual life award. Live snapshot data for the
only active slot in this recording (slot 0 -- it's a 1-player game) shows
`ram_210E` moving through 0/1/2 rather than sitting still, consistent with
real awards happening during the session, matching the user's report of
getting extra lives. This is not yet pinned to an exact frame/award moment;
that would need a tighter, targeted probe around one specific transition.

**Centipede segment count -- well-supported, not fully confirmed.**
`sub_D8D5` seeds `ram_2119`/`ram_211A`/`ram_211B` (`CentipedeSegTarget`) from
a 4-entry table, `dat_D97D`, indexed by `ram_1FCB`. Live
snapshot data shows `ram_2119` counting down cleanly -- `12, 11, 10, 9` --
then jumping back *up* to `12` (frame 9180 of the recording) and continuing
down again -- `11, 10, 9, 8, 7, 6` -- for the rest of the session. That
reset-then-recount shape is a strong match for "segments remaining in the
current centipede," reset to a fresh count when a wave is cleared and a new
centipede begins. `ram_211A`/`ram_211B` get the same seed value but never
move afterward in this recording, so their role is still open.

That frame-9180 reset lines up with two other signals moving at the same
moment: `ram_2124` bit 7 (otherwise 0 during normal play) goes high from
roughly frame 8400 to 9180, and `ram_2129` bit 6 pulses briefly (about a
second, per `rom:DD7E`'s own `AND #$BF` clear) six separate times across the
whole session at irregular intervals. The cluster around 8400-9180 reads as
a wave-clear/respawn transition (gameplay paused, segment count reset,
*something* pulsed) but which of the six `ram_2129` pulses are deaths versus
wave-clears versus bonus events isn't disentangled yet -- `ram_2122`, which
several routines compare against `2` and `3`, stays flat at 0 for this
entire 1-player recording, so it's plausibly a player-turn index that a
2-player recording would actually exercise.

**`ram_1FCB` is *not* confidently "difficulty" any more.** An early
hypothesis (visible in `annotations.json`'s comment history) was that this
is the novice/standard selector, since it seeds the segment-count table at
boot. Live data doesn't support that as cleanly as hoped: it cycles through
several small values (`1, 2, 1, 3, 1, 0`) in the first ~150 frames before
settling at `1` for the rest of normal play -- more consistent with a
boot/attract-sequence state index than a value the player sets once and the
game holds for the whole session. Left unlabeled rather than asserted.

## The `$2000`-`$20FF` dead end, and where the real state lives instead

The obvious hypothesis for a mushroom-field grid was `$2000`-`$20FF` (256
bytes, changing constantly during live play, nothing in the traced code
referencing it by name). A PC-tagged write-tap on that exact range
(`tools/probe-mushroom-writes.lua`) found only 2039 hits, **all in the first
~3000 frames** -- i.e. boot initialization only, nothing during actual play.
That contradicted the live snapshot data showing bytes in that range still
changing at frame 16680+, which meant the write-tap and the snapshot
couldn't both be reading the same underlying story -- and they weren't: the
7800 mirrors `$2040`-`$20FF` down to `$0040`-`$00FF` (a documented toolkit
pitfall, `a7800-toolkit/docs/pitfalls.md`), so ongoing writes during play
were going through the low-address zero-page form the whole time, invisible
to a tap watching only the high addresses.

Re-running the snapshot probe over zero page and the stack page instead
(`tools/probe-ram-snapshots.lua`, now covering `$0000`, `$0100`,
`$1E00`,`$1F00`,`$2000`,`$2100`,`$2700`) found the real thing: **two clean
12-byte parallel arrays**, `$00D0`-`$00DB` and `$00E2`-`$00ED`, both
churning on nearly every one of 500 one-second checkpoints across the whole
session -- a strong live match for 12 independently-moving objects, i.e. the
classic 12-segment centipede.

Static reading then confirmed it directly, not just by pattern-matching the
live churn: `sub_C7FC` (renamed `CentipedeSegRow`/`CentipedeSegCol` in
`annotations.json`) builds the centipede at wave start, looping while
`X < ram_0044` and writing both arrays per segment, bounded by
`CentipedeSegTarget`. Right after the build loop, a branch fires when the
number of segments actually placed doesn't match the target
(`rom:C825`) -- a strong candidate for the bottom-of-screen multi-head-spawn
mechanic, though not yet confirmed against a live frame where it visibly
fires. Further down, `sub_CD16`/`sub_CD68` -- unlocked by the RAM-vector fix
below -- read `CentipedeSegRow` directly to place each segment into MARIA's
per-row display-list zone, which is about as direct a confirmation as static
code can give for what the live data already suggested.

Poison-mushroom state specifically is still not located. A likely
candidate, `ram_005C,X` (set alongside `CentipedeSegCol` in the build loop
via what looks like an LCG-style generator), is noted in `annotations.json`
but not confirmed.

## A second RAM-vector bug: real code hiding behind `dat_ED41`

The same class of mistake as the `chr_rom_C000` retraction above, caught
while reading `dat_ED41` (adjacent to the already-resolved `$ED20` gap
group) looking for mushroom-state code: its first 4 bytes are a genuine
small table, but everything after that -- about 100 bytes, rendering as
`.byte` under a `dat_` label because nothing `JSR`/`JMP`s to it -- is real
code, including a *second*, previously-unknown target for the
`ram_00F4`/`ram_00F5` NMI-vector pair (`$ED64`, on top of the already-known
`$C298` and `$ED45`).

`disasm.py`'s `scan_ram_vectors` only tracked `LDA #imm / STA` pairs at the
time, and the `$ED64` writer uses `LDA`+`LDY` into `STA`+`STY` (a
mixed-register form the scanner didn't follow), so declaring `ram_vectors`
for `$F4`/`$F5` wasn't enough by itself at first -- `$ED45` and `$ED64` were
added to `entries` by hand as an immediate, working fix. The unlocked code
turned out to be a two-handler DLI ping-pong chain (`VEC_ED45` /
`VEC_ED64`), the same mechanism Ballblazer used: each handler sets a
different `CTRL`/`CHARBASE` pair (`$C1` vs `$39`) and re-arms the *other*
handler for the next interrupt, then one of them calls `sub_CD16` -- the
zone-slot allocator mentioned above. This recovered 519 bytes of real code
in one fix, including the centipede-renders-itself confirmation.

**Fixed at the root afterward, in the toolkit itself.** The hand-added
`entries` worked but left the actual cause -- a RAM-vector scan only as
complete as the register forms it looks for -- as a latent gap that would
bite the next project the same way. `scan_ram_vectors` now tracks A/X/Y
independently (each register's last `LD{A,X,Y} #imm` value, matched against
any `ST{A,X,Y}` to the vector address, cleared by anything that loads that
register other than an immediate -- deliberately not trying to track values
through arithmetic, to stay exactly as conservative as the original
A-only version rather than trading a narrow miss for a new false-positive
risk). With the fix in place, the manual `rom:ED45`/`rom:ED64` entries were
removed from `annotations.json` -- the `ram_vectors` declaration alone now
finds all three targets (`$C298`, `$ED45`, `$ED64`) automatically, same gap
count, round-trip still passes. Checked for regressions against Ballblazer
too (the toolkit's other completed project): round-trip still passes there,
and coverage went up slightly (58.5% -> 58.9%) from a previously-missed
mixed-register vector write in that ROM as well -- a pure improvement, not
just a neutral one.

## What's still open

* Poison-mushroom state specifically (see above -- `ram_005C,X` is a
  candidate, not confirmed) and the mushroom sprites' own graphic identity.
* The bottom-of-screen multi-head-spawn branch (`rom:C825`) is a strong
  static candidate but hasn't been confirmed against a live frame where it
  actually fires.
* `CentipedeSegRow`/`CentipedeSegCol` still don't explain the *shape* of
  centipede movement (the left-right weave, the turn-at-a-wall/mushroom
  behavior) -- only where each segment currently is.
* Six small scattered gaps remain, 653 bytes total (`$C946`-`$C9A7` down to
  `$CFFB`-`$CFFF`) -- two of them (`$E9AD`-`$E9BB`, `$CFFB`-`$CFFF`) have no
  live or static evidence at all pointing to either code or data, genuinely
  open rather than just unexamined.
* Per-enemy-type behavior (spider, flea, scorpion) and the
  novice-vs-standard gameplay difference are still untraced.
* 2-player mode is entirely unexercised by any recording so far, which
  limits confidence on `ram_2122`/`ram_211A`/`ram_211B` specifically.
