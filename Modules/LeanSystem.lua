local Config = require("Modules/Config")
local Helpers = require("Modules/Helpers")

---
--- Check if player is aiming down sights
--- @return boolean isAiming
---
local function IsAiming()
    local player = Game.GetPlayer()
    if not player then return false end
    
    local bb = Game.GetBlackboardSystem()
    if not bb then return false end
    
    local defs = Game.GetAllBlackboardDefs()
    local playerBB = bb:GetLocalInstanced(player:GetEntityID(), defs.PlayerStateMachine)
    
    if playerBB then
        local upperBodyState = playerBB:GetInt(defs.PlayerStateMachine.UpperBody)

        local psmState = playerBB:GetInt(defs.PlayerStateMachine.UpperBody)

        return upperBodyState == 1 or upperBodyState == 6
    end
    
    return false
end

local LeanSystem = {
    direction = "None",
    holdState = { left = false, right = false },
    toggleState = { left = false, right = false },
    pendingLean = nil,
    wasReloading = false,
    wasSprinting = false,
    wasScanning = false,
    wasAiming = false,
    currentRoll = 0.0,
    targetRoll = 0.0,
    rollTransitionSpeed = 50.0,
    lastDirection = "None",
    lastVanillaLeanDir = "None",
    lastRollUpdate = false,
}

---
--- Get the player obstacle system
--- @return userdata|nil obstacleSystem
---
local function GetObstacleSystem()
    local spatialSystem = Game.GetSpatialQueriesSystem()
    if spatialSystem then
        return spatialSystem:GetPlayerObstacleSystem()
    end
    return nil
end

---
--- Get the cover direction for player
--- @param player userdata Player entity
--- @return userdata|nil coverDirection
---
local function GetCoverDirection(player)
    local obstacle = GetObstacleSystem()
    if obstacle and player then
        return obstacle:GetCoverDirection(player)
    end
    return nil
end

---
--- Get all blackboard definitions
--- @return userdata blackboardDefs
---
local function GetAllBlackboardDefs()
    return Game.GetAllBlackboardDefs()
end

---
--- Check if player is in menu or vehicle
--- @return boolean inMenuOrVehicle
---
local function IsInMenuOrVehicle()
    if Helpers.IsInVehicle() then return true end
    
    local player = Game.GetPlayer()
    if not player then return true end
    
    local bb = Game.GetBlackboardSystem()
    if not bb then return true end
    
    local defs = GetAllBlackboardDefs()
    local playerBB = bb:GetLocalInstanced(player:GetEntityID(), defs.PlayerStateMachine)
    
    if playerBB and playerBB:GetBool(defs.PlayerStateMachine.MountedToVehicle) then
        return true
    end
    return false
end

---
--- Check if player is reloading weapon
--- @return boolean isReloading
---
local function IsReloading()
    local player = Game.GetPlayer()
    if not player then return false end
    
    local bb = Game.GetBlackboardSystem()
    if not bb then return false end
    
    local defs = GetAllBlackboardDefs()
    local playerBB = bb:GetLocalInstanced(player:GetEntityID(), defs.PlayerStateMachine)
    
    if playerBB then
        return playerBB:GetInt(defs.PlayerStateMachine.Weapon) == 2
    end
    return false
end

---
--- Check if player is scanning
--- @return boolean isScanning
---
local function IsScanning()
    local player = Game.GetPlayer()
    if not player then return false end
    
    local bb = Game.GetBlackboardSystem()
    if not bb then return false end
    
    local defs = GetAllBlackboardDefs()
    local playerBB = bb:GetLocalInstanced(player:GetEntityID(), defs.PlayerStateMachine)
    
    if playerBB then
        return playerBB:GetInt(defs.PlayerStateMachine.Vision) == 1
    end
    return false
end

---
--- Check if player locomotion is restricted (sprinting, jumping, etc.)
--- @return boolean isRestricted
---
local function IsLocomotionRestricted()
    local player = Game.GetPlayer()
    if not player then return false end
    
    local bb = Game.GetBlackboardSystem()
    if not bb then return false end
    
    local defs = GetAllBlackboardDefs()
    local playerBB = bb:GetLocalInstanced(player:GetEntityID(), defs.PlayerStateMachine)
    
    if playerBB then
        local state = playerBB:GetInt(defs.PlayerStateMachine.LocomotionDetailed)
        -- Sprint(4), Slide(5), SlideFall(6), Ladder(10-13), Fall(14), SuperheroFall(17),
        -- Jump(18), DoubleJump(19), ChargeJump(20), HoverJump(21), DodgeAir(22),
        -- Knockdown(29), Felled(31)
        return state == 4 or state == 5 or state == 6 or
               (state >= 10 and state <= 14) or
               state == 17 or
               (state >= 18 and state <= 22) or
               state == 29 or state == 31
    end
    return false
