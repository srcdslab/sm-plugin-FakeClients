#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

#define MAX_TIERS 32

ConVar g_hCount;
ConVar g_hDelay;
ConVar g_hUseTiers;
ArrayList g_hNames;

int g_iTierThreshold[MAX_TIERS]; // real player count that triggers this tier
int g_iTierMaxBots[MAX_TIERS];   // max bots allowed for this tier
int g_iTierCount = 0;
int g_iPendingBots = 0;

bool g_bUseTiers = false;

public Plugin myinfo = {
	name        = "FakeClients",
	author      = "Tsunami, .Rushaway",
	description = "Put fake clients in server with tier system",
	version     = "3.0.0",
	url         = "https://github.com/srcdslab/sm-plugin-FakeClients"
}

public void OnPluginStart()
{
	g_hCount = CreateConVar("sm_fakeclients_players", "8", "Fallback: number of bots when tier system is disabled", _, true, 0.0, true, 64.0);
	g_hDelay = CreateConVar("sm_fakeclients_delay", "120", "Delay after map change before fake clients join (seconds)", _, true, 0.0, true, 10000.0);
	g_hUseTiers = CreateConVar("sm_fakeclients_tiers", "0", "Use tier system from fakeclients_tiers.cfg (1 = enabled, 0 = disabled)", _, true, 0.0, true, 1.0);

	g_bUseTiers = g_hUseTiers.BoolValue;
	g_hUseTiers.AddChangeHook(OnConVarChanged);

	AutoExecConfig(true);
}

public void OnMapStart()
{
	ParseNames();
	ParseTiers();
	CreateTimer(g_hDelay.FloatValue, Timer_CreateFakeClients, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConVarChanged(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (hConVar == g_hUseTiers)
	{
		g_bUseTiers = g_hUseTiers.BoolValue;
		LogMessage("Tier system %s", g_bUseTiers ? "enabled" : "disabled");

		if (g_bUseTiers)
		{
			g_iPendingBots = 0;

			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsClientConnected(i) || !IsClientInGame(i))
					continue;

				if (!IsFakeClient(i) || IsClientSourceTV(i))
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
 * Computes the clamped target bot count, accounting for available slots and
 * server over-capacity. Shared by AdjustFakeClientsToTier and OnClientPutInServer.
 */
int ComputeTarget(int iBots, int iRealPlayers, int iReservedSlots)
{
	int iTarget = GetTargetBotCount(iRealPlayers);
	if (iTarget < 0)
		iTarget = 0;

	// Bots currently being added already count as occupied slots
	int iEffectiveBots = iBots + g_iPendingBots;
	int iFreeSlots     = MaxClients - (iRealPlayers + iEffectiveBots + iReservedSlots);

	if (iFreeSlots < 0)
	{
		iTarget = iEffectiveBots + iFreeSlots;
		if (iTarget < 0)
			iTarget = 0;
	}
	else
	{
		int iMaxBotsBySlots = iEffectiveBots + iFreeSlots;
		if (iTarget > iMaxBotsBySlots)
			iTarget = iMaxBotsBySlots;
	}

	return iTarget;
}

/**
 * Kicks excess bots until the bot count reaches iTarget.
 * Never kicks real players or SourceTV.
 */
void KickExcessBots(int iBots, int iRealPlayers, int iTarget)
{
	int iToKick = iBots - iTarget;
	int iKicked = 0;

	for (int i = 1; i <= MaxClients && iKicked < iToKick; i++)
	{
		if (!IsClientConnected(i) || !IsClientInGame(i))
			continue;

		// Safety: never kick real players or SourceTV
		if (!IsFakeClient(i) || IsClientSourceTV(i))
			continue;

		LogMessage("Kicking fake client '%N' (slot %d) — bots:%d target:%d", i, i, iBots, iTarget);

		KickClient(i, "Client Disconnect");
		iKicked++;
	}

	if (iKicked > 0)
		LogMessage("Kicked %d bot(s) — real:%d bots:%d target:%d slots:%d", iKicked, iRealPlayers, iBots, iTarget, MaxClients);
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
		fNextDelay += GetRandomFloat(0.7, 1.9);
	}
}

/**
 * Compares current bot count against the target and either kicks excess bots
 * or schedules new ones to fill the gap.
 */
void AdjustFakeClientsToTier()
{
	int iBots, iRealPlayers, iReservedSlots;
	CollectClientCounts(iBots, iRealPlayers, iReservedSlots);

	int iTarget    = ComputeTarget(iBots, iRealPlayers, iReservedSlots);
	int iFreeSlots = MaxClients - (iRealPlayers + iBots + iReservedSlots);

	// Too many active bots -> kick extras
	if (iBots > iTarget)
	{
		g_iPendingBots = 0;
		KickExcessBots(iBots, iRealPlayers, iTarget);
	}
	// Active + pending bots are below target -> add missing bots
	else if ((iBots + g_iPendingBots) < iTarget)
		ScheduleBotsToAdd(iTarget - iBots - g_iPendingBots, iFreeSlots);
}

/**
 * Collects fake bots, real players and reserved slots in a single client loop.
 */
void CollectClientCounts(int &iBots, int &iRealPlayers, int &iReservedSlots)
{
	iBots        = 0;
	iRealPlayers = 0;
	bool bHasSourceTV = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i))
			continue;

		if (IsClientSourceTV(i))
		{
			bHasSourceTV = true;
			continue; // SourceTV occupies its own slot in MaxClients — do not count it as a bot
		}

		if (IsFakeClient(i))
			iBots++;
		else
			iRealPlayers++;
	}

	// Reserve 1 free slot so a real player can always connect.
	// When SourceTV is active, reserve 1 extra (SourceTV's slot is already in MaxClients).
	iReservedSlots = bHasSourceTV ? 2 : 1;
}

