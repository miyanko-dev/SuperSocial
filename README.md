# GetInTouch

Whisper, reply, port, and chat-scan tools for WoW Classic 1.15.x.

## Modules

| File | Purpose |
|---|---|
| `Intro.lua` | Login banner and `/getintouch` command reference |
| `Whisper.lua` | Whisper your target, `/who` results, or auction sellers |
| `Reply.lua` | Reply to recent whisperers in bulk |
| `Port.lua` | Find mages or warlocks offering teleports |
| `Scan.lua` | Monitor chat channels for keywords |

Type `/getintouch` in-game to see the full command list.

## Whisper

| Command | Description |
|---|---|
| `/wt MESSAGE` | Whisper your current target |
| `/wt+ MESSAGE` | Whisper target and remember (skipped on future `+` commands) |
| `/ww MESSAGE` | Whisper everyone in your `/who` results |
| `/ww N MESSAGE` | Whisper the first N players |
| `/ww N -FILTER... MESSAGE` | Whisper first N, excluding any class or zone filter match |
| `/ww+ ... MESSAGE` | Whisper `/who` results and remember |
| `/w-clear` | Clear the remembered whisper list |
| `/ws MESSAGE` | Whisper every seller in the open auction house (Auctionator or native) |

Filters are dash-prefixed tokens like `-warlock`, `-mage`, `-deadmines`, or `-stormwind`. Each filter is matched case-insensitively against both class and zone — a player is skipped if any filter matches either. Combine multiple filters: `/ww 10 -warlock -deadmines MESSAGE`.

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

## Chat Scan

| Command | Description |
|---|---|
| `/cs` | Toggle the chat scan panel |
| `/cs start` | Start scanning with saved settings |
| `/cs stop` | Stop the active scan |

Inside the panel each row is one independent match (**OR** across rows). Within a row, separate keywords with commas to require all of them (**AND**). Use *Add keyword group* to add rows and the × button to remove them. Matching is case-insensitive and uses plain text (no Lua patterns).

Examples:
- Row `wts thunderfury` → matches any message containing `wts thunderfury`.
- Row `lf, tank` → matches messages containing both `lf` and `tank` anywhere.
- Two rows `lf, tank` and `lf, heal` → matches `lf`+`tank` OR `lf`+`heal`.
