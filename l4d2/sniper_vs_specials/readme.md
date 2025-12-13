A plugin that enables instant-kill sniper rifles against certain special infected to give them a distinct role.

Convars can be controlled via config, Convars are done via bitwise operations:

Supports: Excluding certain special infected:

( Convar: svs_disable )

[ Adding numbers excludes them from the plugin, 0 = all SI are affected, 127 = all SI are excluded]
- Tank (64)
- Charger (32)
- Jockey (16)
- Hunter (8)
- Boomer (2)
- Smoker (1)

Supports: Excluding certain weapons

( Convar: svs_weapon )

[ Adding numbers excludes the weapon from the plugin, 0 = all weapons are disabled, 3 = all guns are used]
- Scout (1)
- AWP (2)

Supports: Excluding certain gamemodes

( Convar: svs_mode )

[ Adding numbers excludes the gamemode, 0 = all gamemodes are enabled, 15 = all gamemodes are disabled]
- Coop (1)
- Survival (2)
- Versus (4)
- Scavenge (8)