local previewPed, previewCam
local characters, spawnOptions = {}, {}
local activeCharacter, activeCharacterData
local waitingForClothing, selectorOpen = false, false
local openingClothing, clothingHandledElsewhere = false, false
local customClothingOpen = false
local clothingItems = {}
local clothingHeading = 0.0
local clothingPreviewPed, clothingPreviewCam
local clothingPreviewUsesPlayer = false
local requestModel
local applyAppearanceItem
local applyEditorAppearance
local previewToken = 0
local selectorHiddenPeds = {}

local function sceneFloor(coords, configuredFloorZ)
    if configuredFloorZ then return configuredFloorZ end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
    if found then return groundZ end
    return coords.z
end

local function placeOnSceneFloor(entity, coords, configuredFloorZ)
    if not entity or not DoesEntityExist(entity) then return end
    local floorZ = sceneFloor(coords, configuredFloorZ)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, floorZ + 0.02, false, false, false)
    SetEntityHeading(entity, coords.w or 0.0)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityLoadCollisionFlag(entity, true)
end
local clothingPreviewToken = 0

local function clothingPreviewSettings()
    return Config.Client.ClothingPreview or {
        coords = Config.Client.Scene.coords,
        camera = Config.Client.Scene.camera,
        cameraLookAt = Config.Client.Scene.cameraLookAt,
        fov = 40.0
    }
end

local function hideSelectorPeds(allowedPed)
    local anchor = Config.Client.Scene.coords
    for _, ped in ipairs(GetGamePool("CPed")) do
        if ped ~= allowedPed and DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            if Vdist(coords.x, coords.y, coords.z, anchor.x, anchor.y, anchor.z) < 30.0 then
                selectorHiddenPeds[ped] = true
                SetEntityVisible(ped, false, false)
                SetEntityLocallyInvisible(ped)
            end
        end
    end
end

local function restoreSelectorPeds()
    for ped in pairs(selectorHiddenPeds) do
        if DoesEntityExist(ped) then
            SetEntityVisible(ped, true, false)
            SetEntityLocallyVisible(ped)
        end
    end
    selectorHiddenPeds = {}
end

local function destroyClothingPreview()
    clothingPreviewToken = clothingPreviewToken + 1
    if clothingPreviewCam then
        RenderScriptCams(false, true, 250, true, true)
        if DoesCamExist(clothingPreviewCam) then DestroyCam(clothingPreviewCam, false) end
        clothingPreviewCam = nil
    end
    if clothingPreviewPed and DoesEntityExist(clothingPreviewPed) and not clothingPreviewUsesPlayer then
        SetEntityAsMissionEntity(clothingPreviewPed, true, true)
        DeleteEntity(clothingPreviewPed)
    end
    local playerPed = PlayerPedId()
    if playerPed and DoesEntityExist(playerPed) then
        SetEntityVisible(playerPed, true, false)
        SetEntityLocallyVisible(playerPed)
        ResetEntityAlpha(playerPed)
        SetEntityCollision(playerPed, true, true)
        SetEntityHasGravity(playerPed, true)
        SetEntityInvincible(playerPed, false)
        SetEntityCanBeDamaged(playerPed, true)
        SetPedCanBeTargetted(playerPed, true)
        SetPedCanRagdoll(playerPed, true)
    end
    clothingPreviewPed = nil
    clothingPreviewUsesPlayer = false
    restoreSelectorPeds()
    ClearFocus()
end

local function overlayValue(ped, overlay)
    local value = GetPedHeadOverlayValue(ped, overlay)
    return value == 255 and -1 or value
end

local function applyHeadOverlay(targetPed, overlay, value, hairColor, hairHighlight)
    if not targetPed or not DoesEntityExist(targetPed) then return end
    if value == nil or value < 0 or value == 255 then
        SetPedHeadOverlay(targetPed, overlay, 255, 0.0)
        return
    end

    SetPedHeadOverlay(targetPed, overlay, math.floor(value), 1.0)
    if overlay == 1 or overlay == 2 then
        local selectedHairColor = math.max(0, math.floor(tonumber(hairColor) or GetPedHairColor(targetPed) or 0))
        local selectedHighlight = math.max(0, math.floor(tonumber(hairHighlight) or GetPedHairHighlightColor(targetPed) or selectedHairColor))
        SetPedHeadOverlayColor(targetPed, overlay, 1, selectedHairColor, selectedHighlight)
    end
