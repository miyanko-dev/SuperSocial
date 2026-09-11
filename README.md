# Super Social

Mass-whisper and quick-reply social tools for WoW Classic 1.15.x.

## What it does

Run a `/who` search, then `/ww MESSAGE` whispers everyone in the results. That's the whole idea.

## Try it

1. Type `/who 25-30` in chat (or any filter you like).
2. When the results appear, type `/ww WTB Wool Cloth 1g/stack`.
3. Done — everyone in your `/who` results just got whispered.

You'll never whisper yourself, anyone in your party or raid, or anyone who was grouped with you in the last 15 minutes.

## Five optional extras for /ww

Use any, all, or none — they compose in any order. One rule covers the shape: a single number stands bare (`-limit 10`, `-cd 30`), anything with more than one word goes in brackets (`-skip (warlock maraudon)`).

### Limit the count

```
/ww -limit 10 LFM SM live
```

Whispers only the first 10 people from your `/who` results. The same `-limit` works on `/rr` and `/ws`.

### Skip a class, zone or name

```
/ww -skip (warlock) LFM tank for SM
/ww -skip (maraudon) WTS Black Lotus 50g
/ww -skip (xander) already asked him, LFM healer
/ww -skip (warlock maraudon) LFM healer
```

`-skip` drops anyone whose class, zone **or** name contains a word in the brackets: `-skip (war)` drops Warriors, anyone in Warsong Gulch and a player named Warence. Several words go in the same brackets, separated by spaces.

To aim at one field, lead the word with the same key `/who` uses: `c-` for class, `z-` for zone, `n-` for name.

```
/ww -skip (c-warrior z-warsong) LFM tank
/ww -skip (z-"Blackrock Depths" n-xander) LFM healer
```

`c-warrior` now drops only Warriors, not Warsong Gulch. A phrase with spaces goes in quotes. Keyed and bare words mix freely inside one pair of brackets.

### Whisper only certain classes, zones or names

```
/ww -only (priest paladin) LFM healer for SM
/ww -only (c-mage) WTS portals to any major city
```

`-only` is the inverse of `-skip`: it whispers **only** people matching a word in the brackets, dropping everyone else. Same keys, same quoting. Combine the two to include a class but drop a zone (`-skip (z-maraudon) -only (priest)`); when a player matches both, `-skip` wins and they're skipped.

### Cool off recipients for a while

```
/ww -cd 30 WTB Black Lotus, paying 80g
/ww -cd 2h LFM SM live, need 1 tank
/ww -cd 30d Selling enchant mats, whisper for list
```

`-cd` whispers everyone not already on cooldown, then puts each recipient on cooldown for the duration. A bare number is minutes; `s`, `m`, `h` and `d` spell seconds, minutes, hours and days. Run the same `-cd` again within the window and the people you just whispered are skipped. The list is account-wide and survives reloads and relogs, so it keeps working across your characters. Entries expire on their own. Clear early with `/ss -cd clear`, inspect with `/ss -cd`.

Use `-cd 30` when you'll repeat the same broadcast every few minutes. Use `-cd 30d` when you're pitching the same thing over a long stretch and nobody should hear it twice — this is what the old `-ignore` flag did.

**Bare `-cd` (no duration)** behaves differently:

```
/ww -cd LFM SM live, need 1 tank
```

It skips anyone **already** on cooldown but does **not** add the people it whispers. Use it to honour existing cooldowns for a one-off message without resetting everyone's timer — for example, a quick follow-up between your timed `-cd 30` broadcasts.

Leaving `-cd` off entirely ignores the cooldown list completely: everyone in your `/who` results gets whispered and nobody is recorded.

### Run the /who yourself with -who

`-who` folds the search into the command, so one line does what a two-line macro did — and quietly: results skip your chat frame and the Who panel stays closed.

```
/ww -who (mage 50-60 stormwind) -cd 60 hey, got a portal to spare? :)
```

The filter always goes in brackets right after the flag. Inside the brackets write anything `/who` itself accepts: bare words match class, zone, name, race or guild (`mage`, `stormwind`, `Xander`), level ranges narrow by level (`50-60`, `60`), and the keyed terms still work when a word is ambiguous (`c-warrior`, `z-"Blackrock Depths"`, `n-`, `g-`, `r-`). The closing bracket ends the filter, so the message may start with anything, numbers included.

```
/ww -who (warrior 57-59) -skip blackrock LFM tank for BRD
/ww -who (z-"Blackrock Depths" 55-60) 60 mage here, need a summon?
```

`-who` without brackets, with empty brackets, or with the closing bracket missing aborts with a notice that names the slip. The brackets are mandatory, there is no unbracketed form.

The whisper waits for this query's own results. If the server answers empty or throttles the search (it allows roughly one `/who` every few seconds), the run aborts with a notice instead of whispering the previous search's list. A capped answer tells you how many matched in total: `50 of 137 online match. Narrow the filter to reach the rest.`

### Combine freely

```
/ww -who (55-60) -limit 20 -skip (c-warlock) -cd 15 LFM SM live, need 1 tank
```

