# [L4D2] Barbed Wire

A SourceMod plugin for Left 4 Dead 2 that lets survivors place and dismantle damaging barbed-wire obstacles with the CSS knife melee weapon.

### Commands

| Command | Access | Description |
|---|---|---|
| `sm_barbedwire` | Any player; must be an alive survivor to use | Gives and equips the knife tool. |
| `sm_clearwire` | `ADMFLAG_SLAY` | Removes all wires, including wires still being built. |

### Damage and movement effects

- Completed wires damage and slow survivors, player-controlled infected, and common infected that touch them. Ghost infected are excluded.
- Each wire has its own damage cooldown for each target, so overlapping wires can deal damage independently.
- Tanks still take wire damage. With `sm_barbedwire_tank_immune` enabled, they are not slowed.
- Survivor and player-infected movement is slowed with the player movement multiplier. Common infected are slowed by scaling their horizontal movement.
- Damage attribution is credited to the wire owner for infected targets when that owner is still connected. Survivor damage has no player attacker attribution.
- In-progress wires do not damage or slow. The plugin removes wires at round start/end and map transitions; `sm_clearwire` can also clear them manually.
- Build and placement state is removed when a build is cancelled, its builder disconnects or dies, or the plugin shuts down.

## Convars

All convars use the `sm_barbedwire_` prefix. Defaults are written to `cfg/sourcemod/barbed_wire.cfg`.

| Convar | Default | Allowed range | Description |
|---|---:|---:|---|
| `sm_barbedwire_enable` | `1` | `0` or `1` | Enables or disables the plugin’s tool controls and wire damage/slowdown processing. Existing wires remain when disabled. |
| `sm_barbedwire_distance` | `150.0` | `16.0`–`1000.0` | Maximum distance from the player’s eyes for placement and dismantling. |
| `sm_barbedwire_damage` | `10.0` | `0.0` or higher | Damage dealt by each wire on each eligible damage tick. |
| `sm_barbedwire_tank_immune` | `1` | `0` or `1` | When enabled, tanks are immune to slowdown, but still take damage from wires. |
| `sm_barbedwire_interval` | `0.5` | `0.05` or higher | Minimum seconds between damage ticks from the same wire to the same target. |
| `sm_barbedwire_slow` | `0.2` | `0.05`–`1.0` | Movement multiplier while touching wire. `1.0` means no movement reduction. |
| `sm_barbedwire_max` | `3` | `1`–`100` | Maximum number of wires owned by an individual player. |
| `sm_barbedwire_cooldown` | `0.4` | `0.0` or higher | Minimum seconds between starting a build or attempting a dismantle. |
| `sm_barbedwire_build_time` | `1` | `0.0`–`60.0` | Seconds secondary attack must be held to finish building. `0` places the wire immediately. |
| `sm_barbedwire_block_melee` | `1` | `0` or `1` | When enabled, consumes secondary attack and Zoom input while the knife tool is active. |
| `sm_barbedwire_glow` | `1` | `0` or `1` | Adds a colored outline to the placement hologram. |

The plugin supports up to 128 wire slots on the map in total, independently of the per-player limit. If all slots are occupied, no additional wire can be started until one is removed.