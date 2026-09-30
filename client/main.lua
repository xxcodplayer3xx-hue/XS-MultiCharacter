local previewPed, previewCam
local characters, spawnOptions = {}, {}
local activeCharacter, activeCharacterData
local waitingForClothing, selectorOpen = false, false
local openingClothing, clothingHandledElsewhere = false, false
local customClothingOpen = false
local clothingItems = {}
local clothingHeading = 0.0
local previewToken = 0

if not XSValidation.print('client') then return end

local function debugPrint(message)
    if Config.Debug then print(('[XS-MultiCharacter] %s'):format(message)) end
end

local function fadeOut()
    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end
end

local function destroyPreviewPed()
    previewToken = previewToken + 1
    if previewPed and DoesEntityExist(previewPed) then DeleteEntity(previewPed) end
    previewPed = nil
end

local function destroyCamera(transition)
    if not previewCam then return end
    RenderScriptCams(false, transition == true, Config.Client.Scene.cameraTransitionMs, true, true)
    DestroyCam(previewCam, false)
    previewCam = nil
end

local function removeScene()
    selectorOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    destroyCamera(true)
    destroyPreviewPed()
    NetworkEndTutorialSession()
    DisplayRadar(true)
    ClearFocus()
    XSWeather.leaveScene()
    XSSceneEffects.leave()
end

local function requestModel(model)
    RequestModel(model)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model)
end

local function showPed(character, fallbackGender)
    previewToken = previewToken + 1
    local token = previewToken
    destroyPreviewPed()
    previewToken = token
    local gender = character and character.charinfo and character.charinfo.gender or fallbackGender or 0
    local model = XSAppearance.model(character and character.appearance, gender)
    if not requestModel(model) or token ~= previewToken then return end
    local pos = Config.Client.Scene.coords
    previewPed = CreatePed(2, model, pos.x, pos.y, pos.z - 1.0, pos.w, false, true)
    SetEntityInvincible(previewPed, true)
    FreezeEntityPosition(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetPedDefaultComponentVariation(previewPed)
    if character and character.appearance then XSAppearance.apply(previewPed, character.appearance) end
    local jobName = character and character.job and character.job.name
    XSAnimation.play(previewPed, jobName)
    SetModelAsNoLongerNeeded(model)
    TriggerEvent('XS-MultiCharacter:client:characterPreviewed', character, previewPed)
end

local function createCamera(coords, lookAt, interpolate)
    local newCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(newCamera, coords.x, coords.y, coords.z)
    PointCamAtCoord(newCamera, lookAt.x, lookAt.y, lookAt.z)
    SetCamFov(newCamera, Config.Client.CinematicSpawn.fov)
    XSSceneEffects.applyCamera(newCamera)
    SetCamActive(newCamera, true)
    if previewCam and interpolate then
        local previous = previewCam
        SetCamActiveWithInterp(newCamera, previous, Config.Client.CinematicSpawn.transitionMs, true, true)
        CreateThread(function()
            Wait(Config.Client.CinematicSpawn.transitionMs + 50)
            if DoesCamExist(previous) then DestroyCam(previous, false) end
        end)
    else
        RenderScriptCams(true, false, 0, true, true)
        if previewCam and DoesCamExist(previewCam) then DestroyCam(previewCam, false) end
    end
    previewCam = newCamera
end

local function setupScene()
    fadeOut()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    NetworkStartSoloTutorialSession()
    DisplayRadar(false)
    XSWeather.enterScene()
    XSSceneEffects.enter()
    local scene = Config.Client.Scene
    SetEntityCoords(PlayerPedId(), scene.coords.x, scene.coords.y, scene.coords.z - 5.0, false, false, false, false)
    FreezeEntityPosition(PlayerPedId(), true)
    SetEntityVisible(PlayerPedId(), false, false)
    showPed(nil, 0)
    createCamera(scene.camera, scene.cameraLookAt, false)
    XSSceneEffects.startOrbit(previewCam, scene.camera, scene.cameraLookAt)
    DoScreenFadeIn(500)
end

local function openCharacters()
    selectorOpen = true
    setupScene()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'loading',
        config = { characters = Config.Characters, ui = Config.Client.UI, locale = XSLocaleTable() }
    })
    TriggerServerEvent('XS-MultiCharacter:server:list')
end

local function savedAppearance()
    for _, character in ipairs(characters) do
        if character.citizenid == activeCharacter then return character.appearance end
    end
    return nil
end