Up to 20 non-warlocks between 55 and 60, on a 15-minute cooldown. Flag order doesn't matter, but flags go **before** the message: a known flag found inside the message aborts the send with a notice instead of whispering it as text. A bracket flag without its brackets, with empty brackets, or with the closing bracket missing aborts with a notice naming the slip.

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
| `/wt -cd 30d MESSAGE` | Whisper your target and put them on cooldown for the duration. |
| `/ws MESSAGE` | Whisper every seller in the auction house Browse tab. Takes `-limit N` and `-cd D` (sellers carry no class or zone, so `-skip`/`-only` don't apply). |
| `/rr MESSAGE` | Reply to everyone whispered via `/ww` who has whispered you back and hasn't been answered yet (minus your party and raid, including anyone who was grouped with you in the last 15 minutes). Recipients accumulate across `/ww` runs, and any reply — an earlier `/rr` or a manual whisper — counts as answered, so run several `/ww` queries, then one `/rr` handles them all without whispering anyone twice. People you've answered — via `/rr` or a manual whisper — stay excluded even if they whisper again; only a fresh `/ww` that includes them starts a new exchange. Takes `-limit N` (caps to the most recent repliers). |
| `/rr` | Report how many people are waiting on an answer, and name them when there are ten or fewer. |
| `/rr reset` or `/rr clear` | Forget all tracked `/ww` recipients and their replies. Tracking survives a `/reload` and a relog, and entries age out on their own after 15 minutes — a reply older than that is a stale conversation, not something to answer. |
| `/ss` | Open the command and parameter reference panel. |
| `/ss stop` | Cancel any whispers still queued to send (reports how many went out and how many were cancelled). |
| `/ss quiet` | Toggle replacing your own outgoing lines during a run with one in-place `Y/Z` counter. Covers `/ww`, `/ws` and `/rr`. On by default. `/ss quiet on` and `/ss quiet off` set it outright. |
| `/ss rate` | Show the learned send rate in whispers per second. |
| `/ss rate reset` | Restore the default send rate; the server re-teaches it from there. |
| `/ss -cd` | Show how many names are on cooldown and how long the longest one still runs. |
| `/ss -cd NAME` | Put a player on cooldown by hand for 30 days — the same list `-cd` sends build. |
| `/ss -cd NAME DURATION` | Same, with your own duration: `/ss -cd Thrall 2h`. |
| `/ss -cd clear` | Empty the cooldown list. |
| `/ss -block NAME` | Block a player permanently: no command ever whispers them. The list is account-wide, survives reloads, and isn't touched by `/ss -cd clear`. |
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
[Super Social]: Whispering 50 of 137 /who results, ~63s, 60 min cooldown.
[Super Social]: Skipped 87: 12 blocked, 70 on cooldown, 5 in your group.
[Super Social]: Sending: "LFM SM live, need a tank"
[Super Social]: 34/50 sent.
```

One fact per line, in the order they matter: who hears it, who doesn't and why, then exactly what they'll receive. The opening line carries a rough finish time when the run outlasts the burst, priced at the learned send rate, and the cooldown the run records when `-cd` has a duration. The skipped line appears only when there is something to say, so a run with no flags and nothing filtered is three lines and a verdict. A `;` message names each part in the order it goes out: `Sending: "Hey, how are you?" then "up for tanking Scholo?"`.

That last line is the same line throughout. It counts up in place and picks up `, 1 unreachable` if anyone drops out, so it never adds a line however many people the run reaches.

When the run finishes it stays a counter, and the verdict arrives as **its own message at the bottom of chat**:

```
[Super Social]: Whispering 50 of 137 /who results.
[Super Social]: Skipped 87: 12 blocked, 70 on cooldown, 5 in your group.
[Super Social]: Sending: "LFM SM live, need a tank"
[Super Social]: 50/50 sent.
[Super Social]: Skipped Ardynel. Unreachable.
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
| Blue | list bookkeeping: cooldowns, the whisper cap |

A line colours its lead token only and leaves the body white, so your eye lands on the same spot every time. The one exception is a line reporting a mix of outcomes, where each count takes its own colour (`2 sent, 1 unreachable of 3 whispers.`).

| Moment | Line |
|---|---|
| Who hears it | `Whispering 20 of 34 /who results, ~15s, 60 min cooldown.` |
| Who doesn't | `Skipped 14: 1 blocked, 13 on cooldown.` |
| What they'll get | `Sending: "LFM SM live, need a tank"` |
| Burst budget spent | `Burst spent. Pacing 12 more at 0.80/s.` |
| Cap trips | `Whisper cap hit. 16/50 sent, slowing to 0.40/s, pausing 10s.` |
| Pause ends | `Probing with Playername, 5 waiting.` |
| Probe swallowed | `Still capped. 5 waiting, pausing another 10s.` |
| Probe gets through | `Cap lifted. 5 whispers to go.` |
| Queuing during the pause | `Cap active. 5 queued.` |
| Target unreachable | `Skipped Playername. Unreachable.` |
| Retries exhausted | `Gave up on Playername after 3 tries.` |
| Run in flight | `12/20 sent.` (one line, rewritten in place) |
| Whispers still going | the counter keeps ticking wherever it was printed |
| Run ends, all confirmed | `Sent all 20 whispers.` |
| A single whisper run | `Sent 1 whisper.` |
| Run ends with losses | `18 sent, 1 unreachable, 1 failed of 20 whispers.` |

If no recipients are eligible (everyone got filtered out), you'll see a single line saying so along with the skip breakdown — useful for working out which flag is being too aggressive.

## Chat colour

Incoming whispers are recoloured to a softer blend of your outgoing whisper colour, so both sides of a conversation read consistently. The addon's own status lines carry a yellow `[Super Social]` tag.
