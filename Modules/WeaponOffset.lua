local Config = require("Modules/Config")
local Helpers = require("Modules/Helpers")
local WeaponOffset = {}

WeaponOffset.currentWeapon = nil
WeaponOffset.currentWeaponHash = nil
WeaponOffset.modifiers = {}
WeaponOffset.originalZoomValues = {}
WeaponOffset.originalFOVValues = {}
WeaponOffset.lastPitch = 0
WeaponOffset.wasLookingDown = false

---
--- Check if a weapon is blacklisted
--- @param weapon userdata The weapon to check
--- @return boolean Is the weapon blacklisted
---
function WeaponOffset.IsWeaponBlacklisted(weapon)
    if not weapon then return false end
    
    local weaponID = weapon:GetItemID()
    if not weaponID then return false end
    
    local tdbid = weaponID.id
    local weaponIDString = TDBID.ToStringDEBUG(tdbid)

    if not weaponIDString then return false end

    if Config.inner.weaponBlacklist then
        for _, blacklistedWeapon in ipairs(Config.inner.weaponBlacklist) do
            if weaponIDString == blacklistedWeapon then
			return true
			end
		end
    end

    return false
end

---
--- Get the weapon's TweakDB ID string for identification
--- @param weapon userdata The weapon to get ID from
--- @return string|nil The weapon's TweakDB ID string or nil
---
function WeaponOffset.GetWeaponIDString(weapon)
    if not weapon then return nil end
    
    local weaponID = weapon:GetItemID()
    if not weaponID then return nil end

    local tdbid = weaponID.id
    return TDBID.ToStringDEBUG(tdbid)
end

---
--- Add a weapon to the blacklist
--- @param weapon userdata The weapon to add
--- @return boolean Success
---
function WeaponOffset.AddToBlacklist(weapon)
    local weaponIDString = WeaponOffset.GetWeaponIDString(weapon)
    if not weaponIDString then return false end

    if not Config.inner.weaponBlacklist then
        Config.inner.weaponBlacklist = {}
    end

    for _, blacklistedWeapon in ipairs(Config.inner.weaponBlacklist) do
        if weaponIDString == blacklistedWeapon then
            return false
    end
    end

    table.insert(Config.inner.weaponBlacklist, weaponIDString)
    Config.SaveConfig()
    return true
end

---
--- Remove a weapon from the blacklist
--- @param weaponIDString string The weapon's TweakDB ID string
--- @return boolean Success
---
function WeaponOffset.RemoveFromBlacklist(weaponIDString)
    if not weaponIDString or weaponIDString == "" then
        return false
    end

    if not Config.inner.weaponBlacklist then
        Config.inner.weaponBlacklist = {}
    end

    for i, blacklistedWeapon in ipairs(Config.inner.weaponBlacklist) do
        print("[IMFP-E] RemoveFromBlacklist: comparing with entry [" .. i .. "] = \"" .. tostring(blacklistedWeapon) .. "\"")
        if weaponIDString == blacklistedWeapon then
            table.remove(Config.inner.weaponBlacklist, i)
            Config.SaveConfig()
            return true
        end
    end

    return false
end

---
--- Get the currently equipped weapon in the right hand slot
--- @return userdata|nil weapon The equipped weapon or nil
---
function WeaponOffset.GetCurrentWeapon()
    local player = Game.GetPlayer()
    if not player then return nil end

    local ts = Game.GetTransactionSystem()
    if not ts then return nil end

    return ts:GetItemInSlot(player, TweakDBID.new('AttachmentSlots.WeaponRight'))
end

---
--- Get a unique hash for the weapon to track changes
--- @param weapon userdata The weapon item
--- @return number|nil hash The weapon hash or nil
---
function WeaponOffset.GetWeaponHash(weapon)
    if not weapon then return nil end

    local weaponID = weapon:GetItemID()
    if not weaponID then return nil end

    return weaponID.id.hash
end

