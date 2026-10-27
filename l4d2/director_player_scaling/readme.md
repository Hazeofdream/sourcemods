# [L4D2] Director Player Scaling

A SourceMod plugin for Left 4 Dead 2 that scales Director infected limits, mob sizes, special infected respawn time, and Tank health according to the number of human survivors.

### How scaling works

- Only human survivors count. Filler survivor bots do not count; a bot temporarily controlled by an idle human does.
- The scale is `1 + ((survivors / base survivors) - 1) * intensity` when the survivor count is above the base. At or below the base, the scale is `1.0`.
- Scaling stops increasing at the configured maximum survivor count. With the default settings, counts above 8 use the same scale as 8 survivors.
- Scaled integer values are rounded up, except Tank health, which is rounded to the nearest integer.
- Smoker, Hunter, Jockey, and Charger limits are each individually capped at the human survivor count.
- Updates are event-driven and delayed briefly so team changes and disconnects settle before counting. The plugin also updates at round start, after relevant bot/human replacements, on configuration execution, and when a scaling convar changes.
- Tank health is set through `z_tank_health`, so the game difficulty multiplier remains in effect. Existing Tank entities are not healed during updates.

### Scaling table

The table shows representative values with the default settings (`dps_base_survivor_count 1`, `dps_max_scaled_survivors 8`, `dps_scale_intensity 1.0`, and `dps_base_tank_health 7000`). Mob size is shown as minimum–maximum.

| Human survivors | Scale | Common limit | Mob size | Special respawn (seconds) | Tank health |
|---:|---:|---:|---:|---:|---:|
| 1 | 1x | 40 | 15–30 | 40.0 | 7,000 |
| 2 | 2x | 80 | 30–60 | 20.0 | 14,000 |
| 3 | 3x | 120 | 45–90 | 13.3 | 21,000 |
| 4 | 4x | 160 | 60–120 | 10.0 | 28,000 |
| 5 | 5x | 200 | 75–150 | 8.0 | 35,000 |
| 6 | 6x | 240 | 90–180 | 6.7 | 42,000 |
| 7 | 7x | 280 | 105–210 | 5.7 | 49,000 |
| 8 or more | 8x | 320 | 120–240 | 5.0 | 56,000 |

These are examples, not fixed values: changing the convars below changes the scale and the resulting values. The special respawn interval has a 5-second minimum.

### Director values

The plugin sets the following game convars based on the calculated scale:

| Game convar | Base value | Scaling |
|---|---:|---|
| `z_smoker_limit` | 1 | Scaled up; individually capped at the human survivor count |
| `z_hunter_limit` | 1 | Scaled up; individually capped at the human survivor count |
| `z_jockey_limit` | 1 | Scaled up; individually capped at the human survivor count |
| `z_charger_limit` | 1 | Scaled up; individually capped at the human survivor count |
| `z_spitter_limit` | 1 | Scaled up |
| `z_boomer_limit` | 2 | Scaled up |
| `z_common_limit` | 40 | Scaled up |
| `z_mob_spawn_min_size` | 15 | Scaled up |
| `z_mob_spawn_max_size` | 30 | Scaled up |
| `z_reserved_wanderers` | 15 | Scaled up |
| `z_special_spawn_interval` | 40 seconds | Divided by scale; minimum 5 seconds |
| `z_tank_health` | 7,000 | Scaled from the configured base Tank health |

## Convars

The plugin's convars use the `dps_` prefix. Defaults are written to `cfg/sourcemod/director_player_scaling.cfg`.

| Convar | Default | Allowed range | Description |
|---|---:|---:|---|
| `dps_base_survivor_count` | `1` | `1`–`10` | Human survivor count that the base values are balanced for. |
| `dps_max_scaled_survivors` | `8` | `1`–`31` | Maximum human survivor count used to calculate scaling. |
| `dps_scale_intensity` | `1.0` | `0.0`–`3.0` | Scaling intensity. `1.0` is linear; `0.0` disables additional scaling above the base count. |
| `dps_base_tank_health` | `7000` | `1` or higher | Unscaled Tank health. The game's difficulty multiplier is applied on top. |

The plugin has no player commands. Updates and resulting values are logged to the server console.