end

local function applyHairColor(targetPed, color, highlight)
    if not targetPed or not DoesEntityExist(targetPed) then return end
    local hairColor = math.max(0, math.floor(tonumber(color) or 0))
    local hairHighlight = math.max(0, math.floor(tonumber(highlight) or hairColor))
    SetPedHairColor(targetPed, hairColor, hairHighlight)
    -- Freemode facial-hair overlays use the hair color channel. Reapply it
    -- after changing the component because GTA can reset overlay colors.
    for _, overlay in ipairs({ 1, 2 }) do
        local value = overlayValue(targetPed, overlay)
        if value >= 0 then SetPedHeadOverlayColor(targetPed, overlay, 1, hairColor, hairHighlight) end
    end
end

local function editorItem(itemId)
    for _, item in ipairs(clothingItems) do
        if item.id == itemId then return item end
    end
    return nil
end

local function editorHairColors()
    local item = editorItem("hairColor")
    local color = item and item.value or 0
    return color, color
end

local function applyHairAppearance(targetPed)
    if not targetPed or not DoesEntityExist(targetPed) then return end
    local style = editorItem("hairStyle")
    local hairComponent = editorItem("hair")
    local hairColor, hairHighlight = editorHairColors()

    if style then
        local texture = GetPedTextureVariation(targetPed, 2)
        SetPedComponentVariation(targetPed, 2, math.floor(style.value or 0), texture, 0)
    elseif hairComponent then
        SetPedComponentVariation(targetPed, 2, math.floor(hairComponent.drawable or 0), math.floor(hairComponent.texture or 0), 0)
    end

    applyHairColor(targetPed, hairColor, hairHighlight)
end

local function copyHeadAppearance(sourcePed, targetPed)
    local hairColor = GetPedHairColor(sourcePed)
    local hairHighlight = GetPedHairHighlightColor(sourcePed)
    SetPedEyeColor(targetPed, GetPedEyeColor(sourcePed))
    applyHairColor(targetPed, hairColor, hairHighlight)

    for overlay = 0, 12 do
        applyHeadOverlay(targetPed, overlay, overlayValue(sourcePed, overlay), hairColor, hairHighlight)
    end
end

local function copyPedAppearance(sourcePed, targetPed)
    SetPedDefaultComponentVariation(targetPed)

    for component = 0, 11 do
        SetPedComponentVariation(
            targetPed,
            component,
            GetPedDrawableVariation(sourcePed, component),
            GetPedTextureVariation(sourcePed, component),
            GetPedPaletteVariation(sourcePed, component)
        )
    end

    for prop = 0, 7 do
        local drawable = GetPedPropIndex(sourcePed, prop)
        if drawable < 0 then
            ClearPedProp(targetPed, prop)
        else
            SetPedPropIndex(targetPed, prop, drawable, GetPedPropTextureIndex(sourcePed, prop), true)
        end
    end

    for feature = 0, 19 do
        SetPedFaceFeature(targetPed, feature, GetPedFaceFeature(sourcePed, feature))
    end

    copyHeadAppearance(sourcePed, targetPed)
end

local function clearClothingVisualEffects()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    AnimpostfxStopAll()
    SetNightvision(false)
    SetSeethrough(false)
    StopGameplayCamShaking(true)
end

local function editorFloor(coords, configuredFloorZ)
    -- An explicit floor is safer than GetGroundZFor_3dCoord at locations with
    -- roofs, balconies, or streamed interior shells above the player.
    if configuredFloorZ then return configuredFloorZ end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local deadline = GetGameTimer() + 2500
    local found, groundZ
    repeat
        RequestCollisionAtCoord(coords.x, coords.y, coords.z + 5.0)
        found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
        if not found then Wait(0) end
    until found or GetGameTimer() >= deadline

    return found and groundZ or coords.z
end

