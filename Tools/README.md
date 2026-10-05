# Tools

Development only. Nothing here is listed in a toc, so the client never loads it.

## harness.lua

A stub WoW Forever 1.60.1 client that loads `SuperSocial.toc`'s file list in order, starting from no
saved variables, and drives every slash command. The stub has `LFGWhoListFrame` as the only who
listener, `ChatFrameUtil` as the filter API, unit names as first name plus surname with
`RegionalUniqueNamesEnabled()` true (and a pass with it false, where a realm rides behind `-` across
realms), secret chat payloads and an active chat lockdown.

The `/ss` panel is built against stub `ButtonFrameTemplate`, `InsetFrameTemplate` and
`ScrollFrameTemplate` children, which checks the title, portrait, strata, hidden button bar, Escape
registration and the scroll gutter, not how the panel looks.

`/ws` runs against a stub `C_AuctionHouse` with item and commodity search results, the
`AUCTION_HOUSE_SHOW`/`AUCTION_HOUSE_CLOSED` and `ITEM_SEARCH_RESULTS_UPDATED`/`COMMODITY_SEARCH_RESULTS_UPDATED`
events, and a load-on-demand `AuctionHouseFrame` whose display mode is Browse, an item, a commodity,
the Sell tab, or cleared the way Auctionator's tabs clear it. The cases cover your own `"player"`
entries and your own spelled-out name, duplicate, empty and hidden owners, rows that name fewer
sellers than they count, empty listings, `-limit`, `-cd`, the block list, `;` and `/rr` pickup.

Chat colours: the stub colour objects wrap text the way `ColorMixin:WrapTextInColorCode` does (the
shades are stand-ins, the client builds them from `C_UIColor`), and one check scans every toc file
for a literal `|c` colour code.

It also checks the name rule: `/wt` builds the name the way Blizzard's own menu does, and a whisper
echo, a reply or a `/who` row spelled another way (`First Surname`, `First-Surname`, a bare first
name) still matches, so nothing is resent.

```sh
for secrets in strict lenient; do
  lua Tools/harness.lua . $secrets || break
done
```

The second argument decides what `issecretvalue` does when tainted code hands it a secret: `strict`
(the default) raises, as its `SecretArguments = "AllowedWhenUntainted"` annotation can be read,
`lenient` answers. No source settles which one the client does. `canaccessvalue` answers in both
modes, because Blizzard's own chat filter wrapper calls it under addon taint and reads the result
(`ChatFrameFilters.lua`); the addon guards secrets with it, and `strict` proves nothing slips back to
`issecretvalue`. Both predicates raise on `nil`, because the argument is declared `Nilable = false`,
and the stub defines no bare `SendChatMessage` global, because it only exists while the
`loadDeprecationFallbacks` CVar is on.

Two cases pin client details the stub models: the Who tab inside a closed Group Finder still reports
`IsShown()` but not `IsVisible()`, so a `-who` run must leave results in chat; and
`C_FriendList.GetNumWhoResults()` returns nothing while the friend list is unavailable
(`RequiresFriendList`, `FailureMode = "ReturnNothing"`).

Exits non-zero when any expectation fails. Lua 5.2 or newer.

What it proves: load order, that every `ns.*` capture resolves, and the control flow of each command.
What it cannot prove: anything about the real client — frame layout, whether the server actually
fires an event, which spelling each API really returns, or what a genuine secret value does to a
string operation. Those belong in in-game checks.
