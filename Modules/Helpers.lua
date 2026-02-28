local GameSettings = require("Modules/GameSettings")
local Config = require("Modules/Config")
local Vars = require("Modules/Vars")
local Easings = require("Modules/Easings")
local logLevel = 0

local Helpers = {}

--------------------
-- UTILS
--------------------

function Helpers.PrintMsg(msg)
    msg = ('[IMFP-E] ' .. msg)
    print(msg)
end

function Helpers.RaiseError(msg)
    msg = ('[IMFP-E] ERROR: ' .. msg)
    print(msg)
    error(msg, 2)
end


----------------
-- THE REST
----------------

function Helpers.HasBVFP()
    local bvfp = GetMod("EnhancedVehicleCamera")
    return bvfp ~= nil
end

function Helpers.HasShift()
	local shiftMod = GetMod("Shift")
	return shiftMod ~= nil
end

-----------------
-- CAMERA
-----------------

-- Camera Y interpolation state for smooth head show/hide transitions
Helpers._cameraInterp = {
    isActive = false,
    startY = 0,
    targetY = 0,
    duration = 0.4,
    elapsed = 0,
}
---
--- Start camera Y interpolation to smoothly transition between positions
--- @param targetY number Target camera Y position
--- @param duration number Duration of interpolation in seconds (default: 0.4)
---
function Helpers.StartCameraYInterpolation(targetY, duration)
    Helpers._cameraInterp.startY = Config.inner.cameraY
    Helpers._cameraInterp.targetY = targetY
    Helpers._cameraInterp.duration = duration or 0.4
    Helpers._cameraInterp.elapsed = 0
    Helpers._cameraInterp.isActive = true
end
    
---
--- Update camera Y interpolation (call every frame from onUpdate)
--- @param delta number Delta time since last frame
---
function Helpers.UpdateCameraYInterpolation(delta)
    if not Helpers._cameraInterp.isActive then
        return
    end

    Helpers._cameraInterp.elapsed = Helpers._cameraInterp.elapsed + delta
    local progress = math.min(1, Helpers._cameraInterp.elapsed / Helpers._cameraInterp.duration)
    local eased = Easings.EaseOutCubic(progress)

    local interpolatedY = Helpers._cameraInterp.startY +
        (Helpers._cameraInterp.targetY - Helpers._cameraInterp.startY) * eased
    local fpp = Helpers.GetFPP()
    if fpp then
        local currentZ = Config.inner.cameraZ
        fpp:SetLocalPosition(Vector4.new(0.0, interpolatedY, currentZ, 1.0))
    end

    if progress >= 1 then
        Helpers._cameraInterp.isActive = false
    end
end

---
--- Check if camera Y interpolation is currently active
--- @return boolean True if interpolation is in progress
---
function Helpers.IsCameraYInterpolating()
    return Helpers._cameraInterp.isActive
end

function Helpers.GetFPP()
    local player = Game.GetPlayer()
    if player == nil then
        return
    end

    local fpp = player:GetFPPCameraComponent()
    if fpp == nil then
    end

    return fpp
end

function Helpers.ResetCamera(defaultFOV)
    local fpp = Helpers.GetFPP()
    if fpp == nil then
        return
    end

	local Z = Config.inner.cameraZ
    local Y = Config.inner.cameraY
    fpp:SetLocalPosition(Vector4.new(0.0, Y, Z, 1.0))
    fpp:SetLocalOrientation(Quaternion.new(0.0, 0.0, 0, 1.0))
    if defaultFOV then
        fpp:SetFOV(defaultFOV)
    end
end

function Helpers.ResetCameraVehicle(defaultFOV)
    local fpp = Helpers.GetFPP()
    if fpp == nil then
        return
    end

    fpp:SetLocalPosition(Vector4.new(0.0, 0.0, 0.0, 1.0))
    fpp:SetLocalOrientation(Quaternion.new(0.0, 0.0, 0, 1.0))
    if defaultFOV then
        fpp:SetFOV(defaultFOV)
    end
end

function Helpers.ResetFOV(fov)
    local fpp = Helpers.GetFPP()
    if fpp == nil then
        return
    end

    if fov then
        fpp:SetFOV(fov)
    end
end

function Helpers.SetCamera(x, y, z, roll, pitch, yaw, fov)
    local fpp = Helpers.GetFPP()
    if not fpp then
        return
    end

    if roll ~= nil or pitch ~= nil or yaw ~= nil then
        if roll == nil then roll = 0 end
        if pitch == nil then pitch = 0 end
        if yaw == nil then yaw = 0 end
        fpp:SetLocalOrientation(GetSingleton('EulerAngles'):ToQuat(EulerAngles.new(roll, pitch, yaw)))
    end

    if x ~= nil or y ~= nil or z ~= nil then
        if x == nil then x = 0 end
        if y == nil then y = 0 end
        if z == nil then z = 0 end
        fpp:SetLocalPosition(Vector4.new(x, y, z, 1.0))
    end

    if fov ~= nil and fov > 1 and fov < 120 then
        fpp:SetFOV(fov)
    end
