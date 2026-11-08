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

Static coverage is **53.8%** as traced code (8822/16384 bytes), plus
3957 bytes of declared data blocks -- **78.0%** accounted for overall, 3605
bytes left as an honest gap (this number has moved around across passes,
occasionally *up*, as wrong claims got caught and reverted -- see the
retraction below; treat "% accounted for" as a proxy for "well-understood",
not a monotonic score to chase). Round-trip is byte-identical throughout
everything documented here.

*Corrected 2026-11-08:* this paragraph read 50.9% code (8332 bytes), 6315
bytes of data blocks and 89.4% accounted for, with a 3737-byte gap. The data
figure didn't add up: 16384 - 8332 - 3737 is 4315, so the true figure was
77.2%. The new numbers come from the page-tail correction below
("Correction: the character sheet is eight half-pages").

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
| `chr_rom_C000` ... `chr_rom_C700` | `$Cn00`-`$Cn97` in each page `$C0`-`$C7` | indirect | `CHARBASE` confirmed by code, not guess: both writers (`$D88D`, `$EC75`) load `#$C0` immediately before the write. Only bytes `$00`-`$97` of each page are tiles; bytes `$98`-`$FF` are code and tables (corrected 2026-11-08, see below). |
| `gfx_CEC6` | `$CEC6`+31 | indirect | A small fragment in the otherwise-unclaimed `$C946`-`$CEE4` gap; runs exactly up to `sub_CEE5` (real code) with zero padding. Rests on a display-list header address only (see the 2026-11-08 note in "The `$C946`-`$CEE4` gap"). |
| `GameSpritesB` | `$D000`-`$D7FF` | direct | A second sheet, referenced from all 8 line-planar pages (`$D000`, `$D100`, ... `$D700` -- the standard base+n*256 layout for an 8-line-tall object), real widths seen at every page. Sits between `chr_rom_C2AC` and `ENTRY_Nmi` (`$D800`) with no gap either side. |

*Corrected 2026-11-08:* this table used to list `chr_rom_C000` as
`$C000`-`$C2AA` and `chr_rom_C2AC` as `$C2AC`-`$C797`, two solid blocks
either side of `ENTRY_Irq`, and `gfx_C9A8` (`$C9A8`+21) as a confirmed
fragment. All three were wrong: the two sheets covered code and tables in
every page tail, and `gfx_C9A8` sat inside the sound tick. See
"Correction: the character sheet is eight half-pages" and the
`$C946`-`$CEE4` section below.

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

*Corrected 2026-11-08:* `ENTRY_Irq` is not an isolated one-byte code
island. It is the closing `RTI` of the first DLI handler, `VEC_C298`
(`$C298`-`$C2AB`: `... PLA / RTI`), so the IRQ vector reuses that
handler's last byte. The two-block split was still wrong too; see the next
section.

## Correction: the character sheet is eight half-pages

Added 2026-11-08, after a review of the techniques mined from this and the
sibling disassemblies flagged it. Code-read from the ROM bytes and a
regenerated listing; not checked live.

The two blocks either side of `ENTRY_Irq` still hid code. The sheet is the
eight line pages `$C000`-`$C7FF` (`CHARBASE` `$C0`), but each page holds
tiles only in bytes `$00`-`$97`. Bytes `$98`-`$FF` of every page are code
or tables, and nothing but MARIA reads `$00`-`$97`: every label, table
base and call target in the range lands at `$98` or above. The tails hold:

