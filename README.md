# fs-cheat-menu

An in-mission cheat menu for [FreeSpace Open](https://www.hard-light.net/), written as a
Lua script hook. Invulnerability, wingman and escort protection, stealth, and a few
mission-unsticking tools, on a HUD menu you open with **Shift+Alt+I**.

It is inert until you open it: no gauge, no key claimed, no behaviour changed.

## Install

Copy the `data` folder into your FreeSpace 2 root — the folder holding `fs2_open.exe`
and the `.vp` files. It merges with any `data` folder already there:

```
<FS2 root>/data/scripts/zz_godmode.lua
<FS2 root>/data/tables/zz-godmode-sct.tbm
```

**Knossos users:** dropping it in the *library root* (the folder containing `bin` and
`FS2`) makes it load for every mod you launch, instead of installing it per mod. Putting
it inside a single mod folder works too if you only want it there.

That is the whole install — two files, no dependencies, nothing to enable.

To uninstall, delete those two files.

## Controls

| Key | Action |
| --- | --- |
| `Shift+Alt+I` | open / close the menu |
| `1`–`7` | pick an entry (consumed, never reaches the game) |
| `Backspace` | back to the main menu |
| `Esc` | close |

While FreeSpace's own comm menu (`C`) is open, the cheat menu hides itself and claims no
keys — number keys give orders and `Esc` closes the comm menu only. `Shift+Alt+I` still
works.

## The menu

```
CHEAT MENU                      ESCORT SHIPS (3 on list)
1  God mode      [ON ]          1  Invulnerable   [OFF]
2  Guardian      [OFF]          2  Heal to full now
3  Escort ships...              3  Keep healing    [ON ]
4  Wingmen...
5  Stealth...                   WINGMEN (3 in Alpha)
6  Scan target now              1  Invulnerable   [OFF]
7  Mission vars [OFF]           2  Heal to full now
                                3  Keep healing    [ON ]
                                4  Scope: my wing

                                STEALTH (you + 3 wingmen)
                                1  Enemies ignore me   [ON ]
                                2  Ghost (no sensors)  [OFF]
                                3  Drop enemy locks now
                                4  Hold IFF (no alarm) [OFF]
                                5  Reset IFF now
```

Toggles persist across missions until you switch them off or close the game.

### God mode / Guardian

- **God mode** — invulnerable, plus unlimited resources.
- **Guardian** — damage applies normally but hull never drops below 1%, plus unlimited
  resources.
- **Resources** means weapon energy, afterburner fuel, countermeasures, and ballistic ammo.

### Escort ships

Affects only ships on your own team. The escort gauge is a monitor list and missions add
hostiles to it as well, which is why it is filtered.

### Wingmen

Defaults to the wing you are flying in (Alpha 2/3/4 when you fly Alpha 1) — your own ship
is left to the god mode entry. **Scope** widens that when the allies who matter are not in
your wing:

| Scope | Covers |
| --- | --- |
| `my wing` | the wing you are flying in |
| `all friendly wings` | every wing on your team — the usual choice |
| `every friendly ship` | also ships in no wing: capships, stations |

Narrowing the scope hands back whatever just left it. Stealth always stays on your own
wing regardless of this setting.

### Stealth

Covers you *and* your wing.

- **Enemies ignore me** — protect-ship, the turret weapon-type protections, and the stealth
  flag. You stay on radar and mission events fire as normal; hostiles simply never select
  you. Existing locks are cleared each frame.
- **Ghost** — hidden-from-sensors. *Nothing* can target you, including your own wingmen and
  the support ship, and missions that gate events on the player being detected can stall.
  Use it only when the first level is not enough.

Neither level defuses homing missiles already in the air.

**Hold IFF** solves a different problem. Sneaking missions usually do not detect you with
sensors at all — they run a SEXP that measures distance and flips the enemy fleet to
Hostile, which no stealth flag can touch. Hold IFF snapshots every ship's team at mission
start and puts back anything that changes sides, so the alarm fires and is undone in the
same frame. Scripted chatter and directives hanging off the alarm still play; only the
hostility is reverted.

> In a mission where enemies are *meant* to reveal themselves — an ambush, a defection —
> this suppresses that and can stall the mission. Switch it on for the mission that needs
> it, not permanently.

### Scan target now

Marks the targeted ship's cargo and every one of its subsystems as scanned, for missions
that gate objectives — or a campaign branch — on scans you would otherwise have to fly in
and hold still for.

Scanning a *ship* and scanning its *subsystems* are different things, and missions usually
count the subsystems. Derelict's `dl3-04`, for example, gives one `@SSCount` point per
Nyarlathotep subsystem (navigation, weapons, sensors, communication) and picks the next
mission from that, not from whether you were spotted.

### Mission vars

Puts the mission's SEXP variables on the HUD — how you check whether a scan actually
registered instead of guessing.

## Engine compatibility

Tested against FSO **23.2.1**, **25.0.x**, and **26.0.0**.

Mods pin their own FSO build and the scripting API surface differs between them. On 23.2.1,
reading an API member that does not exist *aborts the process* rather than raising a
catchable Lua error, so newer calls are gated on the detected engine version instead of
being probed. On 23.2.1 two features are reduced:

| Feature | 23.2.1 | 25.0.0+ |
| --- | --- | --- |
| Heal | hull and shields only | also repairs subsystems |
| Scan target now | ship cargo only | also marks subsystems |

The engine version detected at load is written to `fs2_open.log`.

## Design notes

Every hook is wrapped in a `pcall` guard. An uncaught Lua error inside an FSO hook is
escalated by the engine and takes a release build down with it, so a failure here has to
cost you the menu and nothing else. The first distinct error is reported on screen and to
`fs2_open.log`.

Sections are guarded separately rather than under one shared guard, so a wingman does not
die because the IFF snapshot tripped over an API the current build does not have.

## License

MIT — see [LICENSE](LICENSE).
