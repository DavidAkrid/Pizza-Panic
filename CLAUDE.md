# Pizza Panic

First-person co-op "friendslop" game (think Lethal Company / REPO / Content Warning, plus
Schedule I-style neighborhood navigation). You run a pizza shop in a monster-infested
neighborhood: cook in the cozy shop, deliver through dark streets, get paid, upgrade.

- **Vision & plan:** `PizzaPanic_DesignDoc_v4.txt` (v1-v3 are history). v4 has the long-term vision
  (save Monsterville, bring back the morning) and the BUILD ORDER (Phases A-D) to work from.
- **Current phase:** v4 BUILD ORDER Phase A (co-op confirmed working over Tailscale).
- **Scope:** v4's RELEASE SCOPE section is the contract. Ideas outside it go to its PARKING LOT;
  call out scope creep.

## Co-op status

- Phase 1 is DONE and tagged `poc-final`. `game/` is the finished single-player proof of concept:
  keep it as a reference, don't build co-op on top of it.
- Phase 2 (networking test) lives in `net_spike/` and WORKS: host/join over ENet, players see
  each other, host-owned soda cans can be picked up and thrown. See `net_spike/README.txt`.
- Networking pattern for the rebuild: host owns world state (props, stations, orders, money,
  monsters); each player owns their own movement (MultiplayerSynchronizer); clients change the
  world only via `rpc_id(1, ...)` requests that the host validates. Direct ENet for development,
  Steam lobbies later (swap the MultiplayerPeer).
