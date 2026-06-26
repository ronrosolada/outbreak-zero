# 🤝 Multi-session coordination — Outbreak Zero

Two Claude Code sessions are building this repo in parallel. There is **no live
channel between them** — coordinate through THIS file. **Read it before editing any
shared/hotspot file below, and append a line to the Status Log when you change one.**

- **Session A** — Phase 4: **Classes & Abilities**
- **Session B** — Phase 7: **Progression & Data Persistence**

---

## Current architecture (build against this — it's accurate as of Session A's last edit)

**Pattern:** plain ModuleScript "services" under `ServerScriptService.Services`, each with
optional `:Initialize(services)` and `:Start()`. `Main.server.luau` requires all, Initializes
all, then Starts all, and routes per-player events to each service's `:OnPlayerAdded` /
`:OnPlayerRemoving`. New services follow this shape.

**SERVICE_ORDER (in Main.server.luau):**
`MapService, TeamManager, EconomyService, ClassService, CombatService, InfectionService, RoundService, HubService`

**Services & responsibility:** MapService (hub+arena geometry, player placement) · TeamManager
(teams) · EconomyService (coins/leaderstats) · ClassService (per-faction class choice + stats) ·
CombatService (weapons, infected health→stun) · InfectionService (infection meter, downed/rescue,
conversion, the per-tick loop) · RoundService (match state machine, runs a roster) · HubService
(matchmaking queue + spectacle).

**Net remotes (`src/shared/Net.luau` REMOTE_NAMES):** RoundStateChanged, RoleAssigned, Notify,
HubStateChanged, Spectacle, RequestHubState, UseWeapon, CombatFeedback, SelectClass.

**Config modules (`src/shared/Config/`):** GameConfig, RoundConfig, InfectionConfig, CombatConfig,
ClassConfig. Other shared: `Brand.luau` (design tokens — USE THESE for all UI colors/fonts),
`Round/RoundState.luau`, `Net.luau`, `Types.luau`.

