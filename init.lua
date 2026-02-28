local ImmersiveFirstPerson = { version = "3.0.2" }
local Cron = require("Modules/Cron")
local GameSession = require("Modules/GameSession")
local GameSettings = require("Modules/GameSettings")
local GameUI = require("Modules/GameUI")
local Vars = require("Modules/Vars")
local Easings = require("Modules/Easings")
local Helpers = require("Modules/Helpers")
local Config = require("Modules/Config")
local LeanSystem = require("Modules/LeanSystem")
local WeaponOffset = require("Modules/WeaponOffset")
local HeadManager = require("Modules/HeadManager3")

-- Logging
local logLevel = 0
local function log(level, msg)
    if level <= logLevel then
        print("[IMFP-E] " .. (type(msg) == "function" and msg() or tostring(msg)))
    end
end

-- States
local inited = false
local isLoaded = false
local defaultFOV = 68
local initialFOV = 68
local isOverlayOpen = false
local isEnabled = true
local isDisabledByApi = false
local isYInverted = false
local isXInverted = false
local freeLookInCombat = false
local previousVehicleState = false
local isEnteringVehicle = false
local isInVehicle = false
local isExitingVehicle = false
local wasReset = true
local inMenu = false
local disabledThird = false
local enabledThird = false
local gameStart = false
local gameResume = false
local showExperimental = true
local isHeadVisible = false
local wasFreeLookActive = false
local headHiddenByPitch = false
local cameraWasEnabled = false
local frameCount = 0

local API = {}

---
--- Enable the mod via API
---
function API.Enable()
    isDisabledByApi = false
    isEnabled = true
    if ShouldSetCamera(freeLookInCombat) then
        ImmersiveFirstPerson.HandleCamera(true)
    end
    isHeadVisible = HeadManager.ForceUpdate(function()
        isHeadVisible = HeadManager.Status()
        ImmersiveFirstPerson.HandleCamera(true)
    end)
end

---
--- Disable the mod via API
---
function API.Disable()
    isEnabled = false
    isDisabledByApi = true
    ResetCamera()
    ResetFreeLook()
    isHeadVisible = HeadManager.HideHead(function()
        isHeadVisible = HeadManager.Status()
        Helpers.RestoreCameraY()
    end)
end

---
--- Check if mod is enabled
--- @return boolean enabled
---
function API.IsEnabled()
  return isEnabled
end

---
--- Check if freelook in combat is enabled
--- @return boolean enabled
---
function CombatFreeLook()
    return freeLookInCombat
end

---
--- Get default FOV or nil based on config
--- @return number|nil fov
---
function defaultFovOrNil()
    if not Config.inner.dontChangeFov then
      return defaultFOV
    end
    return nil
end

---
--- Reset camera to default position
--- @param force boolean Force reset even if already reset
---
function ResetCamera(force)
    if not wasReset or force then
		WeaponOffset.Reset()
		if isHeadVisible then
			isHeadVisible = HeadManager.HideHead(function()
				isHeadVisible = HeadManager.Status()
				Helpers.RestoreCameraY()
			end)
		end
        Helpers.ResetCamera(defaultFovOrNil())
        wasReset = true
    end
end

---
--- Check if third party mods are blocking
--- @return boolean blocking
---
function blockingThirdPartyMods()

	-- Place mods that block this mod here, for example gtaTravel:
    -- local gtaTravel = GetMod("gtaTravel")
    -- if gtaTravel and gtaTravel.api and not gtaTravel.api.done then
    --     return true
    -- end
	local shiftMod = GetMod("Shift")
	if shiftMod and shiftMod.api.IsEnabled() then
		return true
	end

    return false
end

function disableThirdPartyMods()

	local shiftMod = GetMod("Shift")
	if shiftMod and shiftMod.api.IsEnabled() then
		shiftMod.api.ResetCamera(0)
		Cron.After(0.1, function()
			shiftMod.api.Disable()
		end)
	end
	local bvfp = GetMod("EnhancedVehicleCamera")
	if bvfp and bvfp.api.IsEnabled() then
		Cron.After(0.1, function()
			bvfp.api.Disable()
		end)
	end
	
	enabledThird = false
end

function enableThirdPartyMods()

	local shiftMod = GetMod("Shift")
	if shiftMod and not shiftMod.api.IsEnabled() and Config.inner.useShift then
		Cron.After(0.1, function()
			shiftMod.api.Enable()
			Cron.After(0.2, function()
				shiftMod.api.IsInVehicle()
			end)
		end)
	end
	local bvfp = GetMod("EnhancedVehicleCamera")
	if bvfp and not bvfp.api.IsEnabled() and Config.inner.useBVFP then
		Cron.After(0.1, function()
			bvfp.api.Enable()
		end)
	end
	
	enabledThird = true
end

local lastPitch = 0

---
--- Check if camera should be set based on game state
--- @param ignoreWeapon boolean Optional, ignore weapon check
--- @return boolean shouldSet
---
function ShouldSetCamera(ignoreWeapon)
    if ignoreWeapon == nil then ignoreWeapon = false end
    local sceneTier = Helpers.GetSceneTier()
    local isFullGameplayScene = sceneTier > 0 and sceneTier < Config.inner.sceneLevel
    local hasWeapon = Helpers.HasWeapon()
    if hasWeapon and not Config.inner.enableWeaponSupport and not ignoreWeapon then
        return false
    end

	if Config.inner.swimming then
		if Helpers.IsSwimming() then return false end
	end
	if Config.inner.takingDown then
		if not Helpers.IsTakingDown() <= 0 then return false end
	end
	if Config.inner.blockingMods then
		if blockingThirdPartyMods() then return false end
	end
	if Config.inner.carryBody then
		if Helpers.IsCarryingBody() then return false end
	end
	if Config.inner.knockedDown then
		if Helpers.IsKnockedDown() then return false end
	end

    return isFullGameplayScene
        and (not hasWeapon or ignoreWeapon or Config.inner.enableWeaponSupport)
        and not Helpers.IsInVehicle()
end

---
--- Check if player is crouching
--- @return boolean isCrouching
---
function IsCrouching()
    return Game.GetPlayer():GetPS():IsCrouch()
end

--- Camera handling
local wasCrouching = false

