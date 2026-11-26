# CrankWatch 3.0

A weapon skill and Magic Burst tracker for Windower 4, with a built-in
skillchain helper based on Ivaar's **SkillChains**.

It shows:

- a big **banner** with the last WS, its damage, your running average, and
  flair for big hits (BIG HIT, MASSIVE HIT, CRANKED);
- a **skillchain block** on your target: what you can use next, with a
  red/green Wait/GO countdown bar underneath;
- **Magic Burst popups** for you and your party's mages;
- a **party panel** tallying everyone's WSs and Magic Bursts.

CrankWatch only *reads* packets the server already sent to your client and
draws text. It never sends, injects or changes packets, and it doesn't
automate anything.

---

## Contents

1. [Install and update](#1-install-and-update)
2. [Quick start: your WSs, party WSs and party MBs](#2-quick-start-your-wss-party-wss-and-party-mbs)
3. [What's on screen](#3-whats-on-screen)
4. [Moving and sizing the HUD](#4-moving-and-sizing-the-hud)
5. [Command reference](#5-command-reference)
6. [settings.xml reference](#6-settingsxml-reference)
7. [What gets counted, and how](#7-what-gets-counted-and-how)
8. [Troubleshooting](#8-troubleshooting)
9. [Running the offline tests](#9-running-the-offline-tests)

---

## 1. Install and update

1. Copy these files into `Windower/addons/CrankWatch/`:

   | File | What it does |
   |---|---|
   | `CrankWatch.lua` | Entry point: settings, events, `//cw` commands |
   | `skills.lua` | Skillchain properties for every WS, spell and pet move |
   | `sc_engine.lua` | Skillchain tracking (port of Ivaar's SkillChains) |
   | `party_tracker.lua` | Who's in your party, plus WS and MB stats |
   | `ui_hud.lua` | Everything drawn on screen |

2. **Unload SkillChains**: CrankWatch includes it, and running both shows two
   skillchain HUDs.
   ```
   //lua u skillchains
   ```
   Also remove `lua load skillchains` from `Windower/scripts/init.txt`.

3. Load CrankWatch:
   ```
   //lua l crankwatch
   ```
   To load it automatically, add `lua load crankwatch` to `Windower/scripts/init.txt`.

4. After copying in new files, reload with `//lua r crankwatch`.

**Settings** live in `Windower/addons/CrankWatch/data/settings.xml`. The file
is created on first load. If you're upgrading from CrankWatch 2.0, your saved
positions, fonts and sizes are kept, and new options get their defaults.

**Upgrading from 2.0?** Run these once:
```
//cw scburst 0     turn off the old 0.45s chain reset your settings still carry
//cw reset         clear any stats left from older builds
```

---

## 2. Quick start: your WSs, party WSs and party MBs

```
//cw bannermode party    every party member's WS on the banner, with their name
//cw party on            the party panel: WS and Magic Burst tallies
//cw mbparty on          party mages' bursts pop with their name (on by default)
//cw trusts on           only if you play with trusts
//cw move                drag everything into place, then //cw move again
```

Pets (avatars, wyverns, automatons, jug pets) are tracked by default.
Alliance members (the other parties in an alliance) are **not**, so a big
alliance doesn't flood the banner, popups and panel: `//cw alliance on` if
you want them. The banner's `Avg:` line is off by default because the party
panel shows every average: `//cw avg on` to show it.

**First session:** turn on `//cw debug` for one fight. If it prints
`Unknown message id …` or `Action error …`, note the line so it can be fixed.
Turn it off with `//cw debug` again.

**Busy party?** `//cw bannermode self` keeps the banner to your own WSs,
while the party panel still tallies everyone.

---

## 3. What's on screen

### The banner (WS display)

```
Last WS: Savage Blade!          ← WS name (or "Name: WS!" in party banner mode)
   54,321 damage!! BIG HIT!     ← damage; flair for big hits at the right end
Avg: 43,210 ↑                   ← optional (//cw avg on): average and trend
   SC Bonus: 12,345!!           ← when a skillchain closes on your target
```

- **Damage colour**: white under 10,000 · blue 10,000+ · gold 50,000+ (BIG HIT!) ·
  red 80,000+ (MASSIVE HIT!!) · purple at 99,999 (CRANKED!!!, or CRANKED x N
  for a streak).
- **WHIFF!!** with a shake when the WS misses.
- **Pop**: hits of 50,000+ briefly grow, then settle.
- **Avg line** (off by default, `//cw avg on`): the average for whoever's
  WS is shown. **Trend arrow** (after 10 WSs): ↑ when the last 5 WSs average
  more than 2% above the 20 before them, ↓ when they average more than 2%
  below, → otherwise. Averages are tracked either way for the party panel
  and `//cw stats`.
- **Hit flair** (BIG HIT! / MASSIVE HIT!! / CRANKED!!!) starts at the right
  end of the damage line, level with it, then floats up and fades.
- **SC Bonus: N!!** appears when a WS closes a skillchain on your target
  (only while the banner is showing). It sits directly under the lowest
  banner line (the damage line, or the `Avg:` line when that's on) and never
  rises into it.
- The banner fades in on each WS, holds for 60 seconds, then fades out.

### The skillchain block

One block that moves as a unit. The bar stays put at the top; the closer
list grows downward under it:

```
██████████████░░░░              ← countdown bar: red = wait, green = GO, pink = burst
   SC Window: GO!! 4.2  Chain: 2  ← seconds left, and how many skillchains so far
Step: 3 → Torcleaver            ← chain step → the WS that made it
[Light] (Fire,Wind,Lightning,Light)   ← active skillchain, burst elements
Torcleaver       → Lv.4 Radiance      ← closer list: what you can use next
Upheaval         → Lv.3 Light         ←   → what it makes (highest level first)
```

The closer list shows up to 4 rows, highest level first: `//cw sc rows <N>`
changes that (0 = show all).

- It appears as soon as **anyone** (party or not) opens a skillchain on your
  current target, whether or not the banner is showing.
- **Wait** (red): too early to continue the chain. **GO** (green): use your
  closer now. **Burst** (pink): the chain is closed; nuke for a Magic Burst.
- Each mob keeps its own chain, so tabbing between targets doesn't reset it.
- The closer list only shows what *you* can use: your weapon skills, plus
  Immanence elements on SCH, blue magic on BLU, and pet moves on BST/SMN.
  It accounts for Aeonic weapons and Aftermath.
- If the block would run off the bottom of the screen, it moves above the
  banner.
- **Just want the countdown?** `//cw scdetail off` hides the top part (Step,
  properties, closer list) on every job, leaving the bar and timer.

### Magic Burst popup

```
MB: 40,000!!                ← yours
Blackmage MB: 35,120!!      ← a party member's (named)
```

- Shows bursts on your **current target**.
- Bursts that land together stack, up to 4 lines.

### Party panel

```
Party WS        #      Avg     Peak
Velner         12   48,210   99,999
Partymember     9   31,402   62,118

Magic Bursts    #      Avg     Peak
Blackmage       7   38,940   52,300
```

- Sorted by total damage. Up to 8 rows per section.
- Stays on screen while it has at least one WS or burst recorded. Hides
  itself when empty (fresh load, `//cw reset`, zoning with autoreset on).
- Magic Bursts are counted on **any** mob, not just your target.

---

## 4. Moving and sizing the HUD

### Drag mode

```
//cw move
```

Every part appears filled with sample data, each with a **coloured box**
and a **name tag** above it (MB popup, Skillchain, Party panel, …). The part
under your mouse brightens, and chat prints the list of parts. Only parts
you have switched on appear: for example, with the party panel off or
`//cw scdetail off`, those parts aren't shown and can't be dragged.

Drag with the **left mouse button**. There are four parts, and **each moves
on its own**: dragging one never moves another.

| Part | Contains |
|---|---|
| **Banner** | Last WS line, damage, average, hit flair, SC Bonus |
| **Skillchain** | closer list, countdown bar, timer |
| **Party panel** | WS and Magic Burst tallies |
| **MB popup** | burst popups |

Inside the Banner, the WS line and damage line are centred, the `Avg:` line
(when on) is left-aligned with the WS line, the hit flair starts at the
right end of the damage line, and SC Bonus is centred under the lowest line.
Adjust the spacing inside it with `//cw gap`, `//cw avggap`, `//cw flairgap`
and `//cw scoffset`. In move mode, a hidden `Avg:` line isn't shown.

- **Grab a part by its name tag** when parts overlap: the tag always picks
  the right one. You can also grab the part itself.
- **To move the whole HUD at once**, use `//cw pos <x> <y>` (it sets the
  banner centre; every part keeps its place relative to it).

Each part saves the moment you let go. Type `//cw move` again to finish.

**Why it looks crowded at first.** In move mode everything shows at once.
In play, several parts share space because they appear at different
moments: by default the MB popup sits near the countdown bar, and the hit
flair and SC Bonus float briefly over the average line. If parts overlap,
grab the one you want by its name tag.
Clicks on empty screen still reach the game. WSs that land while you're
dragging are still recorded, but don't replace the sample.

If the skillchain block or party panel would run off the edge of the screen,
it moves to the other side of the banner automatically.

**Messed it up?** `//cw resetpos` puts every part back in its default place
and saves. Sizes, fonts and all other settings are kept. If you changed
`//cw size`, the banner's line gaps are rebuilt to match that size.

### Sizes

One number per block. Everything inside the block (fonts and spacing)
scales together, so it keeps its shape at any size:

```
//cw size 36            Banner: WS line, damage, average, hit flair, SC Bonus
//cw skillchainsize 13  Skillchain block: closer list, bar, timer
//cw partysize 13       Party panel
//cw mbsize 24          MB popup
```

The numbers above are the defaults. `//cw size` with no number lists all
four current sizes. After resizing, `//cw move` to re-place blocks if
needed.

Also useful: `//cw font <name>` (banner font) and `//cw stroke <n>` (outline
thickness; try 2 or 3 for a smaller banner). `//cw layout` prints the
current position, gaps and font.

Per-line size commands (`scsize`, `scbarsize`, `scdetailsize`,
`scbarlabelsize`, `scchaincountersize`) still work for fine-tuning one
piece, but the block sizes above are all most setups need.

---

## 5. Command reference

Type `//cw` or `//crankwatch`. Any number command typed without a value
prints the current value. Settings changed by commands are saved
immediately.

### Everyday

| Command | What it does |
|---|---|
| `//cw move` | Drag mode on/off (see section 4) |
| `//cw stats` | Print every tracked player's WS and MB stats to chat |
| `//cw reset` | Clear WS stats, averages and MB tallies (`//cw resetavg` also works) |
| `//cw reset ws` | Clear only WS stats and averages |
| `//cw reset mb` | Clear only Magic Burst tallies |
| `//cw show` | Show the banner now |
| `//cw hide` | Hide everything until `//cw show` or your next WS |
| `//cw resetpos` | Put every part back in its default position. Keeps sizes, fonts and other settings |
| `//cw help` | List all commands |

### Who is tracked

| Command | Default | What it does |
|---|---|---|
| `//cw bannermode self\|party` | `self` | `self`: only your WSs on the banner. `party`: everyone's, labelled `Name: WS!` |
| `//cw pets on\|off` | on | Count pets' damaging TP moves and blood pacts |
| `//cw trusts on\|off` | off | Count trusts' weapon skills |
| `//cw alliance on\|off` | off | Count alliance members (other parties) as well as your party |
| `//cw aoesum on\|off` | off | AoE WSs: off counts the main target only; on adds up every target hit |
| `//cw blacklist add <ws>` | | Keep a WS out of stats and the banner. It still counts for skillchains |
| `//cw blacklist remove <ws>` | | Take a WS off the blacklist |
| `//cw blacklist list` | Myrkr, Dagan, Starlight, Moonlight | Show the blacklist |
| `//cw autoreset on\|off` | on | Clear stats automatically when you zone |
| `//cw avg on\|off` | off | Show the `Avg:` line (and trend arrow) on the banner. Averages are tracked either way |

### Party panel

| Command | Default | What it does |
|---|---|---|
| `//cw party on\|off` | off | Show the party panel |
| `//cw party fade on\|off` | off | On: the panel fades out with the banner. Off: it stays while it has data |
| `//cw partypos <dx> <dy>` | 260 0 | Panel position relative to the banner centre (or drag it in `//cw move`) |
| `//cw partysize <n>` | 13 | **Party panel size** |
| `//cw testparty` | | Show a sample panel for 10 seconds |

### Magic Burst popup

| Command | Default | What it does |
|---|---|---|
| `//cw mb on\|off` | on | Show MB popups at all |
| `//cw mbparty on\|off` | on | Also show party members' bursts (named). Off: only yours |
| `//cw mbsize <n>` | 24 | **MB popup size** |
| `//cw mbx <px>` / `//cw mby <px>` | 95 / 101 | Popup position from the banner centre (or drag it) |
| `//cw testmb [damage]` | | Show a sample popup |

MB tallies on the party panel are always collected, whatever `mb` and
`mbparty` are set to.

### Skillchain HUD

| Command | Default | What it does |
|---|---|---|
| `//cw scbar on\|off` | on | The whole skillchain block |
| `//cw schud on\|off` | on | On: shows whenever your target has a chain. Off: only while the banner is showing |
| `//cw sc <part>` | see below | Turn one part on/off **for your current job** |
| `//cw sc color` | on | Coloured skillchain names in the properties line and closer list |
| `//cw sc rows <N>` | 4 | Max closer-list rows, highest level first. 0 = all |
| `//cw scaeonic on\|off` | off | Assume other players have their Aeonic weapon equipped (affects Lv.4 predictions) |
| `//cw scburst <sec>` | 0 | If two *different* actions hit one target within this many seconds, reset the chain. 0 = off |
| `//cw scbardelay <sec>` | 3 | Wait time when a WS has no known delay |
| `//cw scbarwidth <chars>` | 18 | Bar length in characters (min 6) |
| `//cw scbarsize <n>` | 18 | Bar size |
| `//cw scbargap <px>` | 132 | Skillchain block's top edge, below the banner (or drag it) |
| `//cw scbarlabelsize <n>` | 15 | `SC Window:` text size |
| `//cw scbarlabeloverlap <px>` | 20 | How far the `SC Window:` text sits below the bar |
| `//cw scchaincountersize <n>` | 18 | `Chain: N` size |
| `//cw scchaincountergap <px>` | 6 | Gap between `GO!!` and `Chain: N` |
| `//cw scdetail on\|off` | on | The top part of the block (Step, properties, closer list), on every job. Off keeps just the bar and timer |
| `//cw scdetailsize <n>` | 13 | Closer list text size |
| `//cw testbar` | | Sample WS plus a 10-second Wait → GO bar |

**Per-job parts** (`//cw sc <part>`), as in SkillChains. Each one remembers a
separate on/off for every job:

| Part | Default jobs | Controls |
|---|---|---|
| `timer` | all | Seconds after `Wait`/`GO!!`/`Burst!` |
| `step` | all | The `Step: N → WS` line |
| `props` | all | The `[properties] (elements)` line |
| `burst` | all | Burst phase after a chain closes, and burst elements on the properties line |
| `weapon` | all | Your weapon skills in the closer list |
| `spell` | SCH, BLU | Immanence elements (SCH) or blue magic (BLU) in the closer list |
| `pet` | BST, SMN | Pet moves in the closer list (while your pet is out) |

### SC Bonus float

| Command | Default | What it does |
|---|---|---|
| `//cw scsize <n>` | 34 | Text size |
| `//cw scfade <sec>` | 4 | How long it takes to float away |
| `//cw scfloat <px>` | 28 | How far it floats up |
| `//cw scoffset <px>` | 4 | Gap between SC Bonus and the line above it |

### Banner layout and animation

| Command | Default | What it does |
|---|---|---|
| `//cw pos <x> <y>` | 1475 850 | Banner centre on screen. Moves the **whole HUD**; every part keeps its place relative to it |
| `//cw size <n>` | 36 | **Banner size.** Scales the WS line, damage, average, flair, SC Bonus and their spacing together (`//cw bannersize` also works). No number: list all block sizes |
| `//cw skillchainsize <n>` | 13 | **Skillchain block size.** Scales the closer list, bar, timer and their spacing together |
| `//cw gap <px>` | 45 | Damage line distance below the WS line |
| `//cw avggap <px>` | 99 | Average line distance below the WS line |
| `//cw flairgap <px>` | 100 | Flair distance below the WS line |
| `//cw font <name>` | Highwind | Font for the banner and labels |
| `//cw stroke <px>` | 4 | Outline width (big hits use this +1) |
| `//cw fade on\|off` | on | Off: the banner stays up permanently |
| `//cw fadetime <hold> <out>` | 60 5 | Seconds to hold, then seconds to fade out |
| `//cw fadein <sec>` | 0.3 | Damage line fade-in time |
| `//cw killfade on\|off` | off | Fade the banner out as soon as the mob its WS hit dies (or despawns), instead of waiting out the hold |
| `//cw killfade <sec>` | 1 | How long that fade takes |
| `//cw pop on\|off` | on | Grow-and-settle effect on 50,000+ hits |
| `//cw popsize <n>` | 8 | How much bigger the pop gets |
| `//cw poptime <sec>` | 0.35 | Pop duration |
| `//cw flairfade <sec>` | 1.5 | Flair float-away time |
| `//cw flairshrink <n>` | 6 | How much the flair shrinks as it fades |
| `//cw flairfloat <px>` | 32 | How far the flair floats up |
| `//cw whiffshake <strength> <sec>` | 6 0.45 | WHIFF shake |
| `//cw layout` | | Print position, gaps and font |

### Tests (display only, never touch your stats)

| Command | Shows |
|---|---|
| `//cw test` | Savage Blade, 29,973 |
| `//cw testwhite` | Savage Blade, 9,999 (white) |
| `//cw testbig` | Stardiver, 65,000 (BIG HIT) |
| `//cw testred` | Savage Blade, 90,000 (MASSIVE HIT) |
| `//cw testmassive` | Torcleaver, 99,999 (CRANKED) |
| `//cw testcrankedstreak` | three 99,999s (CRANKED x N) |
| `//cw testwhiff` | a miss |
| `//cw testbar`, `testmb [dmg]`, `testparty` | see the sections above |

### Maintenance

| Command | What it does |
|---|---|
| `//cw resetpos` | Reset positions only (see section 4) |
| `//cw factoryreset` | Put **every** setting back to default, including per-job parts and the blacklist |
| `//cw debug` | Print extra detail: unknown message IDs, skillchains seen, ignored actions |

---

## 6. settings.xml reference

`Windower/addons/CrankWatch/data/settings.xml`. Most options have a command
(section 5). Options marked **file only** have no command: edit the file,
then `//lua r crankwatch`. Sizes are font points; positions and gaps are
pixels.

### Banner

| Key | Default | Meaning |
|---|---|---|
| `center_x`, `center_y` | 1475, 850 | Banner centre (`//cw pos`). Every part is placed from here, independently |
| `banner_offset_x`, `banner_offset_y` | 0, 0 | The Banner block's position from the HUD centre (set by dragging the Banner in `//cw move`) |
| `ws_size` | 36 | `Last WS` line size |
| `dmg_size` | 42 | Damage line size |
| `avg_size` | 24 | Average line size |
| `flair_size` | 32 | Flair size |
| `line_gap` | 45 | Damage line below the WS line |
| `avg_gap` | 99 | Average line below the WS line |
| `flair_gap` | 58 | Hit flair height below the WS line (default: level with the damage line) |
| `font` | Highwind | Banner font |
| `stroke_width` | 4 | Outline width |
| `big_stroke_width` | 5 | Outline width for 50,000+ hits |
| `fade_enabled` | true | Fade the banner in and out |
| `fade_in_duration` | 0.3 | Damage fade-in seconds |
| `hold_duration` | 60 | Seconds the banner stays after a WS |
| `fade_out_duration` | 5 | Fade-out seconds |
| `banner_hide_on_kill` | false | Fade the banner when its WS's target dies (`//cw killfade`) |
| `kill_fade_duration` | 1.0 | Seconds for that fade |
| `pop_enabled`, `pop_duration`, `pop_bonus_size` | true, 0.35, 8 | Big-hit pop |
| `flair_fade_duration` | 1.5 | Flair float-away seconds |
| `flair_shrink_size` | 6 | Flair shrink while fading |
| `flair_float_distance` | 32 | Flair float distance |
| `flair_anchor_ratio` | 1.0 | **File only.** Where the flair starts along the damage line (0 = left edge, 1 = just past the right end; 2.0 used 0.72) |
| `flair_offset_y` | −6 | **File only.** Flair vertical nudge |
| `whiff_shake_duration`, `whiff_shake_strength` | 0.45, 6 | WHIFF shake |

### SC Bonus float

| Key | Default | Meaning |
|---|---|---|
| `sc_enabled` | true | **File only.** Show the SC Bonus float |
| `sc_size` | 34 | Text size |
| `sc_offset_y` | 4 | Gap between SC Bonus and the line above it (`//cw scoffset`) |
| `sc_fade_duration` | 4 | Float-away seconds |
| `sc_float_distance` | 28 | Float distance |

### Skillchain HUD

| Key | Default | Meaning |
|---|---|---|
| `sc_bar_enabled` | true | Whole skillchain HUD |
| `sc_hud_independent` | true | Show without the banner |
| `sc_bar_gap`, `sc_bar_offset_x` | 132, −200 | Skillchain block's top-left corner, from the banner centre (set by `//cw move`) |
| `sc_bar_size` | 18 | Bar size |
| `sc_bar_width` | 18 | Bar length in characters |
| `sc_bar_font` | Consolas | **File only.** Bar font (keep it monospaced) |
| `sc_bar_label_size` | 15 | `SC Window:` size |
| `sc_bar_label_overlap` | 20 | `SC Window:` text below the bar |
| `sc_bar_delay` | 3.0 | Wait time when a WS has no known delay |
| `sc_bar_shake_duration`, `sc_bar_shake_strength` | 0.35, 5 | **File only.** Shake when the bar turns GO |
| `sc_bar_burst_window` | 0 | Chain reset window for two different actions (0 = off) |
| `sc_chain_counter_enabled` | true | **File only.** Show `Chain: N` |
| `sc_chain_counter_size`, `sc_chain_counter_gap` | 18, 6 | `Chain: N` size and gap |
| `sc_detail_enabled` | true | Show the top part of the block: Step / properties / closer list (`//cw scdetail`) |
| `sc_detail_size` | 13 | Closer list size |
| `sc_detail_font` | Consolas | **File only.** Closer list font (keep it monospaced so columns line up) |
| `sc_color` | true | Coloured skillchain names |
| `sc_aeonic` | false | Assume others have Aeonic weapons |
| `Show` | see section 5 | Per-job parts: each of `burst`, `pet`, `props`, `spell`, `step`, `timer`, `weapon` lists the jobs it's on for, e.g. `<pet>BST,SMN</pet>` |

### Magic Burst popup

| Key | Default | Meaning |
|---|---|---|
| `mb_enabled` | true | Show MB popups |
| `mb_party` | true | Include party members' bursts |
| `mb_max_lines` | 4 | **File only.** How many simultaneous bursts stack |
| `mb_size` | 24 | Text size |
| `mb_offset_x`, `mb_offset_y` | 95, 101 | MB popup position from the banner centre (set by `//cw move`) |
| `mb_duration` | 3.0 | **File only.** Seconds on screen |
| `mb_fade_in_duration`, `mb_fade_out_duration` | 0.15, 0.35 | **File only.** Fade times |
| `mb_shake_duration`, `mb_shake_strength` | 0.5, 5 | **File only.** Shake when a burst lands |

### Tracking and party panel

| Key | Default | Meaning |
|---|---|---|
| `banner_mode` | self | `self` or `party` |
| `show_banner_avg` | false | Show the `Avg:` line on the banner (`//cw avg`) |
| `sc_closer_rows` | 4 | Max closer-list rows (`//cw sc rows`, 0 = all) |
| `track_pets` | true | Count pets |
| `track_trusts` | false | Count trusts |
| `track_alliance` | false | Count alliance members |
| `aoe_sum` | false | Add up AoE damage across all targets |
| `ws_blacklist` | Starlight,Moonlight,Myrkr,Dagan | WSs kept out of stats (comma-separated, exact names) |
| `auto_reset` | true | Clear stats on zoning |
| `party_panel` | false | Show the party panel |
| `party_panel_fade` | false | Fade the panel with the banner |
| `party_panel_size` | 13 | Panel text size |
| `party_panel_font` | Consolas | **File only.** Panel font (keep it monospaced) |
| `party_panel_offset_x`, `party_panel_offset_y` | 260, 0 | Panel position relative to the banner centre |
| `party_panel_rows` | 8 | **File only.** Max rows per section |

### No longer used

`pending_timeout`, `flair_duration`, `sc_window`, `sc_bar_max_step`,
`sc_anchor_ratio` and `sc_gap` remain in the file so 2.0 settings load cleanly, but
nothing reads them. Chains now close after step 5 or at Lv.4, as in
SkillChains.

The chain line ("Chain 2: Light (…)") was removed; the skillchain block shows
the same information. Any `sc_chain_info_*` or `sc_detail_gap` keys left in
an older settings file are ignored. `//cw testsc`, `//cw scinfogap` and
`//cw scdetailgap` now just say so.

---

## 7. What gets counted, and how

**Who counts**

| Actor | WS stats / banner | MB tallies | Skillchain tracking |
|---|---|---|---|
| You | always | always | always |
| Party members | always | always | always |
| Alliance members | if `alliance on` | if `alliance on` | always |
| Pets | if `pets on` | if `pets on` | always |
| Trusts | if `trusts on` | if `trusts on` | always |
| Anyone else | never | never | always (a stranger's WS on your mob still changes its chain) |

**What counts as a WS hit**

- A weapon skill (or a pet's or trust's TP move) that **damages** the target,
  including HP-drain WSs like Sanguine Blade.
- A **miss** or "no effect" counts as a WHIFF: it shows on the banner and
  resets the CRANKED streak, but doesn't change the average.
- Heals, buffs, MP/TP-drain WSs and status moves are ignored.
- Blacklisted WSs never touch stats or the banner, but still open and close
  skillchains.
- AoE WSs count the main target's damage unless `aoesum` is on.

**Magic Bursts**

- Any damaging burst counts: spells, Lunge/Swipe, Quick Draw, blood pacts,
  weapon-skill bursts. HP-drain bursts don't.
- The **popup** shows bursts on your current target. The **tally** counts
  every burst on any mob.

**Averages and streaks** are kept per player. In `party` banner mode, the
average, trend and CRANKED streak shown belong to whoever's WS is on screen.

**Stats reset** with `//cw reset` (or `reset ws` / `reset mb`), and on zoning
while `autoreset` is on. Test commands never change stats.

---

## 8. Troubleshooting

**`//cw stats` printed text but nothing appeared on screen.**
That's by design: it prints to chat. The on-screen board is the party panel
(`//cw party on`), which appears once something is recorded.

**Nothing shows when I weapon skill.**
- Check it's loaded: `//lua l crankwatch`.
- Try `//cw test`. If that shows, display works; check `//cw bannermode` and,
  for party members, that they're in your party (or `alliance on`).
- If you used `//cw hide`, it stays hidden until `//cw show` or your next WS.

**I see two skillchain HUDs.**
SkillChains is still loaded: `//lua u skillchains`.

**In move mode I can't tell what is what.**
Each part has a coloured box and a name tag; hover to highlight one. Chat
lists every part when you enter move mode. See section 4 for why parts
overlap by default.

**Dragging one part moved another.**
That was fixed: the Banner, Skillchain block, party panel and MB popup each
move on their own. If parts overlap, grab the one you want by its name tag.
After updating, run `//cw resetpos` once, because parts are now placed
differently.

**The party panel or skillchain block is off screen, or my layout is a mess.**
`//cw resetpos` puts everything back in its default place without touching
your other settings. Or use `//cw move` and drag parts back.

**The banner and party panel are still up after the fight.**
That's by design:

- The **banner** holds for 60 seconds after a WS, then fades out over 5.
  Shorten it with `//cw fadetime <hold> <fade>`, e.g. `//cw fadetime 10 3`,
  or use `//cw killfade on` to clear it about a second after the mob dies.
- The **party panel** stays while it has data, so you can read the totals
  after a fight. To clear it, use `//cw reset` (it hides once empty). To have
  it fade with the banner instead, use `//cw party fade on`.
- Zoning clears both while `//cw autoreset` is on.

**My stats include hits I didn't do.**
Builds before this one recorded test commands as real hits. `//cw reset` clears them.

**Chat shows `Action error (please report): …`**
Something in a packet wasn't handled. Note the text and the situation (job,
what was used). CrankWatch keeps running.

---

## 9. Running the offline tests

Optional, for development. The tests load Windower's real libraries and
resources under LuaJIT:

```
git clone --depth 1 https://github.com/Windower/Lua.git
git clone --depth 1 https://github.com/Windower/Resources.git
WINDOWER_LUA=$PWD/Lua/addons/libs WINDOWER_RES=$PWD/Resources/resources_data sh tests/run.sh
```
