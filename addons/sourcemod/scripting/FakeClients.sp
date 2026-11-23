#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

#define MAX_TIERS 32
#define TEAM_SPECTATOR 1

ConVar g_hCount;
ConVar g_hDelay;
ConVar g_hUseTiers;
ConVar g_hTeam;
ConVar g_hBotQuota;
ConVar g_hEngineBotQuota;
ConVar g_hEngineBotQuotaMode;
ArrayList g_hNames;

int g_iTierThreshold[MAX_TIERS]; // real player count that triggers this tier
int g_iTierMaxBots[MAX_TIERS];   // max fake clients allowed for this tier
int g_iTierCount = 0;
int g_iPendingBots = 0;

bool g_bUseTiers = false;
bool g_bLate = false;

// Fake clients created by this plugin. Game bots (bot_quota) and SourceTV are never ours.
bool g_bOurs[MAXPLAYERS + 1];

public Plugin myinfo = {
	name        = "FakeClients",
	author      = "Tsunami, .Rushaway",
	description = "Put fake clients in server with tier system",
	version     = "3.1.0",
	url         = "https://github.com/srcdslab/sm-plugin-FakeClients"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hCount = CreateConVar("sm_fakeclients_players", "8", "Fallback: number of bots when tier system is disabled", _, true, 0.0, true, 64.0);
	g_hDelay = CreateConVar("sm_fakeclients_delay", "120", "Delay after map change before fake clients join (seconds)", _, true, 0.0, true, 10000.0);
	g_hUseTiers = CreateConVar("sm_fakeclients_tiers", "0", "Use tier system from fakeclients_tiers.cfg (1 = enabled, 0 = disabled)", _, true, 0.0, true, 1.0);
	g_hTeam = CreateConVar("sm_fakeclients_team", "0", "Team the fake clients join (0 = stay unassigned, 1 = spectator)", _, true, 0.0, true, 1.0);
	g_hBotQuota = CreateConVar("sm_fakeclients_bot_quota", "-1", "Game bots to keep (sets bot_quota, use bot_quota_mode normal): lowered only when real players need the slots, raised back when they leave. Fake clients leave first. -1 = leave bot_quota alone", _, true, -1.0, true, 64.0);

	g_hEngineBotQuota = FindConVar("bot_quota");
	g_hEngineBotQuotaMode = FindConVar("bot_quota_mode");

	g_bUseTiers = g_hUseTiers.BoolValue;
	g_hUseTiers.AddChangeHook(OnConVarChanged);
	g_hBotQuota.AddChangeHook(OnBotQuotaChanged);

	AutoExecConfig(true);

	if (g_bLate)
	{
		// Adopt the fake clients a previous instance of this plugin created: unassigned or spectator fake
		// clients that are not SourceTV (game bots always join a team).
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i) && !IsClientReplay(i) && GetClientTeam(i) <= TEAM_SPECTATOR)
				g_bOurs[i] = true;
		}
	}
}

public void OnMapStart()
{
	ParseNames();
	ParseTiers();
	CreateTimer(g_hDelay.FloatValue, Timer_CreateFakeClients, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(g_hDelay.FloatValue + 90.0, Timer_CreateFakeClients, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConfigsExecuted()
{
	// server.cfg may have set bot_quota again: apply our cap before the fake clients join
	UpdateBotQuota();
}

public void OnConVarChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (hConVar == g_hUseTiers)
	{
		g_bUseTiers = g_hUseTiers.BoolValue;
		LogMessage("Tier system %s", g_bUseTiers ? "enabled" : "disabled");

		if (g_bUseTiers)
		{
			ParseTiers();

			g_iPendingBots = 0;

			for (int i = 1; i <= MaxClients; i++)
			{
				if (!g_bOurs[i] || !IsClientInGame(i))
					continue;

				KickClient(i, "Client Disconnect");
			}

			// Wait a moment for all bots to be kicked before trying to add new ones according to tiers.
			CreateTimer(1.0, Timer_CreateFakeClients, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			AdjustFakeClientsToTier();
		}
	}
}

public void OnBotQuotaChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	UpdateBotQuota();
}

/**
 * Returns the target bot count based on the current number of real players.
 * Falls back to sm_fakeclients_players if tiers are disabled or not loaded.
 */
int GetTargetBotCount(int iRealPlayers)
{
	if (!g_bUseTiers || g_iTierCount == 0)
		return g_hCount.IntValue;

	// Walk tiers from highest threshold down, pick the first one that applies
	for (int t = g_iTierCount - 1; t >= 0; t--)
	{
		if (iRealPlayers >= g_iTierThreshold[t])
			return g_iTierMaxBots[t];
	}

	// No tier matched (e.g. config missing threshold "0")
	LogMessage("Warning: no tier matched for %d real players, defaulting to 0 bots", iRealPlayers);
	return 0;
}

/**
 * Client counts by kind. SourceTV and Replay are counted in iOthers.
 */
enum struct ClientCounts
{
	int iFakes;    // fake clients created by this plugin
	int iGameBots; // other fake clients (bot_quota bots)
	int iReal;     // real players, connecting ones included
	int iRealInTeam;
	int iOthers;   // SourceTV / Replay
}

void CollectClientCounts(ClientCounts counts)
{
	counts.iFakes = 0;
	counts.iGameBots = 0;
	counts.iReal = 0;
	counts.iRealInTeam = 0;
	counts.iOthers = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i))
			continue;

		if (IsClientSourceTV(i) || IsClientReplay(i))
			counts.iOthers++;
		else if (g_bOurs[i])
			counts.iFakes++;
		else if (IsFakeClient(i))
			counts.iGameBots++;
		else
		{
			counts.iReal++;
			if (IsClientInGame(i) && GetClientTeam(i) > TEAM_SPECTATOR)
				counts.iRealInTeam++;
		}
	}
}

