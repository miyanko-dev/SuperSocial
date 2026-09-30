# SuperSocial — Memory

Updated 2026-09-30 after the Forever-only rework (5.0.0) and the owner's second round of decisions: `/ws` rebuilt on the Forever auction house, chat colours from Blizzard colour objects. The version stays 5.0.0 (not shipped yet). The owner's decision is WoW Forever 1.60.x only: `main` holds the Forever version and `1.15.x-backup` keeps the dual-client 4.1.0. Verified against Gethe `forever` @ `966519cf` (1.60.1.70124) and Ketho `forever` @ `4149af64` (1.60.1.70009). The installed client is 1.60.1.70009. Nothing has run in a client. `Tools/harness.lua` passes 109/109 in `strict` and in `lenient`, which proves logic, not client behaviour.

## Current state

Commands:

- `/ww MESSAGE` whispers everyone in the current `/who` results. Flags: `-limit`, `-skip (…)`, `-only (…)`, `-cd`, `-who (…)`, and `;` to split a message.
- `/wt` whispers your target.
- `/ws MESSAGE` whispers every seller in the item or commodity listings open in the auction house. Flags: `-limit`, `-cd`, and `;`.
- `/rr` replies to people who answered within 15 min.
- `/ss` manages the block and cooldown lists and opens a reference panel.

Every whisper is confirmed by its server echo, and the send rate calibrates itself.

| Item | State |
|---|---|
| Version | 5.0.0, `## Interface: 16001`, `## Category: Social`, `## Author: miyanko`, icon `134149` |
| Git | `main`: `a6130d6` (split), `6878f57` (fixes), `1718da4` (panel), `c62edb3` (MEMORY), then round 2: `b5b03d6` (colour objects), `eb6e6f1` (`/ws`), `fe13040` (MEMORY), then the `/ws` group-skip commit (code and this MEMORY). Not pushed. `1.15.x-backup` = `e715c8a` (dual-client 4.1.0), local and on GitHub, untouched. The Questie integration stays removed: `QuestMacro.lua` exists only in `20c515f`/`2b16d40`. The last Era-only release is 4.0.0 at `2b16d40` |
| Files | `Core/` logic (`Lockdown`, `Names`, `Format`, `Lists`, `Group`, `Auction`, `Flags`, `Queue`), `Commands/` slash commands (`Whisper`, `Reply`, `Admin`), `UI/Help.lua` panel, `Tools/` harness |
| Lua lines | shipped 2,248 → 2,044 (split) → 2,217 (`/ws`, colours) → 2,221 (group skip), harness 677 → 674 → 896 → 928 |

Names and client facts:

- Names: one name rule in `Core/Names.lua`. The key is the lowercase first name plus the second part, with space and hyphen treated as the same separator. It matches "Name", "Name-Realm", "First Surname" and "First-Surname". A bare first name matches any full form of it. Every comparison goes through it: echo confirmation, block and cooldown lists, group skip, `/rr`, and the quiet filter. `ns.UnitFullName` mirrors Mainline `GetFullPlayerName` (`UnitPopupUtils.lua:108-135`): surname with `CHARACTERNAME_SURNAME_SEPARATOR` when `RegionalUniqueNamesEnabled()`, else realm with `CHARACTERNAME_REALMNAME_SEPARATOR` across realms. An exact `/who` needs the hyphen form (`C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator`).
- `/wt` sends Blizzard's unit-menu form, which is "First Surname" when regionally unique names are on.
- Chat colours (owner decision 2026-09-30, "as native as possible"): no literal colour codes. Every line opens with the shared `YELLOW_FONT_COLOR:WrapTextInColorCode("[Super Social]:") .. " "`, like every addon in this folder. Lead tints: `GREEN_FONT_COLOR` sent or done, `RED_FONT_COLOR` skipped or failed, `LIGHTBLUE_FONT_COLOR` bookkeeping (cooldowns, the cap). Light blue replaces the fixed `ff76c8ff`: it is the closest by name, and Blizzard uses it in chat itself (`ChatFrameOverrides.lua:256`). The shades come from `C_UIColor.GetColors()` at load (`Blizzard_SharedXMLBase/Color.lua:79-87`), so no source pins the exact values. The harness fails on any literal `|c` code in a toc file.
- Whisper colour blend: removed (2026-09-25, user decision). Any addon write to `ChatTypeInfo.WHISPER` would taint Blizzard's secret-sender comparison (`ChatFrameOverrides.lua:677-696`). Don't add it back.
- Forever APIs, called directly:
  - `C_ChatInfo.SendChatMessage(text, "WHISPER", nil, target)`, which isn't protected
  - `C_ChatInfo.InChatMessagingLockdown` plus `ADDON_RESTRICTION_STATE_CHANGED`
  - `ChatFrameUtil.AddMessageEventFilter`. The bare `SendChatMessage` and `ChatFrame_AddMessageEventFilter` exist only in `Blizzard_Deprecated*`
  - `canaccessvalue` for the secret guard. Blizzard's filter wrapper calls it under addon taint and reads the answer (`ChatFrameFilters.lua:27-42,115-118`)