---
--- Handle camera position based on pitch and crouch state
--- @param force boolean Optional, force camera update
---
function ImmersiveFirstPerson.HandleCamera(force)
    if force == nil then force = false end

    if Helpers.IsFreeObservation() then
        return
    end

    if not ShouldSetCamera() then
		if isHeadVisible and not HeadManager.IsToggleInProgress() then
			isHeadVisible = HeadManager.HideHead(function()
				isHeadVisible = HeadManager.Status()
				Helpers.RestoreCameraY()
			end)
		end
		if Helpers.IsInVehicle() then
			WeaponOffset.Reset() 
            return
        end
        ResetCamera()
        return
    end

    if Config.inner.enableWeaponSupport and Helpers.HasWeapon() then
        return
    end

    local pitchValue = Helpers.GetPitch()
    if not pitchValue then
        return
    end

    local isCrouching = IsCrouching()

    local curPitch = math.floor(math.min(pitchValue + Vars.OFFSET, 0) * 1000) / 1000
    local maxPitch = -80 + Vars.OFFSET

    local hasPitchNotablyChanged = math.abs(lastPitch - curPitch) >= Vars.PITCH_CHANGE_STEP
    local hasCrouchingChanged = isCrouching ~= wasCrouching
    if not hasPitchNotablyChanged and not force and not hasCrouchingChanged then
        return
    end

    wasCrouching = isCrouching
    lastPitch = curPitch

    if not isEnabled then
        return
    end

    if not ShouldSetCamera() then
        return
    end

    local progress = math.min(1, curPitch / maxPitch)

    if progress <= 0 then
        ResetCamera()
        return
    end

    if wasReset then
        defaultFOV = Helpers.GetFOV()
        wasReset = false
    end

    -- crouch-specific multipilers
    local crouchMultShift = isCrouching and Vars.CROUCH_MULT_SHIFT or 1
    local crouchMultLean = isCrouching and Vars.CROUCH_MULT_LEAN or 1
    local crouchMultHeight = isCrouching and Vars.CROUCH_MULT_HEIGHT or 1

	-- shift changes based on FOV, so we take this into account
    local fovShiftCorrection = defaultFOV / Vars.BASE_FOV

    -- FOV correction offset to prevent clipping
    local fovCorrectionOffset = (68 / defaultFOV - 1) * Vars.FOV_CORRECTION_MULT

    -- at the beginning camera goes way too hard down and can clip through stuff like nomad goggles.
    -- we try to minimize this effect with these multipliers
    local shiftInitialSlowDown = math.min(1, (progress / Vars.STOP_SHIFT_BOOST_AT))
    local shift = math.min(1, progress * Vars.SHIFT_PROGRESS_MULT) * Vars.SHIFT_BASE_VALUE * crouchMultShift * shiftInitialSlowDown + fovCorrectionOffset

    -- Height goes gradually from 0 to N to -N
    local heightInitialBoost = math.max(Vars.HEIGHT_BOOST_MIN, Vars.HEIGHT_BOOST_MULT_A * progress - math.max(0, (progress - Vars.HEIGHT_INCREASE_KEY_POINT) * Vars.HEIGHT_BOOST_MULT_B))

    -- Adjusted to stop higher at max pitch - procedural camera comes up a bit
    -- With cameraZ=0.085, targeting final height around 0.035-0.04... I GUESS?!
    local height = math.min(1, progress * Vars.HEIGHT_PROGRESS_MULT) * -0.05 * (isCrouching and 1 or heightInitialBoost) * crouchMultHeight

    local lean = math.min(1, progress * Vars.LEAN_PROGRESS_MULT) * Vars.LEAN_BASE_VALUE * crouchMultLean
    if Helpers.IsFreeObservation() then
        lean = nil
    end

    local f = Vars.BASE_FOV - defaultFOV
    local fov = math.floor(defaultFOV + f * math.min(1, progress * Vars.FOV_PROGRESS_MULT) + ((math.min(1, progress * 1)) * Vars.FOV_BASE_VALUE))
    if Config.inner.dontChangeFov then
        fov = nil
    end

	if isCrouching then
		Helpers.SetCamera(nil, height, shift, nil, lean, nil, fov)
	else
		Helpers.SetStandCamera(nil, height, shift, nil, lean, nil, fov)
	end
end

local lastNativePitch = 0
local lastNativePitchUsed = false

local freeLookRestore = { progress = 0 }

---
--- Restore camera from freelook mode
--- @param fast boolean Skip smooth transition
---
function ImmersiveFirstPerson.RestoreFreeCam(fast)
    local fpp = Helpers.GetFPP()
    local curEuler = GetSingleton('Quaternion'):ToEulerAngles(fpp:GetLocalOrientation())
    local curPos = fpp:GetLocalPosition()

    if not Config.inner.smoothRestore or fast then
		freeLookRestore.progress = 0
		Helpers.SetRestoringCamera(false)
		Helpers.SetFreeObservation(false)
        ResetCamera(true)
        ImmersiveFirstPerson.HandleCamera(true)
        return
    end

    local targetY = Config.inner.cameraY
    local targetZ = Config.inner.cameraZ
    local positionReached = curEuler.pitch == 0 and curEuler.roll == 0 and curEuler.yaw == 0 and
                           curPos.x == 0 and
                           math.abs(curPos.y - targetY) < 0.001 and
                           math.abs(curPos.z - targetZ) < 0.001
    
    if positionReached then
        freeLookRestore.progress = 0
        Helpers.SetRestoringCamera(false)
        Helpers.SetFreeObservation(false)
        ImmersiveFirstPerson.HandleCamera(true)
        return
    end

    local itersWithSpeed = Vars.FREELOOK_SMOOTH_RESTORE_ITERS / Config.inner.smoothRestoreSpeed * Vars.FREELOOK_SMOOTH_RESTORE_ITERS

    local targetY = Config.inner.cameraY
    local targetZ = Config.inner.cameraZ
    
    -- local progressEased = Easings.EaseOutCubic(freeLookRestore.progress / itersWithSpeed)
    local progressEased = (freeLookRestore.progress / itersWithSpeed)
    local roll = math.floor((curEuler.roll - progressEased * curEuler.roll) * 10) / 10
    local pitch = math.floor((curEuler.pitch - progressEased * curEuler.pitch) * 10) / 10
    local yaw = math.floor((curEuler.yaw - progressEased * curEuler.yaw) * 10) / 10
    local x = math.floor((curPos.x - progressEased * curPos.x) * 1000) / 1000
    -- Interpolate Y and Z towards the target position hurrdurridurr mah head hurts
    local y = math.floor((curPos.y - progressEased * (curPos.y - targetY)) * 1000) / 1000
    local z = math.floor((curPos.z - progressEased * (curPos.z - targetZ)) * 1000) / 1000

    if freeLookRestore.progress >= itersWithSpeed then
        roll = 0
        pitch = 0
        yaw = 0
        x = 0
        y = targetY
        z = targetZ
        freeLookRestore.progress = 0
        Helpers.SetRestoringCamera(false)
        Helpers.SetFreeObservation(false)
        ImmersiveFirstPerson.HandleCamera(true)
    end

	local isCrouching = IsCrouching()
	Helpers.SetFreeCamera(x, y, z, roll, pitch, yaw)
    freeLookRestore.progress = freeLookRestore.progress + 1
end


---
--- Quadratic bezier curve interpolation
--- @param t number Progress (0-1)
--- @param a number Start value
--- @param b number Control point
--- @param c number End value
--- @return number interpolated value
---
local function curve(t, a, b, c)
    local y = (1-t)^2 * a + 2*(1-t)*t * b + t^2 * c
    return y
end