local function createClothingPreview()
    destroyClothingPreview()
    local token = clothingPreviewToken
    local playerPed = PlayerPedId()
    local settings = clothingPreviewSettings()
    local model = GetEntityModel(playerPed)

    if not model or model == 0 or not IsModelInCdimage(model) then
        print("[XS-MultiCharacter] Unable to load the clothing preview model")
        return false
    end

    clearClothingVisualEffects()
    local floorZ = editorFloor(settings.coords, settings.floorZ)
    local previewX, previewY, previewZ = settings.coords.x, settings.coords.y, floorZ + 0.02

    -- Keep the real player hidden and use a separate local mannequin. This stops
    -- apartment/interior collision from moving the entity being edited into a roof.
    SetEntityCoordsNoOffset(playerPed, previewX, previewY, previewZ, false, false, false)
    SetEntityHeading(playerPed, settings.coords.w or 0.0)
    SetEntityVisible(playerPed, false, false)
    SetEntityLocallyInvisible(playerPed)
    SetEntityVelocity(playerPed, 0.0, 0.0, 0.0)
    SetEntityCollision(playerPed, false, false)
    SetEntityHasGravity(playerPed, false)
    FreezeEntityPosition(playerPed, true)

    local mannequin = CreatePed(4, model, previewX, previewY, previewZ, settings.coords.w or 0.0, false, false)
    if not mannequin or not DoesEntityExist(mannequin) then
        print("[XS-MultiCharacter] Unable to create the clothing preview mannequin")
        return false
    end

    if token ~= clothingPreviewToken then
        DeleteEntity(mannequin)
        return false
    end

    clothingPreviewPed = mannequin
    clothingPreviewUsesPlayer = false
    SetEntityAsMissionEntity(mannequin, true, true)
    SetEntityCollision(mannequin, false, false)
    SetEntityHasGravity(mannequin, false)
    SetEntityInvincible(mannequin, true)
    SetEntityCanBeDamaged(mannequin, false)
    SetEntityVisible(mannequin, true, false)
    SetEntityLocallyVisible(mannequin)
    SetEntityAlwaysPrerender(mannequin, true)
    ResetEntityAlpha(mannequin)
    SetEntityAlpha(mannequin, 255, false)
    SetBlockingOfNonTemporaryEvents(mannequin, true)
    SetPedCanBeTargetted(mannequin, false)
    SetPedCanRagdoll(mannequin, false)
    FreezeEntityPosition(mannequin, true)
    SetPedDefaultComponentVariation(mannequin)
    copyPedAppearance(playerPed, mannequin)

    local cameraPosition = settings.camera
    local cameraLookAt = settings.cameraLookAt
    clothingPreviewCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(clothingPreviewCam, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(clothingPreviewCam, cameraLookAt.x, cameraLookAt.y, cameraLookAt.z)
    SetCamFov(clothingPreviewCam, settings.fov or 50.0)
    SetCamActive(clothingPreviewCam, true)
    SetFocusPosAndVel(previewX, previewY, previewZ, 0.0, 0.0, 0.0)
    RenderScriptCams(true, false, 0, true, true)

    CreateThread(function()
        local nextAppearanceRefresh = 0
        while customClothingOpen and clothingPreviewPed == mannequin and DoesEntityExist(mannequin) do
            Wait(0)
            local currentPlayerPed = PlayerPedId()
            if DoesEntityExist(currentPlayerPed) and currentPlayerPed ~= mannequin then
                SetEntityVisible(currentPlayerPed, false, false)
                SetEntityLocallyInvisible(currentPlayerPed)
                SetEntityCollision(currentPlayerPed, false, false)
                SetEntityHasGravity(currentPlayerPed, false)
                FreezeEntityPosition(currentPlayerPed, true)
            end
            hideSelectorPeds(mannequin)
            if GetGameTimer() >= nextAppearanceRefresh then
                applyEditorAppearance(currentPlayerPed)
                applyEditorAppearance(mannequin)
                nextAppearanceRefresh = GetGameTimer() + 250
            end
            clearClothingVisualEffects()
            SetEntityVisible(mannequin, true, false)
            SetEntityLocallyVisible(mannequin)
            SetEntityAlwaysPrerender(mannequin, true)
            ResetEntityAlpha(mannequin)
            SetEntityAlpha(mannequin, 255, false)
            SetEntityCollision(mannequin, false, false)
            SetEntityHasGravity(mannequin, false)
            FreezeEntityPosition(mannequin, true)
            SetEntityVisible(playerPed, false, false)
            SetEntityLocallyInvisible(playerPed)
        end
    end)
    return true
end

if not XSValidation.print('client') then return end

local function debugPrint(message)
    if Config.Debug then print(('[XS-MultiCharacter] %s'):format(message)) end
end

local function fadeOut()
    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end
end

--- Restore the local player after leaving the character-selection scene.
--- @param ped number The current player ped entity
local function restoreGameplayPlayer(ped)
    if not ped or not DoesEntityExist(ped) then return end

    SetPlayerControl(PlayerId(), true, 0)
    SetNuiFocus(false, false)
    ClearFocus()
    SetEntityVisible(ped, true, false)
    SetEntityLocallyVisible(ped)
    ResetEntityAlpha(ped)
    SetEntityAlpha(ped, 255, false)
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityInvincible(ped, false)
    SetEntityCanBeDamaged(ped, true)
    SetPedCanBeTargetted(ped, true)
    SetPedCanRagdoll(ped, true)
    FreezeEntityPosition(ped, false)
end

local function destroyPreviewPed()
    previewToken = previewToken + 1
    restoreSelectorPeds()
    if previewPed and DoesEntityExist(previewPed) then
        SetEntityAsMissionEntity(previewPed, true, true)
        DeleteEntity(previewPed)
    end
    previewPed = nil
    ClearFocus()
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

requestModel = function(model)
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
    if not model or not requestModel(model) or token ~= previewToken then
        print("[XS-MultiCharacter] Selected character preview model could not be loaded")
        return
    end

    local pos = Config.Client.Scene.coords
    local floorZ = Config.Client.Scene.floorZ or pos.z
    local previewZ = floorZ + 0.03
    SetFocusPosAndVel(pos.x, pos.y, previewZ, 0.0, 0.0, 0.0)
    previewPed = CreatePed(4, model, pos.x, pos.y, previewZ, pos.w or 0.0, false, false)
    if not previewPed or not DoesEntityExist(previewPed) then
        SetModelAsNoLongerNeeded(model)
        print("[XS-MultiCharacter] Unable to create the selected character preview ped")
        return
    end

    SetEntityAsMissionEntity(previewPed, true, true)
    SetEntityCoordsNoOffset(previewPed, pos.x, pos.y, previewZ, false, false, false)
    SetEntityHeading(previewPed, pos.w or 0.0)
    SetEntityLoadCollisionFlag(previewPed, true)
    SetEntityInvincible(previewPed, true)
    SetEntityCanBeDamaged(previewPed, false)
    SetEntityCollision(previewPed, false, false)
    SetEntityHasGravity(previewPed, false)
    SetEntityVisible(previewPed, true, false)
    SetEntityLocallyVisible(previewPed)
    SetEntityAlwaysPrerender(previewPed, true)
    ResetEntityAlpha(previewPed)
    SetEntityAlpha(previewPed, 255, false)
    FreezeEntityPosition(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetPedCanRagdoll(previewPed, false)
    SetPedDefaultComponentVariation(previewPed)
    if character and character.appearance then
        XSAppearance.apply(previewPed, character.appearance)
    end
    local jobName = character and character.job and character.job.name
    XSAnimation.play(previewPed, jobName)
    SetEntityVisible(previewPed, true, false)
    SetEntityLocallyVisible(previewPed)
    SetEntityAlwaysPrerender(previewPed, true)
    ResetEntityAlpha(previewPed)
    SetEntityAlpha(previewPed, 255, false)
    SetModelAsNoLongerNeeded(model)
    CreateThread(function()
        Wait(250)
        if selectorOpen and token == previewToken and DoesEntityExist(previewPed) then
            if character and character.appearance then
                XSAppearance.apply(previewPed, character.appearance)
            end
            SetEntityVisible(previewPed, true, false)
            SetEntityLocallyVisible(previewPed)
            ResetEntityAlpha(previewPed)
            SetEntityAlpha(previewPed, 255, false)
        end
    end)
    SetFocusPosAndVel(pos.x, pos.y, previewZ, 0.0, 0.0, 0.0)
    TriggerEvent('XS-MultiCharacter:client:characterPreviewed', character, previewPed)

    CreateThread(function()
        while selectorOpen and token == previewToken and DoesEntityExist(previewPed) do
            Wait(0)
            local playerPed = PlayerPedId()
            if DoesEntityExist(playerPed) and playerPed ~= previewPed then
                SetEntityVisible(playerPed, false, false)
                SetEntityLocallyInvisible(playerPed)
                SetEntityCollision(playerPed, false, false)
                SetEntityHasGravity(playerPed, false)
                FreezeEntityPosition(playerPed, true)
            end
            hideSelectorPeds(previewPed)
            SetEntityVisible(previewPed, true, false)
            SetEntityLocallyVisible(previewPed)
            ResetEntityAlpha(previewPed)
            SetEntityAlpha(previewPed, 255, false)
            SetEntityCollision(previewPed, false, false)
            SetEntityHasGravity(previewPed, false)
            SetEntityInvincible(previewPed, true)
            FreezeEntityPosition(previewPed, true)
        end
    end)
end

local function createCamera(coords, lookAt, interpolate, fov)
    local newCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(newCamera, coords.x, coords.y, coords.z)
    PointCamAtCoord(newCamera, lookAt.x, lookAt.y, lookAt.z)
    SetCamFov(newCamera, fov or Config.Client.CinematicSpawn.fov)
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
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    NetworkStartSoloTutorialSession()
    DisplayRadar(false)
    XSWeather.enterScene()
    XSSceneEffects.enter()
    local scene = Config.Client.Scene
    local playerPed = PlayerPedId()
    placeOnSceneFloor(playerPed, scene.coords, scene.floorZ)
    SetEntityCollision(playerPed, true, true)
    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false, false)
    CreateThread(function()
        while selectorOpen do
            Wait(0)
            hideSelectorPeds(previewPed)
        end
    end)
    createCamera(scene.camera, scene.cameraLookAt, false, scene.fov)
    XSSceneEffects.startOrbit(previewCam, scene.camera, scene.cameraLookAt)
    DoScreenFadeIn(250)
    CreateThread(function()
        showPed(nil, 0)
    end)
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
    restoreGameplayPlayer(ped)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.w or coords.heading or 0.0)
    local deadline = GetGameTimer() + 10000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(0) end
    restoreGameplayPlayer(PlayerPedId())
    XSBridge.clearInside()
    XSBridge.playerLoaded()
    XSPed.begin(savedAppearance())
    DoScreenFadeIn(700)
    CreateThread(function()
        Wait(500)
        if not selectorOpen and not customClothingOpen then
            restoreGameplayPlayer(PlayerPedId())
        end
    end)
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