- Phase 3 rebuild: steps 1-7 DONE in `game_coop/` (main scene `scenes/world.tscn`) - the co-op
  game has the full POC loop. `game_coop/` is now THE game; build on it. Done: step 1
  (menu, host/join, synced players with movement/flashlight/footsteps, per-machine shop mood).
  Connection code lives only in `scripts/net.gd` (autoload `Net`). Players are spawned through
  `PlayerSpawner.spawn(data)` + `World._make_player` so spawn info is identical on every machine
  (setting properties on the host before add_child does NOT reach a client-owned node).
  Step 2 done: items (`scripts/item.gd`, spawned via `World.spawn_item` / `ItemSpawner`). Inventory
  lives on the ITEMS (`holder` peer id + `holder_slot`), so `Player.inventory()` is the same on every
  machine. Pickup/drop/throw are `rpc_id(1, ...)` requests the host validates. Clients keep items
  frozen and display synced transforms; held items follow the holder's hand everywhere.
  Six test soda cans spawn on the cooler until the stations step.
  Step 4 done: stations. `StationBase` (rpc to host -> `_use(player, held, slot)`), `station.gd`
  (dough/toppings/boxes/trash/cooler/freezer), `cook_station.gd` (oven + fryer; host owns what's
  inside, every machine counts down locally from `_sync`). Pizzas/sticks are Items whose synced
  `state` dict holds toppings/stage/bake/condition or fry result; holder == Item.IN_STATION while
  cooking. Host-side pizza damage (`Item.damage_pizza`) sends feedback to the holder. Cold decay
  runs on the host in `World._tick_cold_pizzas`.
  Step 5 done: `scripts/game_state.gd` (node "Game", `GameState.instance`) owns `order` + team
  `money`, synced to all. New order when anyone is in the shop and there's none. Knocks go through
  the host (`HouseDoor._request_knock`); the host picks the visit timing and plays it everywhere
  (`_play_visit` RPC), then `GameState.deliver` takes matching items from EVERYONE within 4.5m
  of the door. House doors are named "Door" and customers are seeded by address so RPC paths and
  looks match on every machine.
  Step 6 done: monsters (`scripts/shambler.gd`, spawned by the host via `MonsterSpawner`). The host
  runs AI/physics; `target_id` + `staggered` are synced. Targets = closest player outside the shop
  who smells of food (14m) or is close (6m). Bites shove the victim on their machine and the host
  damages their exposed pizza (34%). Player hits arrive via `Shambler.request_hit`; thrown items
  call `knock_back` on the host. Heartbeat plays only for the hunted player.
  Step 7 done: upgrade wall (`upgrade_station.gd`). Upgrades are PERSONAL, paid from TEAM money;
  levels live in synced `GameState.upgrades` ({peer id: {id: level}}) and every machine applies
  everyone's via `Player.apply_upgrades` (slot_count only on the owner, it syncs from there).
  Esc = pause menu (Resume / Leave game / Quit; the world keeps running). Hosting shows this PC's
  join addresses (LAN + Tailscale).
  v4 Phase A step 1 done: order terminal + kitchen screen (`order_screen.gd`, one script with
  TERMINAL/KITCHEN modes; each row is its own collider). `GameState.orders` is a list (pending ->
  accepted -> delivered/expired) and deadlines run on the synced host `clock` (replication ALWAYS).
  Screens redraw themselves from synced data; accept/ready are `GameState.request_*` RPCs.
  Dev tests: never let the host's checks finish before the client's (the client reloads to the
  menu when the host quits, freeing nodes the client's checks still touch).
  Step 3 done: combat in `scripts/combat.gd` (child "Combat" of each player). Hits go to whoever
  owns the target: players -> `Player.receive_shove` on their machine (friendly fire = shove only,
  never damage), loose items -> host `Item.request_knock`, thrown items detect hits on the host.
  Dev test: host `<godot> --path game_coop -- --test=host --port=7778 --shots=<dir>` in the
  background, then `--test=client --port=7778`. Put temporary checks in with
  `python game_coop/tools/devtest_checks.py set <host.gd> <client.gd>` and remove them with
  `... clear` (never hand-slice dev_test.gd). ALWAYS run the headless error check after clearing
  and before every commit: a broken dev_test.gd breaks world.gd and the whole game.
- Rebuild order:
  world -> players -> items/inventory -> stations -> orders/delivery -> monsters -> upgrades -> polish.
  Reuse visuals, map builder, sounds, tuning numbers from `game/`.
- Two-instance automated test: `<godot> --path net_spike -- --test=host --shots=<dir>` in the
  background, then the same with `--test=client`; compare the SHOT lines.

## Running it

- Engine: Godot **4.7.2**, GDScript, Forward+, **Jolt** physics. Project lives in `game/`.
- Godot exe: `C:/Users/David/Documents/Godot/Godot_v4.7.2-stable_win64_console.exe`
- Play: open `game/project.godot` in Godot, press F5.
- Headless error check: `<godot> --headless --path game --quit-after 60`
- After adding audio/assets: `<godot> --headless --path game --import`

## Testing workflow (dev harness)

`Game._run_shots()` in `scripts/game.gd` is a scratch test harness, run with
`<godot> --path game -- --shots=<dir>` (opens a window briefly). Helpers: `_pose(pos, yaw, pitch)`,
`_face(monster, dist)`, `_capture(dir, name)`. Print results with a `SHOT` prefix and grep.

**Rule:** add checks only for the feature in progress, then delete them once verified so the
harness goes back to `# (no pending checks)`. Keep runs fast.

## Code map (`game/scripts/`)

| File | What it does |
|---|---|
| `game.gd` | `Game` singleton (`Game.instance`): orders, delivery/payment, upgrades (`UPGRADES`), pizza damage + cold decay, shop-vs-outside mood, HUD refresh, monster spawn, dev harness |
| `player.gd` | First-person controller, stamina, inventory `slots` (Pizza data or Throwable), charged punch/swing/throw, drop, upgrade effects (`apply_upgrade`) |
| `pizza.gd` | `Pizza` data (toppings, stage RAW/BAKED/BOXED, bake quality, condition) + visual builder |
| `throwable.gd` | Physical pick-up-able items (soda, fried food, thrown pizzas). Per-item swing/throw stats, `kind` used by orders, frozen/cooked state |
| `station.gd` | Simple stations: dough, topping bins, boxes, trash, soda cooler, freezer |
| `oven.gd`, `fryer.gd` | Timed cooking with ding + loop sound. Fryer accepts any frozen food (`FRY_TIMES`) |
| `upgrade_station.gd` | Wall plaques that sell upgrades |
| `neighborhood.gd` | Builds the whole greybox map in code (roads, buildings, 12 houses, park, lamps, signs, spawns) |
| `house.gd`, `house_door.gd` | House porch light/chevron; door knock + customer peek/handover animation |
| `shambler.gd` | Monster AI: wander, smell food/see player, chase, stand off ~1m, bite, knockback |
| `hud.gd`, `compass.gd` | HUD (order top-left, slots bottom-right, prompt, messages, hitmarker) and compass strip |
| `ambience.gd` | Procedural placeholder music (shop pad / outside drone / chase heartbeat) |
| `input_setup.gd` | Autoload that registers all input actions in code |

Scenes: `main.tscn` (shop interior is hand-authored here), `player.tscn`, `shambler.tscn`, `soda_can.tscn`.
Sounds: placeholder `.wav`s in `game/audio/`, generated by `game/tools/make_sfx.py` (stdlib Python).
Replace any file with a real sound of the same name.

## Key design facts

- Map: shop at origin, door faces -Z onto Main St. Elm Ave runs north, Hollow Rd across the top,
  Wexley Park in the middle. All 12 houses can order; the first order is always 1 pizza to 12 Main St.
- Orders: 1-2 items from pizza/sticks/soda (never more than slot count), partial delivery allowed.
- Collision layers: 1 world, 2 interactable, 3 player, 4 monster, 5 prop.
- Monsters never enter the shop (`Game.is_in_shop`). Unboxed pizza loses 1%/3s outside.
- No save system yet: money and upgrades reset on restart.
- Shop left wall has a how-to board and a controls board (Label3D text in `main.tscn`, nodes `HowTo` / `Controls`).
  If bindings in `input_setup.gd` or the pizza steps change, update those boards too.

## Gotchas (learned the hard way)

- Hand-written `.tscn` node exports need `node_paths=PackedStringArray(...)` on the node header.
- `.tscn` `Transform3D(...)` basis numbers are written **row by row**, not as axis columns.
  Verify any hand-written rotation with a screenshot.
- Thin colliders let objects sink; ground surfaces use deep colliders (`_surface`), and Jolt
  penetration slop is lowered to 0.002 in `project.godot`.
- CSG collision is hollow; use box colliders where items land.
- Items in inventory are removed from the scene tree (so their `_ready` may never run; see
  `Throwable._paint_soda`).
- When patching files with `python - <<'EOF'` from Bash, a double-backslash-n becomes a real
  newline. Use the Edit tool or `chr(92)` for escapes.

## Git

Work happens on `main` (remote: github.com/DavidAkrid/Pizza-Panic, pushed). The POC is tagged
`poc-final`; `coop` and `milestone-1-poc` are old branches. Commit when David asks; push when he asks.
