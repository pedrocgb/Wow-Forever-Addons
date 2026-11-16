local addonName, ns = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        HelloForeverDB = HelloForeverDB or { logins = 0 } -- SavedVariables exist only from here on
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        HelloForeverDB.logins = HelloForeverDB.logins + 1
        print(("|cff33ff99%s|r loaded. Login #%d. Type /hf"):format(addonName, HelloForeverDB.logins))
    end
end)

SLASH_HELLOFOREVER1 = "/hf"
SlashCmdList.HELLOFOREVER = function(msg)
    print(addonName, "says hi,", UnitName("player"), "- level", UnitLevel("player"), "- you typed:", msg)
end
