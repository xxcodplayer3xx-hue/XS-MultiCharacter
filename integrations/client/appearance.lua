XSAppearance = {}

local function running(resource)
    return GetResourceState(resource):find('start') ~= nil
end

local function qsSettings()
    return Config.Client.Integrations.qsAppearance or {}
end

local function callExport(resource, method, ...)
    if type(method) ~= "string" or method == "" or not running(resource) then return false end
    local ok = pcall(function(...)
        return exports[resource][method](...)
    end, ...)
    return ok
end

local function exportMethods(configured, defaults)
    if type(configured) == "string" and configured ~= "" then return { configured } end
    if type(configured) == "table" and #configured > 0 then return configured end
    return defaults
end

function XSAppearance.mode()
    local mode = Config.Client.Integrations.appearance
    if mode ~= 'auto' then return mode end
    if running('qs-appearance') then return 'qs-appearance' end
    if running('illenium-appearance') then return 'illenium-appearance' end
    if running('fivem-appearance') then return 'fivem-appearance' end
    if running('qb-clothing') then return 'qb-clothing' end
    return 'none'
end

--- Apply a saved appearance using the configured appearance resource.
--- @param ped number The ped receiving the appearance
--- @param saved table The saved character appearance record
--- @return boolean success Whether the appearance adapter accepted the data
local function applyQsAppearance(ped, saved)
    local settings = qsSettings()
    local resource = settings.resource or "qs-appearance"
    local methods = exportMethods(settings.setPedExports, { "setPedAppearance", "setAppearance" })
    for _, method in ipairs(methods) do
        if callExport(resource, method, ped, saved) then return true end
    end
    return false
end

--- Open the configured qs-appearance editor through an export or event.
--- @return boolean opened Whether an editor handoff was made
local function openQsAppearance()
    local settings = qsSettings()
    local resource = settings.resource or "qs-appearance"
    local methods = exportMethods(settings.firstCharacterExports, { "openAppearance", "openMenu" })
    for _, method in ipairs(methods) do
        if callExport(resource, method) then return true end
    end
    local event = settings.firstCharacterEvent
    if type(event) == "string" and event ~= "" then
        TriggerEvent(event)
        return true
    end
    return false
end

function XSAppearance.qsAppearanceFinishedEvent()
    local event = qsSettings().finishedEvent
    return type(event) == "string" and event ~= "" and event or nil
end

function XSAppearance.model(saved, gender)
    local model = saved and saved.model
    if type(model) == 'string' and tonumber(model) then model = tonumber(model) end
    if type(model) == 'string' then model = joaat(model) end
    model = XSPed.normalize(model)
    if not model or not IsModelInCdimage(model) then
        return tonumber(gender) == 1 and Config.Client.Scene.femaleModel or Config.Client.Scene.maleModel
    end
    return model
end

function XSAppearance.apply(ped, saved)
    if not saved then return false end
    if saved.ped and XSPed.matches(ped, saved.model) then return XSPed.applyVariation(ped, saved.ped) end
    if saved.variation and XSPed.matches(ped, saved.model) then return XSPed.applyVariation(ped, saved.variation) end
    if not saved.appearance then return false end
    local mode = XSAppearance.mode()
    if mode == 'illenium-appearance' then
        return pcall(function() exports['illenium-appearance']:setPedAppearance(ped, saved.appearance) end)
    elseif mode == 'fivem-appearance' then
        return pcall(function() exports['fivem-appearance']:setPedAppearance(ped, saved.appearance) end)
    elseif mode == 'qb-clothing' then
        TriggerEvent('qb-clothing:client:loadPlayerClothing', saved.appearance, ped)
        return true
    elseif mode == 'qs-appearance' then
        return applyQsAppearance(ped, saved.appearance)
    end
    return false
end

local function firstCharacterMode()
    local clothing = Config.FirstCharacter.clothing
    if clothing.mode ~= "auto" and clothing.mode ~= "event" and clothing.mode ~= "none" then
        return clothing.mode
    end
    return XSAppearance.mode()
end

function XSAppearance.firstCharacterEvent()
    local clothing = Config.FirstCharacter.clothing
    if clothing.custom == true or clothing.mode == 'none' then return nil end
    if clothing.mode == 'event' then
        return clothing.event ~= '' and clothing.event or nil
    end
    local mode = firstCharacterMode()
    if mode == "qs-appearance" then
        local qsEvent = qsSettings().firstCharacterEvent
        return type(qsEvent) == "string" and qsEvent ~= "" and qsEvent or nil
    end
    local event = clothing.firstCharacterEvent
    return type(event) == 'string' and event ~= '' and event or nil
end

function XSAppearance.openFirstCharacter()
    if Config.FirstCharacter.clothing.custom == true then return false end
    local clothing = Config.FirstCharacter.clothing
    if clothing.mode == "none" then return false end
    if clothing.mode == "event" then
        if clothing.event == "" then return false end
        TriggerEvent(clothing.event)
        return true
    end

    local mode = firstCharacterMode()
    if mode == "none" then return false end
    if mode == "qs-appearance" then return openQsAppearance() end
    local event = XSAppearance.firstCharacterEvent()
    if not event then return false end
    TriggerEvent(event)
    return true
end

--- Save the current ped through the installed appearance resource.
--- @return boolean success Whether an appearance save request was sent
function XSAppearance.saveCurrent()
    if Config.FirstCharacter.clothing.custom ~= true then return false end
    local mode = XSAppearance.mode()
    local ped = PlayerPedId()
    local ok, appearance
    if mode == "illenium-appearance" or mode == "fivem-appearance" then
        ok, appearance = pcall(function()
            return exports[mode]:getPedAppearance(ped)
        end)
        if ok and appearance then
            TriggerServerEvent(("%s:server:saveAppearance"):format(mode), appearance)
            return true
        end
    end
    if mode == "qs-appearance" then
        local settings = qsSettings()
        local resource = settings.resource or "qs-appearance"
        local getterMethods = exportMethods(settings.getPedExports, { "getPedAppearance", "getAppearance" })
        for _, method in ipairs(getterMethods) do
            ok, appearance = pcall(function()
                return exports[resource][method](ped)
            end)
            if ok and appearance then
                local saveEvent = settings.saveEvent
                if type(saveEvent) == "string" and saveEvent ~= "" then
                    TriggerServerEvent(saveEvent, appearance)
                    return true
                end
                local saveMethods = exportMethods(settings.saveExports, { "saveAppearance" })
                for _, saveMethod in ipairs(saveMethods) do
                    if callExport(resource, saveMethod, appearance) then return true end
                end
            end
        end
    end
    if mode == "qb-clothing" then
        TriggerEvent("qb-clothing:client:saveSkin")
        return true
    end
    return false
end