end

---
--- Send lean event to player
--- @param player userdata Player entity
--- @param direction string|nil "left", "right", or nil for reset
---
local function SendLeanEvent(player, direction)
    local directionId = 0
    local directionEnum = "None"
    
    if direction == "left" then
        directionId = 1
        directionEnum = "Left"
    elseif direction == "right" then
        directionId = 2
        directionEnum = "Right"
    end
    
    LeanSystem.direction = directionEnum
    
    local event = PlayerCoverStatusChangedEvent.new()
    event.fullyBehindCover = false
    if direction then
        event.direction = directionId
    end
    player:QueueEvent(event)
end

---
--- Check if custom lean is currently active
--- @return boolean isCustomLeanActive
---
local function IsCustomLeanActive()
    return LeanSystem.direction ~= "None" or
           LeanSystem.pendingLean ~= nil or
           LeanSystem.holdState.left or
           LeanSystem.holdState.right or
           LeanSystem.toggleState.left or
           LeanSystem.toggleState.right
end
        
---
--- Reset lean to center position
---
function LeanSystem.ResetLean()
    local player = Game.GetPlayer()
    local obstacle = GetObstacleSystem()
    if not player or not obstacle then return end
    
    if LeanSystem.direction ~= "None" then
        if LeanSystem.direction == "Left" then
            obstacle:ManualLeanRight(player)
        elseif LeanSystem.direction == "Right" then
            obstacle:ManualLeanLeft(player)
        end

        SendLeanEvent(player, nil)

        LeanSystem.direction = "None"
        LeanSystem.lastDirection = "None"

        local fpp = Helpers.GetFPP()
        if fpp then
            fpp:SetLocalPosition(Vector4.new(0, Config.inner.cameraY, Config.inner.cameraZ, 1.0))
            fpp:SetLocalOrientation(Quaternion.new(0.0, 0.0, 0.0, 1.0))
        end
    end

    LeanSystem.toggleState.left = false
    LeanSystem.toggleState.right = false
    LeanSystem.holdState.left = false
    LeanSystem.holdState.right = false
end

---
--- Apply lean directly without state checks
--- @param direction string "left" or "right"
---
local function ApplyLeanDirect(direction)
    local player = Game.GetPlayer()
    local obstacle = GetObstacleSystem()
    if not player or not obstacle then return end

    local coverDirection = GetCoverDirection(player)

    if direction == "left" then
        if coverDirection == gamePlayerCoverDirection.Right then
            obstacle:ManualLeanRight(player)
        elseif coverDirection == gamePlayerCoverDirection.Left then
            return
        end
        obstacle:ManualLeanRight(player)
        SendLeanEvent(player, "left")

    elseif direction == "right" then
        if coverDirection == gamePlayerCoverDirection.Left then
            obstacle:ManualLeanLeft(player)
        elseif coverDirection == gamePlayerCoverDirection.Right then
            return
        end
        obstacle:ManualLeanLeft(player)
        SendLeanEvent(player, "right")
    end
end