---
--- Handle freelook camera movement
--- @param relX number Relative X movement
--- @param relY number Relative Y movement
---
function ImmersiveFirstPerson.HandleFreeLook(relX, relY)
    if Helpers.IsRestoringCamera() then
        return
    end

    if not ShouldSetCamera(freeLookInCombat) then
		if Helpers.IsInVehicle() then
            return
        end
        ResetFreeLook()
        return
    end

    local fpp = Helpers.GetFPP()

    local curEuler = GetSingleton('Quaternion'):ToEulerAngles(fpp:GetLocalOrientation())
    local curPos = fpp:GetLocalPosition()

    local curX = curPos.x
    local curY = curPos.y
    local curZ = curPos.z

    local weapon = Helpers.HasWeapon()

    local curYaw = curEuler.yaw
    local curRoll = curEuler.roll
    
    local zoom = fpp:GetZoom()
    local xSensitivity = 0.07 / zoom * Config.inner.freeLookSensitivity/20
    local ySensitivity = 0.07 / zoom * Config.inner.freeLookSensitivity/20
    
    local sensXMult = 1
    local sensYMult = 1
    
    local yawingOut = curYaw > 0 and relX > 0 or curYaw < 0 and relX < 0
    
    local function easeOutCubic(x)
        return 1 - (1-x)^3
    end
    
    local function easeOutExp(x)
        -- return x == 1 and 1 or 1 - 2^(-10*x)
        return x == 0 and 0 or 2 ^ (5 * x - 5)
    end
    

    -- Debug: print(math.abs(curYaw / Vars.FREELOOK_MAX_YAW), easeOutExp(math.abs(curYaw / Vars.FREELOOK_MAX_YAW)))
    local yawProgress = (yawingOut and easeOutExp(math.abs(curYaw / Vars.FREELOOK_MAX_YAW)) or 0) + (1 - easeOutExp(math.abs(curYaw / Vars.FREELOOK_MAX_YAW)))
    
    local yaw = math.min(Vars.FREELOOK_MAX_YAW, math.max( -Vars.FREELOOK_MAX_YAW, (curYaw - (relX*xSensitivity * yawProgress))))
    
    local r = (math.abs(curYaw) + 100) / Vars.FREELOOK_MAX_YAW

    local maxPitch = weapon and Vars.FREELOOK_MAX_PITCH_COMBAT_UP or Vars.FREELOOK_MAX_PITCH

    local maxPitchOnYaw = (weapon and curEuler.pitch < 0) and math.min(Vars.FREELOOK_MAX_PITCH_COMBAT, Vars.FREELOOK_MAX_PITCH_COMBAT * r) or maxPitch

    local curPitch = (not weapon and not lastNativePitchUsed) and math.max(-maxPitchOnYaw, lastNativePitch) or curEuler.pitch
    -- local yaw = -Vars.FREELOOK_MAX_YAW * yawProgress

    local pitchingOut = curPitch > 0 and relY < 0 or curPitch < 0 and relY > 0

    -- yawCorrection need to higher up pitch when approaching high yaw (when looking over shoulder)
    local pitchSmoothing = ((pitchingOut and easeOutExp(-math.min(0, curPitch / maxPitchOnYaw)) or 0) + (1 - easeOutExp(-math.min(0, curPitch / maxPitchOnYaw))))

    -- local maxPitchOnYawOnYaw = weapon and (Vars.FREELOOK_MAX_PITCH_COMBAT_UP * (0.3 + math.abs((curYaw) / Vars.FREELOOK_MAX_YAW))) or maxPitchOnYaw

    local maxDownPitch = -50
    local pitch = math.min(maxPitchOnYaw, math.max(maxDownPitch, (curPitch) + (relY*ySensitivity * pitchSmoothing)))
    lastNativePitchUsed = true

    -- -1(left) +1(right)
    local delta = (yaw < 0) and 1 or -1
    local xShiftMultiplier = math.abs(yaw) / Vars.FREELOOK_MAX_YAW * 2

    local freelookMaxXShift = weapon and Vars.FREELOOK_MAX_X_SHIFT_COMBAT or Vars.FREELOOK_MAX_X_SHIFT
    local x = freelookMaxXShift * xShiftMultiplier * delta
    
    local pitchProgress = -math.min(0, curPitch / maxPitchOnYaw)
	-- local pitchProgress = 0
    -- local pitchProgress = -math.min(0, curPitch / maxPitch) * (1 - easeOutExp(-math.min(0, curPitch / maxPitch)))

    local rollSmoothMult = easeOutCubic(pitchProgress)
    local maxRoll = weapon and Vars.FREELOOK_MAX_COMBAT_ROLL or Vars.FREELOOK_MAX_ROLL
    local roll = maxRoll * (pitchProgress) * (xShiftMultiplier/10) * -delta * rollSmoothMult

    -- FOV correction offset to prevent clipping
    local fovCorrectionOffset = (68 / defaultFOV - 1) * Vars.FOV_CORRECTION_FREELOOK_MULT
    local xShiftMultiplierReduction = 1 - (xShiftMultiplier / 2)
    -- the closer we are to looking behind our shoulders the less prominent should be X and Y axises

    local endForwardMult = weapon and 40 or 20
    local startForwardMult = weapon and 0 or 3
    -- Calculate freelook Y offset and add to user's configured camera depth
    local yOffset = -curve(pitchProgress, 0, Vars.FREELOOK_MAX_Y * startForwardMult, -Vars.FREELOOK_MAX_Y / endForwardMult - 0.05) - 0.005 * xShiftMultiplier
    
    local heightCompensation = Config.inner.cameraZ * pitchProgress * 0.5
    
    local y = Config.inner.cameraY + yOffset + heightCompensation

    local startUpMult = weapon and 0.2 or 1
    local endUpMult = weapon and 0.001 or 1
 
	--local posMinZ = -Vars.FREELOOK_MIN_Z
	--local doMathStupid = posMinZ + math.abs(Config.inner.cameraHeight)
	--local heightZ = -doMathStupid
    local zOffset = curve(pitchProgress, 0, (Vars.FREELOOK_MIN_Z * startUpMult), -0.05 + fovCorrectionOffset * 30 * endUpMult)
    
    local z = Config.inner.cameraZ + zOffset
	--local z = curve(pitchProgress, 0, (-heightZ * startUpMult), heightZ/2 * endUpMult  + 0.02 + poopshit*30 * endUpMult) * xShiftMultiplierReduction

    local defaultFOVFixed = defaultFOV + 2
    local f = Vars.BASE_FOV - defaultFOVFixed

    local fov = math.floor(defaultFOVFixed + f * math.min(1, pitchProgress * 2) + ((math.min(1, pitchProgress)) * -8))
    if Config.inner.dontChangeFov then
        fov = nil
    end

    local isCrouching = IsCrouching()

	Helpers.SetFreeCamera(x, y, z, roll, pitch, yaw, fov)
end

---
--- Reset freelook to normal camera
--- @param fast boolean Skip smooth transition
---
function ResetFreeLook(fast)
    local isCrouching = IsCrouching()
    
    Helpers.SetRestoringCamera(true)
    Helpers.UnlockMovement()
    lastNativePitchUsed = false
    ImmersiveFirstPerson.RestoreFreeCam(fast)
