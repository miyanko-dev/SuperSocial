# WhisperThemAll

Mass-whisper and quick-reply tools for WoW Classic 1.15.x.

## What it does

Run a `/who` search, then `/ww MESSAGE` whispers everyone in the results. That's the whole idea.

## Try it

1. Type `/who 25-30` in chat (or any filter you like).
2. When the results appear, type `/ww WTB Wool Cloth 1g/stack`.
3. Done — everyone in your `/who` results just got whispered.

You'll never whisper yourself or anyone in your party or raid.

## Four optional extras for /ww

Use any, all, or none — they compose in any order.

### Limit the count

```
/ww -limit 10 LFM SM live
```

Whispers only the first 10 people from your `/who` results.

### Skip a class or zone

```
/ww -not Warlock LFM tank for SM
/ww -not Maraudon WTS Black Lotus 50g
/ww -not Warlock,Maraudon LFM healer
```

`-not` skips anyone whose class matches (Warrior, Mage, Warlock, …) or whose zone contains the word (Maraudon, Stormwind, …). Separate multiple with commas — no spaces around them.

### Don't whisper the same people twice

```
/ww -skip Selling enchant mats, whisper for list
```

`-skip` whispers everyone, then **remembers** each recipient. Run `/ww -skip` again and those people are skipped. The list survives reloads. Clear it with `/wta clear skip`.

Use `-skip` when you're pitching the same thing over a long session and want to make sure nobody hears it twice.

### Cool off recipients for a while

```
/ww -cd 30 WTB Black Lotus, paying 80g
```

`-cd 30` whispers everyone, then puts each recipient on a 30-minute cooldown. Run `/ww -cd 30` again within that window and the people you just whispered are skipped. Cooldowns age out on their own. Clear early with `/wta clear cd`.

Use `-cd` when you'll repeat the same broadcast every few minutes.

### Combine freely

```
/ww -limit 20 -not Warlock -cd 15 LFM SM live, need 1 tank
```

Up to 20 non-warlocks, on a 15-minute cooldown. Order doesn't matter.

## Other commands

| Command | What it does |
|---|---|
| `/wt MESSAGE` | Whisper your current target. |
| `/wt -skip MESSAGE` | Whisper your target and add them to the skip list. |
| `/ws MESSAGE` | Whisper every seller in the auction house Browse tab. |
| `/rr [-N] [-name…] MESSAGE` | Reply to recent whisperers. `-N` caps to the last N; any other `-word` skips names containing that substring (e.g. `-bob`). |
| `/rr reset` | Clear the session reply tracker. |
| `/wta` | Print the command and parameter reference to chat. |
| `/wta clear skip` | Empty the skip list. |
| `/wta clear cd` | Empty the cooldown history. |
| `/wta clear all` | Empty both. |

## Chat feedback

Every `/ww` run prints two short summaries to your chat frame:

- **Before sending** — how many of your `/who` results will be whispered, and what each active flag is doing on this run.
- **After sending** — how many whispers went out, what was skipped and why, and any persistent state that changed (new entries added to the skip list, new cooldowns recorded).

If no recipients are eligible (everyone got filtered out), you'll see a single line saying so along with the skip breakdown — useful for working out which flag is being too aggressive.

## Chat colour

Incoming whispers are recoloured to a softer blend of your outgoing whisper colour, so both sides of a conversation read consistently.
