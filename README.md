# WhisperThemAll

Whisper, reply, and port tools for WoW Classic 1.15.x.

## Modules

| File | Purpose |
|---|---|
| `Intro.lua` | Floating command-reference panel and `/wta` slash |
| `Whisper.lua` | Whisper your target, `/who` results, or auction sellers |
| `Reply.lua` | Reply to recent whisperers in bulk |
| `Port.lua` | Find mages or warlocks offering teleports |

Type `/wta` in-game to open the command panel.

## Whisper

| Command | Description |
|---|---|
| `/wt MESSAGE` | Whisper your current target |
| `/wt+ MESSAGE` | Whisper target and remember (skipped on future `+` commands) |
| `/wta list` | Open the remembered-name list (remove individual entries) |
| `/ww MESSAGE` | Whisper everyone in your `/who` results |
| `/ww -N MESSAGE` | Whisper the first N players |
| `/ww -N -FILTER... MESSAGE` | Whisper first N, excluding any class, name, or zone filter match |
| `/ww+ ... MESSAGE` | Whisper `/who` results and remember |
| `/wta clear` | Clear the remembered whisper list |
| `/ws MESSAGE` | Whisper every seller in the native auction house Browse tab |

All options are dash-prefixed and order-independent. `-N` (a number) caps recipients; `-text` (non-number) is an exclusion filter. Each exclusion is matched case-insensitively against the player's class (exact), name (substring), and zone (substring) — a player is skipped if any filter matches any field. Combine freely: `/ww -10 -warlock -Stormwind -Jondalar MESSAGE`.

Mass-whisper commands (`/ww`, `/ws`) are paced through an internal send queue to stay under the server's whisper rate cap.

`/ws` requires the native auction house to be open with results loaded on the Browse tab. It caps recipients at 25 per invocation and prompts for confirmation before sending.

Incoming whispers are recoloured to a softer blend of the outgoing whisper colour, so both sides of a conversation read consistently.

## Reply

| Command | Description |
|---|---|
| `/rr MESSAGE` | Reply to all recent whisperers |
| `/rr N MESSAGE` | Reply to the last N whisperers |
| `/rr reset` | Clear the session reply-tracking list |

## Port

| Command | Description |
|---|---|
| `/port` | Find mages in your current zone |
| `/port ZONE` | Find warlocks in the specified zone |

`/port` honours the server's 5-second `/who` cooldown — repeated calls inside that window are rejected client-side.
