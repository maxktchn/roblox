# Kitchen Chaos

A survivors-style roguelike for Roblox: you're a chef surviving a 10-minute dinner shift against living rotten food. Full design in [docs/PRD.md](docs/PRD.md).

**Current phase:** Phase 1 — playable run prototype (PRD §9).

## Setup (once)

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then from the repo root:
   ```sh
   rokit install
   ```
   This installs the pinned versions of Rojo, StyLua, Selene and luau-lsp from `rokit.toml`.
2. Install the Rojo Studio plugin: `rojo plugin install`
3. In VS Code, install the recommended extensions (VS Code will prompt you; list is in `.vscode/extensions.json`).
4. Turn off Studio's own *Format On Type/Paste* so it doesn't fight StyLua.

## Daily workflow

```sh
rojo serve
```
Then in Studio open the dev place, open the Rojo plugin, and click **Connect**. Edit code in VS Code; Rojo syncs it into Studio live.

- **Code lives in this repo.** Only edit scripts in files, never in Studio — Rojo overwrites Studio edits in synced folders.
- **The world lives in the place.** Maps, models, lighting and hand-built UI are built in Studio and saved with Studio's version history. Rojo ignores `Workspace`.
- Once the dev place exists, put its place ID in `servePlaceIds` in `default.project.json` so Rojo can't sync into the wrong place.

## Checks (CI runs these on every PR)

```sh
stylua src                 # format (or format-on-save in VS Code)
selene src                 # lint
rojo build -o build.rbxl   # project builds
```

## Where things go

| Folder | In Studio | What goes there |
|---|---|---|
| `src/config/` | `ReplicatedStorage.Config` | All game content as data tables (weapons, enemies, bosses, chapters, gear, tuning numbers) |
| `src/shared/` | `ReplicatedStorage.Shared` | Code used by server and client (remotes list, config checks) |
| `src/server/` | `ServerScriptService.Server` | `Main.server.luau` (the one server Script) + `Services/` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | `Main.client.luau` (the one LocalScript) + `Controllers/` |

File names: `Foo.luau` = ModuleScript, `Foo.server.luau` = Script, `Foo.client.luau` = LocalScript.
