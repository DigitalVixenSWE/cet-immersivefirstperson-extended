local Helpers = require("Modules/Helpers")
local Vars = require("Modules/Vars")

local Config = {
    inner = {
        freeLookSensitivity = Vars.FREELOOK_DEFAULT_SENSITIVITY,
        smoothRestore = false,
        freeLookInCombat = false,
        mouseNativeSensX = -1,
        mouseNativeSensY = -1,
        smoothRestoreSpeed = 15,
        dontChangeFov = false,
		cameraZ = 0,
        cameraY = 0,
        leanToggleMode = false,
        enableWeaponSupport = false,
        adsFovOffset = 0,
        scopeFovOffset = 0,
        leanCameraOffset = 0.0,
        leanCameraRoll = 0.0,
        leanCameraHeight = 0.0,
        disableVanillaLean = false,
        enableVanillaLeanCameraFixes = true,
        hybridVanillaLean = false,
		sceneLevel = 3,
        showHead = false,
		carryBody = true,
		swimming = true,
		blockingMods = false,
		takingDown = true,
		knockedDown = true,
		disabledThird = false,
		enableThird = false,
		useShift = false,
		useBVFP = true,
        headMinCameraY = 0.050,
        headPitchDownThreshold = 39.0,
        headPitchUpThreshold = 20.0,
        vanillaLeanRequiresWeapon = false,
        weaponBlacklist = {},
    },
    isReady = false,
}

function Config.InitConfig()
    local config = ReadConfig()
    if config == nil then
        WriteConfig()
    else
        Config.inner = config
    end

    Migrate()
    Config.isReady = true
end

function Config.SaveConfig()
    WriteConfig()
end

function Migrate()
    if Config.inner.dontChangeFov == nil then
      Config.inner.dontChangeFov = false
    end
    if Config.inner.leanToggleMode == nil then
        Config.inner.leanToggleMode = false
    end
    if Config.inner.enableWeaponSupport == nil then
        Config.inner.enableWeaponSupport = false
    end
    if Config.inner.adsFovOffset == nil then
        Config.inner.adsFovOffset = 0
    end
    if Config.inner.scopeFovOffset == nil then
        Config.inner.scopeFovOffset = 0
    end
    if Config.inner.leanCameraOffset == nil then
        Config.inner.leanCameraOffset = 0.0
    end
    if Config.inner.leanCameraRoll == nil then
        Config.inner.leanCameraRoll = 0.0
    end
    if Config.inner.leanCameraHeight == nil then
        Config.inner.leanCameraHeight = 0.0
    end
    if Config.inner.disableVanillaLean == nil then
        Config.inner.disableVanillaLean = false
    end
    if Config.inner.enableVanillaLeanCameraFixes == nil then
        Config.inner.enableVanillaLeanCameraFixes = true
    end
    if Config.inner.hybridVanillaLean == nil then
        Config.inner.hybridVanillaLean = false
    end
    if Config.inner.sceneLevel == nil then
        Config.inner.sceneLevel = 3
    end
    if Config.inner.showHead == nil then
        Config.inner.showHead = false
    end
    if Config.inner.carryBody == nil then
        Config.inner.carryBody = false
    end
    if Config.inner.swimming == nil then
        Config.inner.swimming = false
    end
    if Config.inner.blockingMods == nil then
        Config.inner.blockingMods = false
    end
    if Config.inner.takingDown == nil then
        Config.inner.takingDown = false
    end
    if Config.inner.knockedDown == nil then
        Config.inner.knockedDown = false
    end
    if Config.inner.disabledThird == nil then
        Config.inner.disabledThird = false
    end
    if Config.inner.enableThird == nil then
        Config.inner.enableThird = false
    end
    if Config.inner.useShift == nil then
        Config.inner.useShift = false
    end	
    if Config.inner.useBVFP == nil then
        Config.inner.useBVFP = true
    end
    if Config.inner.headMinCameraY == nil then
        Config.inner.headMinCameraY = 0.050
    end
    if Config.inner.headPitchDownThreshold == nil then
        Config.inner.headPitchDownThreshold = 39
    end
    if Config.inner.headPitchUpThreshold == nil then
        Config.inner.headPitchUpThreshold = 20
    end
    if Config.inner.vanillaLeanRequiresWeapon == nil then
        Config.inner.vanillaLeanRequiresWeapon = false
    end
    if Config.inner.weaponBlacklist == nil then
        Config.inner.weaponBlacklist = {}
    end
    WriteConfig()
end

function WriteConfig()
    local sessionPath = Vars.CONFIG_FILE_NAME
    local sessionFile = io.open(sessionPath, 'w')

    if not sessionFile then
        Helpers.RaiseError(('Cannot write config file %q.'):format(sessionPath))
    end

    sessionFile:write(json.encode(Config.inner))
    sessionFile:close()
end

local function readFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

function ReadConfig()
    local configPath = Vars.CONFIG_FILE_NAME

    local configStr = readFile(configPath)

    local ok, res = pcall(function() return json.decode(configStr) end)
    if not ok then
        Helpers.PrintMsg(('Cannot open config file %q. %q'):format(configPath, res))
        return
    end

    return res
end

return Config