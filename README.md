# Super Social

Mass-whisper, quick-reply and modifier-click social tools for WoW Classic 1.15.x.

## What it does

Run a `/who` search, then `/ww MESSAGE` whispers everyone in the results. That's the whole idea.

On top of that, modifier-clicking any player name in the UI whispers, invites, or friends them without typing a command.

## Try it

1. Type `/who 25-30` in chat (or any filter you like).
2. When the results appear, type `/ww WTB Wool Cloth 1g/stack`.
3. Done — everyone in your `/who` results just got whispered.

You'll never whisper yourself, anyone in your party or raid, or anyone who was grouped with you in the last 15 minutes.

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

`-ignore` whispers everyone, then **remembers** each recipient. Run `/ww -ignore` again and those people are skipped. The list survives reloads and entries age out after 30 days on their own. Clear it early with `/ss -ignore clear`.

Use `-ignore` when you're pitching the same thing over a long session and want to make sure nobody hears it twice.

### Cool off recipients for a while

```
/ww -cd 30 WTB Black Lotus, paying 80g
```

`-cd 30` whispers everyone, then puts each recipient on a 30-minute cooldown. Run `/ww -cd 30` again within that window and the people you just whispered are skipped. The cooldown list is account-wide and survives reloads and relogs, so it keeps working across your characters. Cooldowns age out on their own. Clear early with `/ss -cd clear`.

Use `-cd 30` when you'll repeat the same broadcast every few minutes.

**Bare `-cd` (no minutes)** behaves differently:

```
/ww -cd LFM SM live, need 1 tank
```

It skips anyone **already** on the cooldown list but does **not** add the people it whispers. Use it to honour an existing cooldown for a one-off message without resetting everyone's timer — for example, a quick follow-up between your timed `-cd 30` broadcasts.

Leaving `-cd` off entirely ignores the cooldown list completely: everyone in your `/who` results gets whispered and nobody is recorded.

### Run /who and /ww in one click

Normally you type `/who`, wait for the results, then `/ww`. `-wait` lets a single macro do both: it holds the whisper until the fresh `/who` results arrive, then sends. Put the `/who` on the first line and `/ww -wait` on the second:

```
/who 25-30
/ww -wait LFM SM live, need a tank
```

Only useful in a macro alongside a `/who` — on its own it just waits for the next search. Great for pairing a targeted search with a broadcast, e.g. a zone-and-class `/who`:

```
/run C_FriendList.SendWho('z-"'..GetZoneText()..'" 60 c-Mage')
/ww -wait -limit 20 Got any spare food and water to share?
```

### Combine freely

```
/ww -limit 20 -skip Warlock -cd 15 LFM SM live, need 1 tank
```

Up to 20 non-warlocks, on a 15-minute cooldown. Flag order doesn't matter, but flags go **before** the message: a known flag found inside the message aborts the send with a notice instead of whispering it as text.

## Split a message into several whispers

```
/ww Hey, how are you? ; up for tanking Scholo?
```

A `;` splits the message: each recipient gets the part before it and the part after it as two separate whispers, back to back. More than one `;` sends more parts. Works on `/ww`, `/wt`, `/ws`, and `/rr`, and combines with every flag.

## Modifier-click shortcuts

Hold a modifier and left-click a player name anywhere in the UI to act on them instantly, no command needed.

| Action | Mac | Windows |
| --- | --- | --- |
| Whisper | Ctrl-click | Ctrl-click |
| Invite | Cmd-click | Alt-click |
| Add friend | Option-click | Win-click |

Whispering a chat name opens that player's own whisper tab and focuses its edit box, reusing the tab if it already exists. Whispering a unit frame presets the normal chat edit box instead, because a secure click cannot open a tab without taint. Invite and add friend act immediately.

Click targets:

- Player names in chat
- Target and target-of-target frames
- Party frames
- Raid frames and raid-style party frames
- Friends list, who list and guild roster in the friends panel
- Group listings in the LFG browse panel, acting on the leader

Only left clicks with a modifier are handled, so plain clicks keep their default behavior. Clicks on unit frames still target the unit first, since the secure click cannot be suppressed without taint. Shortcuts never fire on yourself or on NPCs.

## Other commands

