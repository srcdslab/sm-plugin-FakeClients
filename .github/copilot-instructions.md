# FakeClients SourceMod Plugin - Copilot Instructions

## Repository Overview

This repository contains the **FakeClients** plugin for SourceMod, a SourcePawn plugin that simulates fake clients (bots) in Source engine game servers. The plugin helps populate servers by adding configurable fake players with random names, useful for testing and maintaining server activity.

### Key Features
- Configurable number of fake clients (0-64)
- Delayed spawn after map changes
- Random name selection from configuration file
- Automatic fake client management (spawn/kick based on real players)
- Integration with SourceTV detection

## Repository Structure

```
/
├── .github/
│   ├── workflows/ci.yml          # CI/CD pipeline using SourceKnight
│   └── copilot-instructions.md   # This file
├── addons/sourcemod/
│   ├── scripting/
│   │   └── FakeClients.sp        # Main plugin source code
│   └── configs/
│       └── fakeclients.txt       # List of fake client names
├── sourceknight.yaml             # Build configuration
└── .gitignore                    # Git ignore patterns
```

## Development Environment

### Prerequisites
- **SourceMod**: 1.11.0+ (current target: 1.11.0-git6917)
- **Build System**: SourceKnight (modern SourcePawn build tool)
- **Language**: SourcePawn
- **Compiler**: Latest SourcePawn compiler via SourceKnight

### Build Process
1. **Local Development**: Use SourceKnight CLI tools
2. **CI/CD**: Automated via GitHub Actions using `maxime1907/action-sourceknight@v1`
3. **Output**: Compiled `.smx` files in `/addons/sourcemod/plugins/`
4. **Packaging**: Automatic release creation with plugin + configs

## Code Quality Standards

### SourcePawn Best Practices (Current Standards)
- ✅ Use `#pragma semicolon 1` and `#pragma newdecls required`
- ✅ Follow camelCase for local variables, PascalCase for functions
- ✅ Prefix global variables with `g_`
- ❌ **AVOID**: Old Handle syntax (`Handle h = CreateArray()`)
- ✅ **USE**: Modern methodmaps (`ArrayList list = new ArrayList()`)
- ❌ **AVOID**: Manual `CloseHandle()` calls
- ✅ **USE**: `delete` operator for cleanup
- ❌ **AVOID**: `ClearArray()` (causes memory leaks)
- ✅ **USE**: `delete` and recreate collections

### Code Quality Issues to Address
When modifying this codebase, prioritize fixing these patterns:

1. **Replace deprecated array functions**:
   ```sourcepawn
   // OLD (current code)
   Handle g_hNames = CreateArray(64);
   GetArrayString(g_hNames, index, buffer, sizeof(buffer));
   
   // NEW (preferred)
   ArrayList g_Names = new ArrayList(64);
   g_Names.GetString(index, buffer, sizeof(buffer));
   ```

2. **Replace Handle patterns with methodmaps**:
   ```sourcepawn
   // OLD
   Handle hConfig = OpenFile(path, "r");
   if (hConfig != INVALID_HANDLE) {
       // use file
       CloseHandle(hConfig);
   }
   
   // NEW
   File hConfig = OpenFile(path, "r");
   if (hConfig != null) {
       // use file
       delete hConfig;
   }
   ```

3. **ConVar caching and proper cleanup**:
   ```sourcepawn
   // OLD (current - memory leak potential)
   Handle hTVName = FindConVar("tv_name");
   GetConVarString(hTVName, buffer, sizeof(buffer));
   CloseHandle(hTVName);
   
   // NEW (cache ConVars in OnPluginStart)
   ConVar g_cvTVName;
   // In OnPluginStart():
   g_cvTVName = FindConVar("tv_name");
   // Usage:
   g_cvTVName.GetString(buffer, sizeof(buffer));
   ```

### Performance Considerations
- **Timer Management**: Be mindful of timer creation frequency (current code creates many timers)
- **Client Loops**: Optimize loops through MaxClients (consider caching connected clients)
- **String Operations**: Minimize string operations in frequently called functions
- **Memory Management**: Always use `delete` instead of deprecated close functions

## Plugin-Specific Guidelines

### FakeClients Plugin Architecture
1. **Initialization**: `OnPluginStart()` - Set up ConVars and data structures
2. **Map Events**: `OnMapStart()` - Parse names and start delayed fake client creation
3. **Client Management**: 
   - `OnClientPutInServer()` - Kick fake clients when real players join
   - `OnClientDisconnect()` - Create new fake clients to maintain count
