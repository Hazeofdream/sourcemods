# [L4D2] Grenade Launcher Tweaks

A SourceMod plugin for Left 4 Dead 2 that adjusts grenade launcher friendly
fire and reload speed. Survivor teammates take no damage from grenade
launcher projectiles, while self-damage can be scaled separately. The plugin
also shortens the grenade launcher's reload and attack delay; its animation
speed is adjusted to match.

## ConVars

The plugin's configuration is generated at
`cfg/sourcemod/grenade_launcher_tweaks.cfg`.

| ConVar | Default | Allowed range | Description |
|---|---:|---:|---|
| `gl_adjff_enable` | `1` | `0` or `1` | Enables or disables grenade launcher friendly-fire handling. When enabled, survivor teammates take no grenade launcher damage, and self-damage uses the configured multiplier. |
| `gl_adjff_self_scale` | `1.0` | `0.0`–`10.0` | Multiplier for grenade launcher self-damage when friendly-fire handling is enabled. `1.0` keeps self-damage unchanged; `0.0` prevents it. |
| `grenade_launcher_reload_multiplier` | `0.7` | `0.1`–`1.0` | Multiplier applied to the remaining grenade launcher attack delay during reload. Lower values shorten the delay; `1.0` leaves it unchanged. |

The reload multiplier is independent of `gl_adjff_enable`. For example, the
default `0.7` reduces the remaining delay to 70% of its original duration.

## Installation

1. Install MetaMod:Source and SourceMod on your Left 4 Dead 2 server.
2. Ensure the SourceMod SDKHooks extension is available.
3. Copy `grenade_launcher_tweaks.smx` into
   `left4dead2/addons/sourcemod/plugins/`.
4. Restart the server or load the plugin with
   `sm plugins load grenade_launcher_tweaks`.
5. Edit `left4dead2/cfg/sourcemod/grenade_launcher_tweaks.cfg` to change the
   convars. The file is created when the plugin first loads.