| tail | what | evidence |
|---|---|---|
| `$C098`-`$C0FD` | zone tables: hi/lo bytes of the 24 zone display lists (`$C098`/`$C0B0`), hi/lo bytes of 23 rows of the character map at `$24AA` (`$C0C8`/`$C0DF`), bit masks (`$C0F6`) | read by `sub_CD68`, `sub_DB6C`, `sub_DA3D`, `$DCC2`, `$C857` |
| `$C198`-`$C1F6` | `dat_C198`, the DLL template | `$D88F`-`$D8A0` copies 95 bytes to `$1F38` and points `DPPH`/`DPPL` there |
| `$C298`-`$C2F2` | the DLI chain, three stages: `VEC_C298` -> `VEC_C2AC` -> `VEC_C2DA` -> `VEC_C298` | `ENTRY_Nmi` is `PHA / JMP ($00F4)`; each stage stores the next one's address in `$F4`/`$F5` |
| `$C398`-`$C3FC` | `sub_C398`, writes the score digits into the character map | called from DLI stage 2 |
| `$C498`-`$C4DB` | `sub_C498`, the palette loader: copies 12 bytes from `$F4F2`+`ram_211F,X` into palettes 6 down to 3 (fewer when `ram_1FD1` is above 0) | called from DLI stage 2 and from `$EDA1` |
| `$C598`-`$C5F4`, `$C698`-`$C6FB` | message text in character indices (`$40` = blank) and their pointer tables, plus two small 3-entry tables | read at `$D9B8`, `$D99A`, `$D9D3`, `$E5A6`, `$E613`, `$E636`, `$E7CF`, `$EA32`, `$EA62` |
| `$C798`- | `sub_C798` onward, the code already known | |

DLI stage 2 also carries the frame's work: `sub_CEE5`, `sub_C398`,
`sub_CD10` (the zone rebuild, which runs only when the main loop has set
`ram_2108` bit 7 and clears it at `$CEB2` -- so the guess in "Main loop"
below, "presumably cleared by the display-list interrupt chain", was
right), `sub_C498` and `sub_C946` (the sound tick, below). The DLL
template has three DLI-flagged entries, one per stage.

The tool had been pointing at this all along: run on the old blocks,
today's `disasm.py` prints "2 traces ran into a declared data block and
stopped there (first: rom:C298, rom:C498)". The "dense live display-list
refs on both sides of the IRQ byte" that confirmed the old split were
header addresses, which show where objects start, not that every byte
between them is graphics.

Now declared as eight 152-byte `gfx` blocks (`chr_rom_C000` ...
`chr_rom_C700`) plus data blocks for the tables. The DLI chain and the
routines are reached by the `ram_vectors` scan and their own `JSR`s, with no
manual entries. Coverage went from 50.9% to 53.8%. The last few bytes of
some tails (`$C0FE`-`$C0FF`, `$C1F7`-`$C1FF`, `$C2F3`-`$C2FF`,
`$C3FD`-`$C3FF`, `$C4DC`-`$C4FF`, `$C5F5`-`$C5FF`, `$C6FC`-`$C6FF`, 78
bytes) have no reader found and stay gaps.

Two leads from this pass, not followed up: the palette loader's colour
rows (`$F4F2`) and the sound tick's tables (`$F582`-`$F5C1`) sit at the
start of the `$F4F2`-`$FFFF` "graphics region" below; and `sub_C398`
reads each score as three bytes 7 apart (`$008E`, `$0087`, `$0080` for
slot 0, high byte first), the same order as `sub_DDA9`'s `ADC` chain,
which does not fit the score-storage correction in "A reference
cross-check" below. Neither was re-checked here.

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

*Corrected 2026-11-08 (code-read from the ROM bytes, not live):*
`$C946`-`$C9A7` was never a gap, and `gfx_C9A8` was not graphics.
`$C946` is `sub_C946`, the per-frame sound tick, called from DLI stage 2
(`$C2D1`) and running to its `RTS` at `$CA26`. It steps both TIA voices
through the current effect's streams: frequency streams through the
pointer tables at `$F582`/`$F58A`, `AUDV` streams at `$F592`/`$F59A`,
`AUDC` streams at `$F5A2`/`$F5AA`, default durations at `$F5B2`. In the
frequency stream `$FF` ends the effect, `$FE` restarts it, `$FD nn` chains
to effect `nn`, and a byte with bit 7 set is followed by an explicit
duration; in the `AUDV`/`AUDC` streams bit 7 holds the value. Effect 5
resumes from a position saved in `$277D` when its voice was stolen
(`$C92E` saves, `$C975` restores). The "confirmed live" `gfx_C9A8` block
began on this routine's `CMP #$FF` at `$C9A8` and has been removed;
nothing reached it before because the old `chr_rom_C2AC` block hid DLI
stage 2, its only caller.

