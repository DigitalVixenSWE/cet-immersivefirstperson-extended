local HeadManager = {}

local Config = require("Modules/Config")
local Helpers = require("Modules/Helpers")
local Cron = require("Modules/Cron")
local logLevel = 0

local function log(level, msg)
	if level <= logLevel then
		print("[IMFP-E] " .. (type(msg) == "function" and msg() or tostring(msg)))
	end
end

-- State
local isHeadVisible = false
local toggleHeadInProgress = false
local pendingCallbacks = {}

---
--- Get the player's gender prefix for head item
--- @return string "Ma" or "Wa"
---
local function GetGenderPrefix()
    local player = Game.GetPlayer()
    if not player then return "Ma" end
    
    local isFemale = false
    local genderName = tostring(player:GetResolvedGenderName())
    if string.find(genderName, "Female") then
        isFemale = true
    end
    
    if isFemale then
        return "Wa"
    else
        return "Ma"
    end
end

---
--- Calculate appropriate delay for retries
--- @param multiplier number Base multiplier for FPS calculations
--- @return number Delay count
---
local function CalculateDelay(multiplier)
    multiplier = multiplier or 5
    local fps = 1 / (0.016)
    local C = 4800
    local computed = math.ceil(C / fps)
    return math.max(math.min(computed, 120), 60) * (multiplier / 5)
end

---
--- Query current head state from game
--- @return boolean True if a head item is equipped in TppHead slot
---
local function QueryHeadState()
    local player = Game.GetPlayer()
    if not player then return false end
    local ts = Game.GetTransactionSystem()
    if not ts then return false end
    local slot = TweakDBID.new("AttachmentSlots.TppHead")
    local slotItem = ts:GetItemInSlot(player, slot)

    if slotItem == nil then
        return false
    end

    local fppHeadID = ItemID.FromTDBID(TweakDBID.new("Items.PlayerFppHead"))
    if slotItem == fppHeadID then
        return false
    end

    return true
end

---
--- Enqueue a callback to be executed after the current toggle completes
--- @param callback function|nil
---
local function EnqueueCallback(callback)
    if callback then
        table.insert(pendingCallbacks, callback)
    end
end

---
--- Execute and drain all pending callbacks in order
---
local function ExecuteCallbacks()
    local queue = pendingCallbacks
    pendingCallbacks = {}
    for _, cb in ipairs(queue) do
        cb()
    end
end

---
--- Show the player's head (TPP head)
--- @param callback function Optional callback to execute when head is shown
---
function HeadManager.ShowHead(callback)
    log(1, "HeadManager.ShowHead called")
    if toggleHeadInProgress then
        log(1, "ShowManager: Toggle head in progress, queuing callback")
        EnqueueCallback(callback)
	    return isHeadVisible
    end
    toggleHeadInProgress = true
    EnqueueCallback(callback)

    local player = Game.GetPlayer()
    if not player then
        log(1, "ShowManager: Player not found")
        toggleHeadInProgress = false
        ExecuteCallbacks()
	    return isHeadVisible
    end

    local ts = Game.GetTransactionSystem()
    if not ts then
        log(1, "ShowManager: TransactionSystem not found")
        toggleHeadInProgress = false
        ExecuteCallbacks()
	    return isHeadVisible
    end

    local gender = GetGenderPrefix()
    local headItem = "Items.CharacterCustomization" .. gender .. "Head"
    log(1, function() return "ShowManager: Gender prefix: " .. tostring(gender) .. ", Head item: " .. headItem end)

    local slot = TweakDBID.new("AttachmentSlots.TppHead")
    local tdbid = TweakDBID.new(headItem)
    local itemID = ItemID.FromTDBID(tdbid)

    if not ts:HasItem(player, itemID) then
        log(1, "ShowManager: Head item not in inventory, giving item")
        ts:GiveItem(player, itemID, 1)
    end

    local attemptCount = 0
    local maxAttempts = 40

    local function attempt()
        attemptCount = attemptCount + 1
        log(1, function() return "ShowManager: attempt " .. attemptCount end)

        ts:RemoveItemFromSlot(player, slot, true, true, true)

        Cron.After(0.05, function()
            if not toggleHeadInProgress then return end

            local current = ts:GetItemInSlot(player, slot)
            if current == nil then
                ts:AddItemToSlot(player, slot, itemID)
            end

            Cron.After(0.05, function()
                if not toggleHeadInProgress then return end

                local actualState = QueryHeadState()
                if actualState == true then
                    log(1, function() return "ShowManager: Success at attempt " .. attemptCount end)
                    isHeadVisible = true
                    toggleHeadInProgress = false
                    ExecuteCallbacks()
                elseif attemptCount < maxAttempts then
                    attempt()
                else
                    isHeadVisible = QueryHeadState()
                    log(1, function() return "ShowManager: Timeout, final state: " .. tostring(isHeadVisible) end)
                    toggleHeadInProgress = false
                    ExecuteCallbacks()
                end
            end)
        end)
    end

    attempt()
	return isHeadVisible