---
--- Apply weapon offset to compensate for raised camera position
--- This adjusts both the visual position (IK) and functional aiming (stats)
--- @param weapon userdata The weapon to apply offset to
--- @param cameraHeight number The camera height offset (e.g., 0.085)
--- @return boolean success Whether the offset was applied successfully
---
function WeaponOffset.ApplyWeaponOffset(weapon, cameraHeight)
    if not weapon then return false end

    local weaponID = weapon:GetItemID()
    if not weaponID then return false end

    local tdbid = weaponID.id
    local player = Game.GetPlayer()
    if not player then return false end

    local ts = Game.GetTransactionSystem()
    if not ts then return false end

    local stats = Game.GetStatsSystem()
    if not stats then return false end

    local data = ts:GetItemData(player, weaponID)
    if not data then return false end

    local statId = data:GetStatsObjectID()
    if not statId then return false end

    local playerFOV = Game.GetSettingsSystem():GetVar("/graphics/basic", "FieldOfView"):GetValue()
    if not playerFOV or playerFOV < 60 or playerFOV > 120 then
        playerFOV = 80
	end

    WeaponOffset.RemoveWeaponOffset()

    local function OppositeFloat(value)
        if value == 0 then return 0 end
        return value > 0 and -value or math.abs(value)
    end

    local ikOffset = Vector3.new(OppositeFloat(0.0), 0.0, OppositeFloat(cameraHeight))
    TweakDB:SetFlat(tdbid .. ".ikOffset", ikOffset)

    local aimOffsetValue = -cameraHeight

    local aimOffsetMod = Game['gameRPGManager::CreateStatModifier;gamedataStatTypegameStatModifierTypeFloat'](
        'AimOffset', 'Additive', aimOffsetValue)
    local scopeOffsetMod = Game['gameRPGManager::CreateStatModifier;gamedataStatTypegameStatModifierTypeFloat'](
        'ScopeOffset', 'Additive', aimOffsetValue)

    stats:AddModifier(statId, aimOffsetMod)
    stats:AddModifier(statId, scopeOffsetMod)

    local hasScope = weapon:HasScope()
    local isBlacklisted = WeaponOffset.IsWeaponBlacklisted(weapon)

    local shouldUseScopeFOV = hasScope or isBlacklisted

    local aimFovValue = nil
    if shouldUseScopeFOV then
        aimFovValue = (playerFOV - 60) + Config.inner.scopeFovOffset
    else
        aimFovValue = (playerFOV - 60) + Config.inner.adsFovOffset
    end
    
    local aimFOVMod = Game['gameRPGManager::CreateStatModifier;gamedataStatTypegameStatModifierTypeFloat'](
        gamedataStatType.AimFOV, 'Additive', aimFovValue)
    stats:AddModifier(statId, aimFOVMod)

    local scopeFovValue = (playerFOV - 60) + Config.inner.scopeFovOffset
    local scopeFOVMod = Game['gameRPGManager::CreateStatModifier;gamedataStatTypegameStatModifierTypeFloat'](
        gamedataStatType.ScopeFOV, 'Additive', scopeFovValue)
    stats:AddModifier(statId, scopeFOVMod)

    local zoomMod = nil

    if not hasScope and not isBlacklisted then
        local currentZoom = stats:GetStatValue(statId, gamedataStatType.ZoomLevel)
        if currentZoom > 1.0 then
            zoomMod = Game['gameRPGManager::CreateStatModifier;gamedataStatTypegameStatModifierTypeFloat'](
                gamedataStatType.ZoomLevel, 'Additive', 1.0 - currentZoom)
            stats:AddModifier(statId, zoomMod)
        end
    end

    WeaponOffset.ModifyWeaponZoom(tdbid, playerFOV)

    WeaponOffset.modifiers = {
        statId = statId,
        aimOffset = aimOffsetMod,
        scopeOffset = scopeOffsetMod,
        aimFOV = aimFOVMod,
        scopeFOV = scopeFOVMod,
        zoomLevel = zoomMod,
        tdbid = tdbid
    }

    return true
end

---
--- Modify weapon's base zoom level and FOV in TweakDB
--- Sets ZoomLevel to 1.0 and AimFOV to player's FOV so scopes can add their zoom on top
--- @param weaponTDBID userdata The weapon's TweakDB ID
--- @param playerFOV number The player's FOV setting
---
function WeaponOffset.ModifyWeaponZoom(weaponTDBID, playerFOV)
    local weaponRecord = TweakDB:GetRecord(weaponTDBID)
    if not weaponRecord then return end

    local weaponIDString = TDBID.ToStringDEBUG(weaponTDBID)

    local baseName = weaponIDString:match("Items%.Preset_([^_]+)")
    if not baseName then
        baseName = weaponIDString:match("Items%.Base_([^_]+)")
    end
    if not baseName then
        baseName = weaponIDString:match("Items%.w_([^_]+)")
    end

    if not baseName then
        print("[IMFP-E]: Cannot determine weapon name, skipping!")
        return
    end

    local statGroupPatterns = {
        "Items.Base_" .. baseName .. "_Handling_Stats",
        "Items." .. baseName .. "_Handling_Stats",
        "Items.Base_" .. baseName .. "_Aim_Stats",
        "Items." .. baseName .. "_Aim_Stats"
    }

    for _, pattern in ipairs(statGroupPatterns) do
        local statsTDBID = TweakDBID.new(pattern)
        local groupRecord = TweakDB:GetRecord(statsTDBID)

        if groupRecord then
            local modifiers = groupRecord:StatModifiers()
            if modifiers then
                for i, modifier in ipairs(modifiers) do
                    local statType = modifier:StatType()
                    if statType then
                        local statName = Game.NameToString(statType:EnumName())

                        if statName == "ZoomLevel" then
                            local originalValue = modifier:Value()
                            if not WeaponOffset.originalZoomValues[pattern] then
                                WeaponOffset.originalZoomValues[pattern] = originalValue
                            end
                            TweakDB:SetFlat(modifier:GetID() .. ".value", 1.0)
                        end

                        if statName == "AimFOV" then
                            local originalValue = modifier:Value()
                            if not WeaponOffset.originalFOVValues[pattern] then
                                WeaponOffset.originalFOVValues[pattern] = originalValue
                            end
                            TweakDB:SetFlat(modifier:GetID() .. ".value", playerFOV)
                        end
                    end
                end
            end
        end
    end