Why the live walk named `$C9A8` anyway: `tools/live-slots.lua` records
each display-list header's address field, not bytes MARIA was seen to
fetch, and this game's headers need not point at the bytes they draw --
the object placer writes `$C0`+fine for an object's upper zone and an
address 8 pages lower for the zone below (`$CDF5`-`$CDF9`). So a header
address is not evidence that the bytes there are graphics. Which builder
wrote the `$C9A8` header was not traced. The same caveat applies to the
other blocks that rest on this walk alone (`gfx_CEC6` here, and `gfx_FE0C`,
`gfx_FE64` and `gfx_FF24` in the tail above); they were not re-checked in
this pass. What stays open here is `$CA27`-`$CD0F` and `$CEB6`-`$CEC5`.

## The interrupt vector table

`$FFFA`-`$FFFF`, the standard 6502 NMI/RESET/IRQ vector table. Confirmed by
agreement, not guessed: the bytes read back as `$D800`/`$D804`/`$C2AB`,
matching `ENTRY_Nmi`/`ENTRY_Reset`/`ENTRY_Irq` exactly.

## Gameplay logic: main loop, score, and the extra-life mechanism

**Note (added later, see "A reference cross-check" below):** several names
and interpretations in this section turned out to be wrong --
`ScoreDigitsA/B/C/D` (now `Score0/1/2Team/3Extra`), `ExtraLifeAwardCount`
(now `LivesRemaining`), and `CentipedeSegRow`/`CentipedeSegCol` (now
`ObjectStatus`/`ObjectDir` -- they were never position data). Left as
originally written rather than silently edited, per this project's own
discipline of retracting in place, not rewriting history; read the
mechanisms below for the shape of the reasoning, and the later section for
what was actually true.

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

## A reference cross-check, and what it changed

With the independent investigation well advanced, a privately-held
historical source for this game was consulted -- and it turned out to be
better than a disassembly: the original 1984 developer assembly source, 24
files, held in a community archive of commercial source trees apparently
without official authorization.

It was used under the discipline the sibling projects settled on: as a
*check only*, never as the origin of a finding, never quoted or copied into
this repo. None of its contents are reproduced or redistributed here -- no
filenames, no identifier names, no comments from it appear verbatim below or
in `annotations.json`. It was read privately, used to test claims this
document had already made, and every correction below was then
**independently re-derived from this project's own `rom.asm`** before being
written down: the same "confirm against the ROM, not against a claim"
discipline as the rest of the work, with a new kind of claim to confirm.
Development source is not necessarily the shipped product either, so a
disagreement is a question to settle against the ROM rather than an
automatic correction. Where a correction is reference-only -- not
independently re-verified this pass -- that is said explicitly rather than
presented as equally solid.

This was worth doing: it caught real, confidently-stated mistakes.

**The centipede-segment arrays were misread.** `ObjectStatus` and
`ObjectDir` (`$00D0`/`$00E2`, renamed from `CentipedeSegRow`/`CentipedeSegCol`)
were never row/column position data -- they're a status-bits byte
(alive/poisoned/head/turn-stage flags) and a direction/graphics-offset
encoding, for an 18-slot object table shared by the centipede, spider,
flea/scorpion, the player's shooter, and its shot. The theory that they were
positions was pattern-matched from live churn alone and never independently
checked against what the bits actually meant. The *real* per-object pixel
position, `ObjectX`/`ObjectY` (`$005C`/`$006E`), had been touched only in
passing before. Verified independently: `rom:F30A`'s exact instruction
sequence (`AND #$FC / CMP #$4C / ... / ORA #$E7` acting on `ObjectStatus`,
preceded by reads of `ObjectX`/`ObjectY`) is the poison-mushroom collision
check -- **`ObjectStatus` bit 6 is the poison flag**, set on colliding with
a specific mushroom tile value, and it forces the segment into continuous
turning elsewhere in the same routine. That's the mechanism behind the
erratic downward movement the user described watching -- not a separate,
still-undiscovered system, just bits on the array we already had our hands
on and had mislabeled.