end

---
--- Hide the player's head (FPP head)
--- @param callback function Optional callback to execute when head is hidden
---
function HeadManager.HideHead(callback)
    log(1, "HeadManager.HideHead called")
    if toggleHeadInProgress then
        log(1, "Hidemanager: Toggle head in progress, queuing callback")
        EnqueueCallback(callback)
        return isHeadVisible
    end
    toggleHeadInProgress = true
    EnqueueCallback(callback)

    local player = Game.GetPlayer()
    if not player then
        log(1, "Hidemanager: Player not found")
        toggleHeadInProgress = false
        ExecuteCallbacks()
        return isHeadVisible
    end

    local ts = Game.GetTransactionSystem()
    if not ts then
        log(1, "Hidemanager: TransactionSystem not found")
        toggleHeadInProgress = false
        ExecuteCallbacks()
        return isHeadVisible
    end

    local fppHead = ItemID.FromTDBID(TweakDBID.new("Items.PlayerFppHead"))
    log(1, function() return "Hidemanager: Current fppHead is: " .. tostring(fppHead) end)
    local slot = TweakDBID.new("AttachmentSlots.TppHead")
    
    local attemptCount = 0
    local maxAttempts = 40

    local function attempt()
        attemptCount = attemptCount + 1
        log(1, function() return "Hidemanager: attempt " .. attemptCount end)

        ts:RemoveItemFromSlot(player, slot, true, true, true)

        Cron.After(0.05, function()
            if not toggleHeadInProgress then return end

            local current = ts:GetItemInSlot(player, slot)
            if current == nil then
                ts:AddItemToSlot(player, slot, fppHead)
            end

            Cron.After(0.05, function()
                if not toggleHeadInProgress then return end

                local actualState = QueryHeadState()
                if actualState == false then
                    log(1, function() return "Hidemanager: Success at attempt " .. attemptCount end)
                    isHeadVisible = false
                    toggleHeadInProgress = false
                    ExecuteCallbacks()
                elseif attemptCount < maxAttempts then
                    attempt()
                else
                    isHeadVisible = QueryHeadState()
                    log(1, function() return "Hidemanager: Timeout, final state: " .. tostring(isHeadVisible) end)
                    toggleHeadInProgress = false
                    ExecuteCallbacks()
                end
            end)
        end)
    end

    attempt()
    return isHeadVisible
end

---
--- Toggle head visibility
--- @return boolean Current head visibility state
---
function HeadManager.ToggleHead()
    log(1, function() return "HeadManager.ToggleHead called, current state: " .. tostring(isHeadVisible) end)
    if isHeadVisible then
        HeadManager.HideHead()
    else
        HeadManager.ShowHead()
    end
	return isHeadVisible
end

---
--- Get current head visibility status (queries game state)
--- @return boolean True if head is visible, false if hidden
---
function HeadManager.Status()
    local actualState = QueryHeadState()
    isHeadVisible = actualState
    log(1, function() return "HeadManager.Status() query result: " .. tostring(isHeadVisible) end)
    return isHeadVisible
end

---
--- Check if a head toggle operation is in progress
--- @return boolean True if toggle is in progress
---
function HeadManager.IsToggleInProgress()
    return toggleHeadInProgress
end

---
--- Update head visibility based on config
--- @param callback function Optional callback to execute when toggle completes
--- @return boolean Current head visibility state
---
function HeadManager.Update(callback)
    if Config.inner.showHead then
        if not isHeadVisible then
            HeadManager.ShowHead(callback)
        end
    else
        if isHeadVisible then
            HeadManager.HideHead(callback)
        end
    end
	return isHeadVisible
end

---
--- Force update head visibility (e.g. on init or load)
--- @param callback function Optional callback to execute when toggle completes
--- @return boolean Current head visibility state
---
function HeadManager.ForceUpdate(callback)
    if Config.inner.showHead then
        HeadManager.ShowHead(callback)
    else
        HeadManager.HideHead(callback)
    end
	return isHeadVisible
end

return HeadManager