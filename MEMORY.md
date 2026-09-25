# SuperSocial — Memory

Updated 2026-09-25 after the dual-client port with native UI (decision: every addon in the folder supports both clients, with each client's own look). Verified against Gethe `forever` @ `bd2470a` (1.60.1.70009), Gethe `classic_era` @ `33e177d` (1.15.9.69722) and the matching Ketho dumps. Nothing has run in a client. `Tools/harness.lua` passes all four variants (vanilla/camelot × strict/lenient), which proves logic, not client behaviour.

## Current state

Commands:

- `/ww MESSAGE` whispers everyone in the current `/who` results. Flags: `-limit`, `-skip (…)`, `-only (…)`, `-cd`, `-who (…)`, and `;` to split a message.
- `/wt` whispers your target.
- `/ws` whispers the sellers on the current AH browse page. Era only.
- `/rr` replies to people who answered within 15 min.
- `/ss` manages the block and cooldown lists and opens a reference panel.

Every whisper is confirmed by its server echo, and the send rate calibrates itself.

| Item | State |
|---|---|
| Version | 4.1.0, both clients from one toc, `## Interface: 11509, 16001`, `## Author: miyanko` |
| Git | Committed and pushed on 2026-09-25: `main` = `origin/main`. The Questie integration stays removed. GitHub's README restructure and author fix were merged with the local README and toc kept. The last Era-only release is 4.0.0 at `2b16d40` |

Client differences:

- Names: one name rule in `Core/Names.lua`. The key is the lowercase first name plus the second part, with space and hyphen treated as the same separator. It matches "Name", "Name-Realm", "First Surname" and "First-Surname". A bare first name matches any full form of it. Every comparison goes through it: echo confirmation, block and cooldown lists, group skip, `/rr`, and the quiet filter. Block and cooldown lists are re-keyed once (`nameKeyFormat = 2`).
- `/wt` sends Blizzard's unit-menu form, which is "First Surname" on Forever.
- `/ws` registers only where `GetNumAuctionItems` and `GetAuctionItemInfo` exist, which is Era only. Forever's modern AH doesn't expose sellers.
- Whisper colour blend: removed on both clients (2026-09-25, user decision). Any addon write to `ChatTypeInfo.WHISPER` would taint Blizzard's secret-sender comparison on Forever (`ChatFrameOverrides.lua:677-696`). Don't add it back.
- The rest sits in `Core/Compat.lua`:
  - the send API (`C_ChatInfo.SendChatMessage`)
  - lockdown plus `ADDON_RESTRICTION_STATE_CHANGED`
  - the Who frame: `WhoFrame` on Era, the load-on-demand `LFGWhoListFrame` on 1.60
  - the chat filter API
  - `ERR_*` strings with English fallbacks
- Help panel: `BasicFrameTemplateWithInset` and `ScrollFrameTemplate`, both per-client art.

## Blockers, issues, challenges

1. No source pins which name spelling Forever uses for `GetWhoInfo().fullName`, the whisper echo, incoming whispers and "player not found". The rule handles every form.
2. Also inferred, not proven: that the server accepts "First Surname" as a whisper target.
3. On Forever, a bare first name on the block or cooldown list covers every player with that first name. To name one player, use First-Surname (the README says so).
4. When chat lockdown is active on 1.60 is unknown, and so is whether the restriction event fires.
5. The 69913 beta may lose saved variables on a cold start, per Questie's docs. That would affect the lists, the learned rate and `/rr` tracking.
6. There's no `_classic_era_` install. The installed beta is 69913, the source is 70009.

## Next steps

1. You need an alt and a second player. Run `/console scriptErrors 1` first.

Both clients:

- [ ] `/who 60`, then `/ww -limit 3 test`: "3/3 sent", then "Sent all 3 whispers.", with no resend after 10 s.
- [ ] `/ww -who (60) -limit 2 test` with no Who or LFG panel open: results within 6 s, no panel opens.
- [ ] `/rr`: a friend whispers you, `/rr` lists them, `/rr thanks` sends, and the list empties.
- [ ] A 15+ whisper blast shows "Burst spent." and no yellow spam.
- [ ] `/ss` panel: each client's scroll bar inside the well, Escape closes it. `/ss -block <name>` survives `/reload`.

Era:

- [ ] Open the AH and do a Browse search, then `/ws -limit 2 hi`: two unique sellers, never you.
- [ ] `/wt` on a cross-realm target in a battleground sends "Name-Realm".

Forever:

- [ ] Run `/dump RegionalUniqueNamesEnabled(), UnitName("target"), UnitNameUnmodified("target")`, then `/dump C_FriendList.GetWhoInfo(1).fullName` after a `/who`. Record the spellings. This settles issue 1.
- [ ] `/wt hi` on a surnamed target prints "Whispered First Surname." and it arrives. This settles issue 2.
- [ ] Group with someone whose first name matches another player in `/who`: only the groupmate is skipped.
- [ ] `/ws` isn't registered and `/ss` doesn't list it.
- [ ] Get whispered inside a dungeon: no Lua error. `/ww` there prints "Chat restricted here.".
