# WoW Forever addon development

Target: **World of Warcraft: Forever** (launched 2026-11-04). Year-one Classic content on the modern Midnight (12.x) client.
- TOC `## Interface: 16001`. Client version 1.60.x. Game type `Camelot` (TOC suffix `_Camelot.toc` or `_Forever.toc`).
- `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18). That constant exists only on Forever, so check `WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`.
- The API is modern retail, **including Midnight's restrictions**. Classic-era addon code (old `GetSpellInfo`, `UnitAura` etc.) often won't work. Look up the modern `C_*` namespaces.
- To support retail too: `## Interface: 120100, 120105, 16001`.

## Layout
- `addons/<Name>/`: our addons. Each one is symlinked into the game:
  `ln -s "$PWD/addons/<Name>" "$WOW/Interface/AddOns/<Name>"`
- `WOW=/home/pedrohcg/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_` (Wine/Battle.net)
- `$WOW/Interface/AddOns/`: installed third-party addons (Questie, EllesmereUI, LayerSwap…). Use them as real Forever examples.
- `$WOW/WTF/Account/*/SavedVariables/`: saved data, readable after /reload or logout.

## Reference (read these, don't guess APIs)
- `reference/wow-ui-source-forever/`: Blizzard's own UI code for Forever (Gethe/wow-ui-source, branch `forever`).
  - `Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`: **authoritative API signatures**, including `SecretArguments`/`SecretReturns`/`SecretWhen*Restricted` flags. Grep here first.
  - The rest is FrameXML: copy patterns from it (templates, mixins, Settings panel).
- `reference/wow-ui-source-retail/`: same for retail (branch `live`), for diffing.
- `reference/vscode-wow-api/Annotations/`: LuaLS type annotations for the whole API (`.luarc.json` points at them).
- `reference/Ace3/`: Ace3 libs (AceAddon, AceDB, AceConfig, AceGUI…). TOC already lists 16001. Embed under `Libs/` only when an addon needs it.
- `reference/wiki/*.wiki`: warcraft.wiki.gg raw pages: TOC_format, Secret_Values, Patch_12.0.0_API_changes, Events, World_of_Warcraft_API (full function list), Widget_API, Secure_Execution_and_Tainting, Handling_events, Saving_variables..., Localizing_an_addon, UI_escape_sequences.
  Refresh a page: `curl -sL "https://warcraft.wiki.gg/wiki/<Page>?action=raw"`.
- Update the git clones with `git -C reference/<dir> pull` after game patches.

## Hard rules of the platform
- Lua 5.1 (no `goto`, no integer division `//`, no bitwise operators. Use `bit.band` etc.).
- `local addonName, ns = ...` at file top. `ns` is the shared private table across the addon's files. Avoid globals; prefix the ones you need (SavedVariables, `SLASH_*`, frame names).
- SavedVariables are only loaded at `ADDON_LOADED` (arg1 == addonName). Never read them at file scope.
- **Secret values (12.x/Forever):** combat APIs (unit health/power/auras/casts/cooldowns, damage meters…) may return secrets in combat or in instances. Tainted (addon) code can store, pass and concatenate them, and give them to whitelisted widgets (`StatusBar:SetValue`, `FontString:SetText`). It **cannot** compare, do arithmetic, use `#`, or use them as table keys. That fails with an immediate Lua error. Test with `issecretvalue(v)`. Check an API's doc file before writing logic on its return values. Automating combat decisions is effectively impossible by design.
- **Combat lockdown / taint:** protected frames (action buttons, unit frames, anything secure) can't be shown/moved/created in combat. Guard with `InCombatLockdown()`; defer to `PLAYER_REGEN_ENABLED`. Use `hooksecurefunc` rather than replacing Blizzard functions.
- Options UI: modern `Settings` API (`Settings.RegisterVerticalLayoutCategory`/`RegisterCanvasLayoutCategory`); `InterfaceOptions_AddCategory` is gone.

## Dev loop
1. Edit, then `luajit -bl file.lua >/dev/null` for a quick syntax check.
2. In game: `/reload` (TOC changes or new files need a full client restart).
3. Show errors: `/console scriptErrors 1`, or install BugGrabber+BugSack. `/dump expr` inspects values, `/fstack` inspects frames, `/etrace` shows the live event log.
