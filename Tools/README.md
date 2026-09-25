# Tools

Development only. Nothing here is listed in a toc, so the client never loads it.

## harness.lua

A stub WoW client that loads `SuperSocial.toc`'s file list in order and drives every slash command
twice:

- a 1.15.9-shaped environment: `WhoFrame`, `ChatFrame_AddMessageEventFilter`, the classic auction
  house (`GetNumAuctionItems`, `GetAuctionItemInfo`, `AuctionFrame`), unit names as name plus realm,
  no secret values, no restrictions
- a 1.60.1-shaped one: `LFGWhoListFrame`, `ChatFrameUtil`, no seller API, unit names as first name
  plus surname with `RegionalUniqueNamesEnabled()` true,
  secret chat payloads, an active chat lockdown

Both shapes also check the name rule: `/wt` builds the name the way Blizzard's own menu does, and a
whisper echo, a reply or a `/who` row spelled another way (`First Surname`, `First-Surname`, a bare
first name, an Era `Name-Realm`) still matches, so nothing is resent.

```sh
for shape in vanilla camelot; do for secrets in strict lenient; do
  lua Tools/harness.lua . $shape $secrets || break 2
done; done
```

The third argument decides what `issecretvalue` and `canaccessvalue` do when handed a secret: `strict`
(the default) raises, as their `SecretArguments = "AllowedWhenUntainted"` annotation can be read,
`lenient` answers, as Blizzard's chat filters and TSM rely on. No source settles which one the client
does, so the addon must pass both. Both modes also raise on `nil`, because both builds declare the
argument `Nilable = false`, and neither shape defines the bare `SendChatMessage` global, because it
only exists while the `loadDeprecationFallbacks` CVar is on.

Exits non-zero when any expectation fails. Lua 5.2 or newer.

What it proves: load order, that every `ns.*` capture resolves, and the control flow of each command
on both client shapes. What it cannot prove: anything about the real client — frame layout, whether
the server actually fires an event, which spelling each API really returns, or what a genuine secret
value does to a string operation. Those belong in the in-game beta checks listed in `../MEMORY.md`.