**The bottom-loop multi-head-spawn mechanic is now understood, not just
suspected.** `NewHeadCount`/`NewHeadTimer`/`NewHeadFlag` (`$2112`/`$2114`/
`$2115`) drive it: a head reaching the bottom row sets the flag, a timer
counts down, and at zero a new head spawns into a free object-table slot,
with the count shrinking (spawns arriving faster) as the game progresses.
Independently spotted in our own listing at `rom:C7BE` (the
seed-timer/clear-flag pattern) and `rom:DDE2`/`rom:D907` (the
difficulty-dependent speed-up). The earlier candidate for this mechanic,
`rom:C825`'s segment-count-mismatch branch, is a related but different
piece of logic -- not the spawn routine itself.

**`ram_2129`'s bit 6 pulses are mushroom restoration**, not an
unidentified "notable event" -- during certain wave transitions, empty
mushroom-field cells get refilled, matching the six ~1-second pulses
observed live earlier this session.

**Score storage was structurally mischaracterized.** `Score0`/`Score1`/
`Score2Team`/`Score3Extra` (renamed from `ScoreDigitsA/B/C/D`) are four
separate 3-byte BCD numbers (player-0 score, player-1 score, a 2-player
co-op team score, and a spare block for the high-score cart), not four BCD
digit-places shared across three player slots -- the X=0..2 index seen in
the arithmetic selects a byte *within* one number, not a player.
`LivesRemaining` (`$210E`, renamed from `ExtraLifeAwardCount`) is exactly
that -- current lives, capped at 6 -- not a count of bonuses awarded; the
live behavior already observed (moving through 0/1/2 across the session)
was consistent with the correct field the whole time, just named for the
wrong reason.

**Not independently re-verified, flagged as reference-only**: `ram_2122`
is likely a game-type/mode selector (1P/2P variants), not the "current
player turn index" guessed earlier -- consistent with staying flat at 0 for
this entire 1-player recording, but for a different reason than assumed.
This one is taken on the reference's word, not re-derived from our own code
this pass, and is marked that way in `annotations.json`.

There's also a full mushroom-field layout in the reference (a per-cell
character-index map sized for a 24-zone, 31-column playfield, living
somewhere past `$2200` in RAM, directly interpreted through `chr_rom_C000`'s
character sheet) that hasn't been checked against our own ROM at all yet --
worth a live probe next, not written down as a finding here since it's
reference-only so far.

## What's still open

* The mushroom-field RAM layout itself (see above) -- a strong reference-only
  lead, not yet independently confirmed against this ROM's own RAM.
* `ObjectStatus`/`ObjectDir`'s exact bit-by-bit meaning beyond the poison
  flag (turn-stage, bounce, fast-segment bits) -- named generically for now,
  not bit-mapped.
* Eleven gaps remain outside the `$F4F2`-`$FFFF` tail, 859 bytes total:
  `$CA27`-`$CD0F` (745), `$CEB6`-`$CEC5`, `$E9AD`-`$E9BB`, `$CFFB`-`$CFFF`,
  and the seven page-tail leftovers in `$C0FE`-`$C6FF` (78) -- two of them
  (`$E9AD`-`$E9BB`, `$CFFB`-`$CFFF`) have no live or static evidence at all
  pointing to either code or data, genuinely open rather than just
  unexamined. (*Corrected 2026-11-08:* this item read "six small scattered
  gaps, 653 bytes, `$C946`-`$C9A7` down to `$CFFB`-`$CFFF`"; `$C946`-`$C9A7`
  turned out to be the sound tick.)
* Per-enemy-type behavior (spider, flea, scorpion) and the
  novice-vs-standard gameplay difference are still untraced.
* 2-player mode is entirely unexercised by any recording so far, which
  limits confidence on `ram_2122`/`ram_211A`/`ram_211B` specifically.
