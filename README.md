# My Caramelo

Idle growth game built with Godot 4.4.1 (GDScript, Compatibility renderer).
Caramelo trains on his own on a floating island shown as a transparent desktop
overlay. The design is in `../Caramelo_Game_Development_Master_Plan.md`.

- Design canvas: 1920×1080. Development window: 1280×720.
- Target: desktop, Windows first.

## Running

The game starts as a transparent, borderless overlay in the bottom-right
corner of the primary screen. Clicks outside the island reach the desktop.
Defaults live in `data/settings/display_defaults.json`; the island
composition and anchors in `data/environment/island_layout.json`.

```sh
godot --path caramelo-game                                   # overlay
godot --path caramelo-game -- --display-mode windowed        # normal window
godot --path caramelo-game -- --display-mode windowed --window-size 1366x768 --debug-overlay
godot --path caramelo-game -- --overlay-scale 0.75 --corner bottom_left
godot --path caramelo-game -- --screenshot shot.png          # save a frame and quit
godot --path caramelo-game -- --animation workout --form 6    # preview an animation
godot --path caramelo-game -- --animation celebration --animation-frame 1   # freeze one frame
godot --path caramelo-game -- --time-scale 10 --debug-overlay  # watch the loop quickly
godot --path caramelo-game -- --start-level 50               # start further along
godot --path caramelo-game -- --bones 5000 --equip cosmic_final --meal premium_beef_pumpkin
godot --path caramelo-game -- --open-shop food --bones 900     # open a window: food, equipment, upgrades, menu, furniture, wardrobe
godot --path caramelo-game -- --preview-cosmetic head:ui.currency_xp_star:0.28   # development check of attachment points
```

Caramelo runs himself: he trains, recovers, eats when hungry and sleeps when
tired, with no input from the player. Energy and satiety are 0-100 values
shown as the sleep and hunger bars; they steer the cycle, need no attention
from the player, and never cause failure. Rates, thresholds and durations live in `data/balance/behaviour.json`.
Passing `--animation` switches the loop off so a single group can be inspected.

Finished workouts pay XP and bones. Levels run 1-100 and the look changes
every ten levels, through an evolution the player cannot interrupt. Levels
never drop, leftover XP carries into the next level, and at level 100 the
curve ends while bones keep coming. The curve and payouts live in
`data/balance/progression.json`; reaching 100 currently takes roughly 25
hours of running, which is a placeholder until the client decides (plan §14)
and is retuned with `rewards.workout_xp` alone.

Bones buy four upgrades (strength, endurance, speed, recovery), six dumbbell
tiers and five meals, all in `data/balance/upgrades.json`,
`data/equipment/dumbbells.json` and `data/food/meals.json`. Upgrades only ever
speed the loop up: more XP per workout, longer sessions, quicker reps, shorter
rests and better meals. Nothing can be sold and no balance goes negative.
Hunger and sleep bars (the loop's satiety and energy, live) sit over the
tree; `island_layout.json` names the layer and the offset under `"hud"`. A
strip along the bottom of the island shows the level badge, the XP bar and
the bone count, with buttons for training, the wardrobe (a placeholder until
cosmetic art arrives) and the menu. The menu switches between overlay and
windowed mode and quits the game, which an overlay needs because it has no
title bar; Escape opens it too.

Clicking Caramelo opens the training window, where bones buy the four stat
upgrades. Clicking the chair or the table opens the furniture window, and the
HUD's wardrobe button opens the wardrobe. Both list items by slot, and items
not yet owned can be tried on the island or on Caramelo before buying. Adding
furniture or cosmetics is a data change only (`data/furniture/furniture.json`,
`data/cosmetics/cosmetics.json`); no variant or cosmetic art exists yet, so
the wardrobe is empty and each furniture slot holds today's piece. Cosmetics
attach to per-frame points estimated from each frame's silhouette (top of
head, eyes, neck, chest; see `frame_geometry.json`), corrected by hand in
`data/animations/attachment_overrides.json`, and hide on lying-down frames. Clicking the dumbbell rack opens the dumbbell window; clicking the
food station opens the food window. Each lists every tier with its own art, what it
does and its price; owned tiers carry a green background and the one in use is
marked. Bought items are shown in those windows only, never on the island.

To stay cheap when left running all day, the game runs at 60 FPS while
someone uses it, 20 FPS when idle (the animations never exceed 12), 15 on
battery where the system reports it (Linux today), and 5 when minimized;
`data/settings/performance.json` holds the numbers and nothing uses physics.
The menu also offers "Always on top", a "30 FPS cap" and "Start with the
computer" (installed builds only: the Windows registry Run key, or an
autostart file on Linux); all three are saved.

