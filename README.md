# Super Social

Mass-whisper and quick-reply social tools for WoW Classic 1.15.x.

## What it does

Run a `/who` search, then `/ww MESSAGE` whispers everyone in the results. That's the whole idea.

## Try it

1. Type `/who 25-30` in chat (or any filter you like).
2. When the results appear, type `/ww WTB Wool Cloth 1g/stack`.
3. Done — everyone in your `/who` results just got whispered.

You'll never whisper yourself, anyone in your party or raid, or anyone who was grouped with you in the last 15 minutes.

## Seven optional extras for /ww

Use any, all, or none — they compose in any order.

### Limit the count

```
/ww -limit 10 LFM SM live
```

Whispers only the first 10 people from your `/who` results. The same `-limit` works on `/rr` and `/ws`.

### Skip a class, zone or name

```
/ww -skip Warlock LFM tank for SM
/ww -skip Maraudon WTS Black Lotus 50g
/ww -skip Xander already asked him, LFM healer
/ww -skip Warlock,Maraudon LFM healer
/ww -skip Maraudon, Warlock LFM healer
```

`-skip` skips anyone whose class, zone **or** name contains the word: `-skip war` drops Warriors, anyone in Warsong Gulch and a player named Warence. All three are substring matches (class examples: Warrior, Mage, Warlock; zone examples: Maraudon, Stormwind; or any player name). Separate multiple with commas — spaces around the commas are fine (`Warlock,Maraudon` and `Warlock, Maraudon` both work). Note that a trailing comma means "another term follows", so the next word is read as a filter rather than part of your message.

### Whisper only certain classes, zones or names

```
/ww -only Priest,Paladin LFM healer for SM
/ww -only Mage WTS portals to any major city
```

`-only` is the inverse of `-skip`: it whispers **only** people whose class, zone or name contains the word, dropping everyone else. Same comma rules as `-skip`. Combine the two to include a class but drop a zone (`-skip Maraudon -only Priest`); when a player matches both, `-skip` wins and they're skipped.

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

### Run the /who yourself with -who

`-who` folds the search into the command, so one line does what a two-line macro did — and quietly: results skip your chat frame and the Who panel stays closed.

```
/ww -who 57-59 c-warrior -cd 60 -skip blackrock hey, would you be up for tanking BRD? :)
```

The filter is anything `/who` itself accepts, written as level ranges and keyed terms: `57-59`, `c-warrior`, `z-"Blackrock Depths"`, `r-`, `n-`, `g-`. The first word shaped like neither ends the filter and starts the flags or the message, so no closing quote is needed. One caveat follows from that: a message can't *begin* with something filter-shaped like `60` or `55-60` — put a word first.

The whisper waits for this query's own results. If the server answers empty or throttles the search (it allows roughly one `/who` every few seconds), the run aborts with a notice instead of whispering the previous search's list. A capped answer tells you how many matched in total: `50 of 137 online match. Narrow the filter to reach the rest.`

### Run /who and /ww in one click, the old way

`-wait` holds the whisper until fresh `/who` results arrive, for a two-line macro with its own `/who` line — useful when the query needs `/run` scripting:

```
/run C_FriendList.SendWho('z-"'..GetZoneText()..'" 60 c-Mage')
/ww -wait -limit 20 Got any spare food and water to share?
```

For everything else, `-who` does it in one line without opening the panel.

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

## Modifier-click shortcuts moved

The modifier-click shortcuts (Ctrl-click whispers, Cmd/Alt-click invites, Opt/Win-click adds friend) now live in the standalone **SuperSocial Shortcuts** WeakAura, so they can be shared without installing this addon. Import the WeakAura to keep them.

## Paste a Questie quest into a macro

Questie already pastes a quest link into an open chat box when you shift-click a quest in its tracker. This does the same for macros: open the macro window, pick a macro, then shift-click a tracked quest and its link lands in the macro body at the cursor.

```
/1 LFM [[15] The Defias Brotherhood (155)]
```

- Works on quest lines and their objective lines in the Questie tracker.
- An open chat edit box always wins, so the normal chat paste is untouched.
- Without the macro window open, shift-click keeps untracking the quest as before.
- The text is exactly what Questie would paste into chat, so the quest level shows only when Questie's own "show quest level" option is on.
- A paste that won't fit the 255 character macro limit is refused with a chat notice instead of being cut off.
- Achievement lines are left alone.

## Other commands