end

---
--- Remove weapon offset modifiers
--- Call this when switching weapons or disabling weapon support
---
function WeaponOffset.RemoveWeaponOffset()
    if not WeaponOffset.modifiers.statId then return end

    local stats = Game.GetStatsSystem()
    if not stats then return end

    if WeaponOffset.modifiers.aimOffset then
        stats:RemoveModifier(WeaponOffset.modifiers.statId, WeaponOffset.modifiers.aimOffset)
    end
    if WeaponOffset.modifiers.scopeOffset then
        stats:RemoveModifier(WeaponOffset.modifiers.statId, WeaponOffset.modifiers.scopeOffset)
    end
    if WeaponOffset.modifiers.aimFOV then
        stats:RemoveModifier(WeaponOffset.modifiers.statId, WeaponOffset.modifiers.aimFOV)
    end
    if WeaponOffset.modifiers.scopeFOV then
        stats:RemoveModifier(WeaponOffset.modifiers.statId, WeaponOffset.modifiers.scopeFOV)
    end
    if WeaponOffset.modifiers.zoomLevel then
        stats:RemoveModifier(WeaponOffset.modifiers.statId, WeaponOffset.modifiers.zoomLevel)
    end

    if WeaponOffset.modifiers.tdbid then
        TweakDB:SetFlat(WeaponOffset.modifiers.tdbid .. ".ikOffset", Vector3.new(0.0, 0.0, 0.0))
    end

    WeaponOffset.modifiers = {}
end

---
--- Restore original zoom and FOV values for all modified weapons
--- Call this on shutdown
---
function WeaponOffset.RestoreZoomValues()
    for statsID, originalValue in pairs(WeaponOffset.originalZoomValues) do
        local statsTDBID = TweakDBID.new(statsID)
        local groupRecord = TweakDB:GetRecord(statsTDBID)

        if groupRecord then
            local modifiers = groupRecord:StatModifiers()
            if modifiers then
                for i, modifier in ipairs(modifiers) do
                    local statType = modifier:StatType()
                    if statType and Game.NameToString(statType:EnumName()) == "ZoomLevel" then
                        TweakDB:SetFlat(modifier:GetID() .. ".value", originalValue)
                        break
                    end
                end
            end
        end
    end

    for statsID, originalValue in pairs(WeaponOffset.originalFOVValues) do
        local statsTDBID = TweakDBID.new(statsID)
        local groupRecord = TweakDB:GetRecord(statsTDBID)

        if groupRecord then
            local modifiers = groupRecord:StatModifiers()
            if modifiers then
                for i, modifier in ipairs(modifiers) do
                    local statType = modifier:StatType()
                    if statType and Game.NameToString(statType:EnumName()) == "AimFOV" then
                        TweakDB:SetFlat(modifier:GetID() .. ".value", originalValue)
                        break
                    end
                end
            end
        end
    end

    WeaponOffset.originalZoomValues = {}
    WeaponOffset.originalFOVValues = {}
end

---
--- Update weapon offset if weapon has changed
--- Call this in the main update loop
--- @param cameraHeight number The current camera height setting
---
function WeaponOffset.Update(cameraHeight)
    local currentWeapon = WeaponOffset.GetCurrentWeapon()
    local currentHash = WeaponOffset.GetWeaponHash(currentWeapon)

    local currentPitch = Helpers.GetLookPitch()
    local isLookingDown = currentPitch and currentPitch < -40

    local justLookedUp = WeaponOffset.wasLookingDown and not isLookingDown

    local weaponChanged = currentHash ~= WeaponOffset.currentWeaponHash

    if weaponChanged or (justLookedUp and currentWeapon) then
        if currentWeapon then

            if weaponChanged and not WeaponOffset.currentWeapon then
                Helpers.ResetCamera()
            end

            WeaponOffset.ApplyWeaponOffset(currentWeapon, cameraHeight)
            WeaponOffset.currentWeapon = currentWeapon
            WeaponOffset.currentWeaponHash = currentHash
        else
            WeaponOffset.RemoveWeaponOffset()
            WeaponOffset.currentWeapon = nil
            WeaponOffset.currentWeaponHash = nil
        end
    end

    WeaponOffset.lastPitch = currentPitch or 0
    WeaponOffset.wasLookingDown = isLookingDown
end

---
--- Reset all weapon offset state
--- Call this on shutdown or when disabling the mod
---
function WeaponOffset.Reset()
    WeaponOffset.RemoveWeaponOffset()
    WeaponOffset.RestoreZoomValues()
    WeaponOffset.currentWeapon = nil
    WeaponOffset.currentWeaponHash = nil
    WeaponOffset.lastPitch = 0
    WeaponOffset.wasLookingDown = false
end

return WeaponOffset