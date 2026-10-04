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
    local methods = exportMethods(settings.firstCharacterExports, { "openAppearance", "openMenu", "openClothing" })
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

local function nativeAppearance(ped, appearance)
    if not ped or not DoesEntityExist(ped) or type(appearance) ~= "table" then return false end
    local changed = false

    for _, component in ipairs(appearance.components or {}) do
        local slot = component.component_id or component.componentId or component.id
        local drawable = component.drawable or component.drawableId or 0
        local texture = component.texture or component.textureId or 0
        if slot then
            SetPedComponentVariation(ped, slot, drawable, texture, component.palette or 0)
            changed = true
        end
    end

    for _, prop in ipairs(appearance.props or {}) do
        local slot = prop.prop_id or prop.propId or prop.id
        local drawable = prop.drawable or prop.drawableId or -1
        local texture = prop.texture or prop.textureId or 0
        if slot then
            if drawable < 0 then ClearPedProp(ped, slot) else SetPedPropIndex(ped, slot, drawable, texture, true) end
            changed = true
        end
    end

    local blend = appearance.headBlend or appearance.head_blend
    if blend and IsPedFreemodeModel(ped) then
        SetPedHeadBlendData(
            ped,
            blend.shapeFirst or blend.shape_first or 0,
            blend.shapeSecond or blend.shape_second or 0,
            blend.shapeThird or blend.shape_third or 0,
            blend.skinFirst or blend.skin_first or 0,
            blend.skinSecond or blend.skin_second or 0,
            blend.skinThird or blend.skin_third or 0,
            blend.shapeMix or blend.shape_mix or 0.5,
            blend.skinMix or blend.skin_mix or 0.5,
            blend.thirdMix or blend.third_mix or 0.0,
            false
        )
        changed = true
    end

    for feature, value in pairs(appearance.faceFeatures or appearance.face_features or {}) do
        local index = tonumber(feature)
        if index then SetPedFaceFeature(ped, index, tonumber(value) or 0) changed = true end
    end

    local hair = appearance.hair
    if hair then
        local style = hair.style or hair.model or hair.drawable
        if style then SetPedComponentVariation(ped, 2, style, hair.texture or 0, 0) end
        if hair.color or hair.color == 0 then SetPedHairColor(ped, hair.color, hair.highlight or hair.color) end
        changed = true
    end
    if appearance.eyeColor or appearance.eyeColor == 0 then
        SetPedEyeColor(ped, appearance.eyeColor)
        changed = true
    end

    for overlay, data in pairs(appearance.headOverlays or appearance.head_overlays or {}) do
        local index = tonumber(overlay) or (type(data) == "table" and tonumber(data.id))
        if index then
            local value = type(data) == "table" and (data.style or data.value or data.index) or data
            local opacity = type(data) == "table" and (data.opacity or 1.0) or 1.0
            if tonumber(value) == -1 then
                value = 255
                opacity = 0.0
            end
            SetPedHeadOverlay(ped, index, value == nil and 255 or value, opacity)
            if type(data) == "table" and data.color then
                SetPedHeadOverlayColor(ped, index, data.colorType or 1, data.color, data.secondColor or data.color)
            end
            changed = true
        end
    end

    return changed
end

local function applyAppearanceResource(ped, appearance)
    local mode = XSAppearance.mode()
    if mode == "illenium-appearance" then
        return pcall(function() exports[mode]:setPedAppearance(ped, appearance) end)
    elseif mode == "fivem-appearance" then
        return pcall(function() exports[mode]:setPedAppearance(ped, appearance) end)
    elseif mode == "qb-clothing" then
        TriggerEvent("qb-clothing:client:loadPlayerClothing", appearance, ped)
        return true
    elseif mode == "qs-appearance" then
        -- Some qs-appearance releases expose an export that returns success
        -- without applying every field. Always run the native mapper as well so
        -- hair, beard, face features, and clothing cannot silently disappear.
        local resourceApplied = applyQsAppearance(ped, appearance)
        local nativeApplied = nativeAppearance(ped, appearance)
        return resourceApplied or nativeApplied
    end
    return nativeAppearance(ped, appearance)
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
    return applyAppearanceResource(ped, saved.appearance)
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

local function nativeAppearanceFromPed(ped)
    if not ped or not DoesEntityExist(ped) then return nil end

    local blendData = {}
    pcall(GetPedHeadBlendData, ped, blendData)
    local appearance = {
        components = {},
        props = {},
        headBlend = {
            shapeFirst = tonumber(blendData.shapeFirst) or 0,
            shapeSecond = tonumber(blendData.shapeSecond) or 0,
            shapeThird = tonumber(blendData.shapeThird) or 0,
            skinFirst = tonumber(blendData.skinFirst) or 0,
            skinSecond = tonumber(blendData.skinSecond) or 0,
            skinThird = tonumber(blendData.skinThird) or 0,
            shapeMix = tonumber(blendData.shapeMix) or 0.5,
            skinMix = tonumber(blendData.skinMix) or 0.5,
            thirdMix = tonumber(blendData.thirdMix) or 0.0
        },
        faceFeatures = {},
        hair = {
            style = GetPedDrawableVariation(ped, 2),
            texture = GetPedTextureVariation(ped, 2),
            color = GetPedHairColor(ped),
            highlight = GetPedHairHighlightColor(ped)
        },
        eyeColor = GetPedEyeColor(ped),
        headOverlays = {}
    }

    for feature = 0, 19 do
        appearance.faceFeatures[tostring(feature)] = GetPedFaceFeature(ped, feature)
    end

    for component = 0, 11 do
        appearance.components[#appearance.components + 1] = {
            id = component,
            drawable = GetPedDrawableVariation(ped, component),
            texture = GetPedTextureVariation(ped, component),
            palette = GetPedPaletteVariation(ped, component)
        }
    end

    for prop = 0, 7 do
        local drawable = GetPedPropIndex(ped, prop)
        appearance.props[#appearance.props + 1] = {
            id = prop,
            drawable = drawable,
            texture = drawable >= 0 and GetPedPropTextureIndex(ped, prop) or 0
        }
    end

    for overlay = 0, 12 do
        local style = GetPedHeadOverlayValue(ped, overlay)
        appearance.headOverlays[tostring(overlay)] = {
            style = style == 255 and -1 or style,
            opacity = style == 255 and 0.0 or 1.0,
            color = GetPedHairColor(ped),
            secondColor = GetPedHairHighlightColor(ped)
        }
    end

    return appearance
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
            if ok and type(appearance) == "table" then
                local saveEvent = settings.saveEvent
                if type(saveEvent) == "string" and saveEvent ~= "" then
                    TriggerServerEvent(saveEvent, appearance)
                    return true
                end
                local saveMethods = exportMethods(settings.saveExports, { "saveAppearance", "savePedAppearance" })
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

    local nativeAppearance = nativeAppearanceFromPed(ped)
    if nativeAppearance then
        TriggerServerEvent("XS-MultiCharacter:server:saveNativeAppearance", nativeAppearance)
        return true
    end
    return false
end
