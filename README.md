# Outbreak Zero

An **asymmetrical infection PvP** game for Roblox — a hub-based "outbreak" shooter
where **Survivors** fight to stay human and the **Infected** spread the mutation.

> **North star:** a Roblox **smash hit that's genuinely fun for kids 6–15.** Every
> system is built for **instant readability** (you should understand it with zero
> reading), fast fun, and **platform safety** (sci-fi containment theme, no
> chat-dependent design, fair cosmetic-only monetization — many players are under 13).

## The loop

1. **Hub** — everyone spawns in a social hub. Step on the green **queue pad** to join the Outbreak queue (`X / Y`).
2. **Queue pops** — when enough players queue, an alarm blares, the pad drops like an airlock, and that roster is pulled into the **arena** (everyone else keeps hanging out in the hub).
3. **Prep → Action** — a random **Patient Zero** is chosen; everyone else is a Survivor.
4. **Infection meter** — standing near an Infected fills your meter (orange→red); escape and it decays. At **100%** you go **DOWNED**.
5. **Downed & rescue** — a teammate holds **Rescue** to revive you (a green world-space beacon marks you) — *unless* an Infected is guarding. Don't get rescued in time → you **convert**.
6. **Combat** — Survivors have a **Pulse Rifle** + **Stun Baton**. Damaging an Infected **stuns** it for a few seconds (it can't infect or guard) — never kills it. Shoot the guard to free a downed ally.
7. **Win** — Infected win by converting everyone; Survivors win by outlasting the timer. Then back to the hub.

---

## Project layout (Rojo + Luau)

Code lives here as `.luau` files; Rojo live-syncs them into Roblox Studio. Architecture is
**plain ModuleScript services + a bootstrap registry** (`Initialize`/`Start`), the 2026
community-standard alternative to a framework. **The server decides everything; the client
only draws UI and sends intent** — never trust the client.

```
C:\Claude\
├── default.project.json     # maps src/ into Studio
├── rokit.toml               # pins rojo / stylua / selene
├── selene.toml · stylua.toml · .gitignore
└── src/
    ├── shared/              -> ReplicatedStorage
    │   ├── Config/  GameConfig · RoundConfig · InfectionConfig · CombatConfig   # ⭐ all tunables
    │   ├── Round/RoundState.luau   · Types.luau   · Net.luau                    # remotes
    ├── server/              -> ServerScriptService
    │   ├── Main.server.luau                # bootstrap registry
    │   └── Services/
    │       ├── HubService          # social hub + matchmaking queue + queue-pop spectacle
    │       ├── RoundService        # match state machine, runs a roster through Prep→Action→Results
    │       ├── InfectionService    # infection meter, downed/rescue, conversion
    │       ├── CombatService       # weapons, server-auth damage, infected health → stun
    │       ├── MapService          # builds the hub + arena, moves players
    │       ├── TeamManager         # Survivors / Infected teams
    │       └── EconomyService      # coins (leaderboard)
    └── client/              -> StarterPlayer/StarterPlayerScripts
        ├── ClientMain.client.luau
        └── Controllers/  RoundHudController (HUD/meter/downed) · CombatController (weapons/crosshair)
```

Per-player state that the HUD reacts to (`InMatch`, `Queued`, `Infection`, `Downed`, `Health`,
`Stunned`) is stored as **instance Attributes** — cheap to replicate, no polling.

---

## Running it

The toolchain is **already installed** (Rokit + Rojo 7.6.1, StyLua, Selene), and Roblox
Studio + the Rojo plugin are set up. To play:

1. In `C:\Claude`, start the live-sync server (leave it running):
   ```powershell
   rojo serve
   ```
2. In **Roblox Studio**: open a Baseplate place → open the **Rojo** panel → **Connect**.
3. **Test ▸ Clients and Servers ▸ 2–3 players ▸ Start.** (A match needs 2+ queued; the
   downed/rescue/standoff combo is best seen with 3.) Keep **View ▸ Output** open for logs.

> Studio is the only thing you do by hand — everything else (lint/format/build) is automated.

---

## Tuning (no code changes needed — edit, re-Play, Rojo live-syncs)

| File | Controls |
|---|---|
| `src/shared/Config/RoundConfig.luau` | min players, prep/action/results timers, patient-zero ratio |
| `src/shared/Config/InfectionConfig.luau` | meter fill/decay, contact range, spawn immunity, bleed-out, rescue time, guard range |
| `src/shared/Config/CombatConfig.luau` | weapon damage/range/cooldown, infected health, stun duration |
| `src/shared/Config/GameConfig.luau` | walk speeds, team colors, coin rewards |
| `src/shared/Config/ProgressionConfig.luau` | XP curve, per-match XP, daily-login reward ladder |

---

## Roadmap

**Done:** core architecture · social hub + matchmaking · infection meter · downed-and-rescue ·
combat (weapons + infected stun) · world-space readability cues.

**Next (each its own playtested phase):**
- **Phase 4 — Classes & abilities _(in progress)_:** Assault / Medic (human) + Bruiser / Stalker (infected) — signature abilities (Frag Grenade / Cleanse Beam / Ground Slam / Cloak Lunge), cooldowns, and a class-select screen.
- **Phase 5 — Objectives & modes:** the full Outbreak mode (objectives + extraction), anti-snowball comeback mechanics.
- **Phase 6 — Maps & hazards:** real hand-built maps, hazard zones, map rotation/voting.
- **Phase 7 — Progression & data _(in progress)_:** ✅ persistent coins + XP/level (DataStore via a `Persistence` lib with a Studio in-memory fallback so it works without API access), round-end XP awards, daily-login rewards, and a client Level/XP HUD. ⏳ Remaining: unlock-gating wired into `ClassService`, contracts, and (optionally) swapping the `Persistence` lib for real ProfileStore for cross-server session locking.
- **Phase 8 — UX/social/polish:** tutorial, ping system, end-of-round commendations, VFX/SFX/juice.
- **Phase 9 — Monetization & live-ops:** cosmetic shop, fair gamepasses, seasonal events.

---

## Safety & monetization principles (non-negotiable for the audience)

- Sci-fi **containment/mutation** framing — stylized and creepy, **not** fetish-coded.
- **No chat-dependent gameplay** — teamwork runs through pings + world-space cues.
- **Cosmetic-first, no pay-to-win** monetization.
- Keep all content Roblox-policy / COPPA appropriate.

---

## Troubleshooting

- **`rojo` not recognized** → open a new terminal (PATH updates after Rokit install).
- **Studio won't connect** → ensure `rojo serve` is running and the **v7** Rojo plugin is installed.
- **`rojo plugin install` says "couldn't find registry keys"** → launch Roblox Studio once (sign in) so it registers, then re-run.
- **"address already in use"** → a `rojo serve` is already running; reuse it or `rojo serve --port 34873`.
