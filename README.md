## Description:
This SourceMod plugin adds fake clients (bots) to your server with a flexible tier system that adjusts the number of bots based on the number of real players currently connected. It helps simulate player activity and maintain server population dynamically.

---

## Features

- Dynamic bot count adjustment based on real player count using configurable tiers.
- Configurable delay before bots join after a map change.
- Supports fallback mode without tiers.
- Loads bot display names from an external file for varied and realistic bot names.
- Prevents kicking real players or SourceTV clients.
- Staggered bot join timers with random delays to avoid scripted behavior.

---

## Installation

1. Place the compiled plugin (`FakeClients.smx`) into your `addons/sourcemod/plugins/` directory.
2. Place the configuration files in the `configs/` directory:
   - `fakeclients_tiers.cfg` — defines the tier thresholds and max bots per tier.
   - `fakeclients.txt` — list of bot names, one per line.

3. Restart or change the map on your server to load the plugin.

---

## Configuration

### 1. `fakeclients_tiers.cfg`

This file defines the tier system controlling how many bots are allowed based on the number of real players connected.

Format (KeyValues):

```plaintext
"FakeClientsTiers"
{
    "0"   "23"
    "3"   "22"
    "9"   "20"
    "12"  "19"
    "18"  "17"
    "45"  "8"
    "48"  "7"
    "62"  "0"
}
```

- The key is the minimum number of real players required to trigger that tier.
- The value is the maximum number of bots allowed at that tier.
- Entries are automatically sorted by threshold, so order in the file does not matter.
- You can define up to 32 tiers.

---

### 2. `fakeclients.txt`

This file contains the list of bot names to be used when creating fake clients. Each name should be on its own line.

Example names:

```
SHITSHITSHIT
-Impulse-
SLAVA_UKRAINE
4ik-pyk
BigBoss
muhahahahaha
nide.gg
HeadShot
CRAY_ZEE
mlpro
Deadmemories
MaGothic
Hawk
```

- Duplicate names are allowed but the plugin tries to avoid assigning the same name to multiple bots simultaneously.
- You can customize this list freely to fit your server's theme.

---

## ConVars

- `sm_fakeclients_players` (default: 8)  
  Number of bots to spawn when tier system is disabled.

- `sm_fakeclients_delay` (default: 120)  
  Delay in seconds after map change before bots start joining.

- `sm_fakeclients_tiers` (default: 0)  
  Enable (1) or disable (0) the tier system. When enabled, bot counts follow the tiers defined in `fakeclients_tiers.cfg`.

---

## How It Works

- On map start, the plugin loads the bot names and tier configuration.
- After the configured delay, it adjusts the number of bots based on the current number of real players.
- If there are too many bots, it kicks the excess ones.
- If there are too few, it schedules staggered timers to add bots gradually.
- When real players join or leave, the bot count is adjusted accordingly.
- The plugin reserves slots to ensure real players can always connect, including extra slots if SourceTV is active.

---

## Troubleshooting

- Make sure `fakeclients_tiers.cfg` and `fakeclients.txt` are correctly placed in the `configs/` folder.
- Check your server logs for any errors related to missing or malformed config files.
- If the tier system is not working as expected, verify that `sm_fakeclients_tiers` ConVar is set to `1`.
- Ensure your bot names file has enough unique names to avoid duplicates.

---

## Support & Contribution

For issues, feature requests, or contributions, please visit the GitHub repository:  
[https://github.com/srcdslab/sm-plugin-FakeClients](https://github.com/srcdslab/sm-plugin-FakeClients)