end

function Helpers.SetStandCamera(x, y, z, roll, pitch, yaw, fov)
    local fpp = Helpers.GetFPP()
    if not fpp then
        return
    end

    if roll ~= nil or pitch ~= nil or yaw ~= nil then
        if roll == nil then roll = 0 end
        if pitch == nil then pitch = 0 end
        if yaw == nil then yaw = 0 end
        fpp:SetLocalOrientation(GetSingleton('EulerAngles'):ToQuat(EulerAngles.new(roll, pitch, yaw)))
    end

    if x ~= nil or y ~= nil or z ~= nil then
        if x == nil then x = 0 end
        if y == nil then y = 0 end
        if z == nil then z = 0 end
        local Z = z + Config.inner.cameraZ
        local Z = Z - math.abs(Config.inner.cameraY)
        local Y = Config.inner.cameraY
        fpp:SetLocalPosition(Vector4.new(x, Y, Z, 1.0))
    end

    if fov ~= nil and fov > 1 and fov < 120 then
        fpp:SetFOV(fov)
    end
end

function Helpers.SetFreeCamera(x, y, z, roll, pitch, yaw, fov)
    local fpp = Helpers.GetFPP()
    if not fpp then
        return
    end

    if roll ~= nil or pitch ~= nil or yaw ~= nil then
        if roll == nil then roll = 0 end
        if pitch == nil then pitch = 0 end
        if yaw == nil then yaw = 0 end
        fpp:SetLocalOrientation(GetSingleton('EulerAngles'):ToQuat(EulerAngles.new(roll, pitch, yaw)))
    end

    if x ~= nil or y ~= nil or z ~= nil then
        if x == nil then x = 0 end
        if y == nil then y = 0 end
        if z == nil then z = 0 end
        local Z = z
        local Y = y
        fpp:SetLocalPosition(Vector4.new(x, Y, Z, 1.0))
    end

    if fov ~= nil and fov > 1 and fov < 120 then
        fpp:SetFOV(fov)
    end
end

function Helpers.GetPitch()
    local ok, res = pcall(function()
        local fpp = Helpers.GetFPP()
        if not fpp then
            return
        end

        local matrix = fpp:GetLocalToWorld()
        if not matrix then
            return
        end
        local rotation = matrix:GetRotation(matrix)
        if not rotation then
            return
        end

        return rotation.pitch
    end)

    if ok then
        return res
    end
end

function Helpers.GetLookPitch()
    local ok, res = pcall(function()
        local camSys = Game.GetCameraSystem()
        if not camSys then return end
        local fwd = camSys:GetActiveCameraForward()
        if not fwd then return end
        local clamped = math.max(-1.0, math.min(1.0, fwd.z))
        return math.deg(math.asin(clamped))
    end)
    if ok then return res end
end

function Helpers.GetFOV()
    local fpp = Helpers.GetFPP()
    if not fpp then
        return
    end

    local fov = fpp:GetFOV()

    -- TODO: fix
    if fov < 10 then
        fov = 68
    end

    return fov
end

Helpers._protected = {
    isFreeObservation = false,
    isRestoringCamera = false,
}
function Helpers.IsFreeObservation() return Helpers._protected.isFreeObservation end
function Helpers.IsRestoringCamera() return Helpers._protected.isRestoringCamera end
function Helpers.SetFreeObservation(val) Helpers._protected.isFreeObservation = val end
function Helpers.SetRestoringCamera(val) Helpers._protected.isRestoringCamera = val end

function Helpers.LockMovement()
    GameSettings.Set('/controls/fppcameramouse/FPP_MouseX', 0)
    GameSettings.Set('/controls/fppcameramouse/FPP_MouseY', 0)
end

function Helpers.UnlockMovement()
    local x = Config.inner.mouseNativeSensX
    local y = Config.inner.mouseNativeSensY
    if x == nil or x < 1 then x = 5 end
    if y == nil or y < 1 then y = 5 end

    GameSettings.Set('/controls/fppcameramouse/FPP_MouseX', x)
    GameSettings.Set('/controls/fppcameramouse/FPP_MouseY', y)
end

------------------
-- Context detection
------------------

function Helpers.HasMountedVehicle()
    local player = Game.GetPlayer()
    return player and (not not Game['GetMountedVehicle;GameObject'](player))
end

function Helpers.IsPlayerDriver()
    local player = Game.GetPlayer()
    if player then
        local veh = Game['GetMountedVehicle;GameObject'](player)
        if veh then
            return veh:IsPlayerDriver()
        end
    end
end

function GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    local player = Game.GetPlayer()
    if player then
        local blackboardDefs = Game.GetAllBlackboardDefs()
        if blackboardDefs then
            local blackboardSystem = Game.GetBlackboardSystem()
            if blackboardSystem then
                return player, blackboardDefs, blackboardSystem
            end
        end
    end