| Command | What it does |
|---|---|
| `/wt MESSAGE` | Whisper your current target. |
| `/wt -ignore MESSAGE` | Whisper your target and add them to the ignore list. |
| `/ws MESSAGE` | Whisper every seller in the auction house Browse tab. Takes `-limit N`, `-cd M`, and `-ignore` (sellers carry no class or zone, so `-skip`/`-only` don't apply). |
| `/rr MESSAGE` | Reply to everyone whispered via `/ww` who has whispered you back and hasn't been answered yet (minus your party and raid, including anyone who was grouped with you in the last 15 minutes). Recipients accumulate across `/ww` runs, and any reply — an earlier `/rr` or a manual whisper — counts as answered, so run several `/ww` queries, then one `/rr` handles them all without whispering anyone twice. People you've answered — via `/rr` or a manual whisper — stay excluded even if they whisper again; only a fresh `/ww` that includes them starts a new exchange. Takes `-limit N` (caps to the most recent repliers). |
| `/rr` | Report how many people are waiting on an answer, and name them when there are ten or fewer. |
| `/rr reset` or `/rr clear` | Forget all tracked `/ww` recipients and their replies. Tracking survives a `/reload` and a relog, and entries age out on their own after 15 minutes — a reply older than that is a stale conversation, not something to answer. |
| `/ss` | Open the command and parameter reference panel. |
| `/ss stop` | Cancel any whispers still queued to send (reports how many went out and how many were cancelled). |
| `/ss quiet` | Toggle replacing your own outgoing lines during a run with one in-place `Y/Z` counter. Covers `/ww`, `/ws` and `/rr`. On by default. `/ss quiet on` and `/ss quiet off` set it outright. |
| `/ss rate` | Show the learned send rate in whispers per second. |
| `/ss rate reset` | Restore the default send rate; the server re-teaches it from there. |
| `/ss -ignore` | Show how many names are on the ignore list and how old the oldest one is. |
| `/ss -ignore NAME` | Add a player to the ignore list by hand — the same list `-ignore` sends build. |
| `/ss -ignore clear` | Empty the ignore list. |
| `/ss -cd clear` | Empty the cooldown history. |
| `/ss -block NAME` | Block a player permanently: no command ever whispers them. The list is account-wide, survives reloads, and isn't touched by `/ss -ignore clear`. |
| `/ss -block list` | Show everyone on the block list. |
| `/ss -unblock NAME` | Remove a player from the block list. |

## Confirmed sends

Every whisper that lands is echoed back by the server itself (the `To Name: ...` line). The addon counts those echoes, so "sent" always means the server took it, not that the addon tried: `Sent all 20 whispers.` prints only when every whisper of the run was confirmed, and a run with losses closes with the honest split (`18 sent, 1 unreachable, 1 failed of 20 whispers.`).

A whisper that draws neither an echo nor an error within 10 seconds is re-sent, up to the shared 3-try budget, so a silently swallowed whisper is retried instead of stalling the run's bookkeeping.

## Sending at the server's maximum

The server rate-limits whispers with a token bucket (observed live: about 10 whispers of burst, then one yellow error per dropped message, refilling at under 1 per second). The queue mirrors that bucket client-side: the first 8 whispers go out instantly, then each further whisper is sent at the exact moment a token matures — timer-scheduled, never polled. That is the maximum sustainable rate that never provokes the server.

Because the refill rate is undocumented, the queue calibrates itself: a cap verdict halves the learned rate, a clean oversized run nudges it up, and the learned value is saved across sessions. Over a few runs it converges on the server's true limit and stays just under it. Unreachable targets (offline, ignoring you, wrong faction) don't count against a clean run, so they can't block the recovery. `/ss rate` shows the current value and `/ss rate reset` restores the default.

If the cap trips anyway, the queue takes a hard 10 second break, then risks a single probe whisper instead of blasting blind: the probe's echo proves the cap lifted and releases the rest, while another cap error costs only that one whisper and starts the next pause. Failed probes rotate to the back so no single whisper eats the risk.

No whisper is abandoned while the cap is closed: probe attempts never count against a whisper's retry budget, only swallows during a provably open cap do (3 of those and it's abandoned with a chat notice). If the server refuses every probe for about 3 minutes straight, the run aborts with a clear message. All commands share this cycle, `/rr` included, and unsent `/rr` replies go back on the unanswered list either way, so the next `/rr` picks those people up again — a reply is deferred, never lost.

## Server-side blocking, covered

The addon watches the system chat for every way the server can refuse a whisper, matching the client's own message strings first (locale-proof) with the verified English wording as fallback: the whisper cap, the free-trial tell limit (treated as the same cap), offline targets, players ignoring you, and wrong-faction targets. Unreachable people are removed from the run instead of retried, and the repeating yellow cap error is hidden while a run handles it. Late echoes are matched by their exact text, so a message the server delivers after the addon moved on can never corrupt the `/rr` bookkeeping.

## A quiet run, with a counter