---
--- Handle lean in hold mode
--- @param direction string "left" or "right"
--- @param isPressed boolean Key is pressed
---
local function DoLeanHold(direction, isPressed)
    local player = Game.GetPlayer()
    local obstacle = GetObstacleSystem()
    if not player or not obstacle then return end

    if isPressed then
        local opposite = direction == "left" and "Right" or "Left"
        if LeanSystem.direction == opposite then
            if LeanSystem.direction == "Left" then
                obstacle:ManualLeanLeft(player)
            else
                obstacle:ManualLeanRight(player)
            end
        end

        if direction == "left" then
            obstacle:ManualLeanRight(player)
            SendLeanEvent(player, "left")
        else
            obstacle:ManualLeanLeft(player)
            SendLeanEvent(player, "right")
        end
    else
        local opposite = direction == "left" and "right" or "left"

        if (direction == "left" and LeanSystem.direction == "Left") or
           (direction == "right" and LeanSystem.direction == "Right") then

            if LeanSystem.holdState[opposite] then
                if opposite == "left" then
                    obstacle:ManualLeanLeft(player)
                    obstacle:ManualLeanRight(player)
                    SendLeanEvent(player, "left")
                else
                    obstacle:ManualLeanRight(player)
                    obstacle:ManualLeanLeft(player)
                    SendLeanEvent(player, "right")
                end
            else
                if direction == "left" then
                    obstacle:ManualLeanLeft(player)
                else
                    obstacle:ManualLeanRight(player)
                end
                SendLeanEvent(player, nil)

                local fpp = Helpers.GetFPP()
                if fpp then
                    fpp:SetLocalPosition(Vector4.new(0, Config.inner.cameraY, Config.inner.cameraZ, 1.0))
                end

                LeanSystem.targetRoll = 0.0
            end
        end
    end
end

---
--- Handle lean in toggle mode
--- @param direction string "left" or "right"
---
local function DoLeanToggle(direction)
    local player = Game.GetPlayer()
    local obstacle = GetObstacleSystem()
    if not player or not obstacle then return end

    local opposite = direction == "left" and "right" or "left"

    if LeanSystem.toggleState[direction] then
        if direction == "left" then
            obstacle:ManualLeanLeft(player)
        else
            obstacle:ManualLeanRight(player)
        end
        SendLeanEvent(player, nil)
        LeanSystem.toggleState[direction] = false

        local fpp = Helpers.GetFPP()
        if fpp then
            fpp:SetLocalPosition(Vector4.new(0, Config.inner.cameraY, Config.inner.cameraZ, 1.0))
        end

        LeanSystem.targetRoll = 0.0
        return
    end

    if LeanSystem.toggleState[opposite] then
        if opposite == "left" then
            obstacle:ManualLeanLeft(player)
        else
            obstacle:ManualLeanRight(player)
        end
        SendLeanEvent(player, nil)
        LeanSystem.toggleState[opposite] = false

        local fpp = Helpers.GetFPP()
        if fpp then
            fpp:SetLocalPosition(Vector4.new(0, Config.inner.cameraY, Config.inner.cameraZ, 1.0))
        end

        LeanSystem.targetRoll = 0.0

        return
    end

    if direction == "left" then
        obstacle:ManualLeanRight(player)
        SendLeanEvent(player, "left")
    else
        obstacle:ManualLeanLeft(player)
        SendLeanEvent(player, "right")
    end
    LeanSystem.toggleState[direction] = true
end

---
--- Check if player can lean
--- @return boolean canLean
---
local function CanLean()
    if IsInMenuOrVehicle() then return false end
    if IsReloading() then return false end
    if IsLocomotionRestricted() then return false end
    return true
end

---
--- Handle lean input
--- @param direction string "left" or "right"
--- @param isPressed boolean Key is pressed
---
function LeanSystem.DoLean(direction, isPressed)
    if IsScanning() then return end

	if Config.inner.leanToggleMode then
        if not isPressed then return end

        if not CanLean() then
            LeanSystem.pendingLean = direction
            return
        end

        LeanSystem.pendingLean = nil
        DoLeanToggle(direction)
		return
    end

    if direction == "left" then
        LeanSystem.holdState.left = isPressed
        if isPressed then LeanSystem.holdState.right = false end
    else
        LeanSystem.holdState.right = isPressed
        if isPressed then LeanSystem.holdState.left = false end
    end

    if not CanLean() then
        if isPressed then
            LeanSystem.pendingLean = direction
        elseif LeanSystem.pendingLean == direction then
            LeanSystem.pendingLean = nil
        end
        return
    end

    LeanSystem.pendingLean = nil
    DoLeanHold(direction, isPressed)
end