- Who list: `LFGWhoListFrame` (load-on-demand `Blizzard_GroupFinder_VanillaStyle`) is the only `WHO_LIST_UPDATE` listener. Its OnShow/OnHide call `SetWhoToUi` (`WhoList.lua:247-253`), and it keeps `IsShown()` when `LFGParentFrame` closes, so restore reads `IsVisible()`. `GetNumWhoResults`/`GetWhoInfo` are `RequiresFriendList` (`FailureMode = "ReturnNothing"`).
- All `ERR_CHAT_*` verdict strings used exist with the same enUS text. `ERR_CHAT_WRONG_FACTION` doesn't exist, so the wrong-faction branch is gone; what the server says for a wrong-faction whisper is unknown.
- `ADDON_RESTRICTION_STATE_CHANGED`: `SynchronousEvent`, payload `(type, state)`. `Activating` means enforced once the dispatch completes (`RestrictedActionsConstantsDocumentation.lua`). Which `AddOnRestrictionType` values hide chat is not documented, so the payload is not read (SS-10).
- `/ws` (rebuilt 2026-09-30, owner decision "I liked it"). Same shape as the Era command on the backup: `-limit`, `-cd`, `;`, one whisper per seller (deduped by name key), never yourself, `-skip`/`-only`/`-who` refused, block and cooldown lists applied, the same group skip as `/ww` and `/rr` (party or raid, plus anyone who left the group in the last 15 minutes, owner decision 2026-09-30), echo-confirmed through the queue, recipients handed to `/rr`. `Core/Auction.lua` reads the sellers:
  - Forever's Browse rows carry no seller. Only an item's or a commodity's search results name them: `ItemSearchResultInfo.owners` and `CommoditySearchResultInfo.owners` (`AuctionHouseDocumentation.lua:1604-1673`). The Buy, Sell and Auctions tabs all read those same results (`Blizzard_AuctionHouseItemBuyFrame.lua`, `ItemSellFrame.lua`, `CommoditiesList.lua`, `AuctionsFrame.lua`).
  - A visit runs from `AUCTION_HOUSE_SHOW` to `AUCTION_HOUSE_CLOSED` (both routed by the loaded Mainline `EventRouting.lua:12-14`). Both forget the listing.
  - The listing is the last `ITEM_SEARCH_RESULTS_UPDATED` (payload `itemKey`, `newAuctionID?`) or `COMMODITY_SEARCH_RESULTS_UPDATED` (payload `itemID`) of the visit, read with `GetNumItemSearchResults`/`GetItemSearchResultInfo` or the commodity pair. It is tracked by event, not read off Blizzard's window, because Auctionator's tabs clear `AuctionHouseFrame.displayMode` to nil (`Auctionator/Libs_ModernAH/LibAHTab/LibAHTab.lua:89-90`) and show the same results.
  - Blizzard's window back on its Browse list (`AuctionHouseFrame:GetDisplayMode() == AuctionHouseFrameDisplayMode.Buy`, `Blizzard_AuctionHouseFrame.lua:485-490,541-601`) gets the hint "No item listings open.", and so does a visit with no listing yet. A closed AH gets "Auction house closed.".
  - Owner entries: `"player"` is you (Blizzard `AuctionHouseUtil.AddSellersToTooltip`, Auctionator's `owners[1] == "player"`). Hidden (`canaccessvalue` false) and empty entries are skipped, and so is your own spelled-out name. `totalNumberOfOwners` above `#owners` means the row names only some sellers ("Sellers: %s, and %s more", `AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT`). `/ws` prints "Up to N sellers unnamed", summed over rows, so a seller on two rows may count twice. `containsOwnerItem` only flags that a row holds your item, so it isn't read. `containsAccountItem` means another character on your account, and its entry can't be told apart, so an alt may be whispered and drops out as unreachable.
  - The opening line names the item in its quality colour (`C_AuctionHouse.GetItemKeyInfo`, `MakeItemKey` for commodities, `ColorManager.GetColorDataForItemQuality(quality).color`, loaded Mainline `ColorManager.lua:52-60`). The item stays unnamed while its info isn't cached.
  - It reads only the rows loaded so far. Scrolling Blizzard's list requests more.
  - IN-GAME CHECK: whether the Forever server fills `owners` with real names is UNVERIFIED. No source shows a filled list, and `GetReplicateItemInfo` (`owner`, `ownerFullName`) is the only other seller source. If the lists come back empty, `/ws` prints "No other sellers in the open listings." every time.
- Help panel: `ButtonFrameTemplate` `SuperSocialFrame`, portrait `134149`, title "Super Social", strata HIGH, Escape via `UISpecialFrames`, `ButtonFrameTemplate_HideButtonBar`. The attic holds a `GameFontHighlight` intro and a `GameFontDisableSmall` hint under `TitleContainer`, word wrap off. The sections are `InsetFrameTemplate` boxes with `GameFontNormal` labels in a `ScrollFrameTemplate` inside `frame.Inset`. Gutter = `SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT` (6) + `ScrollBar:GetWidth()` (8, `MinimalScrollBar.xml`) + 8 px pad = 22. Toggle: `ns.TogglePanel`.
- `SuperSocialWAHost` was never part of SuperSocial. It came from the old "SuperSocial Shortcuts" WeakAura.
- Saved variables: `SuperSocialDB` is created lazily on first use. The Forever WTF had no SuperSocial file on 2026-09-30, so no migrations exist.

## Audit 2026-09-30: status

| ID | Finding | Status |
|---|---|---|
| SS-1 | `restoreWhoUi` read `LFGWhoListFrame:IsShown()` | Done (`6878f57`): `IsVisible()`. Harness case added |
| SS-2 | `/ws` used Era's AH API | Done (`a6130d6`): the Era command was removed. Rebuilt on the Forever AH API in `eb6e6f1` (owner decision) |
| SS-3 | "Forever's AH doesn't expose sellers" was wrong | Done: docs corrected, and `/ws` now reads `owners` (`eb6e6f1`). Filled names are an in-game check |
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

Settled 2026-09-30: `/ws` rebuilt on the Forever AH (`eb6e6f1`). Chat colours use Blizzard colour objects with the shared yellow prefix (`b5b03d6`). `/ws` skips groupmates like `/ww` and `/rr` (owner: yes). All three commands run the one `ns.GroupSkip` in `Core/Group.lua`, which replaced the inline `InGroup`/`WasRecentlyGrouped` pairs in `/ww` and `/rr`.

1. Addon Compartment entry. Today: none. Yes means `## AddonCompartmentFunc` plus a global that calls `ns.TogglePanel`, about 5 lines. No means nothing.

## Unverified assumptions

- Icon file ID `134149` (no listfile in the sources).
- `scroll.ScrollBar:GetWidth()` returns the template's 8 px at build time. If it returned 0, the bar would sit 8 px closer to the inset edge.
- The attic's two lines fit on one line each at the default font scale; word wrap is off, so a larger scale truncates them.
- `canaccessvalue` answers instead of raising for tainted callers, inferred from Blizzard's own filter wrapper.
- The Forever server fills `ItemSearchResultInfo.owners`/`CommoditySearchResultInfo.owners` with seller names (see the `/ws` entry).
- The `owners` names use a spelling the whisper box accepts. Every spelling goes through the name rule, so dedupe and "never yourself" hold either way.
- `AUCTION_HOUSE_SHOW` fires on every visit before any search result. It is documented and routed by the loaded `EventRouting.lua`, but Auctionator watches `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` instead.
- The shades of the colour objects, which come from the client's colour DB.

## Blockers, issues, challenges

1. No source pins which name spelling Forever uses for `GetWhoInfo().fullName`, the whisper echo, incoming whispers and "player not found". The rule handles every form.
2. Also inferred, not proven: that the server accepts "First Surname" as a whisper target.
3. A bare first name on the block or cooldown list covers every player with that first name. To name one player, use First-Surname (the README says so).
4. When chat lockdown is active on 1.60 is unknown, and so is whether the restriction event fires before or after it.
5. The whisper throttle bucket (about 10 burst, under 1/s) was measured on Era. The Forever server's limit is unknown.
6. `/ws` reads the last result set of the visit. In Blizzard's Sell or Auctions tab with nothing selected, or after an Auctionator scan that searched items in the background (for example its undercut scan), that set may not be what the window shows. The opening line names the item, but the burst goes out the next frame, so `/ss stop` catches only the paced tail.

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
- [ ] Chat lines: the `[Super Social]:` tag is yellow, "Sent" leads are green, "Skipped" leads are red, and "Burst spent." and cooldown notes are light blue. Record whether the light blue reads well.
- [ ] Open the AH and a commodity's listings, then `/dump C_AuctionHouse.GetCommoditySearchResultInfo(<itemID>, 1)`. Record whether `owners` holds real names and in which spelling. This settles the seller-name check.
- [ ] On an opened item (non-commodity) listing, `/ws -limit 2 hi` whispers two unique sellers, never you, and the opening line names the item in its quality colour. With one of your own auctions in the listing, you are skipped.
- [ ] A commodity row whose tooltip says "and N more": `/ws` prints "Up to N sellers unnamed".
- [ ] Back to the Browse list, then `/ws hi`: "No item listings open.". Close the AH, then `/ws hi`: "Auction house closed.".
- [ ] In Auctionator's Shopping or Selling tab with an item's listings shown, `/ws hi` reads that listing.
- [ ] A seller answers a `/ws`: `/rr` lists them.
- [ ] Group with a player who has an auction up, open that item's listings, then `/ws hi`: "1 in your group". Leave the group and retry: "1 recently grouped".
