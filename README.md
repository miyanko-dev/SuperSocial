# ChitChat-Classic

**World of Warcraft Classic addon** for enhanced chat communication and monitoring.

## Features

- **LFG Broadcasting**: Quickly broadcast messages to World and LookingForGroup channels with a single command
- **Chat Scanning**: Monitor channels for specific keywords with boolean search support (AND, OR, NOT)
- **Raid Symbol Support**: Displays raid markers in chat notifications
- **Audio Notifications**: Plays a sound when keyword matches are found

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

## Installation

1. Download the addon
2. Extract to `World of Warcraft/_classic_/Interface/AddOns/`
3. Restart World of Warcraft or reload UI with `/reload`

## Requirements

- World of Warcraft Classic (Version 1.15.4+)

## Author

MIYANKO