| Command | What it does |
|---|---|
| `/wt MESSAGE` | Whisper your current target. |
| `/wt -ignore MESSAGE` | Whisper your target and add them to the ignore list. |
| `/ws MESSAGE` | Whisper every seller in the auction house Browse tab. Takes `-limit N`, `-cd M`, and `-ignore` (sellers carry no class or zone, so `-skip`/`-only` don't apply). |
| `/rr MESSAGE` | Reply to everyone whispered via `/ww` who has whispered you back and hasn't been answered yet (minus your party and raid, including anyone who was grouped with you in the last 15 minutes). Recipients accumulate across `/ww` runs, and any reply — an earlier `/rr` or a manual whisper — counts as answered, so run several `/ww` queries, then one `/rr` handles them all without whispering anyone twice. People you've answered — via `/rr` or a manual whisper — stay excluded even if they whisper again; only a fresh `/ww` that includes them starts a new exchange. Takes `-limit N` (caps to the most recent repliers). |
| `/rr reset` or `/rr clear` | Forget all tracked `/ww` recipients and their replies. Tracking isn't saved, so a `/reload` or re-login clears it too. |
| `/ss` | Open the command and parameter reference panel. |
| `/ss stop` | Cancel any whispers still queued to send (reports how many went out and how many were cancelled). |
| `/ss rate` | Show the learned send rate in whispers per second. |
| `/ss rate reset` | Restore the default send rate; the server re-teaches it from there. |
| `/ss -ignore NAME` | Add a player to the ignore list by hand — the same list `-ignore` sends build. |
| `/ss -ignore clear` | Empty the ignore list. |
| `/ss -cd clear` | Empty the cooldown history. |
| `/ss -block NAME` | Block a player permanently: no command ever whispers them. The list is account-wide, survives reloads, and isn't touched by `/ss -ignore clear`. |
| `/ss -block list` | Show everyone on the block list. |
| `/ss -unblock NAME` | Remove a player from the block list. |

## Confirmed delivery

Every delivered whisper is echoed back by the server itself (the `To Name: ...` line). The addon counts those echoes, so its closing line is a real delivery confirmation, not a guess: `Delivered all 20 whispers.` prints only when every whisper of the run was confirmed by the server, and a run with losses closes with the honest split (`18 delivered, 1 unreachable, 1 failed of 20 whispers.`).

A whisper that draws neither an echo nor an error within 10 seconds is re-sent, up to the shared 3-try budget, so a silently swallowed whisper is retried instead of stalling the run's bookkeeping.

## Sending at the server's maximum

The server rate-limits whispers with a token bucket (observed live: about 10 whispers of burst, then one yellow error per dropped message, refilling at under 1 per second). The queue mirrors that bucket client-side: the first 8 whispers go out instantly, then each further whisper is sent at the exact moment a token matures — timer-scheduled, never polled. That is the maximum sustainable rate that never provokes the server.

Because the refill rate is undocumented, the queue calibrates itself: a cap verdict halves the learned rate, a clean oversized run nudges it up, and the learned value is saved across sessions. Over a few runs it converges on the server's true limit and stays just under it. Unreachable targets (offline, ignoring you, wrong faction) don't count against a clean run, so they can't block the recovery. `/ss rate` shows the current value and `/ss rate reset` restores the default.

If the cap trips anyway, the queue takes a hard 10 second break, then risks a single probe whisper instead of blasting blind: the probe's echo proves the cap lifted and releases the rest, while another cap error costs only that one whisper and starts the next pause. Failed probes rotate to the back so no single whisper eats the risk.

No whisper is abandoned while the cap is closed: probe attempts never count against a whisper's retry budget, only swallows during a provably open cap do (3 of those and it's abandoned with a chat notice). If the server refuses every probe for about 3 minutes straight, the run aborts with a clear message. All commands share this cycle, `/rr` included, and undeliverable `/rr` replies go back on the unanswered list either way, so the next `/rr` picks those people up again — a reply is deferred, never lost.

## Server-side blocking, covered

The addon watches the system chat for every way the server can refuse a whisper, matching the client's own message strings first (locale-proof) with the verified English wording as fallback: the whisper cap, the free-trial tell limit (treated as the same cap), offline targets, players ignoring you, and wrong-faction targets. Unreachable people are removed from the run instead of retried, and the repeating yellow cap error is hidden while a run handles it. Late echoes are matched by their exact text, so a message the server delivers after the addon moved on can never corrupt the `/rr` bookkeeping.

## Chat feedback

Every stage of a run reports to your chat frame in the addon's colors: green for progress, red for problems, blue for cooldown status.

| Moment | Line |
|---|---|
| Run starts | `Whispering 20 of 34 /who results, 14 skipped (...)` |
| Burst budget spent | `Burst budget spent. Pacing the remaining 12 at 0.80/s so the server keeps accepting.` |
| Cap trips | `Whisper cap hit. 16 of 20 delivered so far, slowing to 0.40/s and pausing 10s.` |
| Pause ends | `Probing with Playername, 5 waiting.` |
| Probe swallowed | `Still capped. 5 waiting, pausing another 10s.` |
| Probe delivered | `Cap lifted. 5 whispers to go.` |
| Queuing during the pause | `Cap active. 5 queued until the server accepts again.` |
| Target unreachable | `Skipping Playername. Unreachable, removed from this run.` |
| Retries exhausted | `Gave up on whispering Playername after 3 tries.` |
| Run ends, all confirmed | `Delivered all 20 whispers.` |
| Run ends with losses | `18 delivered, 1 unreachable, 1 failed of 20 whispers.` |

If no recipients are eligible (everyone got filtered out), you'll see a single line saying so along with the skip breakdown — useful for working out which flag is being too aggressive.

## Chat colour

Incoming whispers are recoloured to a softer blend of your outgoing whisper colour, so both sides of a conversation read consistently. The addon's own status lines carry a yellow `[Super Social]` tag.