/**
 * Game bots the engine still wants to add (bot_quota not reached yet). Their slots are kept free.
 */
int GetPendingGameBots(ClientCounts counts)
{
	if (g_hEngineBotQuota == null)
		return 0;

	int iWanted = g_hEngineBotQuota.IntValue;

	char sMode[16];
	if (g_hEngineBotQuotaMode != null)
		g_hEngineBotQuotaMode.GetString(sMode, sizeof(sMode));

	if (strcmp(sMode, "fill", false) == 0)
		iWanted -= counts.iRealInTeam;
	else if (strcmp(sMode, "normal", false) != 0)
		return 0; // "match": depends on the humans' performance, do not guess

	int iPending = iWanted - counts.iGameBots;
	return iPending > 0 ? iPending : 0;
}

/**
 * Slots fake clients may use: everything not taken by real players, game bots (present or still
 * to be added by bot_quota), SourceTV, minus 1 slot kept free so a real player can always connect.
 */
int GetFakeClientSlots(ClientCounts counts)
{
	int iSlots = MaxClients - (counts.iReal + counts.iGameBots + counts.iOthers + GetPendingGameBots(counts) + 1);
	return iSlots > 0 ? iSlots : 0;
}

/**
 * Computes the clamped target fake client count. Shared by AdjustFakeClientsToTier and OnClientConnected.
 */
int ComputeTarget(ClientCounts counts)
{
	int iTarget = GetTargetBotCount(counts.iReal);
	if (iTarget < 0)
		iTarget = 0;

	int iSlots = GetFakeClientSlots(counts);
	if (iTarget > iSlots)
		iTarget = iSlots;

	return iTarget;
}

/**
 * With sm_fakeclients_bot_quota >= 0, sets bot_quota to that value, lowered when real players need the slots.
 * Fake clients do not count: they are kicked first.
 */
void UpdateBotQuota()
{
	int iWanted = g_hBotQuota.IntValue;
	if (iWanted < 0 || g_hEngineBotQuota == null)
		return;

	ClientCounts counts;
	CollectClientCounts(counts);

	int iRoom = MaxClients - (counts.iReal + counts.iOthers + 1);
	if (iRoom < 0)
		iRoom = 0;

	int iQuota = iWanted < iRoom ? iWanted : iRoom;
	if (g_hEngineBotQuota.IntValue == iQuota)
		return;

	LogMessage("bot_quota %d -> %d (wanted:%d real:%d slots:%d)", g_hEngineBotQuota.IntValue, iQuota, iWanted, counts.iReal, MaxClients);
	g_hEngineBotQuota.SetInt(iQuota, false, false);
}

/**
 * Kicks our excess fake clients until their count reaches iTarget.
 * Never kicks real players, game bots or SourceTV.
 */
void KickExcessBots(ClientCounts counts, int iTarget)
{
	int iToKick = counts.iFakes - iTarget;
	int iKicked = 0;

	for (int i = 1; i <= MaxClients && iKicked < iToKick; i++)
	{
		if (!g_bOurs[i] || !IsClientConnected(i) || IsClientInKickQueue(i))
			continue;

		LogMessage("Kicking fake client '%N' (slot %d) — fakes:%d target:%d", i, i, counts.iFakes, iTarget);

		KickClient(i, "Client Disconnect");
		iKicked++;
	}

	if (iKicked > 0)
		LogMessage("Kicked %d fake client(s) — real:%d fakes:%d game bots:%d target:%d slots:%d", iKicked, counts.iReal, counts.iFakes, counts.iGameBots, iTarget, MaxClients);
}