local qsFinishedEvent = XSAppearance.qsAppearanceFinishedEvent()
if qsFinishedEvent then
    RegisterNetEvent(qsFinishedEvent, openApartmentsAfterClothing)
end

local firstCharacterEvent = XSAppearance.firstCharacterEvent()
if firstCharacterEvent then
    AddEventHandler(firstCharacterEvent, function()
        if openingClothing then return end
        clothingHandledElsewhere = true
    end)
end

local function headBlendValues(ped)
    local values = {
        shapeFirst = 0, shapeSecond = 0, shapeThird = 0,
        skinFirst = 0, skinSecond = 0, skinThird = 0,
        shapeMix = 0.5, skinMix = 0.5, thirdMix = 0.0
    }
    local blendData = {}
    local ok = pcall(GetPedHeadBlendData, ped, blendData)
    if ok then
        values.shapeFirst = tonumber(blendData.shapeFirst) or values.shapeFirst
        values.shapeSecond = tonumber(blendData.shapeSecond) or values.shapeSecond
        values.shapeThird = tonumber(blendData.shapeThird) or values.shapeThird
        values.skinFirst = tonumber(blendData.skinFirst) or values.skinFirst
        values.skinSecond = tonumber(blendData.skinSecond) or values.skinSecond
        values.skinThird = tonumber(blendData.skinThird) or values.skinThird
        values.shapeMix = tonumber(blendData.shapeMix) or values.shapeMix
        values.skinMix = tonumber(blendData.skinMix) or values.skinMix
        values.thirdMix = tonumber(blendData.thirdMix) or values.thirdMix
    end
    return values
