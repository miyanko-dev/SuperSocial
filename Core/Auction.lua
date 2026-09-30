local _, ns = ...

-- The auction house listing /ws reads. Forever's Browse rows carry no seller; only an item's or a commodity's own search results name them (ItemSearchResultInfo.owners, CommoditySearchResultInfo.owners), and the Buy, Sell and Auctions tabs all show those same results. So the listing is whichever result set arrived last while the auction house is open. It is tracked by event rather than read off Blizzard's window, because Auctionator's tabs show the same results with the window's display mode cleared.

local auctionOpen = false
local listing -- { itemKey = ItemKey } or { itemID = number }, from the last search results event

-- Blizzard's window going back to its Browse list leaves the last item's results cached, so its own display mode says no listing is on screen. Auctionator's tabs clear the mode, which reads as not browsing.
local function browsing()
    local frame = AuctionHouseFrame
    return frame ~= nil and frame:IsShown() and frame:GetDisplayMode() == AuctionHouseFrameDisplayMode.Buy
end

-- Why no listing can be read right now, "closed" or "browse", or nil when one can.
local function listingProblem()
    if not auctionOpen then return "closed" end
    if not listing or browsing() then return "browse" end
    return nil
end

-- The row count and a row reader for the tracked listing. Item and commodity results take different keys but share the owner fields.
local function listingRows()
    local itemKey, itemID = listing.itemKey, listing.itemID
    if itemKey then
        return C_AuctionHouse.GetNumItemSearchResults(itemKey), function(i) return C_AuctionHouse.GetItemSearchResultInfo(itemKey, i) end
    end
    return C_AuctionHouse.GetNumCommoditySearchResults(itemID), function(i) return C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i) end
end

-- "player" is how the results name you (AuctionHouseUtil.AddSellersToTooltip), and a hidden or empty entry names nobody.
local function namesSeller(owner)
    return ns.CanAccess(owner) and owner ~= "" and owner ~= "player"
end

-- Every named seller in listing order, duplicates included, plus how many sellers the rows count without naming ("Sellers: A, B, and 3 more"). The command decides who qualifies.
local function listingSellers()
    local sellers, unnamed = {}, 0
    local count, readRow = listingRows()
    for i = 1, count do
        local row = readRow(i)
        if row then
            for _, owner in ipairs(row.owners) do
                if namesSeller(owner) then sellers[#sellers + 1] = owner end
            end
            unnamed = unnamed + math.max(row.totalNumberOfOwners - #row.owners, 0)
        end
    end
    return sellers, unnamed
end

-- The listing's item in its quality colour, the way Blizzard's auction house draws it (ColorManager.GetColorDataForItemQuality), so a run names what it read. Nil while the item info isn't cached.
local function listingItem()
    local itemKey = listing.itemKey or C_AuctionHouse.MakeItemKey(listing.itemID)
    local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
    if not info or info.itemName == "" then return nil end
    local quality = ColorManager.GetColorDataForItemQuality(info.quality)
    return quality and quality.color:WrapTextInColorCode(info.itemName) or info.itemName
end

ns.ListingProblem = listingProblem
ns.ListingSellers = listingSellers
ns.ListingItem = listingItem

-- Event wiring stays below the ns definitions, so a wiring failure can never strip the public API.

-- Search results only mean something inside one auction house visit, so opening and closing both forget the listing.
local function onVisit(event)
    auctionOpen = event == "AUCTION_HOUSE_SHOW"
    listing = nil
end

local function onResults(event, key)
    if event == "ITEM_SEARCH_RESULTS_UPDATED" then
        listing = { itemKey = key }
    else
        listing = { itemID = key }
    end
end

local auctionWatch = CreateFrame("Frame")
auctionWatch:RegisterEvent("AUCTION_HOUSE_SHOW")
auctionWatch:RegisterEvent("AUCTION_HOUSE_CLOSED")
auctionWatch:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
auctionWatch:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
auctionWatch:SetScript("OnEvent", function(_, event, key)
    if event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then
        onVisit(event)
    else
        onResults(event, key)
    end
end)
