# CrankWatch 3.0

Packet-driven weapon skill tracker for Windower 4, with a built-in port of
Ivaar's **SkillChains**.

**Unload the separate SkillChains addon** (`//lua u skillchains`, and remove
it from your autoload). CrankWatch now includes it, and running both shows two
SC HUDs.

## Install

Copy these five files into `Windower/addons/CrankWatch/`:

| File | What it does |
|---|---|
| `CrankWatch.lua` | Entry point: settings, events, `//cw` commands, packet pipeline |
| `skills.lua` | Ivaar's skill tables (Aeonic typos fixed) and resource hydration |
| `sc_engine.lua` | Ivaar's resonance engine (per-target chains, timers, closers, Aeonic, Immanence, Chain Affinity) |
| `party_tracker.lua` | Party/alliance roster, pet/trust rules, per-actor and per-WS stats |
| `ui_hud.lua` | All text objects, layout and animations |

Don't copy a `data/settings.xml`. Your existing one keeps working: saved
positions, fonts and sizes are kept, and new settings get their defaults the
first time CrankWatch saves.

**One saved value to check.** 2.0 saved `sc_bar_burst_window = 0.45`. 3.0's
default is `0` (off), but your saved value wins. To match the new default:

```
//cw scburst 0
```

## Moving the HUD: `//cw move`

`//cw move` shows every part filled with sample data. Drag any part with
the left mouse button; it saves when you let go. Run `//cw move` again to
finish.

- Drag the `Last WS` line to move the whole HUD.
- Every other part moves on its own: damage line, average line, hit flair,
  SC Bonus, SC bar, chain line, closer list, party panel and MB popup.
- Clicks on empty space still reach the game. WSs that land while you're
  dragging are still recorded; they just don't replace the sample.

## Recommended: your WSs, your party's WSs and party MBs

```
//cw bannermode party   every party WS on the banner, with the player's name
//cw party on           running per-player count / average / peak
//cw mbparty on         party mages' bursts, named (on by default)
//cw trusts on          only if you play with trusts
//cw move               place the party panel and MB popup
```

Pets and alliance members are tracked by default (`//cw pets`,
`//cw alliance`). MBs pop for your current target only. Bursts that land
together stack, up to 4 lines (`mb_max_lines` in settings). In a busy
alliance, `bannermode self` with the party panel on is calmer.

## What changed from 2.0

- **No chat parsing.** WS damage, SC Bonus and Magic Burst all come from
  action packets, so Battlemod and the damage-display setting can't break it.
- **Party tracking.** Party and alliance members' WSs are recorded. Pets are
  on by default (`//cw pets`). Trusts are off by default (`//cw trusts`).
  Only damaging moves count, not heals or buffs.
- **Banner modes.** In `//cw bannermode self` (the default), only your WSs show
  on the banner. In `party` mode, everyone's do, labelled with their name; the
  average, trend and CRANKED streak follow whoever is on screen.
- **Party panel** (`//cw party on`): per-member WS count, average and peak,
  plus Magic Burst tallies. It stays on screen while it has at least one WS
  or burst recorded, and hides itself when empty (fresh load, `//cw reset`,
  zoning with autoreset on). `//cw party fade on` makes it fade with the
  banner instead. `//cw testparty` shows sample rows for 10 seconds.
- **SkillChains parity.**
  - Chains are kept per target, so switching targets no longer resets them.
  - Wait/Go/Burst timers.
  - A list of what to use next and what it makes.
  - Aeonic Lv4 (`//cw scaeonic` assumes other players have their Aeonic weapon).
  - SCH Immanence, BLU Chain Affinity, pet moves and Chainbound.
- **SC HUD independent of the banner** (`//cw schud`, on by default): the bar
  appears as soon as anyone opens a chain on your target.
- **Per-job SC display toggles**, as in SkillChains:
  `//cw sc burst|pet|props|spell|step|timer|weapon` toggles that part for
  your current job, and `//cw sc color` toggles coloured property text.
- **AoE**: the main target's damage by default; `//cw aoesum on` sums all
  targets.
- **Blacklist**: `//cw blacklist add|remove|list <ws>`. Blacklisted WSs stay
  out of stats and the banner but still open and close skillchains. Defaults:
  Myrkr, Dagan, Starlight, Moonlight.
- **Layout**: the closer list sits under the chain line, and flips above the
  `Last WS` line if it would run off the bottom of the screen
  (`//cw scdetailgap`, `//cw scdetailsize`). The party panel docks right of
  the banner, or left if it would run off screen (`//cw partypos dx dy`).
- `//cw hide` now keeps everything hidden, the SC HUD included, until
  `//cw show` or your next WS.
- Party members' Magic Bursts pop with the caster's name, and simultaneous
  bursts stack (`//cw mbparty on|off`).
- **Magic Burst tallies**: every party member's bursts, on any mob, are
  counted per caster (count, average, peak) in a second section of the party
  panel and in `//cw stats`.
- **Resetting**: `//cw reset` clears WS stats, averages and MB tallies.
  `//cw reset ws` or `//cw reset mb` clears just one. Zoning still resets
  everything while `//cw autoreset` is on.
- Test commands (`//cw test`, `testmassive`, ...) only change the display.
  They never touch your stats or peaks.
- `//cw stats` prints the per-member breakdown to chat.
- `//cw debug` also prints action message IDs CrankWatch doesn't recognise.

Every 2.0 command still works. `pending_timeout`, `sc_window` and
`flair_duration` no longer do anything, but stay in settings so old files load
cleanly. `sc_chain_info_duration` now sets how long `//cw testsc` holds its
line.

## Running the tests (optional, offline)

The tests load Windower's real libraries and resources under LuaJIT:

```
git clone --depth 1 https://github.com/Windower/Lua.git
git clone --depth 1 https://github.com/Windower/Resources.git
WINDOWER_LUA=$PWD/Lua/addons/libs WINDOWER_RES=$PWD/Resources/resources_data sh tests/run.sh
```
