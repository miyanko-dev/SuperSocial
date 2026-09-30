# SuperSocial — Memory

Updated 2026-09-30 after the Forever-only rework (5.0.0). The owner's decision is WoW Forever 1.60.x only: `main` holds the Forever version and `1.15.x-backup` keeps the dual-client 4.1.0. Verified against Gethe `forever` @ `966519cf` (1.60.1.70124) and Ketho `forever` @ `4149af64` (1.60.1.70009). The installed client is 1.60.1.70009. Nothing has run in a client. `Tools/harness.lua` passes 74/74 in `strict` and in `lenient`, which proves logic, not client behaviour.

## Current state

Commands:

- `/ww MESSAGE` whispers everyone in the current `/who` results. Flags: `-limit`, `-skip (…)`, `-only (…)`, `-cd`, `-who (…)`, and `;` to split a message.
- `/wt` whispers your target.
- `/rr` replies to people who answered within 15 min.
- `/ss` manages the block and cooldown lists and opens a reference panel.

Every whisper is confirmed by its server echo, and the send rate calibrates itself.

| Item | State |
|---|---|
| Version | 5.0.0, `## Interface: 16001`, `## Category: Social`, `## Author: miyanko`, icon `134149` |
| Git | `main`: `a6130d6` (split), `6878f57` (fixes), `1718da4` (panel), then this MEMORY commit. Not pushed. `1.15.x-backup` = `e715c8a` (dual-client 4.1.0), local and on GitHub, untouched. The Questie integration stays removed: `QuestMacro.lua` exists only in `20c515f`/`2b16d40`. The last Era-only release is 4.0.0 at `2b16d40` |
| Files | `Core/` logic (`Lockdown`, `Names`, `Format`, `Lists`, `Group`, `Flags`, `Queue`), `Commands/` slash commands (`Whisper`, `Reply`, `Admin`), `UI/Help.lua` panel, `Tools/` harness |
| Lua lines | shipped 2,248 → 2,044, harness 677 → 674 |

Names and client facts:

- Names: one name rule in `Core/Names.lua`. The key is the lowercase first name plus the second part, with space and hyphen treated as the same separator. It matches "Name", "Name-Realm", "First Surname" and "First-Surname". A bare first name matches any full form of it. Every comparison goes through it: echo confirmation, block and cooldown lists, group skip, `/rr`, and the quiet filter. `ns.UnitFullName` mirrors Mainline `GetFullPlayerName` (`UnitPopupUtils.lua:108-135`): surname with `CHARACTERNAME_SURNAME_SEPARATOR` when `RegionalUniqueNamesEnabled()`, else realm with `CHARACTERNAME_REALMNAME_SEPARATOR` across realms. An exact `/who` needs the hyphen form (`C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator`).
- `/wt` sends Blizzard's unit-menu form, which is "First Surname" when regionally unique names are on.
- Whisper colour blend: removed (2026-09-25, user decision). Any addon write to `ChatTypeInfo.WHISPER` would taint Blizzard's secret-sender comparison (`ChatFrameOverrides.lua:677-696`). Don't add it back.
- Forever APIs, called directly:
  - `C_ChatInfo.SendChatMessage(text, "WHISPER", nil, target)`, which isn't protected
  - `C_ChatInfo.InChatMessagingLockdown` plus `ADDON_RESTRICTION_STATE_CHANGED`
  - `ChatFrameUtil.AddMessageEventFilter`. The bare `SendChatMessage` and `ChatFrame_AddMessageEventFilter` exist only in `Blizzard_Deprecated*`
  - `canaccessvalue` for the secret guard. Blizzard's filter wrapper calls it under addon taint and reads the answer (`ChatFrameFilters.lua:27-42,115-118`)