local function spawnAt(coords, spawnId)
    coords = coords or Config.Spawn.default
    fadeOut()
    removeScene()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.w or coords.heading or 0.0)
    local deadline = GetGameTimer() + 10000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(0) end
    XSBridge.clearInside()
    XSBridge.playerLoaded()
    XSPed.begin(savedAppearance())
    DoScreenFadeIn(700)
    TriggerEvent('XS-MultiCharacter:client:characterSpawned', activeCharacter, spawnId, coords)
    TriggerServerEvent('XS-MultiCharacter:server:spawned', spawnId)
end

local function cameraFor(location)
    if location.camera and location.lookAt then return location.camera, location.lookAt end
    local coords = location.coords
    local height, distance = Config.Client.CinematicSpawn.defaultCameraHeight, Config.Client.CinematicSpawn.defaultCameraDistance
    return vec3(coords.x + distance, coords.y + distance, coords.z + height), vec3(coords.x, coords.y, coords.z)
end

local function openSpawns(position, allowedIds)
    XSSceneEffects.stopOrbit()
    local allowed, options = {}, {}
    for _, id in ipairs(allowedIds or {}) do allowed[id] = true end
    if allowed.last and Config.Spawn.allowLastLocation and position and position.x then
        options[#options + 1] = {
            id = 'last', label = XSLocale('lastLocation'), description = XSLocale('lastLocationDescription'),
            district = GetLabelText(GetNameOfZone(position.x, position.y, position.z)), coords = position,
            category = Config.Spawn.lastLocationCategory
        }
    end
    for _, location in ipairs(Config.Spawn.locations) do
        if allowed[location.id] then
            location.category = location.category or Config.Spawn.defaultCategory
            options[#options + 1] = location
        end
    end
    spawnOptions = options
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'spawns', locations = options, categories = Config.Spawn.categories })
end

local function openApartmentsAfterClothing()
    if not waitingForClothing then return end
    waitingForClothing = false
    CreateThread(function()
        local deadline = GetGameTimer() + 3000
        while IsNuiFocused() and GetGameTimer() < deadline do Wait(100) end
        if Config.FirstCharacter.apartments.enabled
            and Config.FirstCharacter.apartments.opensClothingAfterSelection == false then
            XSBridge.openApartments(activeCharacterData or activeCharacter)
        end
    end)
end

for i = 1, #Config.FirstCharacter.clothing.finishedEvents do
    RegisterNetEvent(Config.FirstCharacter.clothing.finishedEvents[i], openApartmentsAfterClothing)
end

local firstCharacterEvent = XSAppearance.firstCharacterEvent()
if firstCharacterEvent then
    AddEventHandler(firstCharacterEvent, function()
        if openingClothing then return end
        clothingHandledElsewhere = true
    end)
end

local function clothingCategories(ped)
    local categories = {
        { id = "mask", short = "01", label = "Face Cover", name = "Mask", kind = "component", slot = 1 },
        { id = "hair", short = "02", label = "Hair", name = "Hair", kind = "component", slot = 2 },
        { id = "arms", short = "03", label = "Arms", name = "Arms", kind = "component", slot = 3 },
        { id = "jacket", short = "04", label = "Outerwear", name = "Jacket", kind = "component", slot = 11 },
        { id = "shirt", short = "05", label = "Base Layer", name = "Shirt", kind = "component", slot = 8 },
        { id = "pants", short = "06", label = "Trousers", name = "Pants", kind = "component", slot = 4 },
        { id = "shoes", short = "07", label = "Footwear", name = "Shoes", kind = "component", slot = 6 },
        { id = "bags", short = "08", label = "Bags", name = "Bag", kind = "component", slot = 5 },
        { id = "accessory", short = "09", label = "Accessories", name = "Accessory", kind = "component", slot = 7 },
        { id = "undershirt", short = "10", label = "Undershirt", name = "Undershirt", kind = "component", slot = 8 },
        { id = "armor", short = "11", label = "Body Armor", name = "Armor", kind = "component", slot = 9 },
        { id = "decals", short = "12", label = "Decals", name = "Decal", kind = "component", slot = 10 },
        { id = "hat", short = "13", label = "Headwear", name = "Hat", kind = "prop", slot = 0 },
        { id = "glasses", short = "14", label = "Eyewear", name = "Glasses", kind = "prop", slot = 1 },
        { id = "ear", short = "15", label = "Earwear", name = "Earrings", kind = "prop", slot = 2 },
        { id = "watch", short = "16", label = "Wristwear", name = "Watch", kind = "prop", slot = 6 },
        { id = "bracelet", short = "17", label = "Bracelets", name = "Bracelet", kind = "prop", slot = 7 }
    }
    for _, item in ipairs(categories) do
        if item.kind == "component" then
            item.drawable = GetPedDrawableVariation(ped, item.slot)
            item.drawables = math.max(GetNumberOfPedDrawableVariations(ped, item.slot), 1)
            item.texture = GetPedTextureVariation(ped, item.slot)
            item.textures = math.max(GetNumberOfPedTextureVariations(ped, item.slot, item.drawable), 1)
        else
            item.drawable = GetPedPropIndex(ped, item.slot)
            item.drawables = math.max(GetNumberOfPedPropDrawableVariations(ped, item.slot), 1)
            item.texture = item.drawable >= 0 and GetPedPropTextureIndex(ped, item.slot) or 0
            item.textures = item.drawable >= 0 and math.max(GetNumberOfPedPropTextureVariations(ped, item.slot, item.drawable), 1) or 1
        end
    end
    return categories