end

---
--- Dedicated head visibility manager
--- Runs independently of camera adjustment system
--- Handles: weapon state, pitch angle, and head visibility
---
function ImmersiveFirstPerson.UpdateHeadVisibility()
    if not isLoaded or not Config.inner.showHead then
		if isHeadVisible and not HeadManager.IsToggleInProgress() then
			isHeadVisible = HeadManager.HideHead(function()
				isHeadVisible = HeadManager.Status()
				Helpers.RestoreCameraY()
			end)
		end
        return
    end
	
	if inMenu then
		return
	end
	
	frameCount = frameCount + 1
	if frameCount < 1 then return end
	frameCount = 0

    if not ShouldSetCamera() and (isHeadVisible and not HeadManager.IsToggleInProgress()) then
		isHeadVisible = HeadManager.HideHead(function()
			isHeadVisible = HeadManager.Status()
			Helpers.RestoreCameraY()
		end)
        return
    end

    if not isEnabled or Helpers.IsFreeObservation() then
        return
    end
            
	if Helpers.IsInVehicle() then
        return
    end

    local hasWeapon = Helpers.HasWeapon()
    local shouldHideDueToWeapon = hasWeapon

    local shouldHideDueToPitch = Helpers.ShouldHideHeadDueToPitch()

    if headHiddenByPitch and not shouldHideDueToPitch then
        local pitchValue = Helpers.GetLookPitch()
        if pitchValue then
            local downThreshold = Config.inner.headPitchDownThreshold or 40.0
            local upThreshold   = Config.inner.headPitchUpThreshold   or 20.0
            local hysteresis    = 5.0
            local clearedDown = pitchValue >= -(downThreshold - hysteresis)
            local clearedUp   = pitchValue <=  (upThreshold  - hysteresis)
            if clearedDown and clearedUp then
                log(1, function() return "UpdateHeadVisibility: pitch hysteresis cleared (pitch=" .. string.format("%.1f", pitchValue) .. ")" end)
                headHiddenByPitch = false
            else
                shouldHideDueToPitch = true
            end
        end
    end

    local shouldHeadBeVisible = not (shouldHideDueToWeapon or shouldHideDueToPitch)

    log(1, function() return "UpdateHeadVisibility: shouldBeVisible=" .. tostring(shouldHeadBeVisible) .. " isHeadVisible=" .. tostring(isHeadVisible) .. " toggleInProgress=" .. tostring(HeadManager.IsToggleInProgress()) .. " weapon=" .. tostring(hasWeapon) .. " pitchHide=" .. tostring(shouldHideDueToPitch) .. " hiddenByPitch=" .. tostring(headHiddenByPitch) end)
    if shouldHeadBeVisible and not isHeadVisible and not HeadManager.IsToggleInProgress() then
        log(1, "Head visibility: showing head")
        headHiddenByPitch = false
        Helpers.AdjustCameraYForHead()
        isHeadVisible = HeadManager.ShowHead(function()
            isHeadVisible = HeadManager.Status()
            log(1, function() return "ShowHead callback: isHeadVisible=" .. tostring(isHeadVisible) end)
			ImmersiveFirstPerson.HandleCamera(true)
        end)
    elseif not shouldHeadBeVisible and isHeadVisible and not HeadManager.IsToggleInProgress() then
        log(1, function() return "Head visibility: hiding head (" .. (shouldHideDueToWeapon and "weapon drawn" or "extreme pitch") .. ")" end)
        if not shouldHideDueToWeapon then
            headHiddenByPitch = true
        end
        isHeadVisible = HeadManager.HideHead(function()
            isHeadVisible = HeadManager.Status()
            log(1, function() return "HideHead callback: isHeadVisible=" .. tostring(isHeadVisible) end)
            Helpers.RestoreCameraY()
        end)
    end
end

---
--- Save native mouse sensitivity settings
---
function SaveNativeSens()
    if not Config.isReady then
        return
    end
    Config.inner.mouseNativeSensX = GameSettings.Get('/controls/fppcameramouse/FPP_MouseX')
    Config.inner.mouseNativeSensY = GameSettings.Get('/controls/fppcameramouse/FPP_MouseY')
    Config.SaveConfig()
end