---
--- Update lean system each frame
--- @param delta number Time delta
---
function LeanSystem.Update(delta)
    local isReloading = IsReloading()
    local isRestricted = IsLocomotionRestricted()
    local isScanning = IsScanning()
    local isAiming = IsAiming()

    if LeanSystem.wasScanning and not isScanning then
        LeanSystem.ResetLean()
    end

    if LeanSystem.wasAiming and not isAiming and LeanSystem.direction ~= "None" then
        local fpp = Helpers.GetFPP()
        if fpp then
            fpp:SetLocalPosition(Vector4.new(0, Config.inner.cameraY, Config.inner.cameraZ, 1.0))
            fpp:SetLocalOrientation(Quaternion.new(0.0, 0.0, 0.0, 1.0))
		end
    end

    LeanSystem.wasAiming = isAiming

    if Config.inner.leanToggleMode and not LeanSystem.wasSprinting and isRestricted then
        if LeanSystem.toggleState.left or LeanSystem.toggleState.right then
            LeanSystem.ResetLean()
        end
	end

    local shouldApply = (LeanSystem.wasReloading and not isReloading) or
                        (LeanSystem.wasSprinting and not isRestricted)

    if shouldApply and CanLean() and not isScanning then
        if Config.inner.leanToggleMode then
            if LeanSystem.pendingLean then
                DoLeanToggle(LeanSystem.pendingLean)
                LeanSystem.pendingLean = nil
            end
        else
            if LeanSystem.holdState.left then
                ApplyLeanDirect("left")
            elseif LeanSystem.holdState.right then
                ApplyLeanDirect("right")
            end
        end
    end

    LeanSystem.wasReloading = isReloading
    LeanSystem.wasSprinting = isRestricted
    LeanSystem.wasScanning = isScanning

    local rollDiff = LeanSystem.targetRoll - LeanSystem.currentRoll
    local rollStep = LeanSystem.rollTransitionSpeed * delta

    if math.abs(rollDiff) > 0.001 then
        if math.abs(rollDiff) <= rollStep then
            LeanSystem.currentRoll = LeanSystem.targetRoll
        else
            LeanSystem.currentRoll = LeanSystem.currentRoll + (rollDiff > 0 and rollStep or -rollStep)
        end
    elseif math.abs(rollDiff) > 0 then
        LeanSystem.currentRoll = LeanSystem.targetRoll
    end

    local directionChanged = LeanSystem.direction ~= LeanSystem.lastDirection
    LeanSystem.lastDirection = LeanSystem.direction

    if LeanSystem.direction ~= "None" then
        if Config.inner.enableWeaponSupport and Helpers.HasWeapon() and IsAiming() then
            local leanMultiplier = LeanSystem.direction == "Left" and -1 or 1
            local xOffset = Config.inner.leanCameraOffset * leanMultiplier
            local targetRollNew = Config.inner.leanCameraRoll * leanMultiplier
            local zOffset = Config.inner.cameraZ + Config.inner.leanCameraHeight

            if directionChanged or math.abs(LeanSystem.currentRoll - targetRollNew) > 0.001 then
                LeanSystem.targetRoll = targetRollNew
                Helpers.SetCamera(xOffset, Config.inner.cameraY, zOffset, LeanSystem.currentRoll, 0, 0)
                LeanSystem.lastRollUpdate = true
            end
        else
            LeanSystem.targetRoll = 0.0
            if directionChanged or math.abs(LeanSystem.currentRoll) > 0.01 then
                Helpers.SetCamera(0, Config.inner.cameraY, Config.inner.cameraZ, LeanSystem.currentRoll, 0, 0)
                LeanSystem.lastRollUpdate = true
            else
                LeanSystem.lastRollUpdate = false
            end
        end
    else
        local vanillaLeanDir = "None"
        if not Config.inner.disableVanillaLean and Config.inner.enableVanillaLeanCameraFixes and Config.inner.enableWeaponSupport and Helpers.HasWeapon() and IsAiming() then
            local player = Game.GetPlayer()
            local coverDir = player and GetCoverDirection(player) or nil
            if coverDir and coverDir == gamePlayerCoverDirection.Left then
                vanillaLeanDir = "Left"
            elseif coverDir and coverDir == gamePlayerCoverDirection.Right then
                vanillaLeanDir = "Right"
            end
        end

        local vanillaLeanDirChanged = vanillaLeanDir ~= LeanSystem.lastVanillaLeanDir
        LeanSystem.lastVanillaLeanDir = vanillaLeanDir

        if vanillaLeanDir ~= "None" then
            local leanMultiplier = vanillaLeanDir == "Left" and -1 or 1
            local xOffset = Config.inner.leanCameraOffset * leanMultiplier
            local targetRollNew = Config.inner.leanCameraRoll * leanMultiplier
            local zOffset = Config.inner.cameraZ + Config.inner.leanCameraHeight

            if vanillaLeanDirChanged or math.abs(LeanSystem.currentRoll - targetRollNew) > 0.001 then
                LeanSystem.targetRoll = targetRollNew
                Helpers.SetCamera(xOffset, Config.inner.cameraY, zOffset, LeanSystem.currentRoll, 0, 0)
                LeanSystem.lastRollUpdate = true
            end
        else
            LeanSystem.targetRoll = 0.0
            if vanillaLeanDirChanged or math.abs(LeanSystem.currentRoll) > 0.01 then
                Helpers.SetCamera(0, Config.inner.cameraY, Config.inner.cameraZ, LeanSystem.currentRoll, 0, 0)
                LeanSystem.lastRollUpdate = true
            else
                LeanSystem.lastRollUpdate = false
            end
        end
    end
