# WhisperThemAll

Mass-whisper and quick-reply tools for WoW Classic 1.15.x.

## What it does

Run a `/who` search, then `/ww MESSAGE` whispers everyone in the results. That's the whole idea.

## Try it

1. Type `/who 25-30` in chat (or any filter you like).
2. When the results appear, type `/ww WTB Wool Cloth 1g/stack`.
3. Done — everyone in your `/who` results just got whispered.

You'll never whisper yourself or anyone in your party or raid.

If a single `/ww` or `/ws` run would whisper more than 20 people, you'll get a confirmation prompt first so a near-full list can't go out by accident.

## Six optional extras for /ww

Use any, all, or none — they compose in any order.

### Limit the count

```
/ww -limit 10 LFM SM live
```

Whispers only the first 10 people from your `/who` results. The same `-limit` works on `/rr` and `/ws`.

### Skip a class or zone

```
/ww -skip Warlock LFM tank for SM
/ww -skip Maraudon WTS Black Lotus 50g
/ww -skip Warlock,Maraudon LFM healer
/ww -skip Maraudon, Warlock LFM healer
```

`-skip` skips anyone whose class **or** zone contains the word: `-skip war` drops Warriors and anyone in Warsong Gulch. Both are substring matches (class examples: Warrior, Mage, Warlock; zone examples: Maraudon, Stormwind). Separate multiple with commas — spaces around the commas are fine (`Warlock,Maraudon` and `Warlock, Maraudon` both work). Note that a trailing comma means "another term follows", so the next word is read as a filter rather than part of your message.

### Skip everyone already in an instance

```
/ww -skip instance LFM tank for SM
```

`instance` is a shorthand that expands to every classic dungeon and raid name (Ragefire Chasm through Naxxramas), so anyone already inside an instance is skipped — handy when recruiting, since those people can't join you anyway. It works inside `-only` too (`-only instance` whispers only people currently in one) and mixes with other terms (`-skip instance, Warlock`). Battlegrounds aren't included.

### Whisper only certain classes or zones

```
/ww -only Priest,Paladin LFM healer for SM
/ww -only Mage WTS portals to any major city
```

`-only` is the inverse of `-skip`: it whispers **only** people whose class or zone contains the word, dropping everyone else. Same comma rules as `-skip`. Combine the two to include a class but drop a zone (`-skip Maraudon -only Priest`); when a player matches both, `-skip` wins and they're skipped.

### Don't whisper the same people twice

```
/ww -ignore Selling enchant mats, whisper for list
```

`-ignore` whispers everyone, then **remembers** each recipient. Run `/ww -ignore` again and those people are skipped. The list survives reloads. Clear it with `/wta clear`.

Use `-ignore` when you're pitching the same thing over a long session and want to make sure nobody hears it twice.

### Cool off recipients for a while

```
/ww -cd 30 WTB Black Lotus, paying 80g
```

`-cd 30` whispers everyone, then puts each recipient on a 30-minute cooldown. Run `/ww -cd 30` again within that window and the people you just whispered are skipped. Cooldowns age out on their own. Clear early with `/wta clear cd`.

Use `-cd 30` when you'll repeat the same broadcast every few minutes.

**Bare `-cd` (no minutes)** behaves differently:

```
/ww -cd LFM SM live, need 1 tank
```

It skips anyone **already** on the cooldown list but does **not** add the people it whispers. Use it to honour an existing cooldown for a one-off message without resetting everyone's timer — for example, a quick follow-up between your timed `-cd 30` broadcasts.

Leaving `-cd` off entirely ignores the cooldown list completely: everyone in your `/who` results gets whispered and nobody is recorded.

### Combine freely

```
/ww -limit 20 -skip Warlock -cd 15 LFM SM live, need 1 tank
```

Up to 20 non-warlocks, on a 15-minute cooldown. Order doesn't matter.

## Other commands

| Command | What it does |
|---|---|
| `/wt MESSAGE` | Whisper your current target. |
| `/wt -ignore MESSAGE` | Whisper your target and add them to the ignore list. |
| `/ws MESSAGE` | Whisper every seller in the auction house Browse tab. Takes `-limit N`, `-cd M`, and `-ignore` (sellers carry no class or zone, so `-skip`/`-only` don't apply). |
| `/rr MESSAGE` | Reply to everyone from your last `/ww` who has whispered you back (minus your party and raid). Each `/ww` starts a fresh batch, so `/rr` always targets the latest blast. Takes `-limit N` (caps to the most recent repliers). |
| `/rr reset` or `/rr clear` | Forget the current batch and its replies. The batch isn't saved, so a `/reload`, re-login, or the next `/ww` resets it too. |
| `/wta` | Open the command and parameter reference window. |
| `/wta stop` | Cancel any whispers still queued to send (reports how many went out and how many were cancelled). |
| `/wta reset` or `/wta clear` | Empty the ignore list. |
| `/wta clear cd` | Empty the cooldown history. |
| `/wta clear all` | Empty both. |

## Throttling

Whispers are sent one every 250ms rather than all at once, so a big `/ww`, `/ws`, or `/rr` run stays under Blizzard's chat throttle instead of silently dropping messages or disconnecting you. The chat summary prints immediately; the whispers themselves trickle out over the following seconds. Spotted a mistake mid-run? `/wta stop` cancels whatever's still queued.

## Chat feedback

Every `/ww` run prints a short summary to your chat frame: how many of your `/who` results are being whispered and how many were skipped.

If no recipients are eligible (everyone got filtered out), you'll see a single line saying so along with the skip breakdown — useful for working out which flag is being too aggressive.

## Chat colour

Incoming whispers are recoloured to a softer blend of your outgoing whisper colour, so both sides of a conversation read consistently. The `[Whisper Them All]` tag on the addon's own status lines uses that same colour.