public void OnClientPutInServer(int client)
{
	// Skip fake clients: bot additions are managed via timers.
	// Calling AdjustFakeClientsToTier on every bot join would cause cascading timers.
	if (!client || IsFakeClient(client))
		return;

	// A real player joined: only kick excess bots, never schedule additions.
	// Scheduling here would race with the staggered timers already in flight.
	int iBots, iRealPlayers, iReservedSlots;
	CollectClientCounts(iBots, iRealPlayers, iReservedSlots);

	int iTarget = ComputeTarget(iBots, iRealPlayers, iReservedSlots);
	if (iBots > iTarget)
		KickExcessBots(iBots, iRealPlayers, iTarget);
}

public void OnClientDisconnect(int client)
{
	// Ignore bot disconnects (caused by our own kicks) to avoid cascading timers.
	if (IsFakeClient(client))
		return;

	CreateTimer(0.5, Timer_CreateFakeClients, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CreateFakeClient(Handle timer)
{
	g_iPendingBots--;
	if (g_iPendingBots < 0)
		g_iPendingBots = 0;

	int iBots, iRealPlayers, iReservedSlots;
	CollectClientCounts(iBots, iRealPlayers, iReservedSlots);

	int iTarget    = ComputeTarget(iBots, iRealPlayers, iReservedSlots);
	int iFreeSlots = MaxClients - (iRealPlayers + iBots + iReservedSlots);

	// Recheck: tier may have changed since this timer was scheduled
	if (iFreeSlots <= 0 || iBots >= iTarget)
		return Plugin_Handled;

	char sName[MAX_NAME_LENGTH];
	char sTarget[MAX_TARGET_LENGTH];
	int  iTargets[MAXPLAYERS];
	bool bTN_Is_ML;

	// Pick a random name, re-roll if it's already taken by a fake client.
	// Stop after trying all available names to prevent an infinite loop when
	// the name list is smaller than the number of bots (duplicates are allowed).
	int iNameCount = g_hNames.Length;
	g_hNames.GetString(GetRandomInt(0, iNameCount - 1), sName, sizeof(sName));

	for (int iAttempt = 1; iAttempt < iNameCount; iAttempt++)
	{
		if (ProcessTargetString(sName, 0, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_MULTI, sTarget, MAX_TARGET_LENGTH, bTN_Is_ML) != 1 || !IsFakeClient(iTargets[0]))
			break;

		g_hNames.GetString(GetRandomInt(0, iNameCount - 1), sName, sizeof(sName));
	}

	CreateFakeClient(sName);
	return Plugin_Handled;
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