The game saves to `user://save.json` (on Windows,
`%APPDATA%\Godot\app_userdata\My Caramelo\save.json`) after level-ups,
evolutions and purchases, every minute, and on quitting. Writes are atomic
and keep the previous save as `save.bak.json`; a save that fails to load is
renamed aside, never deleted, and the backup is used instead. On startup the
time since the last save is played through the real behaviour loop, up to
8 hours (a placeholder in `data/balance/offline.json` until the client
decides), and a "while you were away" window sums it up. A clock that moved
backwards grants nothing. `--no-save` neither loads nor writes, and
`--save-file <path>` uses another file; use one of them with preview options
such as `--start-level` or `--bones`, which would otherwise be saved.

Keys: F3 toggles the debug overlay (layer bounds, character boxes, anchors,
stage bounds and the click-through outline); `[` / `]` cycle animation groups;
`-` / `=` cycle forms; `X` grants a level's worth of XP; `B` grants bones;
`1`-`4` buy stat upgrades; `E` / `F` buy the next dumbbell tier or meal. Animation groups, frame rates and per-frame fixes live
in `data/animations/animation_groups.json`. If the OS cannot make the window
transparent, the game falls back to windowed mode.

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
| `assets/runtime/` | Hash-verified copies the game loads: the selected form plus shared packs. PNGs only. | Yes |
| `data/catalog/runtime_layout.json` | Hand-authored: pack → runtime folder and import profile. | — |
| `data/…` (other JSON) | Generated metadata. Regenerate, never hand-edit. | — |
| `docs/asset_inventory.*`, `docs/ingestion_report.json` | Reports from the last runs. | — |

Run these from the workspace root (the folder containing `00/` and `caramelo-game/`),
in order:

```sh
# 1. Validate the original packs (exit 0 = no unexpected issues)
godot --headless --path caramelo-game --script res://tools/asset_inventory.gd -- --source ../00 --out docs

# 2. Mirror ../00 into assets/source and stage runtime copies of one form plus
#    the shared packs (safe to rerun; never overwrites or deletes). Rerun with
#    another --runtime-form to add that form.
godot --headless --path caramelo-game --script res://tools/ingest_assets.gd -- --runtime-form 01

# 3. Import the runtime textures
godot --headless --path caramelo-game --import

# 4. Regenerate the metadata in data/
godot --headless --path caramelo-game --script res://tools/build_catalog.gd

# 5. Validate metadata, runtime hashes and import settings
godot --headless --path caramelo-game --script res://tools/validate_catalog.gd

# Tests
godot --headless --path caramelo-game --script res://tests/run_tests.gd
```

If ingestion reports a **conflict**, a file in `assets/` differs from the
original. The tool leaves it alone. Inspect it, then fix it by hand.

### Import profiles

Before copying a runtime PNG, ingestion writes its `.import` file from the
pack's profile in `runtime_layout.json`. It never overwrites an existing one.
Character frames use VRAM compression (S3TC/BPTC, about 50 MiB per form instead
of about 198 MiB). The other packs are lossless for now.

### Generated metadata

| File | Contents |
|---|---|
| `data/catalog/asset_catalog.json` | Every source image: ID, hash, size, visible bounds, anchor, runtime path (null if not staged). |
| `data/forms/character_forms.json` | Forms 1–11: level ranges (from folder names), theme, staged state. |
| `data/animations/animation_slots.json` | Canonical 33-slot table. The slot number is the identity. |
| `data/animations/animation_groups.json` | Hand-authored animation groups, frame rates and per-frame fixes. |
| `data/balance/behaviour.json` | Hand-authored tuning for the autonomous loop. |
| `data/balance/progression.json` | Hand-authored XP curve and workout payouts. |
| `data/balance/upgrades.json`, `data/equipment/dumbbells.json`, `data/food/meals.json` | Hand-authored bone costs and their effects. |
| `data/animations/frame_geometry.json` | Per-frame visible bounds and bottom-centre anchor (alpha ≥ 32), per-form canvas, review flags. |
| `data/catalog/known_source_issues.json` | Source inconsistencies and how they are handled. |

## Large source assets

`assets/source/` is about 460 MiB of PNGs (430 files), so it is **kept local and
git-ignored**. Each developer rebuilds it from the original packs with
`tools/ingest_assets.gd`. The original packs must be shared outside git (shared
drive, release archive).

The repository versions only what the build needs: `assets/runtime/` (all 11
forms and the shared packs, 415 PNGs, about 460 MiB) and the metadata in `data/`.

Git LFS is **not** enabled. Consider it only after confirming the remote
supports it and its storage quota fits. Setting it up means `git lfs install`,
`git lfs track "assets/runtime/**/*.png"`, and committing `.gitattributes`.

Never edit files in `assets/source/` or `assets/runtime/` directly.