end

---
--- Initialize lean system overrides
---
function LeanSystem.Init()
    Override("CoverActionTransition", "IsPlayerInCorrectStateToPeek", function(self, scriptInterface, stateContext, wrappedMethod)
        if not self or not scriptInterface or not stateContext then
            return false
        end

        if LeanSystem.direction == "None" then
            if Config.inner.disableVanillaLean then
                return false
            end
            if Config.inner.vanillaLeanRequiresWeapon and not Helpers.HasWeapon() then
                return false
            end
            return wrappedMethod(scriptInterface, stateContext)
        end
        
        if self.IsInSafeSceneTier and self:IsInSafeSceneTier(scriptInterface) then 
            return false 
        end
        
        local blackboardDefs = GetAllBlackboardDefs()
        if blackboardDefs and scriptInterface.localBlackboard then
            if scriptInterface.localBlackboard:GetBool(blackboardDefs.PlayerStateMachine.MountedToVehicle) then 
                return false 
            end

            local locomotion = scriptInterface.localBlackboard:GetInt(blackboardDefs.PlayerStateMachine.LocomotionDetailed)
            local weapon = scriptInterface.localBlackboard:GetInt(blackboardDefs.PlayerStateMachine.Weapon)

            -- Sprint(4), Slide(5), SlideFall(6), Ladder(10-13), Fall(14), SuperheroFall(17),
            -- Jump(18), DoubleJump(19), ChargeJump(20), HoverJump(21), DodgeAir(22),
            -- Knockdown(29), Felled(31)
            if locomotion == 4 or locomotion == 5 or locomotion == 6 or
               (locomotion >= 10 and locomotion <= 14) or
               locomotion == 17 or
               (locomotion >= 18 and locomotion <= 22) or
               locomotion == 29 or locomotion == 31 or
               weapon == 2 then
                return false
            end
        end
        return true
    end)

    Override("PlayerObstacleSystem", "GetCoverDirection", function(self, instigator, wrappedMethod)
        if LeanSystem.direction ~= "None" and IsCustomLeanActive() then
            return gamePlayerCoverDirection[LeanSystem.direction]
        end
        return wrappedMethod(instigator)
    end)

    Override("ActivateCoverEvents", "OnEnter", function(self, stateContext, scriptInterface, wrappedMethod)
        if LeanSystem.direction == "None" or not IsCustomLeanActive() then
            if not Config.inner.disableVanillaLean then
                wrappedMethod(stateContext, scriptInterface)
            end
            return
        end
        if self and self.SetCoverStateAnimFeature then
            self:SetCoverStateAnimFeature(scriptInterface, EnumInt(gamePlayerCoverMode.Auto))
        end
        if self then
            self.usingCover = false
        end
    end)

    Override("InactiveCoverEvents", "OnEnter", function(self, stateContext, scriptInterface, wrappedMethod)
        if LeanSystem.direction == "None" or not IsCustomLeanActive() then
            if not Config.inner.disableVanillaLean then
                wrappedMethod(stateContext, scriptInterface)
            end
            return
        end
        if self and self.SetCoverStateAnimFeature then
            self:SetCoverStateAnimFeature(scriptInterface, 0)
        end
        if stateContext and stateContext.SetPermanentBoolParameter then
            stateContext:SetPermanentBoolParameter("QuickthrowHoldPeek", true, true)
        end
        if not (LeanSystem.toggleState.left or LeanSystem.toggleState.right or
                LeanSystem.holdState.left or LeanSystem.holdState.right) then
            LeanSystem.ResetLean()
        end
    end)
end

return LeanSystem