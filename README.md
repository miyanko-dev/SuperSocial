# ChitChat-Classic

**World of Warcraft Classic addon** for enhanced chat communication and monitoring.

Type `/chitchat` in-game to see all available commands in a convenient tooltip.

## Features

- **LFG Broadcasting**: Quickly broadcast messages to World and LookingForGroup channels with a single command
- **Chat Scanning**: Monitor channels for specific keywords with boolean search support (AND, OR, NOT)
- **Raid Symbol Support**: Displays raid markers in chat notifications
- **Audio Notifications**: Plays a sound when keyword matches are found
- **Whisper Target**: Send whispers to your current target with spam protection
- **Whisper Who**: Send whispers to players from who list results with optional class filtering and spam protection
- **Reply Recent**: Reply to multiple recent whisperers at once with tracking
- **Port Finder**: Find mages (in current zone) or warlocks (in target zone) for teleports/summons

## Commands

### /lfg [message]
Broadcasts your message to both World and LookingForGroup channels simultaneously.

**Example:**
```
/lfg LF Tank for SM Library
```

### /cs [keywords]
Scans chat channels for specific keywords with boolean operators.

**Examples:**
```
/cs tank                    - Watch for "tank"
/cs tank AND healer         - Watch for messages containing both words
/cs SM OR Scarlet           - Watch for either word
/cs LFG NOT full            - Watch for "LFG" but not "full"
/cs                         - Disable scanning
```

### /wt [message]
Sends a whisper to your current target.

**Example:**
```
/wt Need help with quest?
```

### /wt+ [message]
Sends a whisper to your current target but remembers who you've contacted to prevent spam.

**Example:**
```
/wt+ WTS [Item] 50g
```

### /ww [N] [-CLASS] [message]
Sends whispers to players from your who list results.

**Examples:**
```
/ww Hello!                  - Whisper all who results
/ww 5 Need help?            - Whisper first 5 results
/ww -warrior LF Tank        - Whisper all except warriors
/ww 3 -mage Need DPS        - Whisper first 3 non-mages
```

### /ww+ [N] [-CLASS] [message]
Same as /ww but tracks who you've contacted to prevent duplicate messages.

**Example:**
```
/ww+ 10 LFM for dungeon
```

### /ww reset
Clears the list of contacted players so you can message them again.

**Example:**
```
/ww reset
```

### /rr [N] [message]
Reply to recent players who have whispered you.

**Examples:**
```
/rr Thanks for the trade!   - Reply to all recent whisperers
/rr 5 Still interested?     - Reply to last 5 whisperers
```

### /rr reset
Resets the list of players you've replied to this session.

**Example:**
```
/rr reset
```

### /port [zone]
Finds mages or warlocks for teleports/summons.

**Examples:**
```
/port                       - Find mages in current zone
/port Orgrimmar             - Find warlocks in Orgrimmar
```
