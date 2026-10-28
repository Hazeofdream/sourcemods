#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <ripext>

public Plugin myinfo =
{
    name        = "Discord Server Status",
    author      = "Haze_of_dream",
    description = "Posts the server name, address, map and player scores to a Discord webhook as an embed.",
    version     = "1.0",
    url         = ""
};

#define TEAM_SPECTATOR      1
#define TEAM_SURVIVOR       2
#define TEAM_INFECTED       3

// Discord limits: embed description 4096 characters.
#define MAX_DESCRIPTION     4000

// Returns {"ip":"x.x.x.x"} with the address the request came from, i.e. the server's public IP.
#define PUBLIC_IP_URL       "https://api.ipify.org?format=json"

// =====================
// ConVars
// =====================

ConVar g_hWebhook;
ConVar g_hAddress;
ConVar g_hInterval;
ConVar g_hOnMapStart;
ConVar g_hIncludeBots;
ConVar g_hColor;
ConVar g_hMessageId;

ConVar g_hHostname;
ConVar g_hHostIp;
ConVar g_hHostPort;

Handle g_hTimer = null;

char g_sPublicIp[64];
bool g_bLookingUpIp;
bool g_bPosting;		// A new message is being created; don't create a second one before its ID is known.

// =====================
// Plugin start
// =====================