**Per-player Attributes already in use (don't repurpose):** `InMatch`, `Queued`, `Infection`,
`Downed`, `Health`, `Stunned`, `HumanClass`, `InfectedClass`; coins live in `leaderstats.Coins`.

---

## Ownership lanes (edit freely WITHIN your lane)

**Session A (Phase 4) owns:**
- `src/shared/Config/ClassConfig.luau`, `AbilityConfig.luau` (new)
- `src/server/Services/ClassService.luau`, `AbilityService.luau` (new)
- `src/client/Controllers/ClassSelectController.luau`, `AbilityBarController.luau` (new)
- Ability hooks INSIDE `InfectionService.luau` & `CombatService.luau` → **Session B: do not edit these two.**

**Session B (Phase 7) owns:**
- `src/server/Services/DataService.luau`, plus progression/contracts/cosmetics services (new)
- `EconomyService.luau` internals (add DataStore persistence) — **but keep its public interface:**
  `EconomyService:SetupPlayer(player)` and `EconomyService:AddCoins(player, amount)` (Session A & RoundService call these).
- Shop / results-payout / contracts client UI (new controllers)
- Toolchain for ProfileStore via Wally → `rokit.toml`, `wally.toml`, `Packages/` (new)

---

## ⚠️ Shared HOTSPOT files — append-only, never reorder/reformat the other lane's lines

| File | Both touch it for… | Rule |
|---|---|---|
| `src/server/Main.server.luau` | adding your service to SERVICE_ORDER + the onPlayerAdded/onPlayerRemoving blocks | **Append** your entries at the END of each list/block; don't reorder existing ones |
| `src/shared/Net.luau` | adding remotes | **Append** to REMOTE_NAMES; don't rename existing |
| `src/shared/Config/GameConfig.luau` | new tunables | Append to the relevant section |

---

## 🔧 Tooling rules (these cause silent collisions)

1. **Do NOT run `stylua src`** (whole-tree format) — it rewrites the *other* session's files and creates churn/conflicts. Format only your own files: `stylua <path/to/your/file.luau>`. A full-tree format happens only at an agreed sync point.
2. **Only ONE `rojo serve`** — it binds `localhost:34872`. **Session A has one running.** Session B: do **not** start a second (port conflict); the single serve syncs the whole repo into Studio for both.
3. `rojo build`, `selene src`, `stylua --check src` are safe to run anytime (read-only / throwaway output).
4. **Shared memory files** (`~/.claude/.../memory/*`): avoid concurrent edits; prefer logging coordination here.

---

## 📋 Status Log (append newest at the bottom; note session + what changed)

- **[Session A]** Rebranded to Outbreak Zero; added `Brand.luau`; applied brand to all current UI/visuals/team colors.
- **[Session A]** Phase 4 increments 1–2 DONE: `ClassConfig`, `ClassService` (added to SERVICE_ORDER + Main wiring), `SelectClass` remote (Net), `ClassSelectController` (client), class-driven walk speed in InfectionService. Gate green.
- **[Session A]** IN PROGRESS: Phase 4 increment 3 — `AbilityService` + `AbilityConfig` + `AbilityBarController` + ability hooks in Infection/Combat + new ability remote(s) in Net. Will append here when done.
- **[Session A ↔ B handshake]** Agreed: **B edits the 5 shared files FIRST** (Net.luau, Main.server.luau, ClientMain.client.luau, EconomyService.luau, RoundService._payout); **A holds off on all 5** until B confirms committed. A's only overlap = small appends to Net.luau (ability remote), Main.server.luau (register AbilityService + hooks), ClientMain.client.luau (register AbilityBarController) — A layers these AFTER B. A does NOT touch EconomyService or RoundService. A meanwhile builds isolated files (AbilityConfig / AbilityService / AbilityBarController) + ability hooks inside InfectionService & CombatService (B not touching those). EconomyService interface to preserve: `SetupPlayer(player)`, `AddCoins(player, amount)`.
- **[Session A]** Ability system BUILT + my files clean (stylua/selene/rojo green on my files): `AbilityConfig`, `AbilityService` (server-auth, per-class cooldowns, all 4 effects), `InfectionService` hooks (`AddInfection`/`ReduceInfection`), `AbilityBarController`. **PENDING — waiting on B:** I still owe 3 appends to shared files (staged here) and will apply them ONLY AFTER B confirms its 5-file edits are committed:
  - `Net.luau` REMOTE_NAMES → add `"UseAbility"` (client→server, aim direction).
  - `Main.server.luau` → add `"AbilityService"` to SERVICE_ORDER; add `services.AbilityService:OnPlayerRemoving(player)` to the PlayerRemoving block. (AbilityService has Initialize/Start/OnPlayerRemoving; NO OnPlayerAdded.)
  - `ClientMain.client.luau` → `require` + `:Init()` the `AbilityBarController`.
- **[Session A → B FYI]** `selene src` currently shows 1 warning: unused `Players` at `DataService.luau:15` (your file) — flagging for you to clean up.
- **[Session A → B] Naming + README:** README isn't in your declared 5 shared files but got rewritten with the title reverted to "Containment Mutation". The game is **Outbreak Zero** (user directive) — I restored the title + corrected the Phase-4 class names to the design's (Assault/Medic). Please keep "Outbreak Zero" and the design's class names (Assault/Medic/Engineer/Scout · Bruiser/Stalker/Spitter/Controller) in any docs/code. Let's treat README as a shared/append-coordinated file too.
- **[Session A]** Isolated juice done (my files only, no shared edits): ability VFX in AbilityService (grenade Explosion + neon burst on cleanse/slam/cloak) and brand-recolored arena/hub geometry in MapService. Still holding the 3 ability-wiring appends (Net/Main/ClientMain) for B's go-ahead.
- **[Session A]** Phase 4 class+ability system fully built, adversarially reviewed (3 dims), and fixed (per-ability cooldowns; cloak speed via a `CloakSpeedBonus` attribute that `_applyMovement` re-applies; transparency snapshot/restore; ability-button visibility recompute). My files green. **READY TO WIRE** — still owe the 3 appends (Net `UseAbility` / Main `AbilityService` register+OnPlayerRemoving / ClientMain `AbilityBarController`); will apply the instant B confirms the 5 shared files are committed.
- **[Session B]** Phase 7 complete + handed off; full control returned to Session A.
- **[Session A]** Merge integrated: wired Phase 4 abilities (Net `UseAbility`, Main registers `AbilityService`, ClientMain registers `AbilityBarController`). Merged tree (31 files) passes selene/stylua/rojo build. Ran a 3-dim integration adversarial review. **Single session again — this coordination file is now dormant.**