4. **Configuration**: Text file with one name per line

### Configuration Management
- **File Location**: `addons/sourcemod/configs/fakeclients.txt`
- **Format**: One name per line, UTF-8 encoding
- **Parsing**: Trim whitespace, skip empty lines
- **Validation**: Check for name conflicts with existing players

### ConVar Configuration
- `sm_fakeclients_players`: Number of fake clients (0-64)
- `sm_fakeclients_delay`: Delay in seconds before spawning fake clients after map change

## Testing Guidelines

### Manual Testing Checklist
1. **Plugin Loading**: Verify plugin loads without errors
2. **ConVar Functionality**: Test all ConVar settings
3. **Real Player Join**: Verify fake clients are kicked when real players join
4. **Player Disconnect**: Verify new fake clients spawn when players leave
5. **Map Change**: Verify delayed spawn functionality
6. **Name Conflicts**: Test with duplicate names in config file
7. **SourceTV Integration**: Verify SourceTV bots are not kicked

### Common Test Scenarios
- Empty server → fake clients should spawn after delay
- Full server → no fake clients should be present
- Mixed population → balance should be maintained
- Map change → proper cleanup and respawn
- Invalid config file → graceful error handling

## Common Development Patterns

### Error Handling Best Practices
```sourcepawn
// Always check file operations
File hFile = OpenFile(path, "r");
if (hFile == null) {
    LogError("Failed to open config file: %s", path);
    return;
}
// ... use file
delete hFile;
```

### Safe Client Validation
```sourcepawn
// Always validate client index and connection state
bool IsValidClient(int client) {
    return (client >= 1 && client <= MaxClients && IsClientConnected(client));
}
```

### Modern ConVar Patterns
```sourcepawn
// Cache ConVars globally
ConVar g_cvPlayerCount;
ConVar g_cvDelay;

// Initialize in OnPluginStart
g_cvPlayerCount = CreateConVar("sm_fakeclients_players", "8", "Number of fake clients");
g_cvDelay = CreateConVar("sm_fakeclients_delay", "120", "Spawn delay in seconds");

// Use directly without repeated FindConVar calls
int maxPlayers = g_cvPlayerCount.IntValue;
```

## CI/CD Pipeline

### Automated Build Process
1. **Trigger**: Push to any branch or pull request
2. **Build**: SourceKnight compiles the plugin
3. **Package**: Creates distributable package with plugin + configs
4. **Release**: Automatic release creation for main/master branch
5. **Artifacts**: Built packages available for download

### Release Versioning
- **Tags**: Use semantic versioning (MAJOR.MINOR.PATCH)
- **Latest**: Always points to the latest main/master build
- **Artifacts**: Include both plugin (.smx) and configuration files

## Troubleshooting

### Common Issues
1. **Build Failures**: Check SourceKnight configuration in `sourceknight.yaml`
2. **Plugin Load Errors**: Verify SourceMod version compatibility
3. **Name Conflicts**: Ensure config file uses proper encoding and format
4. **Memory Issues**: Look for Handle leaks and replace with modern patterns

### Debug Techniques
1. Use `LogMessage()` for debugging (remove before production)
2. Test with minimal fake client counts first
3. Monitor server console for error messages
4. Use SourceMod's profiler for performance analysis

## Contribution Guidelines

### Before Making Changes
1. **Test Current State**: Verify plugin works as expected
2. **Identify Issues**: Use modern SourcePawn patterns
3. **Minimal Changes**: Focus on specific improvements
4. **Maintain Compatibility**: Ensure SourceMod 1.11+ compatibility

### Code Review Focus Areas
- Memory management (proper use of `delete`)
- Performance optimization (reduce O(n) operations)
- Error handling completeness
- Modern SourcePawn syntax usage
- Timer and resource management

### Documentation Updates
When making functional changes:
1. Update plugin version in source code
2. Update this instructions file if development patterns change
3. Consider adding inline documentation for complex logic
4. Update configuration examples if ConVars change

## References

- [SourceMod Scripting Documentation](https://sm.alliedmods.net/new-api/)
- [SourcePawn Language Reference](https://wiki.alliedmods.net/SourcePawn)
- [SourceKnight Build Tool](https://github.com/sourcepawn-dev/sourceknight)
- [Modern SourcePawn Patterns](https://forums.alliedmods.net/showthread.php?t=336033)