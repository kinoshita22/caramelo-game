# My Caramelo

Idle growth game built with Godot 4.4.1 (GDScript, Compatibility renderer).
Caramelo trains on his own on a floating island shown as a transparent desktop
overlay. The design is in `../Caramelo_Game_Development_Master_Plan.md`.

- Design canvas: 1920×1080. Development window: 1280×720.
- Target: desktop, Windows first.

## Repository layout

```text
assets/
  source/          Immutable local mirror of ../00 (.gdignore, git-ignored)
  runtime/         Hash-verified copies the game actually loads
    characters/ environment/ equipment_food/ ui/ button_states/ effects/ audio/
data/              JSON the game reads; owns all tuning values and asset mappings
  catalog/ forms/ animations/ balance/ equipment/ food/
scenes/            boot/ main/ character/ environment/ ui/ effects/
scripts/
  autoload/        Singletons (AppState, GameState, SaveManager, ContentCatalog, ...)
  components/      Reusable node behaviours (CharacterAnimator, InteractionZone, ...)
  systems/         Simulation logic with no UI or scene dependencies
  platform/        Windows / wallpaper adapter boundary
  tools/           Shared helper classes used by the tools below
tools/             Headless command-line entry points (inventory, ingestion)
tests/             Automated tests
docs/              Generated reports and design notes
```

## Asset pipeline

The original art lives outside the project in `../00` and is never modified.

| Path | What it is | Imported by Godot |
|---|---|---|
| `../00/` | Original packs as delivered. Read-only. | No (outside project) |
| `assets/source/` | Byte-for-byte local mirror of `../00`. | No (`.gdignore`) |
| `docs/asset_inventory.*` | Inventory and validation report. | — |
| `docs/ingestion_report.json` | Result of the last ingestion run. | — |

Run these from the workspace root (the folder containing `00/` and `caramelo-game/`):

```sh
# Validate the original packs (exit 0 = no unexpected issues)
godot --headless --path caramelo-game --script res://tools/asset_inventory.gd -- --source ../00 --out docs

# Mirror them into assets/source (safe to rerun; never overwrites or deletes)
godot --headless --path caramelo-game --script res://tools/ingest_assets.gd -- \
    --source ../00 --destination assets/source --runtime-form 01
```

If ingestion reports a **conflict**, a file in `assets/source/` differs from the
original. The tool leaves it alone. Inspect it, then fix it by hand.

## Large source assets

`assets/source/` is about 460 MiB of PNGs (430 files), and more forms and packs
may follow. Committing that as regular git objects makes clones and history slow.
Git LFS is **not** enabled. Choose one of these strategies:

1. **Keep `assets/source/` local and ignored; version only runtime assets.**
   Add `assets/source/` to `.gitignore`. Each developer rebuilds the mirror from
   the original packs with `tools/ingest_assets.gd`. The repository versions only
   the runtime assets and metadata that the game loads. This keeps the repository
   small, but the original packs must be distributed some other way (shared drive,
   release archive).
2. **Track `assets/source/` with Git LFS.**
   Run `git lfs install` and `git lfs track "assets/source/**/*.png"`, then commit
   the updated `.gitattributes`. The originals are versioned alongside the code,
   but every clone needs LFS and the hosting LFS quota must allow about 460 MiB
   and up.

Either way, never edit files in `assets/source/` directly.