end

local function appearanceCategories(ped)
    local blend = headBlendValues(ped)
    local categories = {
        { id = "faceShape", short = "F1", label = "Face Shape", name = "Face Shape", kind = "faceBlend", field = "shapeFirst", value = blend.shapeFirst, minimum = 0, maximum = 45, step = 1 },
        { id = "faceMix", short = "F2", label = "Face Structure", name = "Structure Mix", kind = "faceBlend", field = "shapeMix", value = blend.shapeMix, minimum = 0, maximum = 1, step = 0.05 },
        { id = "skinTone", short = "S1", label = "Skin Tone", name = "Skin Tone", kind = "faceBlend", field = "skinFirst", value = blend.skinFirst, minimum = 0, maximum = 45, step = 1 },
        { id = "skinMix", short = "S2", label = "Skin Structure", name = "Skin Mix", kind = "faceBlend", field = "skinMix", value = blend.skinMix, minimum = 0, maximum = 1, step = 0.05 },
        { id = "eyes", short = "E1", label = "Eye Color", name = "Eye Color", kind = "eyeColor", value = GetPedEyeColor(ped), minimum = 0, maximum = 8, step = 1 },
        { id = "noseWidth", short = "N1", label = "Nose Width", name = "Nose Width", kind = "faceFeature", feature = 0, value = GetPedFaceFeature(ped, 0), minimum = -1, maximum = 1, step = 0.05 },
        { id = "noseHeight", short = "N2", label = "Nose Height", name = "Nose Height", kind = "faceFeature", feature = 1, value = GetPedFaceFeature(ped, 1), minimum = -1, maximum = 1, step = 0.05 },
        { id = "noseLength", short = "N3", label = "Nose Length", name = "Nose Length", kind = "faceFeature", feature = 2, value = GetPedFaceFeature(ped, 2), minimum = -1, maximum = 1, step = 0.05 },
        { id = "cheekHeight", short = "C1", label = "Cheek Height", name = "Cheek Height", kind = "faceFeature", feature = 8, value = GetPedFaceFeature(ped, 8), minimum = -1, maximum = 1, step = 0.05 },
        { id = "cheekWidth", short = "C2", label = "Cheek Width", name = "Cheek Width", kind = "faceFeature", feature = 9, value = GetPedFaceFeature(ped, 9), minimum = -1, maximum = 1, step = 0.05 },
        { id = "jawWidth", short = "J1", label = "Jaw Width", name = "Jaw Width", kind = "faceFeature", feature = 13, value = GetPedFaceFeature(ped, 13), minimum = -1, maximum = 1, step = 0.05 },
        { id = "chinLength", short = "J2", label = "Chin Length", name = "Chin Length", kind = "faceFeature", feature = 16, value = GetPedFaceFeature(ped, 16), minimum = -1, maximum = 1, step = 0.05 },
        { id = "brows", short = "B1", label = "Eyebrows", name = "Eyebrow Style", kind = "overlay", overlay = 2, value = overlayValue(ped, 2), minimum = -1, maximum = math.max(GetNumHeadOverlayValues(2) - 1, 0), step = 1 },
        { id = "beard", short = "B2", label = "Facial Hair", name = "Beard Style", kind = "overlay", overlay = 1, value = overlayValue(ped, 1), minimum = -1, maximum = math.max(GetNumHeadOverlayValues(1) - 1, 0), step = 1 },
        { id = "makeup", short = "M1", label = "Makeup", name = "Makeup Style", kind = "overlay", overlay = 4, value = overlayValue(ped, 4), minimum = -1, maximum = math.max(GetNumHeadOverlayValues(4) - 1, 0), step = 1 },
        { id = "hairStyle", short = "H1", label = "Hair Style", name = "Hair Style", kind = "hairStyle", value = GetPedDrawableVariation(ped, 2), minimum = 0, maximum = math.max(GetNumberOfPedDrawableVariations(ped, 2) - 1, 0), step = 1 },
        { id = "hairColor", short = "H2", label = "Hair Color", name = "Hair Color", kind = "hairColor", value = GetPedHairColor(ped), minimum = 0, maximum = math.max(GetNumHairColors() - 1, 63), step = 1 }
    }
    return categories
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