end

local function openCustomClothing()
    local ped = PlayerPedId()
    clothingItems = clothingCategories(ped)
    clothingHeading = GetEntityHeading(ped)
    customClothingOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "clothingOpen", categories = clothingItems })
    if IsScreenFadedOut() then DoScreenFadeIn(350) end
end

local function finishCustomClothing()
    if not customClothingOpen then return end
    customClothingOpen = false
    waitingForClothing = false
    XSAppearance.saveCurrent()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "clothingClose" })
    openApartmentsAfterClothing()
end

local function openCustomAfterApartment()
    CreateThread(function()
        Wait(750)
        local deadline = GetGameTimer() + 120000
        while waitingForClothing and GetGameTimer() < deadline do
            if not IsNuiFocused() then
                Wait(350)
                if waitingForClothing and not IsNuiFocused() then
                    openCustomClothing()
                    return
                end
            end
            Wait(150)
        end
    end)
end

local function openClothingWhenClear()
    local clothing = Config.FirstCharacter.clothing
    CreateThread(function()
        Wait(clothing.openDelayMs or 0)
        if clothing.custom == true then
            if waitingForClothing then openCustomClothing() end
            return
        end
        if IsNuiFocused() then
            local clear = GetGameTimer() + ((clothing.waitForOtherMenusSeconds or 0) * 1000)
            while waitingForClothing and IsNuiFocused() and GetGameTimer() < clear do Wait(150) end
            local handoff = GetGameTimer() + ((clothing.handoffSeconds or 0) * 1000)
            while waitingForClothing and not clothingHandledElsewhere and GetGameTimer() < handoff do Wait(150) end
        end
        if not waitingForClothing or clothingHandledElsewhere then return end
        openingClothing = true
        XSBridge.openClothing()
        openingClothing = false
        local deadline = GetGameTimer() + (clothing.fallbackSeconds * 1000)
        while waitingForClothing and not IsNuiFocused() and GetGameTimer() < deadline do Wait(100) end
        if not waitingForClothing then return end
        if IsNuiFocused() then while waitingForClothing and IsNuiFocused() do Wait(150) end end
        Wait(250)
        openApartmentsAfterClothing()
    end)
end

exports('GetSelectedCharacter', function() return activeCharacter, activeCharacterData end)
exports('IsSelectingCharacter', function() return selectorOpen end)

RegisterNetEvent('XS-MultiCharacter:client:list', function(payload)
    characters = payload.characters or {}
    for _, character in ipairs(characters) do
        if character.position and character.position.x and character.dossier and character.dossier.activity then
            character.dossier.activity.lastDistrict = GetLabelText(GetNameOfZone(character.position.x, character.position.y, character.position.z))
        end
    end
    SendNUIMessage({ action = 'characters', characters = characters, slots = payload.slots or 1 })
end)

RegisterNetEvent('XS-MultiCharacter:client:adminOpen', function()
    TriggerServerEvent('XS-MultiCharacter:server:adminList')
end)

RegisterNetEvent('XS-MultiCharacter:client:adminData', function(payload)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'adminSlots',
        players = payload.players or {},
        maximum = payload.maximum,
        locale = XSLocaleTable(),
        ui = Config.Client.UI
    })
end)

