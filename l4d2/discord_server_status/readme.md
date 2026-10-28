# Discord Server Status

This Left 4 Dead 2 SourceMod plugin posts the server's status to a Discord
webhook as an embed. The embed includes the server name, address, current map,
player count, and a player list grouped by team and sorted by score. Player
names are escaped for Discord Markdown, and bots can optionally be included.

The plugin posts once after each map starts by default. It can also update
automatically on a repeating interval or on demand with the `sm_discordstatus`
admin command. After the first successful post, the plugin saves the Discord
message ID and edits that same message for later updates.

## Commands

| Command | Access | Description |
| --- | --- | --- |
| `sm_discordstatus` | `ADMFLAG_GENERIC` | Posts the current server status to the configured webhook, or edits the saved status message. |

## ConVars

| ConVar | Default | Description |
| --- | --- | --- |
| `sm_discordstatus_webhook` | Empty | Discord webhook URL used to post the status. Required. |
| `sm_discordstatus_address` | Empty | Address displayed in the embed, such as `1.2.3.4:27015`. When empty, the plugin looks up the server's public IP using ipify and adds the configured host port. |
| `sm_discordstatus_interval` | `0` | Minutes between automatic status updates. `0` disables interval updates. |
| `sm_discordstatus_mapstart` | `1` | Post once 30 seconds after each map starts (`1` = enabled, `0` = disabled). |
| `sm_discordstatus_bots` | `0` | Include bots in the player list (`1` = enabled, `0` = disabled). |
| `sm_discordstatus_color` | `3066993` | Embed color as a decimal RGB value. The default is green. |
| `sm_discordstatus_message_id` | Empty | ID of the status message to edit. The plugin sets and saves this automatically after creating a message; leave empty to create a new message. |

## Installation

1. Install MetaMod:Source and SourceMod on your Left 4 Dead 2 server.
2. Install the **RIPExt** SourceMod extension, which this plugin requires for
   HTTP requests and JSON handling.
3. Copy `discord_server_status.smx` into
   `left4dead2/addons/sourcemod/plugins/`.
4. Restart the server or load the plugin with `sm plugins load
   discord_server_status`.
5. On first load, the plugin creates
   `left4dead2/cfg/sourcemod/discord_server_status.cfg`. Set
   `sm_discordstatus_webhook` to a Discord webhook URL in that file. Set any
   other desired convars, then reload the plugin or restart the server to
   apply the settings.

The webhook URL is sensitive; keep the generated configuration private. If
`sm_discordstatus_address` is left empty, the server must be able to reach
ipify (`api.ipify.org`) to look up its public IP. Otherwise, set the address
manually.
