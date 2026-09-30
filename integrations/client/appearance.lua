XSAppearance = {}

local function running(resource)
    return GetResourceState(resource):find('start') ~= nil
end

function XSAppearance.mode()
    local mode = Config.Client.Integrations.appearance
    if mode ~= 'auto' then return mode end
    if running('illenium-appearance') then return 'illenium-appearance' end
    if running('fivem-appearance') then return 'fivem-appearance' end
    if running('qb-clothing') then return 'qb-clothing' end
    return 'none'
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
    end
    return false
end

function XSAppearance.firstCharacterEvent()
    local clothing = Config.FirstCharacter.clothing
    if clothing.custom == true or clothing.mode == 'none' then return nil end
    if clothing.mode == 'event' then
        return clothing.event ~= '' and clothing.event or nil
    end
    local event = clothing.firstCharacterEvent
    return type(event) == 'string' and event ~= '' and event or nil
end

function XSAppearance.openFirstCharacter()
    if Config.FirstCharacter.clothing.custom == true then return false end
    if Config.FirstCharacter.clothing.mode == 'auto' and XSAppearance.mode() == 'none' then return false end
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
    if mode == "qb-clothing" then
        TriggerEvent("qb-clothing:client:saveSkin")
        return true
    end
    return false
end