local function applyHeadBlend()
    local values = {}
    for _, item in ipairs(clothingItems) do
        if item.kind == "faceBlend" then values[item.field] = item.value end
    end
    SetPedHeadBlendData(
        PlayerPedId(), values.shapeFirst or 0, values.shapeSecond or 0, values.shapeThird or 0,
        values.skinFirst or 0, values.skinSecond or 0, values.skinThird or 0,
        values.shapeMix or 0.5, values.skinMix or 0.5, values.thirdMix or 0.0, false
    )
    if clothingPreviewPed and DoesEntityExist(clothingPreviewPed) then
        SetPedHeadBlendData(
            clothingPreviewPed, values.shapeFirst or 0, values.shapeSecond or 0, values.shapeThird or 0,
            values.skinFirst or 0, values.skinSecond or 0, values.skinThird or 0,
            values.shapeMix or 0.5, values.skinMix or 0.5, values.thirdMix or 0.0, false
        )
    end
end

applyAppearanceItem = function(targetPed, item)
    if not targetPed or not DoesEntityExist(targetPed) then return end
    if item.kind == "faceFeature" then
        SetPedFaceFeature(targetPed, item.feature, item.value)
    elseif item.kind == "eyeColor" then
        SetPedEyeColor(targetPed, item.value)
    elseif item.kind == "overlay" then
        local hairColor, hairHighlight = editorHairColors()
        applyHeadOverlay(targetPed, item.overlay, item.value, hairColor, hairHighlight)
    elseif item.kind == "hairStyle" then
        applyHairAppearance(targetPed)
    elseif item.kind == "hairColor" then
        applyHairAppearance(targetPed)
    end
