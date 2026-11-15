# [L4D2] Fortifications

A SourceMod plugin for Left 4 Dead 2 that turns survivors into builders. Survivors place blueprints of fortifications with a construction tool (a baseball bat melee weapon), then build them up by hitting them. Finished fortifications are solid, functional and stay on the map until they are dismantled or the round ends.

## Note

This is identical to the [VScript version](https://steamcommunity.com/sharedfiles/filedetails/?id=3840030874) with two differences:
- The Crit Marker is a manually drawn sprite, it doesn't require any client downloads (admittedly looks less cool)
- Crit Markers are only visible to the builder (VScript limitations do not allow otherwise)

## Buildable fortifications

| Fortification | Finished result | Crits to build (default) | Dismantle time (default) |
|---|---|---:|---:|
| Barbed Wire | Damages and slows anything that touches it. | `1` | `0.8` s |
| Barricade | Solid plastic and metal barrier, topped with barbed wire that damages and slows like a normal wire. Quicker to build than a Bremer wall. | `4` | `1.5` s |
| Bremer Wall | Solid concrete wall. | `8` | `6.0` s |
| .50 Cal | A real, usable .50 cal turret (`prop_minigun`). | `8` | `3.0` s |
| Minigun | A real, usable minigun turret (`prop_minigun_l4d1`). | `8` | `3.0` s |

Each type can be turned off on its own with its `_enable` convar.

## How to build

Type `sm_fortifications` to get the construction tool. It replaces your secondary weapon.

1. **Enter build mode.** Hold `+walk` and press `+zoom`. A placement hologram shows where the fortification will go.
2. **Place a blueprint.** In build mode:
   - `+attack` (Mouse1) places a blueprint. Attacks are blocked while in build mode.
   - `+zoom` cycles the fortification type.
   - `+reload` rotates the placement between 0° and 90°.
3. **Build it.** Leave build mode (`+walk` + `+zoom` again) and swing at the blueprint.
   - A crit marker (a small X) appears on the blueprint's surface. A swing that passes through the marker counts as a crit and gives full progress.
   - A swing that misses the marker still builds, at a reduced rate (`sm_fortifications_noncrit_factor`, 25% of a crit by default).
   - After each hit the marker jumps to a new spot, so you have to move around the blueprint to follow it.
   - Blueprints become more opaque as they are built, and glow when nearly finished.

Blueprints do not collide and have no effect until they are finished. A blueprint is never removed for being far from its owner.

### Other controls

| Input | Action |
|---|---|
| Hold `+attack2` (shove) while aiming at a fortification | Dismantle it. Each type has its own hold time. |
| `+walk` + `+use` | Show how many fortifications you have and your limits. |

### Placement rules

Placement is refused:

- in the starting area, saferooms and rescue closets (requires Left 4 DHooks),
- in mid air,
- through walls,
- for solid types, where a player is in the way.

## Limits

- Each player can have `sm_fortifications_max` (default `6`) fortifications at a time, blueprints included. Building past the limit destroys that player's oldest fortification.
- Each player can have at most `sm_50cal_max` (default `1`) .50 cal and `sm_minigun_max` (default `1`) minigun. These count toward the per-player limit.
- The map holds up to 128 fortifications in total.

## Barbed wire behavior

These rules apply to barbed wire and to the wire on top of a barricade.

- Finished wire damages and slows survivors, special infected and common infected that touch it.
- Survivors take `sm_barbedwire_damage` per tick. Infected take `sm_barbedwire_damage_infected` per tick.
- Each wire tracks its damage cooldown separately for each target, so overlapping wires deal damage independently. The slowdown does not stack.
- Tanks always take wire damage. With `sm_barbedwire_tank_immune 1` they are not slowed.

## Cleanup

All fortifications are removed at round start, round end and map change. Fortifications stay when their owner dies or disconnects. Admins can remove everything with `sm_clearfortifications`.

## Commands

| Command | Access | Description |
|---|---|---|
| `sm_fortifications` | Any player; must be an alive survivor | Gives and equips the construction tool. |
| `sm_clearfortifications` | `ADMFLAG_SLAY` | Removes every fortification and blueprint on the map. |

## ConVars

Defaults are written to `left4dead2/cfg/sourcemod/fortifications.cfg` the first time the plugin loads.

### General

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_fortifications_enable` | `1` | `0` or `1` | Enables or disables the plugin. |
| `sm_fortifications_distance` | `150.0` | `16.0`–`1000.0` | Maximum placement and dismantle distance from the player's eyes, in units. |
| `sm_fortifications_cooldown` | `0.01` | `0.0` or higher | Seconds between placing a blueprint or starting a dismantle. |
| `sm_fortifications_block_melee` | `1` | `0` or `1` | Consumes the tool buttons it uses: attack while in build mode, zoom, and shove while aiming at a fortification. |
| `sm_fortifications_glow` | `1` | `0` or `1` | Outline on the placement hologram, and the glow on nearly finished blueprints. |
| `sm_fortifications_max` | `6` | `1`–`100` | Fortifications per player. Building past it destroys that player's oldest one. |
| `sm_fortifications_melee_range` | `150.0` | `20.0`–`300.0` | Tool reach for swings, and the furthest a crit marker may be from the player's eyes. |
| `sm_fortifications_crit_radius` | `5.0` | `2.0`–`100.0` | How close, in units, a swing must pass to the crit marker to count as a crit. |
| `sm_fortifications_noncrit_factor` | `0.25` | `0.0`–`1.0` | Progress from a swing that misses the marker, as a fraction of a crit. |
| `sm_fortifications_marker_move` | `50.0` | `8.0`–`500.0` | Furthest, in units, a crit marker may jump after being hit. |
| `sm_fortifications_hints` | `0` | `0` or `1` | Shows guidance hints. Type and mode changes and error messages always show. |

### Barbed wire

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_barbedwire_enable` | `1` | `0` or `1` | Allows building barbed wire. |
| `sm_barbedwire_crits` | `1` | `1`–`50` | Crit hits needed to finish a barbed wire. |
| `sm_barbedwire_dismantle_time` | `0.8` | `0.0`–`120.0` | Seconds to hold shove to dismantle. `0` is instant. |
| `sm_barbedwire_damage` | `10.0` | `0.0` or higher | Damage per tick to survivors. |
| `sm_barbedwire_damage_infected` | `40.0` | `0.0` or higher | Damage per tick to special and common infected. |
| `sm_barbedwire_interval` | `0.5` | `0.05` or higher | Seconds between damage ticks, per wire and per target. |
| `sm_barbedwire_slow` | `0.2` | `0.05`–`1.0` | Movement speed multiplier while touching wire. `1.0` means no slowdown. |
| `sm_barbedwire_tank_immune` | `1` | `0` or `1` | Makes tanks immune to the slowdown. They still take damage. |

### Barricade

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_barricade_enable` | `1` | `0` or `1` | Allows building barricades. |
| `sm_barricade_crits` | `4` | `1`–`50` | Crit hits needed to finish a barricade. |
| `sm_barricade_dismantle_time` | `1.5` | `0.0`–`120.0` | Seconds to hold shove to dismantle. `0` is instant. |

### Bremer wall

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_bremerwall_enable` | `1` | `0` or `1` | Allows building Bremer walls. |
| `sm_bremerwall_crits` | `8` | `1`–`50` | Crit hits needed to finish a Bremer wall. |
| `sm_bremerwall_dismantle_time` | `6.0` | `0.0`–`120.0` | Seconds to hold shove to dismantle. `0` is instant. |

### .50 Cal

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_50cal_enable` | `1` | `0` or `1` | Allows building .50 cals. |
| `sm_50cal_crits` | `8` | `1`–`50` | Crit hits needed to finish a .50 cal. |
| `sm_50cal_dismantle_time` | `3.0` | `0.0`–`120.0` | Seconds to hold shove to dismantle. `0` is instant. |
| `sm_50cal_max` | `1` | `1`–`20` | .50 cals each player can have at once. |

### Minigun

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_minigun_enable` | `1` | `0` or `1` | Allows building miniguns. |
| `sm_minigun_crits` | `8` | `1`–`50` | Crit hits needed to finish a minigun. |
| `sm_minigun_dismantle_time` | `3.0` | `0.0`–`120.0` | Seconds to hold shove to dismantle. `0` is instant. |
| `sm_minigun_max` | `1` | `1`–`20` | Miniguns each player can have at once. |

## Requirements

- MetaMod:Source and SourceMod 1.10 or newer on the Left 4 Dead 2 server.
- The SDKTools and SDKHooks extensions (included with SourceMod).
- Optional: [Left 4 DHooks Direct](https://forums.alliedmods.net/showthread.php?t=321696), used to block placement in the start area and saferooms.

## Installation

1. Install the requirements listed above on your Left 4 Dead 2 server.
2. Copy `fortifications.smx` into `left4dead2/addons/sourcemod/plugins/`.
3. Restart the server or load the plugin with `sm plugins load fortifications`.
4. Edit `left4dead2/cfg/sourcemod/fortifications.cfg` to change the ConVars. The file is created when the plugin first loads.