- Who list: `LFGWhoListFrame` (load-on-demand `Blizzard_GroupFinder_VanillaStyle`) is the only `WHO_LIST_UPDATE` listener. Its OnShow/OnHide call `SetWhoToUi` (`WhoList.lua:247-253`), and it keeps `IsShown()` when `LFGParentFrame` closes, so restore reads `IsVisible()`. `GetNumWhoResults`/`GetWhoInfo` are `RequiresFriendList` (`FailureMode = "ReturnNothing"`).
- All `ERR_CHAT_*` verdict strings used exist with the same enUS text. `ERR_CHAT_WRONG_FACTION` doesn't exist, so the wrong-faction branch is gone; what the server says for a wrong-faction whisper is unknown.
- `ADDON_RESTRICTION_STATE_CHANGED`: `SynchronousEvent`, payload `(type, state)`. `Activating` means enforced once the dispatch completes (`RestrictedActionsConstantsDocumentation.lua`). Which `AddOnRestrictionType` values hide chat is not documented, so the payload is not read (SS-10).
- Forever's AH does expose sellers: `ItemSearchResultInfo.owners` and `CommoditySearchResultInfo.owners` (with `"player"` for your own), and `GetReplicateItemInfo` (`owner`, `ownerFullName`). Only Browse results carry none (`AuctionHouseDocumentation.lua:610-635,1612,1654`). Whether the server fills the names is UNVERIFIED. `/ws` (Era `GetAuctionItemInfo`) was removed; rebuilding it is an owner question.
- Help panel: `ButtonFrameTemplate` `SuperSocialFrame`, portrait `134149`, title "Super Social", strata HIGH, Escape via `UISpecialFrames`, `ButtonFrameTemplate_HideButtonBar`. The attic holds a `GameFontHighlight` intro and a `GameFontDisableSmall` hint under `TitleContainer`, word wrap off. The sections are `InsetFrameTemplate` boxes with `GameFontNormal` labels in a `ScrollFrameTemplate` inside `frame.Inset`. Gutter = `SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT` (6) + `ScrollBar:GetWidth()` (8, `MinimalScrollBar.xml`) + 8 px pad = 22. Toggle: `ns.TogglePanel`.
- `SuperSocialWAHost` was never part of SuperSocial. It came from the old "SuperSocial Shortcuts" WeakAura.
- Saved variables: `SuperSocialDB` is created lazily on first use. The Forever WTF had no SuperSocial file on 2026-09-30, so no migrations exist.

## Audit 2026-09-30: status

| ID | Finding | Status |
|---|---|---|
| SS-1 | `restoreWhoUi` read `LFGWhoListFrame:IsShown()` | Done (`6878f57`): `IsVisible()`. Harness case added |
| SS-2 | `/ws` used Era's AH API | Done (`a6130d6`): command, help rows, README and harness parts removed. Backup keeps it |
| SS-3 | "Forever's AH doesn't expose sellers" was wrong | Done: docs corrected. Rebuild is an open owner question |
| SS-4 | Compat probes and Era fallbacks | Done (`a6130d6`): APIs called directly, `Compat.lua` split into `Core/Lockdown.lua` and `ns.UnitFullName` in `Core/Names.lua`, FriendsFrame and `WhoFrame` gone |
| SS-5 | `ERR_*` enUS fallbacks, wrong-faction branch | Done (`a6130d6`). The "Free Trial accounts…" prefix match stays, it covers the store-link markup |
| SS-6 | Era SavedVariables migrations | Done (`a6130d6`): `DEAD_KEYS`, `migrateCooldowns`, `rekeyNames`, the ADDON_LOADED cleanup, `TRACKING_FORMAT`, the `-ignore` pointer |
| SS-7 | No backup branch | Done by the lead: `1.15.x-backup` = `e715c8a` |
| SS-8 | `GetNumWhoResults` can return nothing | Done (`6878f57`): `or 0` in `/ww`, the `-who` waiter keeps waiting. Harness case added |
| SS-9 | `pcall(issecretvalue)` guard | Done (`6878f57`): `value == nil or canaccessvalue(value)` |
| SS-10 | Restriction event may land before the lockdown | Not changed. The docs pin the state semantics but not which types hide chat, so the one-frame re-read plus the 10 s echo sweep stay. Comment added |
| SS-11 | Harness vanilla shape, pre-migration SVs | Done: Forever shape only, `strict`/`lenient`, nil initial DB, SS-1 and SS-8 cases, panel checks. Run `lua Tools/harness.lua . strict` and `. lenient` (the shape argument is gone) |
| SS-12 | Era wording, Era scroll gutter | Done: comments reworded, gutter 28 → 22 from the real bar |
| SS-13 | README said `-cd` works on `/rr` | Done. Also fixed: README claimed `g-`/`r-` keys for `-skip`/`-only`, which only take `c- z- n-` |
| SS-14 | Dead `ns.MigrateCooldowns`, `ns.SkipReasons` | Done (`a6130d6`) |
| SS-15 | toc metadata | Done: `16001`, Forever notes, `## Category: Social` (the lead's choice over the audit's "Chat"). No compartment entry added. Icon `134149` is UNVERIFIED |