end

applyEditorAppearance = function(targetPed)
    if not targetPed or not DoesEntityExist(targetPed) then return end

    -- Component 2 can reset native hair and overlay colors. Apply the complete
    -- hair state first, then overlays, then the hair color one final time.
    applyHairAppearance(targetPed)
    for _, item in ipairs(clothingItems) do
        if item.kind == "faceFeature" or item.kind == "eyeColor" then
            applyAppearanceItem(targetPed, item)
        end
    end
    for _, item in ipairs(clothingItems) do
        if item.kind == "overlay" then
            applyAppearanceItem(targetPed, item)
        end
    end
    local hairColor, hairHighlight = editorHairColors()
    applyHairColor(targetPed, hairColor, hairHighlight)
end

local function syncHairControls(changedItem)
    if changedItem.kind ~= "component" and changedItem.kind ~= "hairStyle" then return end
    if changedItem.kind == "component" and changedItem.slot ~= 2 then return end

    for _, item in ipairs(clothingItems) do
        if changedItem.kind == "component" and item.kind == "hairStyle" then
            item.value = changedItem.drawable
        elseif changedItem.kind == "hairStyle" and item.kind == "component" and item.slot == 2 then
            item.drawable = changedItem.value
            item.texture = item.texture or 0
            item.drawables = math.max(GetNumberOfPedDrawableVariations(PlayerPedId(), 2), 1)
        end
    end
end

local function openCustomClothing()
    XSPed.stop()
    local ped = PlayerPedId()
    local gender = activeCharacterData and activeCharacterData.charinfo and activeCharacterData.charinfo.gender or 0
    local model = XSAppearance.model(nil, gender)
    local settings = clothingPreviewSettings()
    if GetEntityModel(ped) ~= model and requestModel(model) then
        local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
        SetPlayerModel(PlayerId(), model)
        ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false, false)
        SetEntityHeading(ped, heading)
        SetEntityLoadCollisionFlag(ped, true)
        SetPedDefaultComponentVariation(ped)
        SetModelAsNoLongerNeeded(model)
    end
    placeOnSceneFloor(ped, settings.coords, settings.floorZ)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, true, false)
    SetEntityLocallyVisible(ped)
    ResetEntityAlpha(ped)
    SetEntityAlpha(ped, 255, false)
    SetEntityHasGravity(ped, false)
    clearClothingVisualEffects()
    clothingItems = appearanceCategories(ped)
    for _, item in ipairs(clothingCategories(ped)) do clothingItems[#clothingItems + 1] = item end
    clothingHeading = GetEntityHeading(ped)
    customClothingOpen = true
    if not createClothingPreview() then
        customClothingOpen = false
        SetEntityVisible(ped, true, false)
        SetEntityLocallyVisible(ped)
        ResetEntityAlpha(ped)
        SetEntityCollision(ped, true, true)
        SetEntityHasGravity(ped, true)
        SetEntityInvincible(ped, false)
        SetEntityCanBeDamaged(ped, true)
        SetPedCanBeTargetted(ped, true)
        SetPedCanRagdoll(ped, true)
        FreezeEntityPosition(ped, false)
        ClearFocus()
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "clothingClose" })
        print("[XS-MultiCharacter] Style Lab could not load a visible preview mannequin")
        return
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "clothingOpen", categories = clothingItems })
    if IsScreenFadedOut() then DoScreenFadeIn(250) end