RegisterNetEvent('XS-MultiCharacter:client:loggedIn', function(citizenid, position, isNew, playerData, allowedSpawns)
    activeCharacter, activeCharacterData = citizenid, playerData
    TriggerEvent('XS-MultiCharacter:client:characterSelected', citizenid, isNew, playerData)
    if isNew then
        waitingForClothing = false
        clothingHandledElsewhere = false
        fadeOut()
        removeScene()
        local ped = PlayerPedId()
        SetEntityVisible(ped, true, false)
        FreezeEntityPosition(ped, false)
        DoScreenFadeIn(450)

        -- The stock apartment flow opens clothing after the apartment is made.
        -- Starting either of those here would make the two menus overlap.
        if Config.FirstCharacter.apartments.enabled
            and (Config.FirstCharacter.clothing.custom == true
                or Config.FirstCharacter.apartments.opensClothingAfterSelection ~= false)
            and XSBridge.openApartments(activeCharacterData or activeCharacter) then
            XSPed.begin(nil)
            if Config.FirstCharacter.clothing.custom == true then
                waitingForClothing = true
                openCustomAfterApartment()
            end
            return
        end

        debugPrint('No apartment resource to hand the new character to, using the spawn and clothing fallback.')
        spawnAt(Config.Spawn.default, 'default')
        if Config.FirstCharacter.clothing.enabled and (Config.FirstCharacter.clothing.custom == true or Config.FirstCharacter.clothing.mode ~= 'none') then
            waitingForClothing = true
            openClothingWhenClear()
        else
            waitingForClothing = true
            openApartmentsAfterClothing()
        end
    else
        openSpawns(position, allowedSpawns)
    end
end)

RegisterNetEvent('XS-MultiCharacter:client:spawnApproved', function(spawnId, coords)
    spawnAt(coords, spawnId)
end)

RegisterNetEvent('XS-MultiCharacter:client:refresh', function()
    TriggerServerEvent('XS-MultiCharacter:server:list')
end)

RegisterNUICallback("clothingChange", function(data, cb)
    if not customClothingOpen or type(data) ~= "table" then cb("ok") return end
    local ped = PlayerPedId()
    for _, item in ipairs(clothingItems) do
        if item.id == data.id and item.kind == data.kind then
            local minimum = item.kind == "prop" and -1 or 0
            local drawable = math.max(minimum, math.min((item.drawables or 1) - 1, math.floor(tonumber(data.drawable) or 0)))
            local textures = 1
            if item.kind == "component" then
                textures = math.max(GetNumberOfPedTextureVariations(ped, item.slot, drawable), 1)
            elseif drawable >= 0 then
                textures = math.max(GetNumberOfPedPropTextureVariations(ped, item.slot, drawable), 1)
            end
            local texture = math.max(0, math.min(textures - 1, math.floor(tonumber(data.texture) or 0)))
            item.drawable, item.texture, item.textures = drawable, texture, textures
            if item.kind == "component" then
                SetPedComponentVariation(ped, item.slot, drawable, texture, 0)
            elseif drawable < 0 then
                ClearPedProp(ped, item.slot)
            else
                SetPedPropIndex(ped, item.slot, drawable, texture, true)
            end
            cb({ ok = true, id = item.id, drawable = item.drawable, texture = item.texture, textures = item.textures })
            return
        end
    end
    cb({ ok = false })
end)

RegisterNUICallback("clothingRotate", function(data, cb)
    if customClothingOpen then
        clothingHeading = clothingHeading + (tonumber(data.direction) or 0) * 12.0
        SetEntityHeading(PlayerPedId(), clothingHeading % 360.0)
    end
    cb("ok")
end)

RegisterNUICallback("clothingFinish", function(_, cb)
    finishCustomClothing()
    cb("ok")
end)

RegisterNUICallback('preview', function(data, cb)
    local selected
    for _, character in ipairs(characters) do
        if character.citizenid == data.citizenid then selected = character break end
    end
    showPed(selected, data.gender or 0)
    cb('ok')
end)

RegisterNUICallback('previewSpawn', function(data, cb)
    if Config.Client.CinematicSpawn.enabled then
        for _, location in ipairs(spawnOptions) do
            if location.id == data.id then
                local camera, lookAt = cameraFor(location)
                SetFocusPosAndVel(location.coords.x, location.coords.y, location.coords.z, 0.0, 0.0, 0.0)
                createCamera(camera, lookAt, true)
                TriggerEvent('XS-MultiCharacter:client:spawnPreviewed', activeCharacter, location)
                break
            end
        end
    end
    cb('ok')
end)

RegisterNUICallback('play', function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('XS-MultiCharacter:server:load', data.citizenid)
    cb('ok')
end)

RegisterNUICallback('create', function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('XS-MultiCharacter:server:create', data)
    cb('ok')
end)

RegisterNUICallback('delete', function(data, cb)
    TriggerServerEvent('XS-MultiCharacter:server:delete', data.citizenid)
    cb('ok')
end)

RegisterNUICallback('spawn', function(data, cb)
    TriggerServerEvent('XS-MultiCharacter:server:selectSpawn', data.id)
    cb('ok')
end)

RegisterNUICallback('adminSetSlots', function(data, cb)
    TriggerServerEvent('XS-MultiCharacter:server:adminSetSlots', data.license, data.slots, data.reset == true)
    cb('ok')
end)

RegisterNUICallback('adminClose', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'adminClosed' })
    cb('ok')
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(100) end
    Wait(500)
    openCharacters()
end)