---
--- Initialize the mod
--- Sets up event handlers, observers, and overrides
--- @return table API table with version and api
---
function ImmersiveFirstPerson.Init()
    registerForEvent("onShutdown", function()
        local fpp = Helpers.GetFPP()
        if fpp then
            fpp:ResetPitch()
            ImmersiveFirstPerson.RestoreFreeCam()
            Helpers.SetCamera(nil, nil, nil, nil, nil, nil, defaultFovOrNil())
        end
        ResetCamera()
        WeaponOffset.Reset()
        HeadManager.HideHead()
    end)
    registerForEvent("onInit", function()
        inited = true
        Config.InitConfig()
        LeanSystem.Init()
        defaultFOV = Helpers.GetFOV()
        isYInverted = Helpers.IsYInverted()
        isXInverted = Helpers.IsXInverted()

        if Config.inner.mouseNativeSensX == -1 or Config.inner.mouseNativeSensX == nil then
            SaveNativeSens()
        end

        if GameSettings.Get('/controls/fppcameramouse/FPP_MouseX') == 0 then
            Helpers.UnlockMovement()
        end
		
        isHeadVisible = HeadManager.ForceUpdate(function()
            isHeadVisible = HeadManager.Status()
        end)

        local wasLeaning = false
        local wasSliding = false

        Override('AimingStateEvents', 'OnEnter', function(self, stateContext, scriptInterface, wrappedMethod)
            wrappedMethod(stateContext, scriptInterface)
            
            if not Config.inner.enableWeaponSupport or not isEnabled then
                return
            end
            
            self.weapon = self:GetWeaponObject(scriptInterface)
            
            if not self.weapon then
                return
            end
            
            scriptInterface:SetAnimationParameterBool("has_scope", self.weapon:HasScope())
            self:UpdateWeaponOffsetPosition(scriptInterface)
        end)
        
        Override('AimingStateEvents', 'OnUpdate', function(self, timeDelta, stateContext, scriptInterface, wrappedMethod)
            wrappedMethod(timeDelta, stateContext, scriptInterface)

            if not Config.inner.enableWeaponSupport or not isEnabled then
                return
            end

            self:UpdateWeaponOffsetPosition(scriptInterface)
        end)
        
        Override('AimingStateEvents', 'OnExit', function(self, stateContext, scriptInterface, wrappedMethod)
            wrappedMethod(stateContext, scriptInterface)

            wasLeaning = false
            wasSliding = false
        end)
        
        Override('AimingStateEvents', 'UpdateWeaponOffsetPosition', function(self, scriptInterface, wrappedMethod)
            if not Config.inner.enableWeaponSupport or not isEnabled then
                wrappedMethod(scriptInterface)
                return
            end

            local stats = scriptInterface:GetStatsSystem()

            if not self.weapon then
                return
            end
            
            self.posAnimFeature.isEnabled = self.weapon:GetWeaponRecord():IsIKEnabled()
            self.posAnimFeature.hasScope = self.weapon:HasScope()
            
            if self.posAnimFeature.hasScope then
                self.posAnimFeature.position = self.weapon:GetScopeOffset()
            else
                self.posAnimFeature.position = self.weapon:GetIronSightOffset()
            end

            local player = Game.GetPlayer()
            if not player then
                wrappedMethod(scriptInterface)
                return
            end
            
            local isSliding = false
            local blackboardDefs = Game.GetAllBlackboardDefs()
            if blackboardDefs then
                local blackboardSystem = Game.GetBlackboardSystem()
                if blackboardSystem then
                    local blackboardPSM = blackboardSystem:GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)
                    if blackboardPSM then
                        local locomotionState = blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.LocomotionDetailed)
                        isSliding = (locomotionState == 9)
                    end
                end
            end
            
            if isSliding and not wasSliding then
                wasSliding = true
            end
            
            if not isSliding and not wasSliding then
                local addedPosition = self.weapon:GetWeaponRecord():IkOffset()
                
                local x = self.posAnimFeature.position.x + addedPosition.x
                local y = self.posAnimFeature.position.y + addedPosition.y
                local z = self.posAnimFeature.position.z + addedPosition.z
                
                self.posAnimFeature.position = Vector4.new(x, y, z, 1.00)
            end
            
            self.posAnimFeature.offset = stats:GetStatValue(self.weapon:GetEntityID(), gamedataStatType.AimOffset)
            self.posAnimFeature.scopeOffset = stats:GetStatValue(self.weapon:GetEntityID(), gamedataStatType.ScopeOffset)
            scriptInterface:SetAnimationParameterFeature("ProceduralIronsightData", self.posAnimFeature)
        end)

        Observe("SettingsMainGameController", "OnUninitialize", function()
            SaveNativeSens()
            isYInverted = Helpers.IsYInverted()
            isXInverted = Helpers.IsXInverted()
            defaultFOV = Helpers.GetFOV()
        end)

        Observe("DeathDecisionsWithResurrection", "ToResurrect", function()
			isLoaded = true
			defaultFOV = Helpers.GetFOV()
        end)

		Observe("hudCameraController", "OnUninitialize", function ()
			if cameraWasEnabled and not isEnabled then
				isEnabled = true
				cameraWasEnabled = false
				ImmersiveFirstPerson.HandleCamera()
			end
		end)

		Observe("hudCameraController", "OnInitialize", function ()
			if isEnabled then
				ResetCamera(force)
				isEnabled = false
				cameraWasEnabled = true
			end
		end)

        GameSession.OnStart(function()
			isLoaded = true
			gameStart = true
			defaultFOV = Helpers.GetFOV()
			isHeadVisible = HeadManager.ForceUpdate(function()
				isHeadVisible = HeadManager.Status()
				log(1, function() return "OnStart: head state synced, isHeadVisible=" .. tostring(isHeadVisible) end)
			end)
        end)

        GameSession.OnResume(function()
			isLoaded = true
			gameResume = true
			isHeadVisible = HeadManager.ForceUpdate(function()
				isHeadVisible = HeadManager.Status()
				log(1, function() return "OnResume: head state synced, isHeadVisible=" .. tostring(isHeadVisible) end)
			end)
        end)

        GameSession.OnEnd(function()
			isLoaded = false
			ResetCamera(true)
        end)
        
		GameSession.OnDeath(function()
			isLoaded = false
			if Helpers.IsFreeObservation() then
				ResetFreeLook(true)
			end		  
			ResetCamera()
        end)

        GameSession.OnPause(function()
			isLoaded = false
			ResetCamera()
        end)
		
		GameUI.OnVehicleEnter(function(state)
			isEnteringVehicle = true
		end)
		
		GameUI.OnVehicleExit(function(state)
			isExitingVehicle = true
		end)

		GameUI.OnMenuOpen(function()
			inMenu = true
		end)

		GameUI.OnMenuClose(function()
			inMenu = false
		end)

        local cetVer = tonumber((GetVersion():gsub('^v(%d+)%.(%d+)%.(%d+)(.*)', function(major, minor, patch, wip)
            return ('%d.%02d%02d%d'):format(major, minor, patch, (wip == '' and 0 or 1))
        end))) or 1.12

        Observe('PlayerPuppet', 'OnGameAttached', function(self, b)
          self:RegisterInputListener(self, "CameraMouseY")
          self:RegisterInputListener(self, "CameraMouseX")
          self:RegisterInputListener(self, "CameraMouseY")
          self:RegisterInputListener(self, "right_stick_y")
          self:RegisterInputListener(self, "CameraY")
          self:RegisterInputListener(self, "UI_MoveY_Axis")
          self:RegisterInputListener(self, "MeleeBlock")
          self:RegisterInputListener(self, "RangedADS")
          self:RegisterInputListener(self, "CameraAim")
          self:RegisterInputListener(self, "MeleeAttack")
          self:RegisterInputListener(self, "RangedAttack")
          self:RegisterInputListener(self, "mouse_left")
          self:RegisterInputListener(self, "click")
          self:RegisterInputListener(self, "SwitchItem")
          self:RegisterInputListener(self, "WeaponWheel")
        end)

        Observe('PlayerPuppet', 'OnAction', function(a, b)
            if not isLoaded then
              return
            end

            local action = a
            if cetVer >= 1.14 then
                action = b
            end

            local ListenerAction = GetSingleton('gameinputScriptListenerAction')
            local actionName = Game.NameToString(ListenerAction:GetName(action))
            local actionValue = ListenerAction:GetValue(action)
            if Helpers.IsFreeObservation() then
                if actionName == "mouse_left" then
                    ResetFreeLook(true)
                else
                    if actionName == "CameraMouseY" then
                        ImmersiveFirstPerson.HandleFreeLook(0, actionValue * (isYInverted and -1 or 1))
                    end
                    if actionName == "CameraMouseX" then
                        ImmersiveFirstPerson.HandleFreeLook(actionValue * (isXInverted and -1 or 1), 0)
                    end
                end
                return
            end

            if actionName == "CameraMouseY"
               or actionName == "right_stick_y"
               or actionName == "CameraY"
               or actionName == "UI_MoveY_Axis"
               or actionName == "MeleeBlock"
               or actionName == "RangedADS"
               or actionName == "CameraAim"
               or actionName == "MeleeAttack"
               or actionName == "RangedAttack"
               or actionName == "mouse_left"
               or actionName == "click"
               or actionName == "SwitchItem"
               or actionName == "WeaponWheel"
               then
                 ImmersiveFirstPerson.HandleCamera()
            end
        end)

		Cron.Every(0.65, function()
			if isLoaded then
				ImmersiveFirstPerson.HandleCamera()
			end
		end)

		Cron.After(3, function()
			enableThirdPartyMods()
		end)

    end)

    registerForEvent("onUpdate", function(delta)
        Cron.Update(delta)
        LeanSystem.Update(delta)
        Helpers.UpdateCameraYInterpolation(delta)

        if not isLoaded or inMenu then
          return
        end
		
        local player = Game.GetPlayer()

        if player then
            local isInVehicle = Helpers.IsInVehicle()
            local currentVehicleState = isEnteringVehicle or isInVehicle

            if not currentVehicleState and not (previousVehicleState or false) and (gameStart or gameResume) then
				if gameStart then
					Cron.After(3, function()
						disableThirdPartyMods()
					end)
					gameStart = false
				end
				gameResume = false
				if not defaultFOV then
					defaultFOV = Helpers.GetFOV()
				end
				Helpers.ResetCamera(defaultFOV)
			end

            if not (previousVehicleState or false) and currentVehicleState then
                WeaponOffset.Reset()
                Helpers.ResetCameraVehicle(defaultFovOrNil())
				if Config.inner.enableThird and not enabledThird then
					enableThirdPartyMods()
				end
                isEnabled = false
				if Config.inner.showHead and isHeadVisible and not HeadManager.IsToggleInProgress() then
					isHeadVisible = HeadManager.HideHead(function()
						isHeadVisible = HeadManager.Status()
						Helpers.RestoreCameraY()
					end)
				end
            end
			
			if (previousVehicleState or false) and not currentVehicleState then
				if enabledThird then
					disableThirdPartyMods()
				end
				isEnabled = true
				isLoaded = true
				if not defaultFOV then
					defaultFOV = Helpers.GetFOV()
				end
				Helpers.ResetCamera(defaultFovOrNil())
				if Config.inner.showHead and not Helpers.HasWeapon() and not isHeadVisible and not HeadManager.IsToggleInProgress() then
					Helpers.AdjustCameraYForHead()
					isHeadVisible = HeadManager.ShowHead(function()
						isHeadVisible = HeadManager.Status()
						ImmersiveFirstPerson.HandleCamera(true)
					end)
				end
			end

            previousVehicleState = isInVehicle or isEnteringVehicle
			isEnteringVehicle = false
        end

        if Config.inner.enableWeaponSupport and not Helpers.IsInVehicle() then
            WeaponOffset.Update(Config.inner.cameraZ)
        end

        if Helpers.IsRestoringCamera() then
            ImmersiveFirstPerson.RestoreFreeCam()
        end

        if not inited then
            return
        end

        if Helpers.IsFreeObservation() and not ShouldSetCamera(freeLookInCombat) and not Helpers.IsRestoringCamera() then
			if Helpers.IsInVehicle() then
                return
            end

            ResetFreeLook()
            return
        end

        ImmersiveFirstPerson.UpdateHeadVisibility()

    end)

    ---
    --- Show tooltip if item is hovered
    --- @param text string Tooltip text
    ---
    function TooltipIfHovered(text)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.SetTooltip(text)
            ImGui.EndTooltip()
        end
    end

    registerForEvent("onDraw", function()
        if not isOverlayOpen then
            return
        end
		
		local changed = false

        ImGui.PushStyleVar(ImGuiStyleVar.WindowMinSize, 300, 300)
        ImGui.Begin("ImmersiveFirstPerson", ImGuiWindowFlags.AlwaysAutoResize)

        isEnabled, IsEnabledToggled = ImGui.Checkbox("Enabled", isEnabled)
        if IsEnabledToggled then
            if isEnabled and ShouldSetCamera(freeLookInCombat) then
                ImmersiveFirstPerson.HandleCamera(true)
			elseif not Helpers.IsInVehicle() then
                ResetCamera()
            end
        end

		if isEnabled then
			ImGui.Separator()
			Config.inner.enableWeaponSupport, changed = ImGui.Checkbox("Enable Weapon Support", Config.inner.enableWeaponSupport)
			if changed then
				Config.SaveConfig()
				if not Config.inner.enableWeaponSupport then
					WeaponOffset.Reset()
				end
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Allows camera adjustment while holding weapons.\nAdjusts weapon position during ADS to match camera height.")
			end
		
			ImGui.Separator()
			ImGui.Text("Camera Settings")
			ImGui.Spacing()

			Config.inner.dontChangeFov, changed = ImGui.Checkbox("Don't change FOV (may cause clipping)", Config.inner.dontChangeFov)
			if changed then
				Config.SaveConfig()
				if isEnabled and isLoaded then
					if Config.inner.dontChangeFov then
					Helpers.ResetFOV(defaultFOV)
					end
				end
			end

			Config.inner.cameraZ, changed = ImGui.SliderFloat("Camera Height", math.abs(Config.inner.cameraZ), -0.15, 0.15)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Vertical camera position.\nPositive = higher (eye level)\nNegative = lower\nRecommended: 0.085 for eye level")
			end

			Config.inner.cameraY, changed = ImGui.SliderFloat("Camera Depth", Config.inner.cameraY, -0.10, 0.10)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Forward/backward camera position.\nPositive = forward\nNegative = backward\nRecommended: -0.085")
			end
		
			Config.inner.smoothRestore, changed = ImGui.Checkbox("Smooth transition for FreeLook", Config.inner.smoothRestore)
			if changed then
				Config.SaveConfig()
				if isEnabled and ShouldSetCamera(freeLookInCombat) then
					ImmersiveFirstPerson.HandleCamera(true)
				elseif not Helpers.IsInVehicle() then
					ResetCamera()
				end
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("If your character stuck during transition,\nload the latest save file and\nthen either turn this option off or increase the transition speed.\nThis is caused by internal game bug and for now is unfixable.")
			end

			if Config.inner.smoothRestore then
				Config.inner.smoothRestoreSpeed, changed = ImGui.SliderInt("Transition speed", math.floor(Config.inner.smoothRestoreSpeed), 5, 50)
				if changed then
					Config.SaveConfig()
				end
			end

			Config.inner.freeLookSensitivity, changed = ImGui.SliderInt("FreeLook sensitivity", math.floor(Config.inner.freeLookSensitivity), 1, 100)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Individual sensitivity setting for the Freelook camera")
			end

			if Config.inner.enableWeaponSupport then
				ImGui.Separator()
				ImGui.Text("Weapon Settings")
				ImGui.Spacing()
            
				Config.inner.adsFovOffset, changed = ImGui.SliderInt("ADS FOV Offset (Iron Sights)", Config.inner.adsFovOffset, -60, 60)
				if changed then
					Config.SaveConfig()
					if Helpers.HasWeapon() then
						WeaponOffset.RemoveWeaponOffset()
						local weapon = WeaponOffset.GetCurrentWeapon()
						if weapon then
							WeaponOffset.ApplyWeaponOffset(weapon, Config.inner.cameraZ)
						end
					end
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Adjust FOV when aiming with iron sights.\n0 = matches your regular FOV\nNegative = zooms in\nPositive = zooms out")
				end
            
				Config.inner.scopeFovOffset, changed = ImGui.SliderInt("Scope FOV Offset", Config.inner.scopeFovOffset, -60, 60)
				if changed then
					Config.SaveConfig()
					if Helpers.HasWeapon() then
						WeaponOffset.RemoveWeaponOffset()
						local weapon = WeaponOffset.GetCurrentWeapon()
						if weapon then
							WeaponOffset.ApplyWeaponOffset(weapon, Config.inner.cameraZ)
						end
					end
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Adjust FOV when aiming with scopes.\n0 = matches your regular FOV\nNegative = zooms in more\nPositive = zooms out")
				end

				ImGui.Separator()
				ImGui.Text("Built-in Scope Blacklist")
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Add weapons with built-in scopes that should not have their zoom disabled.\nThis prevents the mod from incorrectly handling guns with integrated scopes.")
				end
            
				ImGui.Spacing()
				local currentWeapon = WeaponOffset.GetCurrentWeapon()
				local currentWeaponIDString = nil
				if currentWeapon then
					currentWeaponIDString = WeaponOffset.GetWeaponIDString(currentWeapon)
				end
            
				if currentWeapon and currentWeaponIDString then
					if ImGui.Button("Add Current Weapon to Blacklist") then
						if WeaponOffset.AddToBlacklist(currentWeapon) then
							log(1, function() return "Added weapon to blacklist: " .. currentWeaponIDString end)
						else
							log(1, function() return "Weapon already in blacklist or add failed" end)
						end
					end
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Add the weapon you're currently holding to the blacklist.\n\nWeapon ID: " .. (currentWeaponIDString or "None"))
					end
				else
					ImGui.TextColored(0.7, 0.7, 0.7, 1, "(Equip a weapon to add it)")
				end
            
				ImGui.Spacing()
            
				if #(Config.inner.weaponBlacklist or {}) > 0 then
					ImGui.Text("Blacklisted Weapons (" .. #Config.inner.weaponBlacklist .. "):")
					ImGui.Separator()
                
					local toRemove = nil
					for i, weaponID in ipairs(Config.inner.weaponBlacklist) do
						if ImGui.SmallButton("Remove##" .. i) then
							toRemove = weaponID
						end
						ImGui.SameLine()
						ImGui.Text("[" .. i .. "] " .. weaponID)
					end
					if toRemove then
						if WeaponOffset.RemoveFromBlacklist(toRemove) then
							log(1, function() return "Removed weapon from blacklist: " .. toRemove end)
						end
					end
				else
					ImGui.TextColored(0.7, 0.7, 0.7, 1, "No blacklisted weapons")
				end
			
				ImGui.Separator()
				ImGui.Text("Lean Compensation (ADS with Weapon)")
            
				Config.inner.leanCameraOffset, changed = ImGui.SliderFloat("Lean Offset", Config.inner.leanCameraOffset, -0.05, 0.05)
				if changed then
					Config.SaveConfig()
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Sideways camera movement when leaning with weapon.\nAdjust until camera aligns with weapon sights.\nRecommended: 0.031")
				end
            
				Config.inner.leanCameraRoll, changed = ImGui.SliderFloat("Lean Roll", Config.inner.leanCameraRoll, 0.0, 30.0)
				if changed then
					Config.SaveConfig()
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Camera tilt angle when leaning with weapon.\nAdjust until camera rotation matches weapon angle.\nRecommended: 22.334")
				end
            
				Config.inner.leanCameraHeight, changed = ImGui.SliderFloat("Lean Height", Config.inner.leanCameraHeight, -0.010, 0.010)
				if changed then
					Config.SaveConfig()
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Vertical adjustment when leaning with weapon.\nAdjust until front and rear sights are level.\nRecommended: -0.006")
				end
			end

			ImGui.Separator()
			ImGui.Text("Free Lean Settings")

			Config.inner.leanToggleMode, changed = ImGui.Checkbox("Toggle Mode (vs Hold)", Config.inner.leanToggleMode)
			if changed then
				Config.SaveConfig()
				LeanSystem.ResetLean()
			end
			if ImGui.IsItemHovered() then
				if Config.inner.leanToggleMode then
					ImGui.SetTooltip("Press to lean, press again to reset")
				else
					ImGui.SetTooltip("Hold to lean, release to reset")
				end
			end
			ImGui.TextColored(0.7, 0.7, 0.7, 1, "Keyboard: bind in CET Bindings")

			ImGui.Separator()
			ImGui.Text("Vanilla Lean Settings")
        
			Config.inner.disableVanillaLean, changed = ImGui.Checkbox("Disable Vanilla Lean System", Config.inner.disableVanillaLean)
			if changed then
				Config.SaveConfig()
				LeanSystem.ResetLean()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Completely disables the game's automatic lean when near cover.")
			end
        
			if not Config.inner.disableVanillaLean then
                Config.inner.enableVanillaLeanCameraFixes, changed = ImGui.Checkbox("Apply Camera Fixes to Vanilla Lean", Config.inner.enableVanillaLeanCameraFixes)
                if changed then
                    Config.SaveConfig()
                end
                if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Applies the same camera offsets (shift, roll, height) to the vanilla lean system.\nPlease be warned: this does not work very well!")
                end
                
                ImGui.Spacing()
                Config.inner.vanillaLeanRequiresWeapon, changed = ImGui.Checkbox("Vanilla Lean Only With Weapon", Config.inner.vanillaLeanRequiresWeapon)
                if changed then
                    Config.SaveConfig()
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Disable vanilla lean when no weapon is equipped.\nUnholstering a gun will allow vanilla lean system to work as normal.")
                end
			end

			ImGui.Separator()
			ImGui.Text("Extra options")
        
			Config.inner.carryBody, changed = ImGui.Checkbox("Disable while carrying a body", Config.inner.carryBody)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("If this is enabled then the camera returns to standard settings when you carry a body")
			end

			Config.inner.swimming, changed = ImGui.Checkbox("Disable while swimming", Config.inner.swimming)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("If this is enabled then the camera returns to standard settings when you're swimming")
			end

			Config.inner.takingDown, changed = ImGui.Checkbox("Disable while performing takedown", Config.inner.takingDown)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("If this is enabled then the camera returns to standard settings while you're performing a takedown")
			end

			Config.inner.knockedDown, changed = ImGui.Checkbox("Disable while being knocked down", Config.inner.knockedDown)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("If this is enabled then the camera returns to standard settings while you're in a knocked down state")
			end

			ImGui.Separator()
			ImGui.Text("Scene Level")

			Config.inner.sceneLevel, changed = ImGui.SliderInt("Scene Level", Config.inner.sceneLevel, 2, 5)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("This adjust at which scene level (less than) the mod is active.\nRecommended: 3 (1 & 2 = active. 3, 4 & 5 = inactive).\nSetting this lower may help with handling animations or semi-cutscenes such as the first braindance event.\nCannot set lower than 2.\nScene levels: 1) FullGameplay. 2) StagedGameplay. 3) LimitedGameplay. 4) FPPCinematic. 5) Cinematic")
			end

			if showExperimental then
				ImGui.Separator()
				ImGui.Text("Experimental")

				Config.inner.showHead, changed = ImGui.Checkbox("Show Head (Experimental)", Config.inner.showHead)
				if changed then
					Config.SaveConfig()
					if Config.inner.showHead then
						Helpers.AdjustCameraYForHead()
						isHeadVisible = HeadManager.ShowHead(function()
							isHeadVisible = HeadManager.Status()
							if isLoaded then
								ImmersiveFirstPerson.HandleCamera(true)
							end
						end)
					else
						isHeadVisible = HeadManager.HideHead(function()
							isHeadVisible = HeadManager.Status()
							Helpers.RestoreCameraY()
						end)
					end
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Forces the TPP head to be visible in FPP.\nMay cause clipping with camera if not adjusted properly.")
				end

				if Config.inner.showHead then
					ImGui.Spacing()
					ImGui.Text("Head Clipping Prevention")
				
					Config.inner.headMinCameraY, changed = ImGui.SliderFloat("Min Camera Depth (Head)", Config.inner.headMinCameraY, 0.000, 0.200)
					if changed then
						Config.SaveConfig()
					end
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Minimum camera depth (Y) when head is shown.\nIncreases to prevent clipping through head.\nRecommended: 0.050")
					end

					ImGui.Spacing()
					ImGui.Text("Pitch-Based Head Hiding")

					Config.inner.headPitchDownThreshold, changed = ImGui.SliderInt("Look Down Threshold (°)", Config.inner.headPitchDownThreshold, 10, 90)
					if changed then
						Config.SaveConfig()
					end
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Hide head when looking down past this angle.\nRecommended: 35-40°\n90° is practically turning this feature off.")
					end

					Config.inner.headPitchUpThreshold, changed = ImGui.SliderInt("Look Up Threshold (°)", Config.inner.headPitchUpThreshold, 10, 40)
					if changed then
						Config.SaveConfig()
					end
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Hide head when looking up past this angle.\nRecommended: 20°")
					end
				end
			end

			ImGui.Separator()
			ImGui.Text("Third Party Mods")
		
			Config.inner.blockingMods, changed = ImGui.Checkbox("Disable if third party mod blocks", Config.inner.blockingMods)
			if changed then
				Config.SaveConfig()
			end
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("If this is enabled then the camera returns to standard settings while other mods are in a blocking state")
			end
		
			Config.inner.disableThird, changed = ImGui.Checkbox("Disable Third Party Mods", Config.inner.disableThird)
			if changed then
				if (Config.inner.enableThird or false) and Config.inner.disableThird then
					Config.inner.enableThird = false
					disableThirdPartyMods()
				end
				Config.SaveConfig()
			end

			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Will try to disable Third Party Mods that might interfere")
			end

			if not Config.inner.disableThird then
				Config.inner.enableThird, changed = ImGui.Checkbox("Enable Third Party Mods only for Vehicles", Config.inner.enableThird)
				if changed then
					Config.SaveConfig()
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("This option enables using other mods while using vehicles.")
				end
			end
		
			if Config.inner.enableThird then
				if not Config.inner.useShift then
					Config.inner.useBVFP, changed = ImGui.Checkbox("Use Better Vehicle First Person", Config.inner.useBVFP)
					if changed then
						if Config.inner.useShift then
							Config.inner.useShift = false
							disableThirdPartyMods()
						end
						Config.SaveConfig()
					end
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Will disable self and enable Better Vehicle First Person upon entering a vehicle")
					end
				end
			end
		
			if Config.inner.enableThird then
				if not Config.inner.useBVFP then
					Config.inner.useShift, changed = ImGui.Checkbox("Use Shift", Config.inner.useShift)
					if changed then
						if Config.inner.useBVFP then
							Config.inner.useBVFP = false
							disableThirdPartyMods()
						end
						Config.SaveConfig()
					end
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Will disable self and enable Shift upon entering a vehicle")
					end
				end
			end

			ImGui.End()
			ImGui.PopStyleVar(1)
	
		end
    end)

    registerHotkey("ifp_toggle_enabled", "Toggle Enabled", function()
        if HeadManager.IsToggleInProgress() then
            return
        end
        isEnabled = not isEnabled
        if isEnabled and ShouldSetCamera() then
            ImmersiveFirstPerson.HandleCamera(true)
            isHeadVisible = HeadManager.ForceUpdate(function()
                isHeadVisible = HeadManager.Status()
                ImmersiveFirstPerson.HandleCamera(true)
            end)
        elseif not Helpers.IsInVehicle() then
            ResetCamera()
            HeadManager.HideHead(function()
                Helpers.RestoreCameraY()
            end)
        end
    end)
    registerInput("ifp_freelook", "FreeLook", function(keydown)
        if isDisabledByApi then
          return
        end

        if not isLoaded then
            return
        end

        if not ShouldSetCamera(freeLookInCombat) then
            return
        end
        local fpp = Helpers.GetFPP()
        if fpp == nil then
            return
        end

        if keydown then
            if Helpers.IsRestoringCamera() then
                freeLookRestore.progress = 0
                Helpers.SetRestoringCamera(false)
                Helpers.SetFreeObservation(false)
            end

            if Config.inner.showHead and isHeadVisible and not HeadManager.IsToggleInProgress() then
				log(1, function() return "FreeLook activated, hiding head" end)
                isHeadVisible = HeadManager.HideHead(function()
                    isHeadVisible = HeadManager.Status()
                    Helpers.RestoreCameraY()
                end)
            end

            lastNativePitch = Helpers.GetLookPitch()
            if not Helpers.HasWeapon() then
                fpp:ResetPitch()
            end
            Helpers.SetFreeObservation(true)
            Helpers.LockMovement()
            ImmersiveFirstPerson.HandleFreeLook(0, 0)
        else
            if Config.inner.showHead and not isHeadVisible and not Helpers.HasWeapon() and not Helpers.ShouldHideHeadDueToPitch() and not HeadManager.IsToggleInProgress() then
				log(1, function() return "FreeLook released, showing head" end)
                Helpers.AdjustCameraYForHead()
                isHeadVisible = HeadManager.ShowHead(function()
                    isHeadVisible = HeadManager.Status()
                    ImmersiveFirstPerson.HandleCamera(true)
                end)
            end

            ResetFreeLook()
        end
    end)

    registerInput("Lean_Left", "Lean Left", function(isPressed)
		if inMenu then return end
		LeanSystem.DoLean("left", isPressed)
    end)
    
    registerInput("Lean_Right", "Lean Right", function(isPressed)
		if inMenu then return end
        LeanSystem.DoLean("right", isPressed)
    end)

    registerForEvent("onOverlayOpen", function()
        isOverlayOpen = true
    end)
    registerForEvent("onOverlayClose", function()
        isOverlayOpen = false
    end)

    return {
      version = ImmersiveFirstPerson.version,
      api = API,
    }
end

return ImmersiveFirstPerson.Init()