Nothing to do (still valid): the send API; secret guards on `CHAT_MSG_WHISPER_INFORM`, `CHAT_MSG_SYSTEM` and `CHAT_MSG_WHISPER`; lockdown refusal and the echo sweep; no Blizzard hooks and no `ChatTypeInfo` writes; the who flow; the name rule; no slash collisions; load order and first load; repo hygiene (no libs).

## Owner questions

1. `/ws` on Forever. Today: removed on `main`, Era version on the backup. Rebuild means a new command reading `C_AuctionHouse.GetNumItemSearchResults`/`GetItemSearchResultInfo` and the commodity pair after `ITEM_SEARCH_RESULTS_UPDATED`/`COMMODITY_SEARCH_RESULTS_UPDATED`, whispering each unique entry of `owners` except `"player"`. It works on an opened item or commodity, not on Browse. About 80 lines plus help, README and harness. Seller names being filled is UNVERIFIED. Drop means nothing more to do.
2. Addon Compartment entry. Today: none. Yes means `## AddonCompartmentFunc` plus a global that calls `ns.TogglePanel`, about 5 lines. No means nothing.
3. Chat status colours. `Core/Format.lua` tints chat lines with fixed hex codes (green, red, blue, yellow tag). The native UI spec asks for Blizzard colour objects in panels; chat lines weren't in scope. Switching means `GREEN_FONT_COLOR`, `RED_FONT_COLOR` and friends in `tint`, with slightly different shades. Keeping means no change.

## Unverified assumptions

- Icon file ID `134149` (no listfile in the sources).
- `scroll.ScrollBar:GetWidth()` returns the template's 8 px at build time. If it returned 0, the bar would sit 8 px closer to the inset edge.
- The attic's two lines fit on one line each at the default font scale; word wrap is off, so a larger scale truncates them.
- `canaccessvalue` answers instead of raising for tainted callers, inferred from Blizzard's own filter wrapper.

## Blockers, issues, challenges

1. No source pins which name spelling Forever uses for `GetWhoInfo().fullName`, the whisper echo, incoming whispers and "player not found". The rule handles every form.
2. Also inferred, not proven: that the server accepts "First Surname" as a whisper target.
3. A bare first name on the block or cooldown list covers every player with that first name. To name one player, use First-Surname (the README says so).
4. When chat lockdown is active on 1.60 is unknown, and so is whether the restriction event fires before or after it.
5. The whisper throttle bucket (about 10 burst, under 1/s) was measured on Era. The Forever server's limit is unknown.

## Forever checks

You need an alt and a second player. Run `/console scriptErrors 1` first.

- [ ] The AddOns list shows Super Social under Social, not out of date. Log in and `/reload`: no Lua errors.
- [ ] `/who 60`, then `/ww -limit 3 test`: "3/3 sent", then "Sent all 3 whispers.", with no resend after 10 s.
- [ ] `/ww -who (60) -limit 2 test` with no Who or LFG panel open: results within 6 s, no panel opens.
- [ ] Two `/ww -who` runs in a row with different filters whisper the new results, not the old ones.
- [ ] Close the Group Finder on its Who tab, run `/ww -who`, then type `/who`: the output prints in chat and no panel opens (SS-1).
- [ ] `/rr`: a friend whispers you, `/rr` lists them, `/rr thanks` sends, and the list empties.
- [ ] A 15+ whisper blast shows "Burst spent." and no yellow spam. Record the Forever burst size (issue 5).
- [ ] `/ss` panel: the portrait shows the icon, the title reads "Super Social", both attic lines show in full, the scroll bar sits inside the inset, there is no empty button bar, Escape and the close button close it, it drags. `/ss -block <name>` survives `/reload`.
- [ ] Run `/dump RegionalUniqueNamesEnabled(), UnitName("target"), UnitNameUnmodified("target")`, then `/dump C_FriendList.GetWhoInfo(1).fullName` after a `/who`. Record the spellings. This settles issue 1.
- [ ] `/wt hi` on a surnamed target prints "Whispered First Surname." and it arrives. This settles issue 2.
- [ ] Group with someone whose first name matches another player in `/who`: only the groupmate is skipped.
- [ ] Get whispered inside a dungeon: no Lua error. `/ww` there prints "Chat restricted here.". Start a long run and walk into a dungeon: "Run stopped." within a second, not after 10 s (SS-10).
- [ ] Whisper a player of the other faction, if the client allows it: record the system message. With no known verdict, the run gives up after 3 tries.