public void OnPluginStart()
{
    g_hWebhook = CreateConVar(
        "sm_discordstatus_webhook",
        "",
        "Discord webhook URL the status embed is posted to",
        FCVAR_PROTECTED
    );

    g_hAddress = CreateConVar(
        "sm_discordstatus_address",
        "",
        "Address shown in the embed (e.g. 1.2.3.4:27015). Empty = public IP (looked up online) + hostport",
        FCVAR_PROTECTED
    );

    g_hInterval = CreateConVar(
        "sm_discordstatus_interval",
        "0",
        "Minutes between automatic status posts. 0 = off",
        FCVAR_NOTIFY,
        true, 0.0
    );

    g_hOnMapStart = CreateConVar(
        "sm_discordstatus_mapstart",
        "1",
        "Post the status once shortly after each map starts",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    g_hIncludeBots = CreateConVar(
        "sm_discordstatus_bots",
        "0",
        "List bots in the player list",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    g_hColor = CreateConVar(
        "sm_discordstatus_color",
        "3066993",
        "Embed color as a decimal RGB value (3066993 = green)",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 16777215.0
    );

    g_hMessageId = CreateConVar(
        "sm_discordstatus_message_id",
        "",
        "ID of the Discord message that gets edited with the status. Saved automatically. Empty = post a new message",
        FCVAR_DONTRECORD
    );

    AutoExecConfig(true, "discord_server_status");

    g_hHostname = FindConVar("hostname");
    g_hHostIp   = FindConVar("hostip");
    g_hHostPort = FindConVar("hostport");

    g_hInterval.AddChangeHook(OnIntervalChanged);

    RegAdminCmd("sm_discordstatus", Cmd_DiscordStatus, ADMFLAG_GENERIC, "Posts the current server status to the Discord webhook.");

    LookupPublicIp();
}

public void OnConfigsExecuted()
{
    RestartTimer();

    // Short delay so the map and hostname have settled and bots/players have started joining.
    if (g_hOnMapStart.BoolValue)
        CreateTimer(30.0, Timer_MapStart, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    // Repeating timer is created with TIMER_FLAG_NO_MAPCHANGE and is killed on map change.
    g_hTimer = null;
}

public void OnIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RestartTimer();
}

void RestartTimer()
{
    delete g_hTimer;

    float minutes = g_hInterval.FloatValue;
    if (minutes > 0.0)
        g_hTimer = CreateTimer(minutes * 60.0, Timer_Interval, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_MapStart(Handle timer)
{
    SendStatus();
    return Plugin_Stop;
}

public Action Timer_Interval(Handle timer)
{
    SendStatus();
    return Plugin_Continue;
}

public Action Cmd_DiscordStatus(int client, int args)
{
    if (SendStatus())
        ReplyToCommand(client, "[Discord Status] Status sent.");
    else
        ReplyToCommand(client, "[Discord Status] sm_discordstatus_webhook is not set.");

    return Plugin_Handled;
}

// =====================
// Embed
// =====================

// Edits the saved status message, or posts a new one when there is none yet.
bool SendStatus()
{
    char webhook[512];
    g_hWebhook.GetString(webhook, sizeof(webhook));
    TrimString(webhook);

    if (webhook[0] == '\0')
        return false;

    char messageId[32];
    g_hMessageId.GetString(messageId, sizeof(messageId));
    TrimString(messageId);

    if (messageId[0] == '\0')
    {
        PostNewMessage(webhook);
        return true;
    }

    // {webhook}/messages/{id}, keeping any query string (e.g. thread_id) at the end.
    char base[512], query[256], url[640];
    SplitWebhook(webhook, base, sizeof(base), query, sizeof(query));
    FormatEx(url, sizeof(url), "%s/messages/%s%s%s", base, messageId, query[0] ? "?" : "", query);

    JSONObject payload = BuildPayload();
    HTTPRequest request = new HTTPRequest(url);
    request.Patch(payload, OnEditResponse);
    delete payload;

    return true;
}

void PostNewMessage(const char[] webhook)
{
    if (g_bPosting)
        return;

    g_bPosting = true;

    // wait=true makes Discord return the created message, which holds its ID.
    char base[512], query[256], url[800];
    SplitWebhook(webhook, base, sizeof(base), query, sizeof(query));
    FormatEx(url, sizeof(url), "%s?wait=true%s%s", base, query[0] ? "&" : "", query);

    JSONObject payload = BuildPayload();
    HTTPRequest request = new HTTPRequest(url);
    request.Post(payload, OnPostResponse);
    delete payload;
}

public void OnPostResponse(HTTPResponse response, any value, const char[] error)
{
    g_bPosting = false;

    if (error[0] != '\0')
    {
        LogError("[Discord Status] Webhook request failed: %s", error);
        return;
    }

    if (response.Status != HTTPStatus_OK || response.Data == null)
    {
        LogError("[Discord Status] Webhook returned HTTP %d", response.Status);
        return;
    }

    char messageId[32];
    JSONObject message = view_as<JSONObject>(response.Data);
    if (!message.GetString("id", messageId, sizeof(messageId)))
        return;

    g_hMessageId.SetString(messageId);
    SaveMessageId(messageId);
}

public void OnEditResponse(HTTPResponse response, any value, const char[] error)
{
    if (error[0] != '\0')
    {
        LogError("[Discord Status] Webhook request failed: %s", error);
        return;
    }

    // The message was deleted (or the webhook changed): forget it and post a fresh one.
    if (response.Status == HTTPStatus_NotFound)
    {
        g_hMessageId.SetString("");
        SaveMessageId("");

        char webhook[512];
        g_hWebhook.GetString(webhook, sizeof(webhook));
        TrimString(webhook);
        if (webhook[0] != '\0')
            PostNewMessage(webhook);
        return;
    }

    if (response.Status != HTTPStatus_OK)
        LogError("[Discord Status] Editing the status message returned HTTP %d", response.Status);
}

// "https://.../webhooks/id/token?thread_id=1" -> base "https://.../webhooks/id/token", query "thread_id=1".
void SplitWebhook(const char[] webhook, char[] base, int baseLen, char[] query, int queryLen)
{
    strcopy(base, baseLen, webhook);
    query[0] = '\0';

    int pos = FindCharInString(base, '?');
    if (pos != -1)
    {
        strcopy(query, queryLen, base[pos + 1]);
        base[pos] = '\0';
    }

    // No trailing slash, so "/messages/..." can be appended.
    int len = strlen(base);
    if (len > 0 && base[len - 1] == '/')
        base[len - 1] = '\0';
}

// Writes the message ID into this plugin's cfg, which is executed on every map start, so the same message
// keeps being edited after a restart.
void SaveMessageId(const char[] messageId)
{
    char path[] = "cfg/sourcemod/discord_server_status.cfg";

    ArrayList lines = new ArrayList(ByteCountToCells(512));
    bool replaced = false;

    char line[512], setting[600];
    FormatEx(setting, sizeof(setting), "sm_discordstatus_message_id \"%s\"", messageId);

    File file = OpenFile(path, "r");
    if (file != null)
    {
        while (file.ReadLine(line, sizeof(line)))
        {
            TrimString(line);

            if (StrContains(line, "sm_discordstatus_message_id") == 0)
            {
                lines.PushString(setting);
                replaced = true;
            }
            else
            {
                lines.PushString(line);
            }
        }
        delete file;
    }

    if (!replaced)
    {
        lines.PushString("");
        lines.PushString("// ID of the Discord message that gets edited with the status. Saved automatically.");
        lines.PushString(setting);
    }

    file = OpenFile(path, "w");
    if (file == null)
    {
        LogError("[Discord Status] Could not write the message ID to %s", path);
        delete lines;
        return;
    }

    for (int i = 0; i < lines.Length; i++)
    {
        lines.GetString(i, line, sizeof(line));
        file.WriteLine("%s", line);
    }

    delete file;
    delete lines;
}

JSONObject BuildPayload()
{
    char hostname[128], address[64], map[PLATFORM_MAX_PATH], players[MAX_DESCRIPTION];
    g_hHostname.GetString(hostname, sizeof(hostname));
    GetServerAddress(address, sizeof(address));
    GetCurrentMap(map, sizeof(map));

    int count = BuildPlayerList(players, sizeof(players));

    char countText[32];
    FormatEx(countText, sizeof(countText), "%d/%d", count, GetMaxHumanPlayers());

    char addressText[96];
    FormatEx(addressText, sizeof(addressText), "`%s`", address);

    char mapText[PLATFORM_MAX_PATH + 2];
    FormatEx(mapText, sizeof(mapText), "`%s`", map);

    JSONArray fields = new JSONArray();
    AddField(fields, "Address", addressText, true);
    AddField(fields, "Map", mapText, true);
    AddField(fields, "Players", countText, true);

    char timestamp[32];
    FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", GetTime() - GetUtcOffset());

    JSONObject embed = new JSONObject();
    embed.SetString("title", hostname);
    embed.SetString("description", players);
    embed.SetInt("color", g_hColor.IntValue);
    embed.SetString("timestamp", timestamp);
    embed.Set("fields", fields);
    delete fields;

    JSONArray embeds = new JSONArray();
    embeds.Push(embed);
    delete embed;

    JSONObject payload = new JSONObject();
    payload.Set("embeds", embeds);
    delete embeds;

    return payload;
}

void AddField(JSONArray fields, const char[] name, const char[] value, bool inline)
{
    JSONObject field = new JSONObject();
    field.SetString("name", name);
    field.SetString("value", value);
    field.SetBool("inline", inline);
    fields.Push(field);
    delete field;
}

// One line per player, sorted by team then score: "**Name** - 12". Returns how many humans are connected.
int BuildPlayerList(char[] buffer, int maxlen)
{
    int clients[MAXPLAYERS];
    int total = 0;
    int humans = 0;
    bool bots = g_hIncludeBots.BoolValue;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsClientSourceTV(i))
            continue;

        bool fake = IsFakeClient(i);
        if (!fake)
            humans++;

        if (fake && !bots)
            continue;

        clients[total++] = i;
    }

    SortCustom1D(clients, total, SortPlayers);

    buffer[0] = '\0';

    if (total == 0)
    {
        strcopy(buffer, maxlen, "*No players online.*");
        return humans;
    }

    char name[MAX_NAME_LENGTH * 2], line[160];
    int lastTeam = -1;

    for (int i = 0; i < total; i++)
    {
        int client = clients[i];
        int team = GetClientTeam(client);

        if (team != lastTeam)
        {
            lastTeam = team;
            FormatEx(line, sizeof(line), "%s__%s__\n", (i == 0) ? "" : "\n", GetTeamLabel(team));
            if (!AppendLine(buffer, maxlen, line, total - i))
                break;
        }

        GetClientName(client, name, sizeof(name));
        EscapeMarkdown(name, sizeof(name));

        FormatEx(line, sizeof(line), "**%s**%s - %d\n", name, IsFakeClient(client) ? " (bot)" : "", GetClientFrags(client));
        if (!AppendLine(buffer, maxlen, line, total - i))
            break;
    }

    return humans;
}

// Appends a line, or a "...and N more" note when the line would not fit.
bool AppendLine(char[] buffer, int maxlen, const char[] line, int remaining)
{
    if (strlen(buffer) + strlen(line) < maxlen - 32)
    {
        StrCat(buffer, maxlen, line);
        return true;
    }

    char more[32];
    FormatEx(more, sizeof(more), "*...and %d more*", remaining);
    StrCat(buffer, maxlen, more);
    return false;
}

public int SortPlayers(int a, int b, const int[] array, Handle hndl)
{
    int teamA = GetTeamOrder(GetClientTeam(a));
    int teamB = GetTeamOrder(GetClientTeam(b));

    if (teamA != teamB)
        return teamA - teamB;

    // Higher score first.
    return GetClientFrags(b) - GetClientFrags(a);
}

int GetTeamOrder(int team)
{
    switch (team)
    {
        case TEAM_SURVIVOR: return 0;
        case TEAM_INFECTED: return 1;
        case TEAM_SPECTATOR: return 2;
    }
    return 3;
}

char[] GetTeamLabel(int team)
{
    char label[16];
    switch (team)
    {
        case TEAM_SURVIVOR:  strcopy(label, sizeof(label), "Survivors");
        case TEAM_INFECTED:  strcopy(label, sizeof(label), "Infected");
        case TEAM_SPECTATOR: strcopy(label, sizeof(label), "Spectators");
        default:             strcopy(label, sizeof(label), "Connecting");
    }
    return label;
}

// =====================
// Utilities
// =====================

// Asks an external service which address the server's requests come from. Cached for the plugin's lifetime.
void LookupPublicIp()
{
    if (g_bLookingUpIp || g_sPublicIp[0] != '\0')
        return;

    g_bLookingUpIp = true;

    HTTPRequest request = new HTTPRequest(PUBLIC_IP_URL);
    request.Get(OnPublicIpResponse);
}

public void OnPublicIpResponse(HTTPResponse response, any value, const char[] error)
{
    g_bLookingUpIp = false;

    if (error[0] != '\0' || response.Status != HTTPStatus_OK || response.Data == null)
    {
        LogError("[Discord Status] Public IP lookup failed: %s (HTTP %d)", error, response.Status);
        return;
    }

    JSONObject data = view_as<JSONObject>(response.Data);
    if (!data.GetString("ip", g_sPublicIp, sizeof(g_sPublicIp)))
        g_sPublicIp[0] = '\0';
}

void GetServerAddress(char[] buffer, int maxlen)
{
    g_hAddress.GetString(buffer, maxlen);
    TrimString(buffer);

    if (buffer[0] != '\0')
        return;

    if (g_sPublicIp[0] != '\0')
    {
        FormatEx(buffer, maxlen, "%s:%d", g_sPublicIp, g_hHostPort.IntValue);
        return;
    }

    // Lookup failed or hasn't finished yet: try again for the next post, use the bound address for this one.
    LookupPublicIp();

    int ip = g_hHostIp.IntValue;
    FormatEx(buffer, maxlen, "%d.%d.%d.%d:%d",
        (ip >> 24) & 0xFF,
        (ip >> 16) & 0xFF,
        (ip >> 8) & 0xFF,
        ip & 0xFF,
        g_hHostPort.IntValue
    );
}

// Seconds the server's local time is ahead of UTC, so the embed timestamp is correct.
int GetUtcOffset()
{
    char offset[8];
    FormatTime(offset, sizeof(offset), "%z");   // e.g. "+0100"

    int value = StringToInt(offset[1]);
    int seconds = (value / 100) * 3600 + (value % 100) * 60;

    return (offset[0] == '-') ? -seconds : seconds;
}

// Stops player names from breaking the embed's Markdown.
void EscapeMarkdown(char[] text, int maxlen)
{
    static const char chars[][] = { "\\", "*", "_", "~", "`", "|", ">" };
    static const char escaped[][] = { "\\\\", "\\*", "\\_", "\\~", "\\`", "\\|", "\\>" };

    for (int i = 0; i < sizeof(chars); i++)
        ReplaceString(text, maxlen, chars[i], escaped[i]);
}