/**
 * Schedules staggered timers to add bots up to iToAdd, respecting free slots.
 */
void ScheduleBotsToAdd(int iToAdd, int iFreeSlots)
{
	if (iFreeSlots <= 0 || iToAdd <= 0)
		return;

	if (iToAdd > iFreeSlots)
		iToAdd = iFreeSlots;

	// Keep a staggered cadence but add jitter so joins look less scripted.
	float fNextDelay = GetRandomFloat(0.4, 1.2);

	for (int j = 0; j < iToAdd; j++)
	{
		g_iPendingBots++;
		CreateTimer(fNextDelay, Timer_CreateFakeClient, _, TIMER_FLAG_NO_MAPCHANGE);
		fNextDelay += GetRandomFloat(0.5, 1.6);
	}
}

/**
 * Compares current bot count against the target and either kicks excess bots
 * or schedules new ones to fill the gap.
 */
void AdjustFakeClientsToTier()
{
	UpdateBotQuota();

	ClientCounts counts;
	CollectClientCounts(counts);

	int iTarget = ComputeTarget(counts);

	// Too many fake clients -> kick extras
	if (counts.iFakes > iTarget)
	{
		g_iPendingBots = 0;
		KickExcessBots(counts, iTarget);
	}
	// Active + pending fake clients are below target -> add missing ones
	else if ((counts.iFakes + g_iPendingBots) < iTarget)
		ScheduleBotsToAdd(iTarget - counts.iFakes - g_iPendingBots, iTarget - counts.iFakes);

	MoveFakeClientsToTeam();
}

/**
 * Puts our fake clients in the team set by sm_fakeclients_team (spectator), e.g. after a map change.
 */
void MoveFakeClientsToTeam()
{
	if (g_hTeam.IntValue != TEAM_SPECTATOR)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bOurs[i] && IsClientInGame(i) && !IsClientInKickQueue(i) && GetClientTeam(i) != TEAM_SPECTATOR)
			ChangeClientTeam(i, TEAM_SPECTATOR);
	}
}

public void OnClientConnected(int client)
{
	// A new client always starts as "not ours": Timer_CreateFakeClient flags it after CreateFakeClient returns.
	g_bOurs[client] = false;

	// Skip fake clients: bot additions are managed via timers.
	// Calling AdjustFakeClientsToTier on every bot join would cause cascading timers.
	if (IsFakeClient(client))
		return;

	// A real player is connecting: kick excess fake clients right away so the reserved slot
	// is freed while they download/load the map, not only once they are in game.
	// Only kick, never schedule additions.
	// Scheduling here would race with the staggered timers already in flight.
	ClientCounts counts;
	CollectClientCounts(counts);

	int iTarget = ComputeTarget(counts);
	if (counts.iFakes > iTarget)
		KickExcessBots(counts, iTarget);

	// Then make room among the game bots if the server is still about to be full
	UpdateBotQuota();
}