end

local function continueFirstCharacter()
    if Config.FirstCharacter.apartments.enabled and XSBridge.openApartments(activeCharacterData or activeCharacter) then
        XSPed.begin(nil)
        return
    end
    spawnAt(Config.Spawn.default, "default")
end

local function finishCustomClothing()
    if not customClothingOpen then return end
    customClothingOpen = false
    waitingForClothing = false
    XSAppearance.saveCurrent()
    destroyClothingPreview()
    local ped = PlayerPedId()
    ResetEntityAlpha(ped)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetPedCanRagdoll(ped, true)
    FreezeEntityPosition(ped, false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "clothingClose" })
    if activeCharacterData then
        continueFirstCharacter()
    end
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
        removeScene()

        if Config.FirstCharacter.clothing.enabled and Config.FirstCharacter.clothing.custom == true then
            -- Move the real ped to the editor floor before it is ever made visible.
            -- This prevents the brief spawn at the default/underground login position.
            waitingForClothing = true
            DoScreenFadeIn(0)
            openCustomClothing()
            return
        end

        local ped = PlayerPedId()
        restoreGameplayPlayer(ped)
        DoScreenFadeIn(0)

        if Config.FirstCharacter.apartments.enabled and XSBridge.openApartments(activeCharacterData or activeCharacter) then
            XSPed.begin(nil)
            return
        end

        debugPrint('No apartment resource to hand the new character to, using the spawn and clothing fallback.')
        spawnAt(Config.Spawn.default, 'default')
        if Config.FirstCharacter.clothing.enabled and Config.FirstCharacter.clothing.mode ~= 'none' then
            waitingForClothing = true
            openClothingWhenClear()
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
    if not customClothingOpen or type(data) ~= "table" then cb({ ok = false }) return end
    local ped = PlayerPedId()
    for _, item in ipairs(clothingItems) do
        if item.id == data.id and item.kind == data.kind then
            if item.kind == "component" or item.kind == "prop" then
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
                local function applyItem(targetPed)
                    if not targetPed or not DoesEntityExist(targetPed) then return end
                    if item.kind == "component" then
                        SetPedComponentVariation(targetPed, item.slot, drawable, texture, 0)
                    elseif drawable < 0 then
                        ClearPedProp(targetPed, item.slot)
                    else
                        SetPedPropIndex(targetPed, item.slot, drawable, texture, true)
                    end
                end
                applyItem(ped)
                applyItem(clothingPreviewPed)
                syncHairControls(item)
                applyEditorAppearance(ped)
                applyEditorAppearance(clothingPreviewPed)
                cb({ ok = true, id = item.id, kind = item.kind, drawable = item.drawable, texture = item.texture, textures = item.textures })
                return
            end

            local value = tonumber(data.value) or item.value or item.minimum or 0
            value = math.max(item.minimum or 0, math.min(item.maximum or value, value))
            item.value = value
            if item.kind == "faceBlend" then
                applyHeadBlend()
            else
                applyAppearanceItem(ped, item)
                applyAppearanceItem(clothingPreviewPed, item)
            end
            syncHairControls(item)
            applyEditorAppearance(ped)
            applyEditorAppearance(clothingPreviewPed)
            cb({ ok = true, id = item.id, kind = item.kind, value = item.value })
            return
        end
    end
    cb({ ok = false })
end)

RegisterNUICallback("clothingRotate", function(data, cb)
    if customClothingOpen then
        clothingHeading = clothingHeading + (tonumber(data.direction) or 0) * 12.0
        if clothingPreviewPed and DoesEntityExist(clothingPreviewPed) then
            SetEntityHeading(clothingPreviewPed, clothingHeading % 360.0)
        end
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
    openCharacters()
end)