A fifty person blast used to print fifty `To Playername:` lines, and the replies it drew arrived in the middle of them. Quiet mode replaces all of that with **one line that rewrites itself in place** as the run advances:

```
[Super Social]: Whispering 50 of 137 /who results, ~63s.
[Super Social]: Skipped 87: 12 blocked, 40 on the ignore list, 30 on cooldown, 5 in your group.
[Super Social]: Recorded: 50 on cooldown for 60 min.
[Super Social]: Sending: "LFM SM live, need a tank"
[Super Social]: 34/50 sent.
```

One fact per line, in the order they matter: who hears it, who doesn't and why, what the run wrote to your lists, then exactly what they'll receive. The opening line carries a rough finish time when the run outlasts the burst, priced at the learned send rate. The skipped and recorded lines appear only when there is something to say, so a run with no flags and nothing filtered is three lines and a verdict. A `;` message names each part in the order it goes out: `Sending: "Hey, how are you?" then "up for tanking Scholo?"`.

That last line is the same line throughout. It counts up in place and picks up `, 1 unreachable` if anyone drops out, so it never adds a line however many people the run reaches.

When the run finishes it stays a counter, and the verdict arrives as **its own message at the bottom of chat**:

```
[Super Social]: Whispering 50 of 137 /who results.
[Super Social]: Skipped 87: 12 blocked, 40 on the ignore list, 30 on cooldown, 5 in your group.
[Super Social]: Sending: "LFM SM live, need a tank"
[Super Social]: 50/50 sent.
[Super Social]: Skipping Ardynel. Unreachable, removed from this run.
[Super Social]: Sent all 50 whispers.
```

The counter sits wherever it was printed, so anything the run reports along the way lands underneath it. Closing on a fresh line means the outcome is always the last thing you see, whatever else happened in between.

`/ss stop` freezes the counter where it got to and marks it: `12/50 sent, stopped.`

### What it covers

Every bulk command works the same way: `/ww`, `/ws` and `/rr` all count instead of printing, and each closes with its own bottom line. `/wt` always prints, because a single hand-aimed whisper is its own confirmation and starts no run to count.

Counting is untouched. The queue confirms every whisper on its own event, which chat filters never reach, so the counter and the verdict are exactly as honest as before.

Turn it off with `/ss quiet off`. Every line comes back and the counter keeps running alongside them.

## Chat feedback

Every stage of a run reports to your chat frame on its own line, and one colour convention runs through the whole addon:

| Colour | Means |
| --- | --- |
| Yellow | the `[Super Social]` tag, nothing else |
| Green | what went out, and actions that completed |
| Red | what didn't go out, and everyone excluded |
| Blue | list bookkeeping: cooldowns, the ignore list, the whisper cap |

A line colours its lead token only and leaves the body white, so your eye lands on the same spot every time. The one exception is a line reporting a mix of outcomes, where each count takes its own colour (`2 sent, 1 unreachable of 3 whispers.`).

| Moment | Line |
|---|---|
| Who hears it | `Whispering 20 of 34 /who results, ~15s.` |
| Who doesn't | `Skipped 14: 1 blocked, 2 on the ignore list, 11 on cooldown.` |
| What was recorded | `Recorded: 20 on cooldown for 60 min.` |
| What they'll get | `Sending: "LFM SM live, need a tank"` |
| Burst budget spent | `Burst budget spent. Pacing the remaining 12 at 0.80/s so the server keeps accepting.` |
| Cap trips | `Whisper cap hit. 16 of 50 sent so far, slowing to 0.40/s and pausing 10s.` |
| Pause ends | `Probing with Playername, 5 waiting.` |
| Probe swallowed | `Still capped. 5 waiting, pausing another 10s.` |
| Probe gets through | `Cap lifted. 5 whispers to go.` |
| Queuing during the pause | `Cap active. 5 queued until the server accepts again.` |
| Target unreachable | `Skipping Playername. Unreachable, removed from this run.` |
| Retries exhausted | `Gave up on whispering Playername after 3 tries.` |
| Run in flight | `12/20 sent.` (one line, rewritten in place) |
| Whispers still going | the counter keeps ticking wherever it was printed |
| Run ends, all confirmed | `Sent all 20 whispers.` |
| A single whisper run | `Sent 1 whisper.` |
| Run ends with losses | `18 sent, 1 unreachable, 1 failed of 20 whispers.` |

If no recipients are eligible (everyone got filtered out), you'll see a single line saying so along with the skip breakdown — useful for working out which flag is being too aggressive.

## Chat colour

Incoming whispers are recoloured to a softer blend of your outgoing whisper colour, so both sides of a conversation read consistently. The addon's own status lines carry a yellow `[Super Social]` tag.
