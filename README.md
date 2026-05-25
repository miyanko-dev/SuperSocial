# WhisperThemAll

Whisper and reply tools for WoW Classic 1.15.x.

Whispers are sent directly through the game's chat system — no internal queueing, throttling, or pacing. The server handles batching on its end. After every multi-target send the addon prints `Sending message to N players.` in chat.

## Modules

| File | Purpose |
|---|---|
| `Whisper.lua` | `/wt`, `/wt+`, `/ww`, `/ww+`, `/ws`, `/wta` |
| `Reply.lua` | `/rr` |
| `Port.lua` | `/port`, `/clickers` and message templates |

## Whisper

| Command | Description |
|---|---|
| `/wt MESSAGE` | Whisper your current target |
| `/wt+ MESSAGE` | Whisper your current target and add them to the skip list |
| `/ww [-N] [-FILTER...] MESSAGE` | Whisper everyone in your `/who` results, optionally capped at N, optionally excluding filters |
| `/ww+ [-N] [-FILTER...] MESSAGE` | Whisper `/who` results, skip anyone already on the skip list, and add the new recipients to it |
| `/ws MESSAGE` | Whisper every seller in the native auction house Browse tab |
| `/wta clear` | Clear the skip list |

`/ww` always skips party/raid members and players you whispered with `/ww` in the last 5 minutes (per-character cooldown, persists across reloads). It does not consult the skip list.

`/ww+` skips party/raid members and any name on the skip list, and adds successful recipients to it. The 5-minute `/ww` cooldown does not apply.

Every option is dash-prefixed — `-N` caps recipients; each `-text` excludes by class (exact), name (substring), or zone (substring), case-insensitive. The first non-dash token starts the message. Example: `/ww -10 -warlock LF tank for SM` whispers the first 10 non-warlocks in `/who` with "LF tank for SM".

## Reply

| Command | Description |
|---|---|
| `/rr [-N] MESSAGE` | Reply to the last whisperers (optionally only the last N) |
| `/rr reset` | Clear the session reply-tracking list |

## Travel

| Command | Description |
|---|---|
| `/port [N] ZONE` | Whisper up to N mages and up to N warlocks in the destination zone with a randomly chosen tip-ready template |
| `/clickers [N] ZONE [MESSAGE]` (alias: `/clicker`) | Whisper up to N non-warlock players in the zone to help click a summon |

Both `/port` and `/clickers` show a native confirmation popup with the recipient count and a sample of the message before any whisper goes out. Click **Send** to fire them; click **Cancel** to abort. The skip list is not consulted and not modified.

`ZONE` is written without a leading dash and can contain spaces (e.g. `Booty Bay`, `Thunder Bluff`). Known aliases:

| Display zone | Aliases |
|---|---|
| Darnassus | `darnassus`, `dar` |
| Stormwind | `stormwind`, `sw` |
| Ironforge | `ironforge`, `if` |
| Orgrimmar | `orgrimmar`, `org` |
| Thunder Bluff | `thunder bluff`, `thunderbluff`, `thunder`, `tb` |
| Undercity | `undercity`, `uc` |
| Booty Bay | `booty bay`, `bootybay`, `bb` |

Default `N` is 5.

### Display vs. search zones

Each whisper template substitutes `{name}` (the recipient's first name) and `{zone}` (the **display** name of the destination). For subzones, hubs, or anywhere `/who` can't resolve directly, the addon looks up the player in the **parent** zone but still puts the original destination in the message. Example: `/port Booty Bay` sends `/who Stranglethorn` but whispers say "summon to Booty Bay". Extend the mapping in `Port.lua`'s `ZONES` table to add more hubs (e.g. Ratchet → The Barrens).

### Mages vs. warlocks

Mage whispers are only sent when the requested destination is a real mage portal target (Darnassus, Stormwind, Ironforge, Orgrimmar, Thunder Bluff, Undercity). For any other destination — including subzone fallbacks like Booty Bay — `/port` skips the mage section and only whispers warlocks.

### Custom messages on `/clickers`

Omit `MESSAGE` to use one of the built-in clicker templates. Pass your own to override — `{name}` and `{zone}` substitutions still apply. Examples:

```
/port Stormwind
/port 3 Thunder Bluff
/port Booty Bay
/clickers 5 Stranglethorn
/clickers Booty Bay help us click please
```

## Chat colour

Incoming whispers are recoloured to a softer blend of the outgoing whisper colour so both sides of a conversation read consistently.
