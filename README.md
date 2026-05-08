# ChitChat-Classic

Enhanced chat tools for World of Warcraft Classic.

## Features

- **Keyword Scanning**: Monitor chat channels for specific keywords with boolean logic.
- **Whisper Tools**: Whisper your target or everyone in your `/who` results.
- **Reply Recent**: Reply to recent whisperers in bulk.
- **Port Finder**: Quickly find mages or warlocks offering teleports.

## Commands

Type `/chitchat` in-game to open the command reference.

### Chat Scanning

| Command | Description |
|---|---|
| `/cs KEYWORD` | Monitor chat for a keyword |
| `/cs WORD AND WORD` | Match messages containing both words |
| `/cs WORD OR WORD` | Match messages containing either word |
| `/cs WORD NOT WORD` | Match first word, exclude second |
| `/cs` | Stop scanning |

### Whisper Utilities

| Command | Description |
|---|---|
| `/wt MESSAGE` | Whisper your current target |
| `/wt-once MESSAGE` | Whisper target (skips already-contacted players) |
| `/ww MESSAGE` | Whisper everyone in your `/who` results |
| `/ww N MESSAGE` | Whisper the first N players |
| `/ww -CLASS MESSAGE` | Whisper `/who` results, excluding a class |
| `/ww-once MESSAGE` | Whisper `/who` results (skips already-contacted players) |
| `/ww reset` | Clear the persistent ignore list (also works with `/ww-once`) |

### Reply to Whispers

| Command | Description |
|---|---|
| `/rr MESSAGE` | Reply to all recent whisperers |
| `/rr N MESSAGE` | Reply to the last N whisperers |
| `/rr reset` | Clear the session reply-tracking list |

### Port Finder

| Command | Description |
|---|---|
| `/port` | Find mages in your current zone |
| `/port ZONE` | Find warlocks in the specified zone |