end

function Helpers.IsInVehicle()
    local player = Game.GetPlayer()
    if player then
        local workspotSystem = Game.GetWorkspotSystem()
        return workspotSystem and workspotSystem:IsActorInWorkspot(player)
            and workspotSystem:GetExtendedInfo(player).isActive
            and Helpers.HasMountedVehicle()
    end
    return false
end

function Helpers.IsSwimming()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
        return blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.Swimming) > 0
    end
    return false
end

function Helpers.IsYInverted()
    return GameSettings.Get('/controls/fppcameramouse/FPP_MouseInvertY')
end
function Helpers.IsXInverted()
    return GameSettings.Get('/controls/fppcameramouse/FPP_MouseInvertX')
end

-- Undefined = 0
-- Tier1_FullGameplay = 1
-- Tier2_StagedGameplay = 2
-- Tier3_LimitedGameplay = 3
-- Tier4_FPPCinematic = 4
-- Tier5_Cinematic = 5
function Helpers.GetSceneTier()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
        return blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.SceneTier)
    end
    return 0
end

function Helpers.IsTakingDown()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
        return blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.Takedown)
    end

    return 0
end

function Helpers.IsKnockedDown()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)

        if blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.Landing) > 1 then
            return true
        end

        if StatusEffectSystem.ObjectHasStatusEffectOfType(Game.GetPlayer(), 'VehicleKnockdown') then
            return true
        end

        if StatusEffectSystem.ObjectHasStatusEffectOfType(Game.GetPlayer(), 'BikeKnockdown') then
            return true
        end
    end

    return false
end

function Helpers.IsCarryingBody()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
        return blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.BodyCarrying) > 0
    end

    return false
end

-- TODO: implement fully?
function Helpers.IsCarrying()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
        return blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.Carrying) > 0
    end
end

function Helpers.IsClimbing()
    local player, blackboardDefs, blackboardSystem = GetPlayerBlackboardDefsAndBlackboardSystemIfAll()
    if player then
        local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
        return blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.Carrying)
    end
end

function Helpers.HasWeapon()
    local player = Game.GetPlayer()
    if player then
        local ts = Game.GetTransactionSystem()
        return ts and ts:GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight")) ~= nil
    end
    return false
end

---
--- Calculate procedural height adjustment for Freelook camera
--- This applies the same downward movement as the regular procedural camera when looking down
--- @param pitch number Current camera pitch
--- @param isCrouching boolean Whether player is crouching
--- @return number height adjustment (negative = downward)
---
function Helpers.CalculateProceduralHeightAdjustment(pitch, isCrouching)
    local Vars = require("Modules/Vars")
    
    local curPitch = math.floor(math.min(pitch + Vars.OFFSET, 0) * 1000) / 1000
    local maxPitch = -80 + Vars.OFFSET
    
    if curPitch >= 0 then
        return 0 
    end
    
    local progress = math.min(1, curPitch / maxPitch)
    
    local crouchMultHeight = isCrouching and Vars.CROUCH_MULT_HEIGHT or 1
    
    local heightInitialBoost = math.max(
        Vars.HEIGHT_BOOST_MIN,
        Vars.HEIGHT_BOOST_MULT_A * progress - math.max(0, (progress - Vars.HEIGHT_INCREASE_KEY_POINT) * Vars.HEIGHT_BOOST_MULT_B)
    )
    
    local height = math.min(1, progress * Vars.HEIGHT_PROGRESS_MULT) * Vars.HEIGHT_BASE_VALUE * (isCrouching and 1 or heightInitialBoost) * crouchMultHeight
    
    return height
end

---
--- Check if player is looking at an angle that would cause head clipping.
--- @return boolean True if head should be hidden due to pitch angle
---
local _lastLoggedPitch = nil
function Helpers.ShouldHideHeadDueToPitch()
    local pitchValue = Helpers.GetLookPitch()
    if not pitchValue then
        return false
    end

    local downThreshold = Config.inner.headPitchDownThreshold or 40.0
    local upThreshold = Config.inner.headPitchUpThreshold or 20.0

    if pitchValue < -downThreshold or pitchValue > upThreshold then
        return true
    end

    return false
end

---
--- Restore camera to the player's configured position with smooth interpolation.
--- Called when head is hidden to undo any Y adjustment.
---
function Helpers.RestoreCameraY()
    Helpers.StartCameraYInterpolation(Config.inner.cameraY, 0.4)
end

---
--- Push camera Y forward enough to prevent clipping with the visible head with smooth interpolation.
---
function Helpers.AdjustCameraYForHead()
    local minY = Config.inner.headMinCameraY or 0.050
    local adjustedY = math.max(Config.inner.cameraY, minY)
    Helpers.StartCameraYInterpolation(adjustedY, 0.4)
end

return Helpers