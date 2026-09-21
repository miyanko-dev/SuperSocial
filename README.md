# SuperSocial

Run a `/who` search, then `/ww MESSAGE` whispers everyone in the results. That's the whole idea.

## Features

- **Mass whisper** — one command whispers every result of your last `/who`, paced at the fastest rate the server allows
- **Filters** — cap the count, skip or target specific classes, zones and names, and fold the `/who` search into the command itself
- **Recipient cooldowns** — put everyone you whisper on a timer so a repeated broadcast never hits the same person twice. Account-wide and survives relogs.
- **Quick reply** — `/rr` answers everyone who whispered you back and hasn't been answered yet, across several `/ww` runs, never twice
- **Auction house whispers** — `/ws` whispers every seller in the Browse tab
- **Block list** — a permanent per-name block no command will whisper
- **Quiet runs** — one status line that rewrites itself in place instead of fifty `To Playername:` lines
- **Confirmed sends** — counts the server's own echo, so "sent" means the server took it
- **Split messages** — a `;` in the message sends it as two back-to-back whispers
- **Questie quest links in macros** — shift-click a tracked quest with the macro window open and its link lands in the macro body
- Never whispers you, your party or raid, or anyone grouped with you in the last 15 minutes

## Installation

1. Copy the `SuperSocial/` folder into `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **Super Social** in the AddOns list.

## Try it

1. Type `/who 25-30` in chat, or any filter you like.
2. When the results appear, type `/ww WTB Wool Cloth 1g/stack`.
3. Done — everyone in your results just got whispered.

## Flags for /ww

Use any, all or none; order doesn't matter, but flags go **before** the message. A single number stands bare, anything longer goes in brackets.

| Flag | Example | Effect |
| --- | --- | --- |
| `-limit N` | `-limit 10` | Whisper only the first N results |
| `-skip (…)` | `-skip (warlock maraudon)` | Drop anyone whose class, zone or name contains a word in the brackets |
| `-only (…)` | `-only (priest paladin)` | Whisper only people matching a word in the brackets |
| `-cd D` | `-cd 30`, `-cd 2h`, `-cd 30d` | Skip anyone on cooldown, then put each recipient on cooldown for the duration |
| `-cd` | `-cd` | Honour existing cooldowns without adding anyone new to the list |
| `-who (…)` | `-who (mage 50-60 stormwind)` | Run the `/who` as part of the command, quietly |

To aim a `-skip` or `-only` word at one field, lead it with the key `/who` uses: `c-` class, `z-` zone, `n-` name, `g-` guild, `r-` race. Phrases with spaces go in quotes: `-skip (z-"Blackrock Depths")`.

A bare `-cd` number is minutes; `s`, `m`, `h` and `d` set seconds, minutes, hours and days. Leaving `-cd` off entirely ignores the cooldown list — everyone gets whispered and nobody is recorded.

`-limit` and `-cd` also work on `/rr` and `/ws`.

```
/ww -who (55-60) -limit 20 -skip (c-warlock) -cd 15 LFM SM live, need 1 tank
```

Up to 20 non-warlocks between 55 and 60, on a 15-minute cooldown.

## Commands

| Command | What it does |
| --- | --- |
| `/ww MESSAGE` | Whisper everyone in your `/who` results |
| `/wt MESSAGE` | Whisper your current target |
| `/ws MESSAGE` | Whisper every seller in the auction house Browse tab |
| `/rr MESSAGE` | Reply to everyone whispered via `/ww` who answered and is still waiting |
| `/rr` | Report how many people are waiting, naming them when there are ten or fewer |
| `/rr reset` | Forget all tracked recipients and their replies |
| `/ss` | Open the command reference panel |
| `/ss stop` | Cancel any whispers still queued |
| `/ss quiet on\|off` | Toggle the in-place counter (on by default) |
| `/ss rate` | Show the learned send rate, `/ss rate reset` restores the default |
| `/ss -cd` | Show how many names are on cooldown and how long the longest runs |
| `/ss -cd NAME [DURATION]` | Put a player on cooldown by hand (30 days by default) |
| `/ss -cd clear` | Empty the cooldown list |
| `/ss -block NAME` | Block a player permanently; `-block list` and `-unblock NAME` manage the list |

## Requirements

WoW Classic Era 1.15.x. Questie is optional, for the quest-link-into-macro feature.

## Restrictions

- The server rate-limits whispers: roughly 10 of burst, then under one per second. The queue paces itself to stay just under that limit and calibrates the exact rate over a few runs, so a long run takes as long as the server makes it take.
- `/who` itself is throttled to about one search every few seconds. A `-who` run that gets throttled aborts with a notice rather than whispering the previous search's list.
- `/who` results are capped by the server. A capped answer reports the total so you can narrow the filter.
- Offline players, players ignoring you and wrong-faction targets are dropped from the run rather than retried.
- The modifier-click shortcuts (Ctrl-click whisper, Cmd/Alt-click invite, Opt/Win-click add friend) now live in the standalone **SuperSocial Shortcuts** WeakAura. Import that to keep them.
- A quest link that would exceed the 255-character macro limit is refused with a chat notice instead of being cut off.