public void OnClientDisconnect(int client)
{
	// Ignore bot disconnects (caused by our own kicks) to avoid cascading timers.
	if (IsFakeClient(client))
		return;

	CreateTimer(0.5, Timer_CreateFakeClients, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect_Post(int client)
{
	g_bOurs[client] = false;
}

public Action Timer_CreateFakeClient(Handle timer)
{
	g_iPendingBots--;
	if (g_iPendingBots < 0)
		g_iPendingBots = 0;

	ClientCounts counts;
	CollectClientCounts(counts);

	// Recheck: tier, players or game bots may have changed since this timer was scheduled
	if (counts.iFakes >= ComputeTarget(counts))
		return Plugin_Handled;

	char sName[MAX_NAME_LENGTH];
	char sTarget[MAX_TARGET_LENGTH];
	int  iTargets[MAXPLAYERS];
	bool bTN_Is_ML;

	// Pick a random name, re-roll if a client already uses it (the engine would rename the copy "(1)name").
	// Stop after trying all available names to prevent an infinite loop when
	// the name list is smaller than the number of bots (duplicates are allowed).
	// If no names are configured, CreateFakeClient will assign a default name based on the engine.
	int iNameCount = g_hNames.Length;
	if (iNameCount > 0)
	{
		g_hNames.GetString(GetRandomInt(0, iNameCount - 1), sName, sizeof(sName));

		for (int iAttempt = 1; iAttempt < iNameCount; iAttempt++)
		{
			if (ProcessTargetString(sName, 0, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY, sTarget, MAX_TARGET_LENGTH, bTN_Is_ML) != 1)
				break;

			g_hNames.GetString(GetRandomInt(0, iNameCount - 1), sName, sizeof(sName));
		}
	}

	int client = CreateFakeClient(sName);
	if (client <= 0)
		return Plugin_Handled;

	g_bOurs[client] = true;

	if (g_hTeam.IntValue == TEAM_SPECTATOR)
		RequestFrame(Frame_JoinSpectator, GetClientUserId(client));

	return Plugin_Handled;
}

public void Frame_JoinSpectator(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client && g_bOurs[client] && IsClientInGame(client) && GetClientTeam(client) != TEAM_SPECTATOR)
		ChangeClientTeam(client, TEAM_SPECTATOR);
}

public Action Timer_CreateFakeClients(Handle timer)
{
	AdjustFakeClientsToTier();
	return Plugin_Continue;
}

/**
 * Loads tier thresholds from configs/fakeclients_tiers.cfg. Max 32 tiers.
 * Format (KeyValues):
 *
 *   "FakeClientsTiers"
 *   {
 *       "0"     "12"   // 0 real players  → up to 12 bots
 *       "5"     "10"   // 5+ real players → up to 10 bots
 *       "15"    "8"    // And so on...
 *   }
 *
 * Entries are sorted by threshold automatically, so order in the file
 * does not matter.
 */
stock void ParseTiers()
{
	if (!g_bUseTiers)
		return;

	g_iTierCount = 0;

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/fakeclients_tiers.cfg");

	KeyValues kv = new KeyValues("FakeClientsTiers");

	if (!kv.ImportFromFile(sPath))
	{
		LogError("configs/fakeclients_tiers.cfg not found — falling back to sm_fakeclients_players");
		g_hUseTiers.BoolValue = false;
		delete kv;
		return;
	}

	if (!kv.GotoFirstSubKey(false))
	{
		LogError("configs/fakeclients_tiers.cfg is empty or malformed");
		g_hUseTiers.BoolValue = false;
		delete kv;
		return;
	}

	do
	{
		if (g_iTierCount >= MAX_TIERS)
			break;

		char sKey[16], sVal[16];
		kv.GetSectionName(sKey, sizeof(sKey));
		kv.GetString(NULL_STRING, sVal, sizeof(sVal), "-1");

		int iMaxBots = StringToInt(sVal);
		if (iMaxBots < 0)
			continue; // skip malformed lines

		g_iTierThreshold[g_iTierCount] = StringToInt(sKey);
		g_iTierMaxBots[g_iTierCount]   = iMaxBots;
		g_iTierCount++;

	} while (kv.GotoNextKey(false));

	delete kv;

	// Bubble sort tiers by threshold (ascending) so GetTargetBotCount() works correctly
	for (int i = 0; i < g_iTierCount - 1; i++)
	{
		for (int j = 0; j < g_iTierCount - 1 - i; j++)
		{
			if (g_iTierThreshold[j] > g_iTierThreshold[j + 1])
			{
				int tmp;
				tmp = g_iTierThreshold[j];  g_iTierThreshold[j]  = g_iTierThreshold[j + 1]; g_iTierThreshold[j + 1] = tmp;
				tmp = g_iTierMaxBots[j];    g_iTierMaxBots[j]    = g_iTierMaxBots[j + 1];   g_iTierMaxBots[j + 1]   = tmp;
			}
		}
	}

	LogMessage("Loaded %d tier(s) from fakeclients_tiers.cfg", g_iTierCount);
}

/**
 * Loads bot display names from configs/fakeclients.txt (one name per line).
 */
stock void ParseNames()
{
	delete g_hNames;
	g_hNames = new ArrayList(MAX_NAME_LENGTH);

	char sBuffer[256];
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/fakeclients.txt");

	File hConfig = OpenFile(sBuffer, "r");
	if (!hConfig)
	{
		LogError("configs/fakeclients.txt not found — using default engine name");
		return;
	}

	while (hConfig.ReadLine(sBuffer, sizeof(sBuffer)))
	{
		TrimString(sBuffer);
		if (strlen(sBuffer) > 0)
			g_hNames.PushString(sBuffer);
	}

	delete hConfig;

	if (!g_hNames.Length)
		LogError("configs/fakeclients.txt is empty — using default engine name");
}
