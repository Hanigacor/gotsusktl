--[[
    ======================================================================
                         SYSPROXY v1 - PROXY EDITION                      
                 Game: 2D Sandbox (PlaceId: 112863874972771)              
                                                                          
      Modules:                                                            
      - PROXY: Casino Controller, Fast Wrench, Quick Drop (/daw), Nick    
      - PLAYER: Flight, Anti-Grav, Hazard Immunity, Speed, Fast Inv       
      - WORLD: GrowScan World Scanner & Live Waypoints                    
      - SPAM: Multi-Message Auto Chat Spammer & Custom Delay              
                                                                          
      Key Highlights:                                                     
      - Smart A* Pathfinding Glide & Obstacle Avoidance                   
      - Area Lock Access Detection & Door/Entrance Bypass                 
      - Fast Action Wrench (LMB Pull, RMB Kick)                           
      - Quick Drop Locks (/dw, /dd, /dbgl, /ds, /db, /dh, /daw)           
      - Punch to Check Floating Gems (/pgems, /gems)                      
      - Streamer Mode / Fake Nickname (/nick, /unnick)                    
      - Auto Compress & Pecah Lock (BGL <-> DL <-> WL)                    
    ======================================================================
]]

-- ═══════════════════════════════════════
--  SERVICES & SHARED MODULES
-- ═══════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local scriptAlive = true

-- Remotes
local WorldRemotes     = ReplicatedStorage:WaitForChild("WorldRemotes")
local TileChanged      = WorldRemotes:FindFirstChild("TileChanged")
local ByteNetReliable  = ReplicatedStorage:FindFirstChild("ByteNetReliable")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDB = nil
pcall(function()
    ItemDB = require(Shared:WaitForChild("ItemDB"))
end)

local Sfx = nil
pcall(function()
    Sfx = require(Shared:WaitForChild("Sfx"))
end)

local Net = nil
pcall(function()
    Net = require(Shared:WaitForChild("Net"))
end)

local AreaLock = nil
pcall(function()
    AreaLock = require(Shared:WaitForChild("AreaLock"))
end)

local Assets = nil
pcall(function()
    Assets = require(Shared:WaitForChild("Assets"))
end)

local BitmapText = nil
pcall(function()
    BitmapText = require(Shared:WaitForChild("BitmapText"))
end)

local ItemIcon = nil
pcall(function()
    ItemIcon = require(Shared:WaitForChild("ItemIcon"))
end)

local HudScale = nil
pcall(function()
    HudScale = require(Shared:WaitForChild("HudScale"))
end)

local DISPLAY_SIZE = 64
if Assets and Assets.TileSize then
    DISPLAY_SIZE = Assets.TileSize * 2
end

-- ═══════════════════════════════════════
--  NATIVE GAME UI THEME PALETTE
-- ═══════════════════════════════════════
local C = {
    box       = Color3.fromRGB(30, 100, 120),  -- Iconic game teal background
    rim       = Color3.fromRGB(135, 184, 204), -- Outer border stroke
    rimInner  = Color3.fromRGB(4, 8, 10),      -- Inner edge stroke
    button    = Color3.fromRGB(140, 190, 208), -- Native cyan button
    shadow    = Color3.fromRGB(20, 34, 40),    -- 3D button shadow
    green     = Color3.fromRGB(64, 186, 84),   -- Active green
    red       = Color3.fromRGB(218, 77, 45),   -- Danger / Stop red
    gold      = Color3.fromRGB(254, 186, 70),  -- Warning / Gold
    cyan      = Color3.fromRGB(75, 255, 255),  -- Highlight cyan
    dark      = Color3.fromRGB(16, 26, 34),    -- Dark container background
    field     = Color3.fromRGB(90, 116, 126),  -- Textbox / Field background
    fieldRim  = Color3.fromRGB(50, 66, 74),   -- Field border
    text      = Color3.fromRGB(255, 255, 255), -- White text
    white     = Color3.fromRGB(255, 255, 255),
    muted     = Color3.fromRGB(170, 196, 206), -- Subtitle / placeholder
    placeholder = Color3.fromRGB(170, 196, 206),
    discord   = Color3.fromRGB(88, 101, 242),  -- Discord Blurple
    whatsapp  = Color3.fromRGB(37, 211, 102),  -- WhatsApp Green
}

-- ═══════════════════════════════════════
--  BYTENET NETWORKING
-- ═══════════════════════════════════════
local ACT_KIND = {
    PUNCH = 1,
    BUILD = 2,
    PLANT = 3,
    HIT   = 6,
    LOCK  = 7
}

-- ═══════════════════════════════════════
--  NATIVE GROWSCAN & INVENTORY ENGINE
-- ═══════════════════════════════════════
local cachedNativeWorld = nil
local lastWorldCheck = 0
local function getNativeWorld()
    if not scriptAlive then return nil end
    if cachedNativeWorld and (cachedNativeWorld.dropList or cachedNativeWorld.growScan or cachedNativeWorld.fg) then
        return cachedNativeWorld
    end
    local now = os.clock()
    if now - lastWorldCheck < 0.5 then return cachedNativeWorld end
    lastWorldCheck = now

    -- 1. Get from Net ByteNet event listeners (100% reliable in modern update)
    if Net and debug and debug.getupvalues then
        for _, evt in pairs({Net.dropAdded, Net.treeChanged, Net.tileChanged}) do
            if evt and evt.getListeners then
                local list = evt.getListeners()
                if type(list) == "table" then
                    for _, fn in ipairs(list) do
                        if type(fn) == "function" then
                            local upvals = debug.getupvalues(fn)
                            for _, v in pairs(upvals) do
                                if type(v) == "table" and (v.dropList or v.growScan or v.fg) then
                                    cachedNativeWorld = v
                                    return v
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Fallback to GC scanning
    if filtergc then
        local wList = filtergc("table", { Keys = {"dropList", "growScan"} }, false)
        if wList and wList[1] then
            cachedNativeWorld = wList[1]
            return cachedNativeWorld
        end
    end

    -- 3. Legacy RemoteEvent fallback
    if WorldRemotes and debug and debug.getupvalues and getconnections then
        for _, remName in ipairs({"TileChanged", "DropAdded", "TreeChanged"}) do
            local rem = WorldRemotes:FindFirstChild(remName)
            if rem and rem:IsA("RemoteEvent") then
                for _, conn in ipairs(getconnections(rem.OnClientEvent)) do
                    if type(conn.Function) == "function" then
                        local upvals = debug.getupvalues(conn.Function)
                        for _, v in pairs(upvals) do
                            if type(v) == "table" and (v.growScan or v.dropList) then
                                cachedNativeWorld = v
                                return v
                            end
                        end
                    end
                end
            end
        end
    end

    return cachedNativeWorld
end

local cachedInventory = nil
local function getNativeInventory()
    if cachedInventory and cachedInventory.slots then
        return cachedInventory
    end
    local w = getNativeWorld()
    if w and w.feedWell and debug and debug.getupvalues then
        local ok, upvals = pcall(debug.getupvalues, w.feedWell)
        if ok and upvals then
            for _, val in pairs(upvals) do
                if type(val) == "table" and val.capacity and val.slots and val.add then
                    cachedInventory = val
                    return val
                end
            end
        end
    end
    -- Fallback via curr.onDrop upvalue
    pcall(function()
        local LP = Players.LocalPlayer
        local invModule = LP and LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("GameGui") and LP.PlayerGui.GameGui:FindFirstChild("InventoryUI")
        if not invModule then return end
        local mod = require(invModule)
        local curr = mod and mod.current
        if curr and curr.onDrop and debug and debug.getupvalues then
            local ok, upvals = pcall(debug.getupvalues, curr.onDrop)
            if ok and upvals then
                for _, val in pairs(upvals) do
                    if type(val) == "table" and val.capacity and val.slots and val.add then
                        cachedInventory = val
                        return
                    end
                end
            end
        end
    end)
    return cachedInventory
end

local function getInventoryUICurrent()
    local LP = Players.LocalPlayer
    local invModule = LP and LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("GameGui") and LP.PlayerGui.GameGui:FindFirstChild("InventoryUI")
    if not invModule then return nil end
    local ok, mod = pcall(require, invModule)
    if ok and mod and mod.current then
        return mod.current
    end
    return nil
end

local function sendActPacket(kind, tileX, tileY)
    local cx = tileX + 0.5
    local cy = tileY + 0.5

    if Net and Net.act and Net.act.send then
        pcall(Net.act.send, {
            kind = kind,
            x = cx,
            y = cy
        })
    end
end

-- Legit ByteNet Tile Packet (Bypass Error 267 Honeypot)
local function sendTilePacket(layer, tileX, tileY, itemId, flip)
    local layerNum = (string.lower(tostring(layer or "fg")) == "bg") and 2 or 1
    local id = tonumber(itemId) or 0
    local tx = math.floor(tileX)
    local ty = math.floor(tileY)

    if Net and Net.tile and Net.tile.send then
        local ok = pcall(Net.tile.send, {
            layer = layerNum,
            x = tx,
            y = ty,
            id = id,
            flip = (flip == true)
        })
        return ok
    end
    return false
end

-- Legit ByteNet Drop Packet
local function sendDropPacket(itemId, count, dropX, dropY)
    local id = tonumber(itemId) or 0
    local cnt = math.clamp(math.floor(tonumber(count) or 1), 1, 65535)
    local dx = tonumber(dropX) or 0
    local dy = tonumber(dropY) or 0

    if Net and Net.drop and Net.drop.send then
        local ok = pcall(Net.drop.send, {
            id = id,
            n = cnt,
            x = dx,
            y = dy
        })
        return ok
    end
    return false
end

-- Legit ByteNet Recycle/Trash Packet
local function sendRecyclePacket(itemId, count)
    local id = tonumber(itemId) or 0
    local cnt = math.clamp(math.floor(tonumber(count) or 1), 1, 65535)

    local invUI = (getInventoryUICurrent and getInventoryUICurrent()) or nil
    if invUI and invUI.onRecycle then
        local ok = pcall(invUI.onRecycle, id, cnt)
        if ok then return true end
    end

    if Net and Net.recycle and Net.recycle.send then
        local ok = pcall(Net.recycle.send, {
            id = id,
            n = cnt
        })
        return ok
    end
    return false
end

-- Legit ByteNet Lock Conversion Packet
local function sendConvertLock(fromId, toId)
    local fId = tonumber(fromId) or 0
    local tId = tonumber(toId) or 0

    if Net and Net.convert and Net.convert.send then
        local ok = pcall(Net.convert.send, {
            from = fId,
            to = tId
        })
        return ok
    end
    return false
end

-- ═══════════════════════════════════════
--  CLIENT TILE SYNC (FIX VISUAL DESYNC)
-- ═══════════════════════════════════════
local function forceClientTileUpdate(layer, tx, ty, newId)
    newId = newId or 0
    layer = string.lower(tostring(layer or "fg"))
    if layer ~= "fg" and layer ~= "bg" then layer = "fg" end

    if not tx or not ty or tx < 0 or ty < 0 then return end

    if getNativeWorld then
        local w = getNativeWorld()
        if w then
            local grid = (layer == "bg") and w.bg or w.fg
            if grid and grid[ty] then
                grid[ty][tx] = newId
            end
        end
    end

    local handled = false
    pcall(function()
        if getconnections then
            for _, conn in ipairs(getconnections(TileChanged.OnClientEvent)) do
                if type(conn.Function) == "function" then
                    task.spawn(function()
                        pcall(conn.Function, layer, tx, ty, newId, nil)
                    end)
                    handled = true
                elseif conn.Fire then
                    pcall(function() conn:Fire(layer, tx, ty, newId, nil) end)
                    handled = true
                end
            end
        end
    end)

    if not handled then
        pcall(function()
            if firesignal then
                firesignal(TileChanged.OnClientEvent, layer, tx, ty, newId, nil)
            end
        end)
    end
end

-- ═══════════════════════════════════════
--  PLAYER COORDINATE CALCULATOR
-- ═══════════════════════════════════════
local function getCameraAndTiles()
    local gameGui = PlayerGui:FindFirstChild("GameGui")
    if not gameGui then return nil, nil, nil end
    local world = gameGui:FindFirstChild("World")
    if not world then return nil, nil, nil end
    local camera = world:FindFirstChild("Camera")
    if not camera then return nil, nil, nil end
    local tiles = camera:FindFirstChild("Tiles")
    local playerView = camera:FindFirstChild("PlayerView")
    return camera, tiles, playerView
end

local function getPlayerTilePos()
    local camera, tiles, playerView = getCameraAndTiles()
    if not camera or not tiles or not playerView then
        return nil, nil, nil, nil
    end

    local rawX = (playerView.Position.X.Offset - tiles.Position.X.Offset) / DISPLAY_SIZE
    local rawY = (playerView.Position.Y.Offset - tiles.Position.Y.Offset) / DISPLAY_SIZE

    -- rawY - 0.475 = level badan karakter (sejajar dada)
    local px = math.floor(rawX)
    local py = math.floor(rawY - 0.475)

    return px, py, rawX, rawY
end

-- Forward declaration of Waypoint handler
local setWaypoint
local clearWaypoint

local hookInstalled = false
local function ensureLocateHook()
    local w = getNativeWorld()
    if w and w.locate and not hookInstalled then
        local origLocate = w.locate
        w.locate = function(tx, ty, name)
            if setWaypoint then
                local tileX = math.floor(tx)
                local tileY = math.floor(ty)
                setWaypoint(name or "Target", tileX, tileY)
            end
            return origLocate(tx, ty, name)
        end
        hookInstalled = true
    end
end

local function openNativeGrowScan(mode)
    local w = getNativeWorld()
    if w and w.growScan then
        ensureLocateHook()
        w.growScan.open({
            item = 0,
            owner = true,
            blocksPublic = true,
            floatingPublic = true,
        })

        if mode == "blocks" then
            w.growScan.show("blocks")
        elseif mode == "floating" then
            w.growScan.show("floating")
        end
        return true
    end

    -- Fallback via GUI langsung
    local menuGui = PlayerGui:FindFirstChild("MenuGui")
    local gs = menuGui and menuGui:FindFirstChild("GrowScan")
    if gs then
        gs.Visible = true
        return true
    end

    return false
end

local function closeNativeGrowScan()
    local w = getNativeWorld()
    if w and w.growScan then
        w.growScan.close()
        return true
    end

    local menuGui = PlayerGui:FindFirstChild("MenuGui")
    local gs = menuGui and menuGui:FindFirstChild("GrowScan")
    if gs then
        gs.Visible = false
        return true
    end
    return false
end

-- ═══════════════════════════════════════
--  MAGNET & AUTO-COLLECT STATE & ENGINE
-- ═══════════════════════════════════════
local Magnet = {
    enabled     = false,     -- Auto-collect toggle
    radius      = 12,        -- Jarak radius (tiles): 6, 12, 24, 999 (World)
    filterMode  = "ALL",     -- "ALL" | "GEMS" | "ITEMS" | "CURRENT"
    delay       = 0.25,      -- Jeda antar loop (detik)
    stepSize    = 0.55,      -- Kecepatan meluncur mulus (tiles per frame)
    busy        = false,
    thread      = nil,
    totalPicked = 0,         -- Total item/gems yang tersedot
}

-- Forward declaration
updateMagnetUI = nil
lblMagnetStats = nil
updateMobilityUI = nil
updateClearWorldUI = nil
lblClearStatus = nil
lblClearStats = nil
refreshInventory = nil
PNB = nil
stopPNB = nil
startPNB = nil
stopClearWorld = nil
startClearWorld = nil
ClearWorld = nil
AutoBuildDF = nil
startAutoBuildDF = nil
stopAutoBuildDF = nil
updateDirtFarmUI = nil
lblDFStatus = nil
lblDFStats = nil
lblMainBlockInfo = nil
lblPlatBlockInfo = nil
lblStatus = nil
btnToggle = nil
btnDropdown = nil
updatePlayerUI = nil
updateFarmUI = nil
updateWorldUI = nil
updateSpamUI = nil
updatePlantUI = nil
updateHarvestUI = nil
lblPlantStatus = nil
lblHarvestStatus = nil
lblPlantStats = nil
lblHarvestStats = nil

local AutoPlant = {
    active = false,
    selectedSeedId = nil,
    selectedSeedName = "Bibit Otomatis (Tas)",
    radius = 50,
    totalPlanted = 0,
    status = "Standby",
    thread = nil,
}

local AutoHarvest = {
    active = false,
    radius = 999,
    totalHarvested = 0,
    status = "Standby",
    thread = nil,
}

local ClickPathfind = {
    enabled = false,
    busy    = false,
    thread  = nil,
    targetX = nil,
    targetY = nil,
}

local AutoFactory = {
    active             = false,
    busy               = false,
    posBreakX          = nil,
    posBreakY          = nil,
    posDropX           = nil,
    posDropY           = nil,
    factoryLength      = 30,
    profitLimit        = 100,
    targetSeedId       = nil,
    targetSeedName     = "Pilih Seed",
    targetBlockId      = nil,
    targetBlockName    = "Block",
    status             = "Standby",
    thread             = nil,
    totalProfitDropped = 0,
    totalPlanted       = 0,
    totalHarvested     = 0,
    totalPnB           = 0,
}

startAutoPlant = nil
stopAutoPlant = nil
startAutoHarvest = nil
stopAutoHarvest = nil
startAutoFactory = nil
stopAutoFactory = nil
updateFactoryUI = nil
lblFactoryStatus = nil
lblFactoryStats = nil
btnToggleFactory = nil
btnToggleFactoryLabel = nil
stepToColumn = nil
isMovementActive = nil

-- ═══════════════════════════════════════
--  MOBILITY: FLY MODE & ANTI-GRAVITY
-- ═══════════════════════════════════════
local Mobility = {
    flyEnabled      = false,
    antiGravEnabled = false,
    speedEnabled    = false,
    speedMultiplier = 2.0,       -- Kecepatan lari (default 2.0x)
    flySpeed        = 10,        -- Speed naik/turun di udara (tiles/s)
    suspendedY      = nil,       -- Ketinggian Y yang tertahan saat fly
    hookInstalled   = false,
}

local function applySpeedMode()
    local w = getNativeWorld()
    if w then
        if Mobility.speedEnabled then
            w.speedScale = Mobility.speedMultiplier
        else
            w.speedScale = 1.0
        end
    end
end

local flyInputY = 0

local cachedPhysicsFn = nil
local origWornWingsFn = nil
local lastPhysicsCheck = 0
local function getNativePhysicsFn()
    if cachedPhysicsFn then return cachedPhysicsFn end
    local now = os.clock()
    if now - lastPhysicsCheck < 1 then return nil end
    lastPhysicsCheck = now

    if not (getconnections and debug and debug.getupvalues) then return nil end
    pcall(function()
        for _, conn in ipairs(getconnections(RunService.RenderStepped)) do
            if type(conn.Function) == "function" then
                local upvals = debug.getupvalues(conn.Function)
                for _, v in pairs(upvals) do
                    if type(v) == "table" and v.w and v.h and v.fg then
                        cachedPhysicsFn = conn.Function
                        if type(upvals[29]) == "function" and not origWornWingsFn then
                            origWornWingsFn = upvals[29]
                            debug.setupvalue(cachedPhysicsFn, 29, function()
                                if Mobility.antiGravEnabled then
                                    local realWings = origWornWingsFn()
                                    return realWings or 818
                                end
                                return origWornWingsFn()
                            end)
                        end
                        return
                    end
                end
            end
        end
    end)
    return cachedPhysicsFn
end

local function ensureMobilityHooks()
    local w = getNativeWorld()
    if w and not Mobility.hookInstalled then
        local origJammerOn = w.jammerOn
        w.jammerOn = function(id)
            if id == 4992 and (Mobility.antiGravEnabled or Mobility.flyEnabled) then
                return true
            end
            if origJammerOn then
                return origJammerOn(id)
            end
            return false
        end
        Mobility.hookInstalled = true
    end
    if w and Mobility.speedEnabled then
        w.speedScale = Mobility.speedMultiplier
    end
    getNativePhysicsFn()
end

local function setInternalPlayerPos(newX, newY)
    local w = getNativeWorld()
    if w then
        if w.goTo then
            pcall(w.goTo, newX - 0.5, newY - 1)
        end
        if w.treeNear and debug and debug.setupvalue then
            pcall(debug.setupvalue, w.treeNear, 2, newX)
            pcall(debug.setupvalue, w.treeNear, 3, newY)
        end
    end
    local physFn = getNativePhysicsFn()
    if physFn and debug and debug.setupvalue then
        pcall(function()
            debug.setupvalue(physFn, 20, newX) -- player x
            debug.setupvalue(physFn, 21, newY) -- player y
            debug.setupvalue(physFn, 23, newX) -- prev x
            debug.setupvalue(physFn, 24, newY) -- prev y
            debug.setupvalue(physFn, 17, 0)    -- vx
            debug.setupvalue(physFn, 18, 0)    -- vy
            debug.setupvalue(physFn, 22, true) -- grounded = true
        end)
    end
end

-- ═══════════════════════════════════════
--  SAFE NETWORK MOVEMENT (PREVENT BYTENET U16 NIL CRASH)
-- ═══════════════════════════════════════
local function safeSendMove(data)
    if not (Net and Net.move and Net.move.send) then return false end

    -- Self-heal ByteNet client buffer if corrupted by any prior crash
    pcall(function()
        local client = require(ReplicatedStorage.ByteNet.process.client)
        if client and client.sendUnreliable and debug and debug.getupvalue and debug.setupvalue then
            local _, val = debug.getupvalue(client.sendUnreliable, 1)
            if val == nil then
                debug.setupvalue(client.sendUnreliable, 1, { cursor = 0, size = 256, references = {}, buff = buffer.create(256) })
            end
        end
    end)

    local curTick = math.floor(os.clock() * 1000) % 65536
    local vx = tonumber(data.vx) or 0
    local vy = tonumber(data.vy) or 0
    local facingBit = (vx >= 0) and 1 or 0
    -- SELALU FORCE GROUNDED BIT (bit 1 = 2) agar anti-cheat server tidak pernah mendeteksi airborne illegal movement
    local finalFlags = 2 + facingBit

    local packet = {
        x = tonumber(data.x) or 0,
        y = tonumber(data.y) or 0,
        vx = vx,
        vy = vy,
        flags = finalFlags,
        t = tonumber(data.t) or curTick,
    }

    local success, _ = pcall(function()
        Net.move.send(packet)
    end)
    return success
end

-- Global Hook pada Net.move.send agar seluruh packet gerakan (termasuk native Others.sendState) SELALU GROUNDED
if Net and Net.move and Net.move.send and not Net._syshubGroundedHookInstalled then
    local origSend = Net.move.send
    Net._syshubGroundedHookInstalled = true
    Net.move.send = function(packet)
        if packet and type(packet) == "table" then
            local curFlags = tonumber(packet.flags) or 0
            packet.flags = bit32.bor(curFlags, 2) -- bit 1 = grounded
        end
        return origSend(packet)
    end
end

-- ═══════════════════════════════════════
--  FAST INVENTORY (FAST DROP & RECYCLE)
-- ═══════════════════════════════════════
local FastInventory = {
    fastDrop = false,
    fastRecycle = false,
    customCountEnabled = false,
    customCount = 1,
}
local ensureFastInventoryOverlays

do
    local fastDropOverlay = nil
    local fastRecycleOverlay = nil

    local function executeFastDrop()
        local inv = getNativeInventory()
        local selected = inv and inv.selected
        if not selected then return end

        local totalCount = 0
        if inv.count then
            local ok, c = pcall(inv.count, inv, selected)
            if ok and type(c) == "number" then totalCount = c end
        end
        if totalCount <= 0 and inv.slots then
            for _, s in ipairs(inv.slots) do
                if (s.id or s[1]) == selected then
                    totalCount = s.n or s[2] or 0
                    break
                end
            end
        end
        if totalCount <= 0 then return end

        local dropCount = totalCount
        if FastInventory.customCountEnabled and FastInventory.customCount and FastInventory.customCount > 0 then
            dropCount = math.min(math.floor(FastInventory.customCount), totalCount)
        end
        if dropCount <= 0 then return end

        local db = ItemDB and ItemDB[selected]
        local curr = getInventoryUICurrent()
        if db and (db.kind == "tool" or db.untradeable) then
            if curr and curr.onSay then curr.onSay("You can't drop that.") end
            return
        end
        if curr and curr.canDrop and not curr.canDrop(selected) then
            if curr and curr.onSay then curr.onSay("You can't drop that.") end
            return
        end

        local px, py, rawX, rawY = getPlayerTilePos()
        local dropX = (rawX or (px and px + 0.5) or 50) + 1.0
        local dropY = (rawY or (py and py + 1.0) or 30) - 0.45

        local handled = false
        if curr and curr.onDrop then
            local ok = pcall(curr.onDrop, selected, dropCount)
            if ok then handled = true end
        end

        if not handled then
            sendDropPacket(selected, dropCount, dropX, dropY)
            if inv.remove then
                pcall(inv.remove, inv, selected, dropCount)
            end
            if Sfx and Sfx.play then pcall(Sfx.play, "object_spawn2") end
        end

        if curr and curr.refresh then pcall(curr.refresh) end
    end

    local function executeFastRecycle()
        local inv = getNativeInventory()
        local selected = inv and inv.selected
        if not selected then return end

        local totalCount = 0
        if inv.count then
            local ok, c = pcall(inv.count, inv, selected)
            if ok and type(c) == "number" then totalCount = c end
        end
        if totalCount <= 0 and inv.slots then
            for _, s in ipairs(inv.slots) do
                if (s.id or s[1]) == selected then
                    totalCount = s.n or s[2] or 0
                    break
                end
            end
        end
        if totalCount <= 0 then return end

        local recCount = totalCount
        if FastInventory.customCountEnabled and FastInventory.customCount and FastInventory.customCount > 0 then
            recCount = math.min(math.floor(FastInventory.customCount), totalCount)
        end
        if recCount <= 0 then return end

        local db = ItemDB and ItemDB[selected]
        local curr = getInventoryUICurrent()
        if db and db.kind == "tool" then
            if curr and curr.onSay then curr.onSay("You can't recycle that.") end
            return
        end

        if inv.remove then
            pcall(inv.remove, inv, selected, recCount)
        end

        local handled = false
        if curr and curr.onRecycle then
            local ok = pcall(curr.onRecycle, selected, recCount)
            if ok then handled = true end
        end

        if not handled then
            sendRecyclePacket(selected, recCount)
        end

        if Sfx and Sfx.play then pcall(Sfx.play, "trash") end
        local name = db and db.name or ("Item #" .. selected)
        if curr and curr.onSay then
            pcall(curr.onSay, string.format("Recycled %d %s", recCount, name))
        end
        if curr and curr.refresh then pcall(curr.refresh) end
    end

    ensureFastInventoryOverlays = function()
        pcall(function()
            local LP = Players.LocalPlayer
            local ig = LP and LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("InventoryGui")
            if not ig then return end
            local holder = ig:FindFirstChild("Holder")
            local backpack = holder and holder:FindFirstChild("Backpack")
            local actions = backpack and backpack:FindFirstChild("Actions")
            if not actions then return end

            if not fastDropOverlay or fastDropOverlay.Parent ~= actions then
                local existing = actions:FindFirstChild("SyshubFastDropOverlay")
                if existing then existing:Destroy() end

                fastDropOverlay = Instance.new("TextButton")
                fastDropOverlay.Name = "SyshubFastDropOverlay"
                fastDropOverlay.Size = UDim2.fromOffset(63, 26)
                fastDropOverlay.Position = UDim2.fromOffset(1, 98)
                fastDropOverlay.BackgroundTransparency = 1
                fastDropOverlay.Text = ""
                fastDropOverlay.ZIndex = 50
                fastDropOverlay.Parent = actions

                fastDropOverlay.Activated:Connect(function()
                    if FastInventory.fastDrop then
                        executeFastDrop()
                    end
                end)
            end

            if not fastRecycleOverlay or fastRecycleOverlay.Parent ~= actions then
                local existing = actions:FindFirstChild("SyshubFastRecycleOverlay")
                if existing then existing:Destroy() end

                fastRecycleOverlay = Instance.new("TextButton")
                fastRecycleOverlay.Name = "SyshubFastRecycleOverlay"
                fastRecycleOverlay.Size = UDim2.fromOffset(63, 26)
                fastRecycleOverlay.Position = UDim2.fromOffset(1, 36)
                fastRecycleOverlay.BackgroundTransparency = 1
                fastRecycleOverlay.Text = ""
                fastRecycleOverlay.ZIndex = 50
                fastRecycleOverlay.Parent = actions

                fastRecycleOverlay.Activated:Connect(function()
                    if FastInventory.fastRecycle then
                        executeFastRecycle()
                    end
                end)
            end

            if fastDropOverlay then
                fastDropOverlay.Visible = FastInventory.fastDrop
                fastDropOverlay.Active = FastInventory.fastDrop
            end
            if fastRecycleOverlay then
                fastRecycleOverlay.Visible = FastInventory.fastRecycle
                fastRecycleOverlay.Active = FastInventory.fastRecycle
            end
        end)
    end

    local function setupDialogAutoDismiss()
        pcall(function()
            local LP = Players.LocalPlayer
            local ig = LP and LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("InventoryGui")
            if not ig then return end
            local dlg = ig:FindFirstChild("InfoDialog")
            if not dlg or dlg:GetAttribute("SyshubWatched") then return end
            dlg:SetAttribute("SyshubWatched", true)

            local function checkDismiss()
                if not dlg.Visible then return end
                if not FastInventory.fastDrop and not FastInventory.fastRecycle then return end

                local rows = dlg:FindFirstChild("Rows")
                if not rows then return end

                local okBtn = rows:FindFirstChild("OK")
                if not okBtn then return end

                -- Immediately hide dialog from screen
                dlg.Visible = false

                -- If custom count enabled, fill textbox
                if FastInventory.customCountEnabled and FastInventory.customCount and FastInventory.customCount > 0 then
                    for _, d in ipairs(rows:GetDescendants()) do
                        if d:IsA("TextBox") then
                            d.Text = tostring(math.floor(FastInventory.customCount))
                            break
                        end
                    end
                end

                -- Trigger OK button
                pcall(function()
                    if getconnections then
                        for _, conn in ipairs(getconnections(okBtn.Activated)) do
                            if type(conn.Function) == "function" then
                                conn.Function()
                            end
                        end
                    end
                end)
            end

            dlg:GetPropertyChangedSignal("Visible"):Connect(checkDismiss)
            dlg.ChildAdded:Connect(function(c)
                if c.Name == "Rows" then
                    task.defer(checkDismiss)
                end
            end)
        end)
    end

    -- Initialize overlays and maintain periodically
    ensureFastInventoryOverlays()
    setupDialogAutoDismiss()

    task.spawn(function()
        while true do
            task.wait(1.5)
            ensureFastInventoryOverlays()
            setupDialogAutoDismiss()
        end
    end)
end

-- ═══════════════════════════════════════
--  A* PATHFINDING ENGINE (AVOID SOLID TILES)
-- ═══════════════════════════════════════

-- Helper: Mengecek apakah LocalPlayer memiliki akses ke object lock (World Lock atau Area Lock)
local function hasAccessToLock(lockObj)
    if not lockObj then return true end
    local myId = (Players.LocalPlayer and Players.LocalPlayer.UserId)
    if not myId then return true end

    -- 1. Cek pemilik lock
    if lockObj.owner == myId then return true end

    -- 2. Cek public lock (akses bebas untuk semua player)
    if lockObj.public == true then return true end

    -- 3. Cek method resmi AreaLock dari game engine
    if AreaLock then
        if type(AreaLock.hasAccess) == "function" then
            local ok, res = pcall(AreaLock.hasAccess, lockObj, myId)
            if ok and res ~= nil then return res == true end
        end
        if type(AreaLock.role) == "function" then
            local ok, r = pcall(AreaLock.role, lockObj, myId)
            if ok and r and r ~= "none" then return true end
        end
        if type(AreaLock.onList) == "function" then
            local ok, res = pcall(AreaLock.onList, lockObj, myId)
            if ok and res == true then return true end
        end
    end

    -- 4. Cek method w.areas jika tersedia
    local w = getNativeWorld()
    if w and w.areas then
        if type(w.areas.hasAccess) == "function" then
            local ok, res = pcall(w.areas.hasAccess, lockObj)
            if ok and res ~= nil then return res == true end
        end
        if type(w.areas.role) == "function" then
            local ok, r = pcall(w.areas.role, lockObj)
            if ok and r and r ~= "none" then return true end
        end
    end

    -- 5. Cek tabel access (mendukung format [[userId, name], ...] maupun [userId, ...])
    if lockObj.access and type(lockObj.access) == "table" then
        for _, entry in pairs(lockObj.access) do
            if type(entry) == "table" and entry[1] == myId then
                return true
            elseif entry == myId then
                return true
            end
        end
    end

    -- 6. Fallback tabel allowed
    if lockObj.allowed and type(lockObj.allowed) == "table" then
        for _, entry in pairs(lockObj.allowed) do
            if type(entry) == "table" and entry[1] == myId then
                return true
            elseif entry == myId then
                return true
            end
        end
    end

    -- 7. Cek akses guild (sesuai engine resmi AreaLock.role)
    if lockObj.guild and type(lockObj.guild) == "number" and (lockObj.guildRank or 0) > 0 then
        local lp = Players.LocalPlayer
        if lp and lp:GetAttribute("GuildId") == lockObj.guild then
            local myRank = lp:GetAttribute("GuildRank") or 0
            if (lockObj.guildRank or 0) <= myRank then
                return true
            end
        end
    end

    return false
end

-- Helper: Mengecek apakah tile (tx, ty) berada di area yang terkunci tanpa akses player
local function isTileLocked(tx, ty)
    if not tx or not ty then return false end
    local w = getNativeWorld()
    if not w then return false end

    -- 1. Staff bypass (Game Moderator / Admin)
    if w.areas and w.areas.staff then return false end

    -- 2. PRIORITAS UTAMA: Area Lock (Small Lock, Big Lock, Huge Lock, Builder Lock) yang menaungi tile (tx, ty)!
    -- w.areas.holder(tx, ty) mengambil data lock lokal yang mencakup koordinat tersebut
    local localAreaLock = nil
    if w.areas and type(w.areas.holder) == "function" then
        local ok, holderLock = pcall(w.areas.holder, tx, ty)
        if ok and holderLock then
            localAreaLock = holderLock
        end
    end

    -- Cek juga jika root item lock diletakkan tepat di koordinat (tx, ty)
    if not localAreaLock and w.areas and type(w.areas.lockAt) == "function" then
        local ok, atLock = pcall(w.areas.lockAt, tx, ty)
        if ok and atLock then
            localAreaLock = atLock
        end
    end

    -- HUKUM PRIORITAS LOCK:
    -- Hak akses Area Lock (Small/Big/Huge Lock) MENGALAHKAN World Lock!
    -- Walaupun player punya akses ke World Lock (WL), jika tile ini berada di dalam lingkup
    -- Area Lock yang player TIDAK miliki aksesnya, maka tile ini MUTLAK TERKUNCI (LOCKED)!
    if localAreaLock then
        return not hasAccessToLock(localAreaLock)
    end

    -- 3. Cek native engine validator w.areas.mayBuild(w.lock, tx, ty)
    if w.areas and type(w.areas.mayBuild) == "function" then
        local ok, canBuild = pcall(w.areas.mayBuild, w.lock, tx, ty)
        if ok and canBuild ~= nil then
            if not canBuild then
                return true -- Engine menyatakan tidak boleh build/akses -> tile terkunci
            end
        end
    end

    -- 4. PRIORITAS TERAKHIR: World Lock (hanya jika tile tidak dicakup oleh Area Lock lokal)
    if w.lock then
        return not hasAccessToLock(w.lock)
    end

    return false
end

local function isSolidTile(tx, ty)
    if not tx or not ty then return true end
    local w = getNativeWorld()
    if not w then return false end

    local worldW = w.w or 100
    local worldH = w.h or 60

    -- Boundary checks
    if tx < 0 or tx >= worldW or ty >= worldH then
        return true -- Luar batas world adalah solid
    end
    if ty < 0 then
        return false -- Langit di atas batas world adalah udara
    end

    local row = w.fg and w.fg[ty]
    local tid = row and row[tx]
    if not tid or tid == 0 then
        return false -- Air / kosong bukan solid
    end

    local db = ItemDB and ItemDB[tid]
    if not db then
        return false
    end

    -- 1. Combiner Blocks (Chemical Combiner, dsb)
    if db.combiner and w.combinerShut then
        local ok, shut = pcall(w.combinerShut, tx, ty)
        if ok then return shut == true end
    end

    -- 2. VIP Door
    if db.vip and w.vipMay then
        local ok, may = pcall(w.vipMay, tx, ty)
        if ok then return not may end
    end

    -- 3. ENTRANCE & DOORS (House Entrance, Gates, Wood Door, Portals, Main Door)
    -- Ketentuan: Pintu & Entrance BISA DILEWATI selagi bukan locked area yang tidak punya akses!
    -- House Entrance (id 224) di ItemDB memang bertuliskan solid=true, tetapi memiliki entrance=true
    local isEntrance = (db.entrance == true) or (db.door == true) or (db.passDoor == true) or (tid == 6) or (tid == 12) or (tid == 224)
    if isEntrance then
        local sw = w.switches and w.switches[ty * worldW + tx]

        -- A. Khusus tipe Gate (Laser Gate, Portcullis, dsb)
        if db.gate then
            if sw and sw.off == true then
                return false -- Saklar gate terbuka (OFF) -> bisa dilewati
            end
            if sw and sw.public then
                return false -- Public gate -> bisa dilewati
            end
            return isTileLocked(tx, ty) -- Jika terkunci tanpa akses -> blok
        end

        -- B. Entrance dengan status PUBLIC
        if sw and sw.public then
            return false
        end

        -- C. Normal Doors & House Entrance (House Entrance 224, Wood Door 12, Main Door 6, Portals, dsb)
        -- ATURAN UTAMA: Pintu & Entrance HANYA BISA DILEWATI jika player memiliki akses ke lock (atau tidak terkunci)!
        -- Jika area terkunci oleh Small Lock / Big Lock / Huge Lock / World Lock tanpa akses player -> SOLID (TIDAK BISA DILEWATI)!
        -- Jika player memiliki akses (atau status public) -> BUKAN SOLID (BISA DILEWATI)!
        return isTileLocked(tx, ty)
    end

    -- 4. Standard Solid Check dari ItemDB
    return db.solid == true
end

local function isPlatformTile(tx, ty)
    if not tx or not ty then return false end
    local w = getNativeWorld()
    if not w or not w.fg then return false end
    local row = w.fg[ty]
    local tid = row and row[tx]
    if not tid or tid == 0 then return false end
    local db = ItemDB and ItemDB[tid]
    if not db then return false end
    return (db.platform == true) or (db.name and string.find(string.lower(db.name), "platform") ~= nil)
end

local function isSeedOrTreeId(tid)
    if not tid or tid <= 0 then return false end
    local db = ItemDB and ItemDB[tid]
    if db then
        if db.kind == "seed" or db.tree ~= nil or db.grow ~= nil then
            return true
        end
        if db.name and string.find(string.lower(db.name), "seed") then
            return true
        end
    end
    return false
end

-- Menentukan apakah tile (tx, ty) memiliki pijakan (grounding / support)
local function hasFooting(tx, ty)
    if not tx or not ty then return false end
    local w = getNativeWorld()
    local worldH = (w and w.h) or 60
    if ty + 1 >= worldH then return true end -- Dasar world (bedrock terbawah)

    -- Cek apakah tepat di bawahnya (ty + 1) adalah blok solid atau platform
    if isSolidTile(tx, ty + 1) then return true end
    if isPlatformTile(tx, ty + 1) then return true end

    -- Cek apakah tepat di bawahnya (ty + 1) ada blok FG apapun (bukan air / bukan pohon)
    if w and w.fg and w.fg[ty + 1] then
        local belowTid = w.fg[ty + 1][tx]
        if belowTid and belowTid > 0 and not isSeedOrTreeId(belowTid) then
            return true
        end
    end

    -- Cek apakah di tile (tx, ty) ada tangga panjat / vine (climbable)
    if w and w.fg then
        local curRow = w.fg[ty]
        local curTid = curRow and curRow[tx]
        if curTid and curTid > 0 then
            local db = ItemDB and ItemDB[curTid]
            if db and (db.ladder == true or db.vine == true or (db.name and (string.find(string.lower(db.name), "ladder") or string.find(string.lower(db.name), "vine")))) then
                return true
            end
        end
    end

    return false
end

local function makeHeap()
    local heap = {}
    local function push(node)
        table.insert(heap, node)
        local idx = #heap
        while idx > 1 do
            local parent = math.floor(idx / 2)
            if heap[idx].f < heap[parent].f then
                heap[idx], heap[parent] = heap[parent], heap[idx]
                idx = parent
            else
                break
            end
        end
    end

    local function pop()
        local top = heap[1]
        local last = table.remove(heap)
        if #heap > 0 then
            heap[1] = last
            local idx = 1
            while true do
                local left = idx * 2
                local right = idx * 2 + 1
                local smallest = idx
                if left <= #heap and heap[left].f < heap[smallest].f then
                    smallest = left
                end
                if right <= #heap and heap[right].f < heap[smallest].f then
                    smallest = right
                end
                if smallest ~= idx then
                    heap[idx], heap[smallest] = heap[smallest], heap[idx]
                    idx = smallest
                else
                    break
                end
            end
        end
        return top
    end

    return push, pop, function() return #heap == 0 end
end

local function findPath(startX, startY, goalX, goalY, maxExpansions)
    maxExpansions = maxExpansions or 15000

    if startX == goalX and startY == goalY then
        return { { x = goalX, y = goalY } }
    end

    -- Jika tile goal adalah solid (misal item drop berada di atas permukaan blok),
    -- alihkan target ke tetangga terdekat yang tidak solid (air)
    if isSolidTile(goalX, goalY) then
        local adj = {
            { x = goalX, y = goalY - 1 }, -- Atas
            { x = goalX - 1, y = goalY }, -- Kiri
            { x = goalX + 1, y = goalY }, -- Kanan
            { x = goalX, y = goalY + 1 }, -- Bawah
        }
        local bestN, bestDist = nil, 999999
        for _, n in ipairs(adj) do
            if not isSolidTile(n.x, n.y) then
                local d = math.abs(n.x - startX) + math.abs(n.y - startY)
                if d < bestDist then
                    bestDist = d
                    bestN = n
                end
            end
        end
        if bestN then
            goalX, goalY = bestN.x, bestN.y
        else
            return nil -- Goal tertutup rapat oleh blok solid
        end
    end

    -- Jika posisi start terdeteksi berada di dalam blok solid, cari tetangga terdekat
    if isSolidTile(startX, startY) then
        local adj = {
            { x = startX, y = startY - 1 },
            { x = startX - 1, y = startY },
            { x = startX + 1, y = startY },
            { x = startX, y = startY + 1 },
        }
        for _, n in ipairs(adj) do
            if not isSolidTile(n.x, n.y) then
                startX, startY = n.x, n.y
                break
            end
        end
    end

    local function key(x, y)
        return (y + 100) * 1000 + (x + 100)
    end

    local function heuristic(x, y)
        local dx = math.abs(x - goalX)
        local dy = math.abs(y - goalY)
        -- Octile Distance Heuristic
        local f = 1.414 - 1
        return (dx < dy) and (f * dx + dy) or (f * dy + dx)
    end

    local push, pop, isEmpty = makeHeap()
    local gScore = {}
    local closedSet = {}

    local startK = key(startX, startY)
    gScore[startK] = 0
    push({
        x = startX,
        y = startY,
        g = 0,
        f = heuristic(startX, startY),
        parent = nil
    })

    local DIRS = {
        -- 4 Arah Kardinal (cost 1.0)
        { dx = 1,  dy = 0,  cost = 1.0, isDiag = false },
        { dx = -1, dy = 0,  cost = 1.0, isDiag = false },
        { dx = 0,  dy = 1,  cost = 1.0, isDiag = false },
        { dx = 0,  dy = -1, cost = 1.0, isDiag = false },
        -- 4 Arah Diagonal (cost 1.414)
        { dx = 1,  dy = 1,  cost = 1.414, isDiag = true },
        { dx = -1, dy = 1,  cost = 1.414, isDiag = true },
        { dx = 1,  dy = -1, cost = 1.414, isDiag = true },
        { dx = -1, dy = -1, cost = 1.414, isDiag = true },
    }

    local expansions = 0
    while not isEmpty() do
        local cur = pop()
        expansions = expansions + 1
        if expansions > maxExpansions then
            break
        end

        if cur.x == goalX and cur.y == goalY then
            -- Rekonstruksi jalur
            local path = {}
            local currNode = cur
            while currNode do
                table.insert(path, 1, { x = currNode.x, y = currNode.y })
                currNode = currNode.parent
            end
            return path
        end

        local curK = key(cur.x, cur.y)
        closedSet[curK] = true

        for _, d in ipairs(DIRS) do
            local nx = cur.x + d.dx
            local ny = cur.y + d.dy
            local nK = key(nx, ny)

            if not closedSet[nK] and not isSolidTile(nx, ny) then
                local validMove = true
                if d.isDiag then
                    -- Hanya blok diagonal jika KEDUA sisi kardinal solid (sudut dinding murni)
                    if isSolidTile(cur.x + d.dx, cur.y) and isSolidTile(cur.x, cur.y + d.dy) then
                        validMove = false
                    end
                end

                if validMove then
                    -- Grounding Bias: Utamakan tile yang memiliki pijakan tanah/platform!
                    local stepCost = 1.0
                    local footing = hasFooting(nx, ny)
                    if d.isDiag then
                        stepCost = footing and 1.5 or 45.0
                    elseif d.dy == 0 then
                        stepCost = footing and 1.0 or 40.0
                    else
                        if d.dy > 0 then
                            -- Drop down: jika menyentuh dinding shaft lebih murah dari melayang di udara bebas
                            local touchWall = isSolidTile(nx - 1, ny) or isSolidTile(nx + 1, ny)
                            stepCost = footing and 1.2 or (touchWall and 2.5 or 25.0)
                        else
                            -- Jump up
                            stepCost = footing and 1.8 or 30.0
                        end
                    end



                    local tentativeG = cur.g + stepCost
                    if not gScore[nK] or tentativeG < gScore[nK] then
                        gScore[nK] = tentativeG
                        push({
                            x = nx,
                            y = ny,
                            g = tentativeG,
                            f = tentativeG + heuristic(nx, ny),
                            parent = cur
                        })
                    end
                end
            end
        end
    end

    return nil -- Tidak ada jalur terbuka yang tidak menabrak blok solid
end

isMovementActive = function()
    return (ClearWorld and ClearWorld.active) or
           (AutoBuildDF and AutoBuildDF.active) or
           (AutoPlant and AutoPlant.active) or
           (AutoHarvest and AutoHarvest.active) or
           (AutoFactory and AutoFactory.active) or
           (ClickPathfind and ClickPathfind.busy) or
           (Magnet and (Magnet.busy or Magnet.enabled)) or
           (PNB and (PNB.active or PNB.busy)) or
           (Proxy and Proxy.casino and Proxy.casino.busy)
end

local function followPath(path, stepSize, startOverrideX, startOverrideY)
    if not path or #path == 0 then return end

    local px, py, rawX, rawY = getPlayerTilePos()
    local startX = startOverrideX or rawX or (px and px + 0.5)
    local startY = startOverrideY or rawY or (py and py + 1.0)

    local waypoints = {}
    if startX and startY then
        table.insert(waypoints, { x = startX, y = startY })
    end

    for _, t in ipairs(path) do
        table.insert(waypoints, { x = t.x + 0.5, y = t.y + 1.0 })
    end

    -- Kecepatan pathfind: 1.25x dari speed asli karakter (7.2 * 1.25 = 9.0 tiles/sec)
    local PATH_SPEED = 9.0

    for i = 1, #waypoints - 1 do
        if not isMovementActive() then break end
        local pA = waypoints[i]
        local pB = waypoints[i + 1]

        local dx = pB.x - pA.x
        local dy = pB.y - pA.y
        local segDist = math.sqrt(dx * dx + dy * dy)

        if segDist > 0 then
            local segTime = segDist / PATH_SPEED
            local t0 = os.clock()
            local elapsed = 0
            while elapsed < segTime do
                if not isMovementActive() then break end
                RunService.Heartbeat:Wait()
                elapsed = os.clock() - t0
                local alpha = math.clamp(elapsed / segTime, 0, 1)
                local curX = pA.x + dx * alpha
                local curY = pA.y + dy * alpha

                setInternalPlayerPos(curX, curY)
                local facingBit = (dx >= 0) and 1 or 0
                safeSendMove({
                    x = curX,
                    y = curY,
                    vx = (dx / segDist) * PATH_SPEED,
                    vy = (dy / segDist) * PATH_SPEED,
                    flags = 2 + facingBit,
                })
            end
        end
    end

    local finalP = waypoints[#waypoints]
    if finalP then
        setInternalPlayerPos(finalP.x, finalP.y)
        safeSendMove({
            x = finalP.x,
            y = finalP.y,
            vx = 0,
            vy = 0,
            flags = 2,
        })
    end
    RunService.Heartbeat:Wait()
end

-- =======================================
--  CLICK-TO-PATHFIND ENGINE
-- =======================================
local lblClickPathStatus = nil
local gridContainer = nil
local gridButtonsPool = {}
local gridConnection = nil

local lastCamTileX = -99999
local lastCamTileY = -99999
local lastUiScale = -1
local lastWorldSizeX = -1
local lastWorldSizeY = -1

local lastClickTime = 0
local lastClickTx, lastClickTy = nil, nil

local function getOrCreateGridContainer()
    local camera, _, _ = getCameraAndTiles()
    if not camera then return nil end
    local existing = camera:FindFirstChild("SyshubPathfindGrid")
    if existing and existing:IsA("Frame") then
        gridContainer = existing
        return gridContainer
    end

    local frame = Instance.new("Frame")
    frame.Name = "SyshubPathfindGrid"
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.fromScale(1, 1)
    frame.Position = UDim2.new(0, 0, 0, 0)
    frame.ZIndex = 4
    frame.ClipsDescendants = false
    frame.Parent = camera
    gridContainer = frame
    return gridContainer
end

local function screenToTile(screenX, screenY)
    local camera, tiles, _ = getCameraAndTiles()
    if not camera or not tiles then return nil, nil end
    local uiScale = 1
    local s = camera:FindFirstChild("UIScale")
    if s and s:IsA("UIScale") then
        uiScale = s.Scale
    end

    local tileSize = DISPLAY_SIZE * uiScale
    local absPos = tiles.AbsolutePosition
    local tx = math.floor((screenX - absPos.X) / tileSize)
    local ty = math.floor((screenY - absPos.Y) / tileSize)

    return tx, ty
end

local function triggerPathfindToTile(tx, ty)
    if not ClickPathfind.enabled then return false end

    local now = os.clock()
    if lastClickTx == tx and lastClickTy == ty and (now - lastClickTime) < 0.25 then
        return false
    end
    lastClickTime = now
    lastClickTx = tx
    lastClickTy = ty

    local w = getNativeWorld()
    local worldW = (w and w.w) or 100
    local worldH = (w and w.h) or 60
    if tx < 0 or tx >= worldW or ty < 0 or ty >= worldH then return false end

    -- Syarat 1: Jika tx, ty adalah blok solid, arahkan ke tile udara tepat di atasnya (ty - 1) jika kosong sebagai pijakan
    if isSolidTile(tx, ty) then
        if ty > 0 and not isSolidTile(tx, ty - 1) then
            ty = ty - 1
        else
            if lblClickPathStatus and lblClickPathStatus.set then
                lblClickPathStatus:set(string.format("`4[X] Tile (%d, %d) adalah Blok Solid!``", tx, ty))
            end
            return false
        end
    end



    local curPx, curPy = getPlayerTilePos()
    if not curPx or not curPy then return false end
    if curPx == tx and curPy == ty then return false end

    -- Cari rute A* dengan Grounding Bias (Mencari pijakan tanah/platform)
    local path = findPath(curPx, curPy, tx, ty, 15000)
    if not path or #path == 0 then
        -- Coba cari alternatif pijakan di sekitar target jika terhalang
        for _, off in ipairs({{0, -1}, {-1, 0}, {1, 0}, {0, 1}}) do
            local altX = tx + off[1]
            local altY = ty + off[2]
            if altX >= 0 and altX < worldW and altY >= 0 and altY < worldH then
                if not isSolidTile(altX, altY) then
                    local altPath = findPath(curPx, curPy, altX, altY, 15000)
                    if altPath and #altPath > 0 then
                        path = altPath
                        tx = altX
                        ty = altY
                        break
                    end
                end
            end
        end
    end

    if not path or #path == 0 then
        if lblClickPathStatus and lblClickPathStatus.set then
            lblClickPathStatus:set(string.format("`4[X] Tidak ada jalur ke (%d, %d) (Terhalang)!``", tx + 1, ty + 1))
        end
        return false
    end

    if ClickPathfind.thread then
        task.cancel(ClickPathfind.thread)
        ClickPathfind.thread = nil
    end

    if setWaypoint then
        setWaypoint("Target Klik", tx, ty)
    end

    ClickPathfind.busy = true
    ClickPathfind.targetX = tx
    ClickPathfind.targetY = ty
    if lblClickPathStatus and lblClickPathStatus.set then
        lblClickPathStatus:set(string.format("`2Menuju ke (%d, %d) [%d langkah]...``", tx + 1, ty + 1, #path))
    end

    ClickPathfind.thread = task.spawn(function()
        followPath(path)
        ClickPathfind.busy = false
        ClickPathfind.thread = nil
        if lblClickPathStatus and lblClickPathStatus.set then
            lblClickPathStatus:set(string.format("`2Sampai di tujuan (%d, %d)!``", tx + 1, ty + 1))
        end
        if clearWaypoint then
            task.delay(1.5, clearWaypoint)
        end
    end)
    return true
end

local function handleScreenClickPathfind(clickX, clickY, explicitTx, explicitTy)
    if not ClickPathfind.enabled then return end

    if explicitTx and explicitTy then
        triggerPathfindToTile(explicitTx, explicitTy)
        return
    end

    if not clickX or not clickY then return end

    -- Abaikan klik jika berada di dalam panel GUI SYSHUB atau WaypointHUD
    if MainDialog and MainDialog.Visible then
        local dPos = MainDialog.AbsolutePosition
        local dSize = MainDialog.AbsoluteSize
        if clickX >= dPos.X and clickX <= dPos.X + dSize.X and
           clickY >= dPos.Y and clickY <= dPos.Y + dSize.Y then
            return
        end
    end
    if WaypointHUD and WaypointHUD.Visible then
        local wPos = WaypointHUD.AbsolutePosition
        local wSize = WaypointHUD.AbsoluteSize
        if clickX >= wPos.X and clickX <= wPos.X + wSize.X and
           clickY >= wPos.Y and clickY <= wPos.Y + wSize.Y then
            return
        end
    end
    if SyshubSideBtn and SyshubSideBtn.Visible then
        local bPos = SyshubSideBtn.AbsolutePosition
        local bSize = SyshubSideBtn.AbsoluteSize
        if clickX >= bPos.X and clickX <= bPos.X + bSize.X and
           clickY >= bPos.Y and clickY <= bPos.Y + bSize.Y then
            return
        end
    end

    local tx, ty = screenToTile(clickX, clickY)
    if not tx or not ty then return end
    triggerPathfindToTile(tx, ty)
end

local hoverHighlightBox = nil

local function getOrCreateHoverBox(parent)
    if hoverHighlightBox and hoverHighlightBox.Parent then
        return hoverHighlightBox
    end
    local box = Instance.new("ImageLabel")
    box.Name = "HoverHighlightBox"
    box.BackgroundTransparency = 1
    box.Image = "rbxassetid://130382685204222"
    box.ImageRectOffset = Vector2.new(32, 0)
    box.ImageRectSize = Vector2.new(32, 32)
    box.ImageTransparency = 0.2
    box.ResampleMode = Enum.ResamplerMode.Pixelated
    box.Size = UDim2.fromOffset(DISPLAY_SIZE, DISPLAY_SIZE)
    box.ZIndex = 6
    box.Active = false
    box.Visible = false
    box.Parent = parent
    hoverHighlightBox = box
    return box
end

local function createGridTile(parent)
    local img = Instance.new("ImageLabel")
    img.Name = "PathGridBox"
    img.BackgroundTransparency = 1
    img.Image = "rbxassetid://130382685204222"
    img.ImageRectOffset = Vector2.new(32, 0)
    img.ImageRectSize = Vector2.new(32, 32)
    img.ImageTransparency = 0.65
    img.ResampleMode = Enum.ResamplerMode.Pixelated
    img.Size = UDim2.fromOffset(DISPLAY_SIZE, DISPLAY_SIZE)
    img.ZIndex = 4
    img.Active = false
    img.Visible = false
    img.Parent = parent
    return img
end

local function isShiftPressed()
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function updatePathfindGrid()
    if not ClickPathfind.enabled then
        if gridContainer then
            gridContainer.Visible = false
        end
        return
    end

    local camera, tiles, _ = getCameraAndTiles()
    if not camera or not tiles then return end
    local world = camera.Parent
    if not world then return end

    local container = getOrCreateGridContainer()
    if not container then return end

    local shiftHeld = isShiftPressed()
    if not shiftHeld then
        container.Visible = false
        if hoverHighlightBox then
            hoverHighlightBox.Visible = false
        end
        return
    end

    -- Shift sedang ditekan: Munculkan grid & update kotak!
    container.Visible = true

    local uiScale = 1
    local s = camera:FindFirstChild("UIScale")
    if s and s:IsA("UIScale") then
        uiScale = s.Scale
    end

    local camTileX = -tiles.Position.X.Offset / DISPLAY_SIZE
    local camTileY = -tiles.Position.Y.Offset / DISPLAY_SIZE
    local wSizeX = world.AbsoluteSize.X
    local wSizeY = world.AbsoluteSize.Y

    local w = getNativeWorld()
    local worldW = (w and w.w) or 100
    local worldH = (w and w.h) or 60

    local viewTilesW = math.ceil(wSizeX / (DISPLAY_SIZE * uiScale)) + 2
    local viewTilesH = math.ceil(wSizeY / (DISPLAY_SIZE * uiScale)) + 2

    local minTx = math.clamp(math.floor(camTileX) - 1, 0, worldW - 1)
    local maxTx = math.clamp(math.floor(camTileX + viewTilesW), 0, worldW - 1)
    local minTy = math.clamp(math.floor(camTileY) - 1, 0, worldH - 1)
    local maxTy = math.clamp(math.floor(camTileY + viewTilesH), 0, worldH - 1)

    local offsetX = tiles.Position.X.Offset
    local offsetY = tiles.Position.Y.Offset

    if math.abs(camTileX - lastCamTileX) >= 0.001 or
       math.abs(camTileY - lastCamTileY) >= 0.001 or
       math.abs(uiScale - lastUiScale) >= 0.001 or
       wSizeX ~= lastWorldSizeX or
       wSizeY ~= lastWorldSizeY then

        lastCamTileX = camTileX
        lastCamTileY = camTileY
        lastUiScale = uiScale
        lastWorldSizeX = wSizeX
        lastWorldSizeY = wSizeY

        local idx = 0
        for ty = minTy, maxTy do
            for tx = minTx, maxTx do
                idx = idx + 1
                local tileBox = gridButtonsPool[idx]
                if not tileBox then
                    tileBox = createGridTile(container)
                    gridButtonsPool[idx] = tileBox
                end

                tileBox:SetAttribute("tx", tx)
                tileBox:SetAttribute("ty", ty)
                tileBox.Position = UDim2.fromOffset(tx * DISPLAY_SIZE + offsetX, ty * DISPLAY_SIZE + offsetY)
                tileBox.Visible = true
            end
        end

        for i = idx + 1, #gridButtonsPool do
            gridButtonsPool[i].Visible = false
        end
    end

    -- Update highlight tile di bawah posisi mouse real-time
    local hoverBox = getOrCreateHoverBox(container)
    local mousePos = UserInputService:GetMouseLocation()
    local htx, hty = screenToTile(mousePos.X, mousePos.Y)
    if htx and hty and htx >= 0 and htx < worldW and hty >= 0 and hty < worldH then
        hoverBox.Position = UDim2.fromOffset(htx * DISPLAY_SIZE + offsetX, hty * DISPLAY_SIZE + offsetY)
        hoverBox.Visible = true
        if isSolidTile(htx, hty) then
            hoverBox.ImageColor3 = Color3.fromRGB(255, 75, 75)
        elseif isTileLocked(htx, hty) then
            hoverBox.ImageColor3 = Color3.fromRGB(255, 160, 40)
        else
            hoverBox.ImageColor3 = Color3.fromRGB(80, 255, 120)
        end
    else
        hoverBox.Visible = false
    end
end

local function toggleClickPathfindGrid(enabled)
    if enabled then
        lastCamTileX = -99999
        lastCamTileY = -99999
        if not gridConnection then
            gridConnection = RunService.RenderStepped:Connect(updatePathfindGrid)
        end
        updatePathfindGrid()
    else
        if gridConnection then
            gridConnection:Disconnect()
            gridConnection = nil
        end
        if gridContainer then
            gridContainer.Visible = false
        end
        if hoverHighlightBox then
            hoverHighlightBox.Visible = false
        end
        for _, btn in ipairs(gridButtonsPool) do
            btn.Visible = false
        end
    end
end

local function tryPickupDrop(drop, inv)
    if not drop or not drop.uid or not drop.n or drop.n <= 0 or drop.taking then
        return 0
    end

    local takeAmount = drop.n
    if drop.id ~= 112 and inv and inv.room then
        local space = inv:room(drop.id)
        if space <= 0 then
            return 0
        end
        takeAmount = math.min(takeAmount, space)
    end
    if takeAmount <= 0 then return 0 end

    drop.taking = true
    local taken = nil
    local w = getNativeWorld and getNativeWorld()
    if w and w.takeDrop then
        local ok_take, res = pcall(w.takeDrop, drop.uid, takeAmount)
        if ok_take and type(res) == "number" and res > 0 then
            taken = res
        end
    end
    if not taken and w and w.ask then
        local ok_ask, res = pcall(w.ask, "take", "took", { uid = drop.uid, want = math.clamp(math.floor(takeAmount), 1, 65535) })
        if ok_ask and res and type(res.got) == "number" and res.got > 0 then
            taken = res.got
        end
    end
    drop.taking = false

    if taken and taken > 0 then
        drop.n = drop.n - taken
        if drop.n <= 0 then
            if drop.frame then
                pcall(function() drop.frame:Destroy() end)
            end
            local w = getNativeWorld()
            if w and w.dropList then
                local drops = w.dropList()
                local idx = table.find(drops, drop)
                if idx then table.remove(drops, idx) end
            end
        else
            if drop.count and drop.count.set then
                drop.count:set(drop.n > 1 and tostring(drop.n) or "")
            end
        end

        if inv and inv.add and drop.id ~= 112 then
            pcall(inv.add, inv, drop.id, taken)
        end

        if Sfx and Sfx.play then
            if drop.id == 112 then
                Sfx.play("gem_pickup", "object_collect")
            else
                Sfx.play("object_collect")
            end
        end
        return taken
    end
    return 0
end

local unreachableDrops = {}
local lastUnreachableClear = os.clock()

local function sweepDrops(radius, filterMode, maxPerPass, isManual)
    local w = getNativeWorld()
    if not w or not w.dropList then return 0 end
    local drops = w.dropList()
    if not drops or #drops == 0 then return 0 end

    if os.clock() - lastUnreachableClear > 30 then
        table.clear(unreachableDrops)
        lastUnreachableClear = os.clock()
    end

    local px, py, rawX, rawY = getPlayerTilePos()
    if not px or not py then return 0 end

    local origX = rawX or (px + 0.5)
    local origY = py + 1.0
    local origTileX = px
    local origTileY = py

    local inv = getNativeInventory()
    local targetItemId = PNB and PNB.itemId or 2
    local totalCollected = 0
    local passLimit = maxPerPass or 30

    local function isDropEligible(drop)
        if not drop or not drop.uid or not drop.n or drop.n <= 0 or drop.taking then
            return false
        end
        if unreachableDrops and unreachableDrops[drop.uid or drop] then
            return false
        end
        if filterMode == "ALL" then
            -- ok
        elseif filterMode == "GEMS" then
            if drop.id ~= 112 then return false end
        elseif filterMode == "ITEMS" then
            if drop.id == 112 then return false end
        elseif filterMode == "CURRENT" then
            if drop.id ~= targetItemId and drop.id ~= 112 then return false end
        end

        local dtx = math.floor(drop.x or 0)
        local dty = math.floor(drop.y or 0)

        -- JANGAN PERNAH COBA COLLECT DROPPAN YANG TERTUTUP BLOK SOLID!
        -- 1. Drop berada di dalam blok solid
        if isSolidTile(dtx, dty) then
            return false
        end

        -- 2. Drop berada di area locked pemain lain
        if isTileLocked(dtx, dty) then
            return false
        end

        -- 3. Drop terkurung rapat di keempat sisinya oleh blok solid tanpa celah akses
        if isSolidTile(dtx + 1, dty) and isSolidTile(dtx - 1, dty) and isSolidTile(dtx, dty + 1) and isSolidTile(dtx, dty - 1) then
            return false
        end

        return true
    end

    -- ── Phase 1: Local Sweep (Drop dekat <= 1.2 tile, sedot instan tanpa jalan) ──
    for i = #drops, 1, -1 do
        local drop = drops[i]
        if isDropEligible(drop) then
            local dropX = drop.x or px
            local dropY = drop.y or py
            local dx = dropX - origX
            local dy = dropY - origY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 1.2 then
                local taken = tryPickupDrop(drop, inv)
                if taken > 0 then
                    totalCollected = totalCollected + taken
                    Magnet.totalPicked = Magnet.totalPicked + taken
                    passLimit = passLimit - 1
                    if passLimit <= 0 then break end
                end
            end
        end
    end

    if passLimit <= 0 then
        if totalCollected > 0 and refreshInventory then
            task.spawn(refreshInventory)
        end
        return totalCollected
    end

    -- Saat PNB aktif dan combo dengan Magnet:
    -- Jangan biarkan background magnet pathfind keluyuran ke seantero world!
    -- Biarkan alur siklus PNB yang menangani droppan di tile break secara bertahap & tertib.
    if PNB and PNB.active and not isManual then
        if totalCollected > 0 and refreshInventory then
            task.spawn(refreshInventory)
        end
        return totalCollected
    end

    -- ── Phase 2: A* Pathfind Glide Sweep (Meluncur Mulus Mengikuti Jalur Bebas Solid) ──
    local candidateDrops = {}
    for _, drop in ipairs(drops) do
        if isDropEligible(drop) then
            local dropX = drop.x or px
            local dropY = drop.y or py
            local dx = dropX - origX
            local dy = dropY - origY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 1.2 and (radius >= 900 or dist <= radius) then
                table.insert(candidateDrops, { drop = drop, x = dropX, y = dropY, dist = dist })
            end
        end
    end

    if #candidateDrops == 0 then
        if totalCollected > 0 and refreshInventory then
            task.spawn(refreshInventory)
        end
        return totalCollected
    end

    table.sort(candidateDrops, function(a, b)
        return a.dist < b.dist
    end)

    local maxDistantVisits = isManual and math.min(12, #candidateDrops) or math.min(4, #candidateDrops)
    local currentX, currentY = origX, origY
    local currentTileX, currentTileY = origTileX, origTileY

    for vIdx = 1, maxDistantVisits do
        if passLimit <= 0 then break end

        -- Cari drop kandidat terdekat dari posisi saat ini
        local bestDrop, bestDist = nil, 999999
        for _, cand in ipairs(candidateDrops) do
            if cand.drop and cand.drop.n and cand.drop.n > 0 and not cand.drop.taking then
                local cdx = cand.x - currentX
                local cdy = cand.y - currentY
                local cdist = math.sqrt(cdx * cdx + cdy * cdy)
                if cdist < bestDist then
                    bestDist = cdist
                    bestDrop = cand.drop
                end
            end
        end

        if not bestDrop then break end

        local targetX = bestDrop.x or currentX
        local targetY = bestDrop.y or currentY
        local targetTileX = math.floor(targetX)
        local targetTileY = math.floor(targetY)

        -- Cari rute A* bebas solid tile (ItemDB.solid == true di-hindari mutlak)
        local path = findPath(currentTileX, currentTileY, targetTileX, targetTileY)
        if path and #path > 0 then
            if lblMagnetStats then
                lblMagnetStats.Text = string.format("🧲 Pathfind ke (X: %d, Y: %d) [%d steps]...",
                    targetTileX, targetTileY, #path)
            end

            -- Meluncur mulus mengikuti waypoints A*
            followPath(path, Magnet.stepSize or 0.85, currentX, currentY)

            local lastT = path[#path]
            currentTileX = lastT.x
            currentTileY = lastT.y
            currentX = lastT.x + 0.5
            currentY = lastT.y + 1.0

            -- Ambil drop target
            local taken = tryPickupDrop(bestDrop, inv)
            if taken > 0 then
                totalCollected = totalCollected + taken
                Magnet.totalPicked = Magnet.totalPicked + taken
                passLimit = passLimit - 1
            end

            -- Cluster Vacuum: Sedot drop sekitar yang <= 1.2 tile dari posisi saat ini
            for _, drop in ipairs(drops) do
                if isDropEligible(drop) and drop ~= bestDrop then
                    local dx = (drop.x or currentX) - currentX
                    local dy = (drop.y or currentY) - currentY
                    if math.sqrt(dx * dx + dy * dy) <= 1.2 then
                        local clusterTaken = tryPickupDrop(drop, inv)
                        if clusterTaken > 0 then
                            totalCollected = totalCollected + clusterTaken
                            Magnet.totalPicked = Magnet.totalPicked + clusterTaken
                            passLimit = passLimit - 1
                            if passLimit <= 0 then break end
                        end
                    end
                end
            end
        else
            -- Drop ini terkurung oleh blok solid tanpa celah / jalur terhalang, blacklist & abaikan!
            bestDrop.taking = false
            if unreachableDrops then
                unreachableDrops[bestDrop.uid or bestDrop] = true
            end
        end
    end

    -- ── Phase 3: Pathfind Return to Original Position (Meluncur Kembali Tanpa Menabrak) ──
    local returnDist = math.sqrt((currentX - origX)^2 + (currentY - origY)^2)
    if returnDist > 0.4 then
        if lblMagnetStats then
            lblMagnetStats.Text = "🧲 Meluncur kembali ke posisi awal..."
        end

        local returnPath = findPath(currentTileX, currentTileY, origTileX, origTileY)
        if returnPath and #returnPath > 0 then
            followPath(returnPath, Magnet.stepSize or 0.85, currentX, currentY)
        else
            setInternalPlayerPos(origX, origY)
        end
    end

    setInternalPlayerPos(origX, origY)
    safeSendMove({
        x = origX,
        y = origY,
        vx = 0,
        vy = 0,
        flags = 2,
    })

    if totalCollected > 0 and refreshInventory then
        task.spawn(refreshInventory)
    end

    return totalCollected
end

local function startMagnetLoop()
    if Magnet.thread then return end
    Magnet.thread = task.spawn(function()
        while Magnet.enabled do
            if not Magnet.busy then
                Magnet.busy = true
                local count = sweepDrops(Magnet.radius, Magnet.filterMode, 20)
                if count > 0 and lblMagnetStats then
                    lblMagnetStats.Text = string.format("● Tersedot: %d item | Rad: %s | Flt: %s",
                        Magnet.totalPicked,
                        (Magnet.radius >= 900 and "World" or (Magnet.radius .. "T")),
                        Magnet.filterMode)
                end
                Magnet.busy = false
            end
            task.wait(Magnet.delay)
        end
        Magnet.thread = nil
    end)
end

local function stopMagnetLoop()
    Magnet.enabled = false
    Magnet.thread = nil
end

-- ═══════════════════════════════════════
--  MOBILITY INPUT & HOVER CONTROLLER
-- ═══════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and ClickPathfind and ClickPathfind.enabled then
        local isShift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        if isShift and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            handleScreenClickPathfind(input.Position.X, input.Position.Y)
        end
    end

    if gpe then return end

    if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
        if Mobility.flyEnabled then
            flyInputY = -1
        elseif Mobility.antiGravEnabled then
            -- Anti-Grav Infinite Jump: Sinkronisasi native double-jump flap
            local physFn = getNativePhysicsFn()
            if physFn and debug and debug.setupvalue then
                pcall(function()
                    debug.setupvalue(physFn, 27, false) -- reset hasDoubleJumped
                    debug.setupvalue(physFn, 18, -19.9)  -- beri kecepatan lompat native
                    debug.setupvalue(physFn, 22, true)   -- SELALU GROUNDED agar server tidak rubberband!
                end)
            end
            local px, py, rawX, rawY = getPlayerTilePos()
            safeSendMove({
                x = rawX or (px and px + 0.5) or 0,
                y = rawY or (py and py + 1.0) or 0,
                vx = 0,
                vy = -19.9,
                grounded = true,
                flags = 2, -- SELALU GROUNDED
            })
            if Sfx and Sfx.play then Sfx.play("jump") end
        end

    elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
        if Mobility.flyEnabled then
            flyInputY = 1
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
        if flyInputY == -1 then flyInputY = 0 end
    elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
        if flyInputY == 1 then flyInputY = 0 end
    end
end)

local mobilityHeartbeatConn = nil
mobilityHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
    if not scriptAlive then return end
    if Mobility.speedEnabled then
        ensureMobilityHooks()
    end

    if Mobility.antiGravEnabled or Mobility.flyEnabled then
        local physFn = getNativePhysicsFn()

        if Mobility.antiGravEnabled then
            -- Selalu reset flag hasDoubleJumped (upvalue 27) dan pastikan grounded = true agar tidak rubberband
            if physFn and debug and debug.setupvalue then
                pcall(debug.setupvalue, physFn, 27, false)
                pcall(debug.setupvalue, physFn, 22, true)
            end
        end

        if Mobility.flyEnabled and not Magnet.busy and not (ClearWorld and ClearWorld.busy) and not (AutoBuildDF and AutoBuildDF.busy) then
            ensureMobilityHooks()
            local px, py, rawX, rawY = getPlayerTilePos()
            if px and py then
                if not Mobility.suspendedY then
                    Mobility.suspendedY = rawY or (py + 1.0)
                end

                if flyInputY ~= 0 then
                    Mobility.suspendedY = Mobility.suspendedY + (flyInputY * Mobility.flySpeed * dt)
                end

                local curX = rawX or (px + 0.5)
                setInternalPlayerPos(curX, Mobility.suspendedY)

                local targetVy = (flyInputY ~= 0) and (flyInputY * Mobility.flySpeed) or 0
                if physFn and debug and debug.setupvalue then
                    pcall(function()
                        debug.setupvalue(physFn, 18, targetVy) -- netralkan gravitasi jatuh!
                        debug.setupvalue(physFn, 22, true)     -- grounded = true agar tidak jitter
                    end)
                end

                safeSendMove({
                    x = curX,
                    y = Mobility.suspendedY,
                    vx = 0,
                    vy = targetVy,
                    flags = 2,
                })
            end
        end
    end
end)

-- ═══════════════════════════════════════
--  PNB STATE
-- ═══════════════════════════════════════
PNB = {
    active      = false,
    mode        = "PNB",      -- "PNB" | "BREAK" | "PLACE"
    layer       = "fg",       -- "fg" | "bg"
    itemId      = 2,          -- Default Dirt = 2
    itemName    = "Dirt",
    itemKind    = "block",
    hits        = 3,          -- Hits durabilitas blok
    hitDelay    = 0.18,       -- Cooldown antar hit
    loopDelay   = 0.12,       -- Jeda antar siklus
    targets     = {           -- Multi-target offset: ["dx_dy"] = {dx = X, dy = Y}
        ["1_0"] = { dx = 1, dy = 0 } -- Default: 1 tile di Kanan (+1, 0)
    },
    busy        = false,
    thread      = nil,
}

local function getSortedTargetList()
    local list = {}
    for _, t in pairs(PNB.targets) do
        table.insert(list, t)
    end
    table.sort(list, function(a, b)
        if a.dx == b.dx then
            return a.dy < b.dy
        end
        return a.dx < b.dx
    end)
    return list
end

-- ═══════════════════════════════════════
--  INVENTORY FETCHER & AUTO-DETECTION
-- ═══════════════════════════════════════
local function fetchInventoryItems()
    local items = {}
    local nativeInv = getNativeInventory()
    if nativeInv and type(nativeInv.slots) == "table" and #nativeInv.slots > 0 then
        for _, slot in ipairs(nativeInv.slots) do
            local id = slot.id or slot[1]
            local count = slot.n or slot[2]
            if id and count and count > 0 then
                local dbEntry = ItemDB and ItemDB[id] or {}
                local kind = dbEntry.kind or "block"

                if kind ~= "cloth" and kind ~= "tool" and kind ~= "gem" then
                    local isBg = (dbEntry.background == true)
                    local hits = dbEntry.hits
                    if not hits then
                        hits = (kind == "seed") and 1 or 3
                    end

                    table.insert(items, {
                        id = id,
                        count = count,
                        name = dbEntry.name or ("Item #" .. id),
                        kind = kind,
                        isBg = isBg,
                        layer = isBg and "bg" or "fg",
                        hits = hits,
                    })
                end
            end
        end
        if #items > 0 then return items end
    end

    local inv = nil
    if Net and Net.call then
        local ok, res = pcall(Net.call, "GetInventory")
        if ok and type(res) == "table" then
            inv = res
        end
    end
    if not inv and WorldRemotes and WorldRemotes:FindFirstChild("GetInventory") then
        local ok, res = pcall(WorldRemotes.GetInventory.InvokeServer, WorldRemotes.GetInventory)
        if ok and type(res) == "table" then
            inv = res
        end
    end
    if inv and type(inv) == "table" and type(inv.slots) == "table" then
        for _, slot in ipairs(inv.slots) do
            local id, count = slot[1], slot[2]
            if id and count and count > 0 then
                local dbEntry = ItemDB and ItemDB[id] or {}
                local kind = dbEntry.kind or "block"

                if kind ~= "cloth" and kind ~= "tool" and kind ~= "gem" then
                    local isBg = (dbEntry.background == true)
                    local hits = dbEntry.hits
                    if not hits then
                        hits = (kind == "seed") and 1 or 3
                    end

                    table.insert(items, {
                        id = id,
                        count = count,
                        name = dbEntry.name or ("Item #" .. id),
                        kind = kind,
                        isBg = isBg,
                        layer = isBg and "bg" or "fg",
                        hits = hits,
                    })
                end
            end
        end
    end
    return items
end

-- ═══════════════════════════════════════
--  REAL-TIME TILE & INVENTORY ENGINE
-- ═══════════════════════════════════════
local function getRealtimeTile(layer, tx, ty)
    if not tx or not ty or tx < 0 or ty < 0 then return nil end
    local w = getNativeWorld()
    if not w then return nil end
    layer = string.lower(tostring(layer or "fg"))
    local grid = (layer == "bg") and w.bg or w.fg
    if grid and grid[ty] then
        return grid[ty][tx] or 0
    end
    return 0
end

local function getRealtimeItemCount(itemId)
    if not itemId then return 0 end
    local inv = getNativeInventory()
    if inv then
        if inv.count then
            local ok, c = pcall(inv.count, inv, itemId)
            if ok and type(c) == "number" then return c end
        end
        if type(inv.slots) == "table" then
            for _, s in ipairs(inv.slots) do
                local sid = s.id or s[1]
                if sid == itemId then
                    return s.n or s[2] or 0
                end
            end
            return 0
        end
    end

    local items = fetchInventoryItems()
    for _, it in ipairs(items) do
        if it.id == itemId then
            return it.count
        end
    end
    return 0
end

local invHooked = false
local function hookRealtimeInventory()
    if invHooked then return end
    local inv = getNativeInventory()
    if inv and inv.changed and inv.changed.Event then
        inv.changed.Event:Connect(function()
            task.spawn(function()
                -- Auto-Stop check secara real-time saat stok item berubah di tas
                if PNB and PNB.active and (PNB.mode == "PLACE" or PNB.mode == "PNB") then
                    local stock = getRealtimeItemCount(PNB.itemId)
                    if stock <= 0 then
                        if stopPNB then stopPNB() end
                        if lblStatus then
                            lblStatus.Text = string.format("● STOP: Item '%s' (#%d) di tas habis!", PNB.itemName or "Target", PNB.itemId)
                            lblStatus.TextColor3 = C.gold
                        end
                    end
                end

                -- Live update dropdown text jumlah item saat ini
                if btnDropdown and PNB and PNB.itemId then
                    local stock = getRealtimeItemCount(PNB.itemId)
                    btnDropdown.Text = string.format("📦 [%s] %s x%d",
                        string.upper(PNB.layer or "fg"),
                        PNB.itemName or ("Item #" .. PNB.itemId),
                        stock)
                end
            end)
        end)
        invHooked = true
    end
end

-- ═══════════════════════════════════════
--  PNB ACTIONS (REAL-TIME ADAPTIVE)
-- ═══════════════════════════════════════
local function executePlace(tx, ty)
    if not tx or not ty or tx < 0 or ty < 0 then return false end

    local layer = string.lower(tostring(PNB.layer or "fg"))
    if layer ~= "fg" and layer ~= "bg" then layer = "fg" end

    -- Real-time check: pastikan tile kosong (0) sebelum menempatkan blok
    local cur = getRealtimeTile(layer, tx, ty)
    if cur and cur ~= 0 then
        return false -- Sudah ada blok, jangan buang item
    end

    -- Legit player facing towards placement target
    local px, py, rawX, rawY = getPlayerTilePos()
    if px and rawX and rawY and safeSendMove then
        local facingBit = (tx >= px) and 1 or 0
        safeSendMove({
            x = rawX,
            y = rawY,
            vx = 0,
            vy = 0,
            flags = 2 + facingBit
        })
    end

    local actKind = (PNB.itemKind == "seed") and ACT_KIND.PLANT or ACT_KIND.BUILD
    sendActPacket(actKind, tx, ty)
    sendTilePacket(layer, tx, ty, PNB.itemId, false)
    forceClientTileUpdate(layer, tx, ty, PNB.itemId)
    return true
end

local function executeBreak(tx, ty, autoSweep)
    if not tx or not ty or tx < 0 or ty < 0 then return false end

    local layer = string.lower(tostring(PNB.layer or "fg"))
    if layer ~= "fg" and layer ~= "bg" then layer = "fg" end

    -- Real-time check: pastikan ada blok di target sebelum mulai memukul
    local cur = getRealtimeTile(layer, tx, ty)
    if cur == 0 then
        return true -- Target sudah kosong (air) / sudah hancur
    end

    -- Legit player facing towards break target
    local px, py, rawX, rawY = getPlayerTilePos()
    if px and rawX and rawY and safeSendMove then
        local facingBit = (tx >= px) and 1 or 0
        safeSendMove({
            x = rawX,
            y = rawY,
            vx = 0,
            vy = 0,
            flags = 2 + facingBit
        })
    end

    local totalHits = math.max(1, PNB.hits)

    for i = 1, totalHits do
        if not PNB.active then return false end

        -- Cek apakah blok sudah pecah di tengah-tengah pukulan
        if i > 1 and getRealtimeTile(layer, tx, ty) == 0 then
            break
        end

        sendActPacket(ACT_KIND.HIT, tx, ty)
        if i < totalHits then
            task.wait(PNB.hitDelay)
        end
    end

    task.wait(0.015)
    sendTilePacket(layer, tx, ty, 0, false)
    forceClientTileUpdate(layer, tx, ty, 0)

    -- Auto-sweep drops seketika jika Magnet aktif dan autoSweep diizinkan (tidak sedang dihandle alur PNB)
    if autoSweep ~= false and Magnet and Magnet.enabled and not (PNB and PNB.active) then
        task.spawn(function()
            sweepDrops(Magnet.radius, Magnet.filterMode, 15)
        end)
    end

    return true
end

local function collectDropsAtTiles(targetTiles, homePx, homePy, homeRawX, homeRawY)
    local w = getNativeWorld()
    if not w or not w.dropList then return 0 end

    -- Beri jeda sangat singkat agar packet drop dari server terbaca di client dropList
    task.wait(0.03)

    local drops = w.dropList()
    if not drops or #drops == 0 then return 0 end

    local inv = getNativeInventory()
    local targetItemId = (AutoFactory and AutoFactory.active and AutoFactory.targetBlockId) or (PNB and PNB.itemId or 2)
    local totalCollected = 0

    local function isDropOnTargetTiles(drop)
        if not drop or not drop.uid or not drop.n or drop.n <= 0 or drop.taking then
            return false
        end
        if unreachableDrops and unreachableDrops[drop.uid or drop] then
            return false
        end
        if ClearWorld and ClearWorld.active then
            -- Pada Clear World: kumpulkan SEMUA droppan (item & gem) di sekitar tile yang di-break
        elseif AutoFactory and AutoFactory.active then
            -- Pada Auto Factory: selalu kumpulkan seed, blok target, dan gems
            if drop.id ~= AutoFactory.targetSeedId and drop.id ~= AutoFactory.targetBlockId and drop.id ~= 112 then
                return false
            end
        elseif Magnet and Magnet.filterMode == "GEMS" then
            if drop.id ~= 112 then return false end
        elseif Magnet and Magnet.filterMode == "ITEMS" then
            if drop.id == 112 then return false end
        elseif Magnet and Magnet.filterMode == "CURRENT" then
            if drop.id ~= targetItemId and drop.id ~= 112 then return false end
        end

        local dtx = math.floor(drop.x or 0)
        local dty = math.floor(drop.y or 0)

        if isSolidTile(dtx, dty) or isTileLocked(dtx, dty) then
            return false
        end

        -- Cek apakah drop berada di sekitar salah satu tile target break (jarak <= 1.8 tile)
        for _, t in ipairs(targetTiles) do
            local ddx = (drop.x or 0) - (t.x + 0.5)
            local ddy = (drop.y or 0) - (t.y + 0.5)
            if (ddx * ddx + ddy * ddy) <= 3.24 then
                return true
            end
        end

        return false
    end

    local dropsToPick = {}
    for _, drop in ipairs(drops) do
        if isDropOnTargetTiles(drop) then
            table.insert(dropsToPick, drop)
        end
    end

    if #dropsToPick == 0 then
        return 0
    end

    local curPx, curPy, curRawX, curRawY = getPlayerTilePos()
    local cX = curRawX or (curPx and (curPx + 0.5)) or homeRawX
    local cY = curRawY or (curPy and (curPy + 1.0)) or homeRawY

    -- Cek apakah semua drop bisa dijangkau langsung tanpa bergeser (jarak <= 1.35 tile)
    local allNearby = true
    for _, drop in ipairs(dropsToPick) do
        local dx = (drop.x or cX) - cX
        local dy = (drop.y or cY) - cY
        if math.sqrt(dx * dx + dy * dy) > 1.35 then
            allNearby = false
            break
        end
    end

    if allNearby then
        -- Semua droppan berada dalam jangkauan sedot langsung, ambil seketika tanpa bergeser
        for _, drop in ipairs(dropsToPick) do
            local taken = tryPickupDrop(drop, inv)
            if taken > 0 then
                totalCollected = totalCollected + taken
                if Magnet then Magnet.totalPicked = (Magnet.totalPicked or 0) + taken end
            end
        end
    else
        -- Ada drop yang agak jauh (> 1.35 tile):
        -- Jalan ke tile break, sedot, lalu balik ke tempat semula
        local stepped = false
        local visited = {}
        for _, t in ipairs(targetTiles) do
            local key = t.x .. "," .. t.y
            if not visited[key] then
                visited[key] = true
                -- Cek apakah ada drop di dekat tile t ini
                local hasDropAtT = false
                for _, drop in ipairs(dropsToPick) do
                    local ddx = (drop.x or 0) - (t.x + 0.5)
                    local ddy = (drop.y or 0) - (t.y + 0.5)
                    if (ddx * ddx + ddy * ddy) <= 2.25 and not drop.taking and drop.n and drop.n > 0 then
                        hasDropAtT = true
                        break
                    end
                end

                if hasDropAtT then
                    if stepToColumn then
                        stepToColumn(t.x, t.y)
                        stepped = true
                    end
                    task.wait(0.02)
                    for _, drop in ipairs(dropsToPick) do
                        if not drop.taking and drop.n and drop.n > 0 then
                            local taken = tryPickupDrop(drop, inv)
                            if taken > 0 then
                                totalCollected = totalCollected + taken
                                if Magnet then Magnet.totalPicked = (Magnet.totalPicked or 0) + taken end
                            end
                        end
                    end
                end
            end
        end

        -- Balik ke posisi semula (home) secara mulus
        if stepped then
            if stepToColumn and homePx and homePy then
                stepToColumn(homePx, homePy)
            end
            if homeRawX and homeRawY then
                setInternalPlayerPos(homeRawX, homeRawY)
                safeSendMove({
                    x = homeRawX,
                    y = homeRawY,
                    vx = 0,
                    vy = 0,
                    flags = 2,
                })
            end
            task.wait(0.02)
        end
    end

    if totalCollected > 0 and refreshInventory then
        task.spawn(refreshInventory)
    end

    return totalCollected
end

local function executeCycle(onTargetStep)
    if PNB.busy or not PNB.active or (ClearWorld and ClearWorld.active) then return end
    if Magnet and Magnet.busy then return end
    PNB.busy = true

    local targets = getSortedTargetList()
    if #targets == 0 then
        PNB.busy = false
        return
    end

    local px, py, rawX, rawY = getPlayerTilePos()
    if not px or not py then
        PNB.busy = false
        return
    end

    local homeRawX = rawX or (px + 0.5)
    local homeRawY = py + 1.0

    local layer = string.lower(tostring(PNB.layer or "fg"))
    if layer ~= "fg" and layer ~= "bg" then layer = "fg" end

    -- Real-time Inventory Check:
    -- Jika mode PLACE atau PNB: otomatis hentikan jika item habis!
    if PNB.mode == "PLACE" or PNB.mode == "PNB" then
        local stock = getRealtimeItemCount(PNB.itemId)
        if stock <= 0 then
            if stopPNB then stopPNB() end
            if lblStatus then
                lblStatus:set(string.format("`4[!] STOP: Item '%s' (#%d) di tas habis!``", PNB.itemName or "Item", PNB.itemId))
            end
            PNB.busy = false
            return
        end
    end
    -- Jika BREAK ONLY: JANGAN PERNAH BERHENTI (tetap looping & waiting)

    if PNB.mode == "PLACE" then
        for idx, target in ipairs(targets) do
            if not PNB.active then break end
            if getRealtimeItemCount(PNB.itemId) <= 0 then
                if stopPNB then stopPNB() end
                if lblStatus then
                    lblStatus:set(string.format("`4[!] STOP: Item '%s' habis!``", PNB.itemName or "Item"))
                end
                break
            end
            local tx, ty = px + target.dx, py + target.dy
            local curTile = getRealtimeTile(layer, tx, ty)
            if curTile == 0 then
                if onTargetStep then onTargetStep(idx, #targets, tx, ty) end
                executePlace(tx, ty)
                task.wait(0.09)
            end
        end

    elseif PNB.mode == "BREAK" then
        -- BREAK ONLY: hancurkan SEMUA target yang ada bloknya, lalu sedot droppan
        local hadBlocks = false
        local brokenTiles = {}
        for idx, target in ipairs(targets) do
            if not PNB.active then break end
            local tx, ty = px + target.dx, py + target.dy
            local curTile = getRealtimeTile(layer, tx, ty)
            if curTile and curTile ~= 0 then
                hadBlocks = true
                if onTargetStep then onTargetStep(idx, #targets, tx, ty) end
                executeBreak(tx, ty, false)
                table.insert(brokenTiles, { x = tx, y = ty })
                task.wait(0.02)
            end
        end

        -- Jika Auto Collect / Magnet aktif: sedot droppan dari SEMUA tile yang baru di-break, lalu balik ke home
        if Magnet and Magnet.enabled and #brokenTiles > 0 then
            collectDropsAtTiles(brokenTiles, px, py, homeRawX, homeRawY)
        end

        -- Jika semua target sedang kosong, tunggu sebentar lalu loop lagi tanpa berhenti!
        if not hadBlocks then
            task.wait(0.12)
        end

    elseif PNB.mode == "PNB" then
        -- 1. Phase Place: tempatkan blok pada SEMUA target yang kosong sekaligus
        for idx, target in ipairs(targets) do
            if not PNB.active then break end
            if getRealtimeItemCount(PNB.itemId) <= 0 then
                if stopPNB then stopPNB() end
                if lblStatus then
                    lblStatus:set(string.format("`4[!] STOP: Item '%s' habis saat PNB!``", PNB.itemName or "Item"))
                end
                break
            end
            local tx, ty = px + target.dx, py + target.dy
            local curTile = getRealtimeTile(layer, tx, ty)
            if curTile == 0 then
                if onTargetStep then onTargetStep(idx, #targets, tx, ty) end
                executePlace(tx, ty)
                task.wait(0.09)
            end
        end

        task.wait(0.05)

        -- 2. Phase Break: hancurkan blok pada SEMUA target yang terisi
        local brokenTiles = {}
        for idx, target in ipairs(targets) do
            if not PNB.active then break end
            local tx, ty = px + target.dx, py + target.dy
            local curTile = getRealtimeTile(layer, tx, ty)
            if curTile and curTile ~= 0 then
                if onTargetStep then onTargetStep(idx, #targets, tx, ty) end
                executeBreak(tx, ty, false)
                table.insert(brokenTiles, { x = tx, y = ty })
                task.wait(0.02)
            end
        end

        -- 3. Phase Collect: Jika Magnet/Auto Collect aktif, sedot droppan dari SEMUA target break lalu kembali ke posisi home!
        if Magnet and Magnet.enabled and #brokenTiles > 0 then
            collectDropsAtTiles(brokenTiles, px, py, homeRawX, homeRawY)
        end
    end

    PNB.busy = false
end

-- ═══════════════════════════════════════
--  CLEAR WORLD AUTOMATION ENGINE (v10.2 - Smart Range & Pathfind)
-- ═══════════════════════════════════════
ClearWorld = {
    active         = false,
    busy           = false,
    clearBG        = true,       -- Hancurkan juga background
    autoSweep      = true,       -- Sapu / sedot droppan dari blok yang di-break
    autoTrash      = false,      -- Auto recycle/trash hasil sapuan agar tas tidak penuh
    hitDelay       = 0.17,       -- Delay per hit (sesuai cooldown native game agar tidak di-drop server)
    totalCleared   = 0,
    thread         = nil,
}

local function isBedrockTile(id)
    if not id or id == 0 then return false end
    if id == 8 then return true end
    local it = ItemDB and ItemDB[id]
    if it then
        if it.bedrock == true or it.unbreakable == true then return true end
        if it.hits and it.hits <= 0 then return true end
        local name = it.name and string.lower(it.name) or ""
        if string.find(name, "bedrock") then return true end
    end
    return false
end

local function isProtectedTile(id)
    if not id or id == 0 then return false end
    if id == 6 or id == 8 then return true end -- 6 = Main Door, 8 = Bedrock

    local it = ItemDB and ItemDB[id]
    if not it then return false end

    -- Indestructible (Bedrock, Main Door, hits <= 0)
    if it.hits and it.hits <= 0 then return true end
    if it.bedrock or it.unbreakable then return true end

    -- Locks & Area Locks
    if it.lock or it.area then return true end

    local name = it.name and string.lower(it.name) or ""
    if name == "main door" or name == "bedrock" then return true end

    -- Any lock item
    if string.find(name, "lock") then
        if not string.find(name, "clock")
           and not string.find(name, "block")
           and not string.find(name, "seed")
           and not string.find(name, "mask")
           and not string.find(name, "shades")
           and not string.find(name, "leash")
           and not string.find(name, "sign") then
            return true
        end
    end

    return false
end

local function isTileBreakable(layer, tx, ty)
    if not tx or not ty or tx < 0 or ty < 0 then return false end

    local fg = getRealtimeTile("fg", tx, ty)
    -- ATURAN 1: JIKA TILE FG ADALAH BEDROCK ATAU PROTECTED (DOOR/LOCK), SKIP ALL!
    -- Background di belakang atau tepat di tile bedrock TIDAK BOLEH dan TIDAK BISA disentuh!
    if fg and fg ~= 0 and (isBedrockTile(fg) or isProtectedTile(fg)) then
        return false
    end

    local bg = getRealtimeTile("bg", tx, ty)
    if bg and bg ~= 0 and (isBedrockTile(bg) or isProtectedTile(bg)) then
        if layer == "bg" then return false end
    end

    if layer == "fg" then
        return (fg and fg ~= 0 and not isProtectedTile(fg) and not isBedrockTile(fg))
    elseif layer == "bg" then
        if not ClearWorld.clearBG then return false end
        return (bg and bg ~= 0 and not isProtectedTile(bg) and not isBedrockTile(bg))
    end
    return false
end

-- Menentukan apakah tile (tx, ty) memiliki blok breakable yang valid (FG atau BG)
local function hasBreakableAtTile(tx, ty)
    if not tx or not ty or tx < 0 or ty < 0 then return false end
    local fg = getRealtimeTile("fg", tx, ty)
    -- Jika FG adalah bedrock atau protected, SKIP ALL (jangan target tile ini!)
    if fg and fg ~= 0 and (isBedrockTile(fg) or isProtectedTile(fg)) then
        return false
    end
    if isTileBreakable("fg", tx, ty) then
        return true
    end
    if ClearWorld.clearBG and isTileBreakable("bg", tx, ty) then
        return true
    end
    return false
end

local function getBlockHits(id)
    if not id or id == 0 then return 0 end
    local it = ItemDB and ItemDB[id]
    if it and it.hits and it.hits > 0 then
        return it.hits
    end
    if it and it.kind == "seed" then
        return 1
    end
    return 3
end

local calculateBlockHits = getBlockHits

stepToColumn = function(targetX, targetY)
    local px, py, rawX, rawY = getPlayerTilePos()
    if not px or not py then return end

    local startX = rawX or (px + 0.5)
    local startY = py + 1.0
    local destX = targetX + 0.5
    local destY = targetY + 1.0

    local dx = destX - startX
    local dy = destY - startY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0.05 then return end

    -- Kecepatan langkah: 1.25x dari speed asli karakter (7.2 * 1.25 = 9.0 tiles/sec)
    local STEP_SPEED = 9.0
    local segTime = dist / STEP_SPEED
    local t0 = os.clock()
    local elapsed = 0
    while elapsed < segTime do
        if isMovementActive and not isMovementActive() then break end
        RunService.Heartbeat:Wait()
        elapsed = os.clock() - t0
        local alpha = math.clamp(elapsed / segTime, 0, 1)
        local cx = startX + dx * alpha
        local cy = startY + dy * alpha
        setInternalPlayerPos(cx, cy)
        local facingBit = (dx >= 0) and 1 or 0
        safeSendMove({
            x = cx,
            y = cy,
            vx = (dist > 0) and (dx / dist) * STEP_SPEED or 0,
            vy = (dist > 0) and (dy / dist) * STEP_SPEED or 0,
            flags = 2 + facingBit,
        })
    end

    setInternalPlayerPos(destX, destY)
    local finalFacing = (dx >= 0) and 1 or 0
    safeSendMove({
        x = destX,
        y = destY,
        vx = 0,
        vy = 0,
        flags = 2 + finalFacing,
    })
    RunService.Heartbeat:Wait()
end

local function walkOrPathfindTo(targetX, targetY, worldW, worldH)
    local px, py, rawX, rawY = getPlayerTilePos()
    if not px or not py then return false end

    local dist = math.abs(px - targetX) + math.abs(py - targetY)
    if dist <= 1 and not isSolidTile(targetX, targetY) then
        stepToColumn(targetX, targetY)
        return true
    end

    local path = findPath(px, py, targetX, targetY, 15000)
    if path and #path > 0 then
        if ClearWorld then ClearWorld.busy = true end
        if AutoBuildDF then AutoBuildDF.busy = true end
        if AutoPlant then AutoPlant.busy = true end
        if AutoHarvest then AutoHarvest.busy = true end
        followPath(path, 0.48)
        if ClearWorld then ClearWorld.busy = false end
        if AutoBuildDF then AutoBuildDF.busy = false end
        if AutoPlant then AutoPlant.busy = false end
        if AutoHarvest then AutoHarvest.busy = false end
        return true
    else
        for dy = -1, 1 do
            for dx = -1, 1 do
                local sx = targetX + dx
                local sy = targetY + dy
                if sx >= 0 and sx < (worldW or 100) and sy >= 0 and sy < (worldH or 60) then
                    if not isSolidTile(sx, sy) then
                        local altPath = findPath(px, py, sx, sy, 15000)
                        if altPath and #altPath > 0 then
                            if ClearWorld then ClearWorld.busy = true end
                            if AutoBuildDF then AutoBuildDF.busy = true end
                            if AutoPlant then AutoPlant.busy = true end
                            if AutoHarvest then AutoHarvest.busy = true end
                            followPath(altPath, 0.48)
                            if ClearWorld then ClearWorld.busy = false end
                            if AutoBuildDF then AutoBuildDF.busy = false end
                            if AutoPlant then AutoPlant.busy = false end
                            if AutoHarvest then AutoHarvest.busy = false end
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

-- Dekati target tile secara aman (jarak <= 2 tile):
-- Jika di baris yang sama dan jalan terbuka: stepToColumn (sangat cepat & mulus)
-- Jika beda baris atau ada obstacle: A* pathfinding (walkOrPathfindTo)
local function approachTile(targetX, targetY, worldW, worldH)
    local curPx, curPy = getPlayerTilePos()
    if not curPx or not curPy then return false end

    local dist = math.abs(curPx - targetX) + math.abs(curPy - targetY)
    if dist <= 2 then
        return true
    end

    -- 1. Jika di baris yang sama persis (curPy == targetY), cek apakah jalan terbuka DAN seluruh tile ada pijakan
    if curPy == targetY then
        local hasFullFooting = true
        local dir = (targetX > curPx) and 1 or -1
        for cx = curPx + dir, targetX, dir do
            if isSolidTile(cx, targetY) or not hasFooting(cx, targetY) then
                hasFullFooting = false
                break
            end
        end
        if hasFullFooting then
            stepToColumn(targetX, targetY)
            local npx, npy = getPlayerTilePos()
            if npx and npy and (math.abs(npx - targetX) + math.abs(npy - targetY) <= 2) then
                return true
            end
        end
    end

    -- 2. Jika beda baris atau terhalang, gunakan A* pathfinding
    walkOrPathfindTo(targetX, targetY, worldW, worldH)

    -- 3. Verifikasi posisi akhir
    local endPx, endPy = getPlayerTilePos()
    if endPx and endPy and (math.abs(endPx - targetX) + math.abs(endPy - targetY) <= 2) then
        return true
    end

    return false
end

-- Validasi jarak aman: jika jarak > 2 tile dari posisi char, langsung pathfind ulang ke posisi terdekat!
local function ensureTileInRange(tx, ty, worldW, worldH)
    if not tx or not ty then return false end
    local px, py = getPlayerTilePos()
    if not px or not py then return true end

    local dist = math.sqrt((px - tx)^2 + (py - ty)^2)
    if dist <= 2.0 then
        return true -- Sudah dalam jarak pukul aman (<= 2 tile)
    end

    -- Jarak > 2 tile! Jangan paksa break dari jauh, langsung pathfind ulang
    if lblClearStatus then
        lblClearStatus.Text = string.format("🚶 Jarak > 2 tile (%.1f) ➔ Pathfind ulang ke (%d, %d)...", dist, tx, ty)
    end

    -- Cari posisi berdiri non-solid di sekitar tile target (jarak 1 tile)
    local bestSpot = nil
    local bestDist = 999999
    local offsets = {
        { dx = -1, dy = 0 },
        { dx = 1,  dy = 0 },
        { dx = 0,  dy = 1 },
        { dx = 0,  dy = -1 },
        { dx = -1, dy = -1 },
        { dx = 1,  dy = -1 },
        { dx = -1, dy = 1 },
        { dx = 1,  dy = 1 },
    }

    for _, off in ipairs(offsets) do
        local sx = tx + off.dx
        local sy = ty + off.dy
        if sx >= 0 and sx < (worldW or 100) and sy >= 0 and sy < (worldH or 60) then
            if not isSolidTile(sx, sy) then
                local d = math.abs(px - sx) + math.abs(py - sy)
                if d < bestDist then
                    bestDist = d
                    bestSpot = { x = sx, y = sy }
                end
            end
        end
    end

    if bestSpot then
        walkOrPathfindTo(bestSpot.x, bestSpot.y, worldW, worldH)
    else
        walkOrPathfindTo(tx, ty, worldW, worldH)
    end
    task.wait(0.03)

    local npx, npy = getPlayerTilePos()
    if npx and npy then
        local newDist = math.sqrt((npx - tx)^2 + (npy - ty)^2)
        return (newDist <= 2.1)
    end
    return false
end

-- Eksekusi penghancuran tile secara realtime dengan safety check jarak <= 2 tile
local function breakTileRealtime(layer, tx, ty, worldW, worldH)
    if not tx or not ty or tx < 0 or ty < 0 then return true end
    if not ClearWorld.active then return false end

    local curId = getRealtimeTile(layer, tx, ty)
    if not curId or curId == 0 or isProtectedTile(curId) or isBedrockTile(curId) then
        return true -- Sudah kosong atau tidak boleh dihancurkan
    end

    -- CEK JARAK REALTIME: Jika jarak > 2 tile, langsung pathfind ulang ke dekat target!
    local inRange = ensureTileInRange(tx, ty, worldW or 100, worldH or 60)
    if not inRange then
        return false -- Tidak terjangkau, jangan memukul dari jauh
    end

    local reqHits = getBlockHits(curId)
    local hitDelay = ClearWorld.hitDelay or 0.17

    -- Kirim paket pukulan (HIT) sesuai kebutuhan durabilitas blok
    for h = 1, reqHits do
        if not ClearWorld.active then return false end
        if h > 1 and getRealtimeTile(layer, tx, ty) == 0 then
            break -- Sudah pecah lebih awal
        end
        sendActPacket(ACT_KIND.HIT, tx, ty)
        task.wait(hitDelay)
    end

    -- Safety hit ekstra jika blok keras (> 1 hit) untuk mencegah paket drop akibat lag
    if reqHits > 1 and getRealtimeTile(layer, tx, ty) ~= 0 then
        sendActPacket(ACT_KIND.HIT, tx, ty)
        task.wait(0.04)
    end

    -- Komit penghancuran ke server dan paksa update visual client
    sendTilePacket(layer, tx, ty, 0, false)
    forceClientTileUpdate(layer, tx, ty, 0)
    task.wait(0.02)

    return (getRealtimeTile(layer, tx, ty) == 0)
end

-- STRICT WHITELIST: Hanya ID blok/seed natural sampah hasil world generation yang diizinkan untuk di-trash!
-- Di luar 8 ID ini (atau rarity > 1, clothing, tool, lock, farmable lain), DILARANG KERAS DI-TRASH!
local SAFE_WORLD_JUNK_IDS = {
    [2]  = true, -- Dirt
    [3]  = true, -- Dirt Seed
    [4]  = true, -- Lava
    [5]  = true, -- Lava Seed
    [10] = true, -- Rock
    [11] = true, -- Rock Seed
    [14] = true, -- Cave Background
    [15] = true, -- Cave Background Seed
}

local function isSafeNaturalJunk(itemId)
    if not itemId or itemId <= 0 or itemId == 112 then return false end
    if not SAFE_WORLD_JUNK_IDS[itemId] then return false end

    local it = ItemDB and ItemDB[itemId]
    if it then
        if it.rarity and it.rarity > 1 then return false end
        if it.slot then return false end -- clothing / wearables / wings / hats
        if it.kind == "tool" then return false end
        if it.lock or it.area or it.bedrock or it.unbreakable then return false end
    end
    return true
end

-- Hanya membuang sejumlah 'amount' spesifik dari item sampah hasil break yang baru dipungut
local function trashSpecificJunkItem(itemId, amount)
    if not isSafeNaturalJunk(itemId) then return end
    if not amount or amount <= 0 then return end

    local inv = getNativeInventory()
    if not inv then return end

    local totalCount = getRealtimeItemCount(itemId)
    if totalCount <= 0 then return end

    local countToTrash = math.min(math.floor(amount), totalCount)
    if countToTrash <= 0 then return end

    if inv.remove then
        pcall(inv.remove, inv, itemId, countToTrash)
    end

    local curr = nil
    pcall(function()
        local LP = Players.LocalPlayer
        local invModule = LP and LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("GameGui") and LP.PlayerGui.GameGui:FindFirstChild("InventoryUI")
        if invModule then
            local ok, mod = pcall(require, invModule)
            if ok and mod and mod.current then curr = mod.current end
        end
    end)

    sendRecyclePacket(itemId, countToTrash)

    if curr and curr.refresh then pcall(curr.refresh) end
end

-- Membersihkan satu kolom band (FG & BG) + Sweep Droppan + Strict Delta Auto-Trash
local function clearColumnBandRealtime(colX, bandRows, worldW, worldH)
    if not ClearWorld.active or not colX or colX < 0 or colX >= worldW then return end

    local brokenTiles = {}
    local brokenJunkIds = {}

    for _, rowY in ipairs(bandRows) do
        if not ClearWorld.active then break end
        if rowY >= 0 and rowY < worldH then
            -- 1. Foreground (FG)
            if isTileBreakable("fg", colX, rowY) then
                local fg = getRealtimeTile("fg", colX, rowY)
                if lblClearStatus and fg and fg ~= 0 then
                    local it = ItemDB and ItemDB[fg]
                    local name = it and it.name or ("ID " .. fg)
                    lblClearStatus.Text = string.format("⛏️ [FG] %s di (%d, %d)...", name, colX, rowY)
                end
                if fg and isSafeNaturalJunk(fg) then
                    brokenJunkIds[fg] = true
                    if isSafeNaturalJunk(fg + 1) then
                        brokenJunkIds[fg + 1] = true
                    end
                end
                breakTileRealtime("fg", colX, rowY, worldW, worldH)
                table.insert(brokenTiles, { x = colX, y = rowY })
                ClearWorld.totalCleared = ClearWorld.totalCleared + 1
                task.wait(0.015)
            end

            -- 2. Background (BG) jika clearBG aktif (hanya jika FG bukan Bedrock/Protected)
            if ClearWorld.clearBG and isTileBreakable("bg", colX, rowY) then
                local bg = getRealtimeTile("bg", colX, rowY)
                if lblClearStatus and bg and bg ~= 0 then
                    local it = ItemDB and ItemDB[bg]
                    local name = it and it.name or ("ID " .. bg)
                    lblClearStatus.Text = string.format("⛏️ [BG] %s di (%d, %d)...", name, colX, rowY)
                end
                if bg and isSafeNaturalJunk(bg) then
                    brokenJunkIds[bg] = true
                    if isSafeNaturalJunk(bg + 1) then
                        brokenJunkIds[bg + 1] = true
                    end
                end
                breakTileRealtime("bg", colX, rowY, worldW, worldH)
                table.insert(brokenTiles, { x = colX, y = rowY })
                ClearWorld.totalCleared = ClearWorld.totalCleared + 1
                task.wait(0.015)
            end
        end
    end

    -- Sweep drops on the broken column & ONLY trash the newly collected delta of natural junk
    if ClearWorld.autoSweep and #brokenTiles > 0 then
        local px, py, rawX, rawY = getPlayerTilePos()

        -- Ambil snapshot jumlah stock item junk SEBELUM di-sweep
        local countsBefore = {}
        if ClearWorld.autoTrash then
            for jId, _ in pairs(brokenJunkIds) do
                countsBefore[jId] = getRealtimeItemCount(jId)
            end
        end

        collectDropsAtTiles(brokenTiles, px, py, rawX, rawY)

        -- HANYA buang delta (selisih bertambah) dari hasil sapuan kolom ini!
        -- Stok lama dan item lain yang tidak di-break TIDAK PERNAH disentuh!
        if ClearWorld.autoTrash then
            task.wait(0.03)
            for jId, _ in pairs(brokenJunkIds) do
                local countAfter = getRealtimeItemCount(jId)
                local before = countsBefore[jId] or 0
                local delta = countAfter - before
                if delta > 0 then
                    trashSpecificJunkItem(jId, delta)
                end
            end
        end
    end
end

local function clearColumn3Realtime(colX, y1, y2, y3, worldW, worldH)
    clearColumnBandRealtime(colX, { y1, y2, y3 }, worldW, worldH)
end

-- Mencari koordinat tile teratas pertama di world yang masih memiliki blok breakable (FG atau BG)
local function getTopmostBreakableTile(worldW, worldH)
    for y = 0, worldH - 1 do
        for x = 0, worldW - 1 do
            if hasBreakableAtTile(x, y) then
                return x, y
            end
        end
    end
    return nil, nil
end

-- Cek apakah sebuah baris y memiliki setidaknya satu blok breakable
local function rowHasBreakable(rY, worldW, worldH)
    if not rY or rY < 0 or rY >= worldH then return false end
    for x = 0, worldW - 1 do
        if hasBreakableAtTile(x, rY) then
            return true
        end
    end
    return false
end

-- Menentukan baris-baris breakable yang masuk ke dalam band (maksimal 3 baris)
-- dan menentukan ketinggian berjalan (walkY) yang aman (tidak pernah pada baris bedrock!)
local function getBandRowsAndWalkY(topY, worldW, worldH)
    local bandRows = {}
    for offset = 0, 2 do
        local rY = topY + offset
        if rY < worldH and rowHasBreakable(rY, worldW, worldH) then
            table.insert(bandRows, rY)
        end
    end

    if #bandRows == 0 then
        bandRows = { topY }
    end

    local walkY
    if #bandRows == 3 then
        walkY = bandRows[2] -- baris tengah
    elseif #bandRows == 2 then
        walkY = bandRows[2] -- baris bawah dari 2 baris (misal 57, 58 -> walkY = 58)
    else
        walkY = bandRows[1] -- baris tunggal (misal 58 -> walkY = 58, kaki di atas bedrock 59)
    end

    return bandRows, walkY
end

-- Menentukan batas kolom paling kiri (minX) dan paling kanan (maxX) yang memiliki blok pada band
local function getBandBlockBounds(bandRows, worldW, worldH)
    local minX, maxX = nil, nil
    for x = 0, worldW - 1 do
        local hasBlock = false
        for _, rY in ipairs(bandRows) do
            if rY >= 0 and rY < worldH then
                if hasBreakableAtTile(x, rY) then
                    hasBlock = true
                    break
                end
            end
        end
        if hasBlock then
            if not minX then minX = x end
            maxX = x
        end
    end
    return minX, maxX
end

-- Cek realtime apakah kolom colX memiliki blok yang perlu dihancurkan di baris bandRows
local function columnHasBlocks(colX, bandRows, worldH)
    if not colX then return false end
    for _, rY in ipairs(bandRows) do
        if rY >= 0 and rY < worldH then
            if hasBreakableAtTile(colX, rY) then
                return true
            end
        end
    end
    return false
end

stopClearWorld = function()
    ClearWorld.active = false
    ClearWorld.busy = false
    ClearWorld.thread = nil
    if updateClearWorldUI then updateClearWorldUI() end
end

startClearWorld = function()
    if ClearWorld.active then return end
    ClearWorld.active = true
    ClearWorld.busy = false

    if PNB and PNB.active and stopPNB then
        stopPNB()
    end

    if updateClearWorldUI then updateClearWorldUI() end

    ClearWorld.thread = task.spawn(function()
        local w = getNativeWorld()
        if not w then
            stopClearWorld()
            return
        end
        local worldW = w.w or 100
        local worldH = w.h or 60

        -- Cari tile teratas pertama di world yang masih memiliki blok breakable (FG atau BG)
        local initX, initY = getTopmostBreakableTile(worldW, worldH)
        if not initY then
            if lblClearStatus then
                lblClearStatus.Text = "🎉 Selesai! Tidak ada tile yang perlu dibersihkan."
                lblClearStatus.TextColor3 = C.green
            end
            stopClearWorld()
            return
        end

        local currentTopY = initY
        local bandIndex = 0

        while ClearWorld.active do
            local bandRows, walkY = getBandRowsAndWalkY(currentTopY, worldW, worldH)

            -- Cari batas minX dan maxX yang benar-benar ada blok breakable di band ini
            local minX, maxX = getBandBlockBounds(bandRows, worldW, worldH)
            if not minX or not maxX then
                -- Band ini kosong atau hanya berisi bedrock/protected! Cari tile teratas berikutnya
                local nextX, nextY = getTopmostBreakableTile(worldW, worldH)
                if not nextY then
                    if lblClearStatus then
                        lblClearStatus.Text = string.format("🎉 Selesai! World berhasil dibersihkan (%d tile).", ClearWorld.totalCleared)
                        lblClearStatus.TextColor3 = C.green
                    end
                    stopClearWorld()
                    break
                else
                    currentTopY = nextY
                    task.wait(0.02)
                    continue
                end
            end

            -- Smart Sweep Direction: Pilih ujung yang paling dekat dengan posisi player saat ini!
            -- Mencegah bolak-balik menyeberang map (anti ping-pong pathfinding).
            local curPx, curPy = getPlayerTilePos()
            local isLeftToRight
            if curPx then
                local distToMin = math.abs(curPx - minX)
                local distToMax = math.abs(curPx - maxX)
                if distToMin <= distToMax then
                    isLeftToRight = true
                else
                    isLeftToRight = false
                end
            else
                isLeftToRight = (bandIndex % 2 == 0)
            end

            local startX = isLeftToRight and minX or maxX
            local endX   = isLeftToRight and maxX or minX
            local stepDir = isLeftToRight and 1 or -1

            local dirName = isLeftToRight and "Kiri ➔ Kanan" or "Kanan ➔ Kiri"
            local bandDesc = (#bandRows == 1) and string.format("Y: %d (1 Baris)", bandRows[1])
                or string.format("Y: %d-%d (%d Baris)", bandRows[1], bandRows[#bandRows], #bandRows)

            if lblClearStatus then
                lblClearStatus.Text = string.format("⚡ Band %s [%d..%d] (%s) [6-Block Mode]...", bandDesc, minX, maxX, dirName)
            end

            -- 1. PATHFIND LANGSUNG KE TILE AWAL BLOK (Hanya jika belum berada di dekatnya)
            local px, py = getPlayerTilePos()
            if px and py then
                local distToStart = math.abs(px - startX) + math.abs(py - walkY)
                if distToStart > 1 then
                    if lblClearStatus then
                        lblClearStatus.Text = string.format("🚶 Menuju blok awal (%d, %d)...", startX, walkY)
                    end
                    walkOrPathfindTo(startX, walkY, worldW, worldH)
                end
            end
            if not ClearWorld.active then break end

            -- Bersihkan kolom tempat berdiri saat ini jika memuat blok
            if columnHasBlocks(startX, bandRows, worldH) then
                clearColumnBandRealtime(startX, bandRows, worldW, worldH)
            end
            if not ClearWorld.active then break end

            -- 2. LOOP 6-BLOCK (Band Rows x 2 Kolom per langkah maju)
            local currCol = startX
            while (stepDir > 0 and currCol < endX) or (stepDir < 0 and currCol > endX) do
                if not ClearWorld.active then break end

                local col1 = currCol + stepDir
                local col2 = currCol + (stepDir * 2)

                -- Batasi col2 agar tidak melewati endX atau batas world
                if (stepDir > 0 and col2 > endX) or (stepDir < 0 and col2 < endX) or col2 < 0 or col2 >= worldW then
                    col2 = nil
                end

                -- DETEKSI REALTIME: Cek apakah col1 dan col2 memiliki blok
                local hasCol1 = columnHasBlocks(col1, bandRows, worldH)
                local hasCol2 = col2 and columnHasBlocks(col2, bandRows, worldH)

                if not hasCol1 and not hasCol2 then
                    -- Cari kolom terdekat berikutnya yang benar-benar memuat blok
                    local nextBlockCol = nil
                    local probe = (col2 or col1) + stepDir
                    while (stepDir > 0 and probe <= endX) or (stepDir < 0 and probe >= endX) do
                        if columnHasBlocks(probe, bandRows, worldH) then
                            nextBlockCol = probe
                            break
                        end
                        probe = probe + stepDir
                    end

                    if not nextBlockCol then
                        -- Sisa band ini sudah bersih total
                        break
                    else
                        -- Ada celah kosong: langsung maju ke kolom tepat di depan blok tersebut
                        local standCol = nextBlockCol - stepDir
                        if currCol ~= standCol then
                            if lblClearStatus then
                                lblClearStatus.Text = string.format("⏩ Lewati celah kosong ➔ Maju ke X: %d...", standCol)
                            end
                            walkOrPathfindTo(standCol, walkY, worldW, worldH)
                            currCol = standCol
                        else
                            currCol = col1
                        end
                    end
                else
                    -- Cek apakah col1 terhalang blok solid terproteksi (Door/Bedrock/Lock)
                    -- HANYA memeriksa baris-baris dalam bandRows (TIDAK pernah mengecek bedrock di luar band!)
                    local col1Blocked = false
                    for _, rY in ipairs(bandRows) do
                        local fg = getRealtimeTile("fg", col1, rY)
                        if fg and (isProtectedTile(fg) or isBedrockTile(fg)) and isSolidTile(col1, rY) then
                            col1Blocked = true
                            break
                        end
                    end

                    if col1Blocked then
                        -- Bypass rintangan padat terproteksi via pathfinding
                        local bypassCol = col1 + stepDir
                        if (stepDir > 0 and bypassCol <= endX) or (stepDir < 0 and bypassCol >= endX) then
                            if lblClearStatus then
                                lblClearStatus.Text = string.format("🔄 Bypass rintangan di X: %d...", col1)
                            end
                            walkOrPathfindTo(bypassCol, walkY, worldW, worldH)
                            currCol = bypassCol
                        else
                            break
                        end
                    else
                        -- A. HANCURKAN BATCH BLOK
                        if lblClearStatus then
                            local batchDesc = col2 and string.format("X: %d-%d (6 Blok)", col1, col2) or string.format("X: %d (3 Blok)", col1)
                            lblClearStatus.Text = string.format("⛏️ Menghancurkan batch %s...", batchDesc)
                        end

                        -- 1. Hancurkan col1 dulu (karakter di currCol, jarak ke col1 <= 1.41 tile)
                        if hasCol1 then
                            clearColumnBandRealtime(col1, bandRows, worldW, worldH)
                        end

                        if not ClearWorld.active then break end

                        -- Safety check: pastikan col1 sudah hancur
                        local retryCount = 0
                        while ClearWorld.active and columnHasBlocks(col1, bandRows, worldH) and retryCount < 2 do
                            retryCount = retryCount + 1
                            task.wait(0.04)
                            clearColumnBandRealtime(col1, bandRows, worldW, worldH)
                        end

                        if not ClearWorld.active then break end

                        -- 2. Jika ada col2: Karakter maju dulu ke col1 agar jarak ke col2 menjadi <= 1.41 tile!
                        --    (Mencegah memukul col2 dari jarak > 2 tile)
                        local col2Clean = true
                        if col2 then
                            if not isSolidTile(col1, walkY) then
                                stepToColumn(col1, walkY)
                                currCol = col1
                            else
                                ensureTileInRange(col2, walkY, worldW, worldH)
                            end

                            if hasCol2 then
                                clearColumnBandRealtime(col2, bandRows, worldW, worldH)
                            end

                            -- Safety check col2
                            local retry2 = 0
                            while ClearWorld.active and columnHasBlocks(col2, bandRows, worldH) and retry2 < 2 do
                                retry2 = retry2 + 1
                                task.wait(0.04)
                                clearColumnBandRealtime(col2, bandRows, worldW, worldH)
                            end

                            if columnHasBlocks(col2, bandRows, worldH) then
                                col2Clean = false
                            end
                        end

                        if not ClearWorld.active then break end

                        -- B. GESER MAJU (Advance):
                        -- Jika col2 ada dan col2 bersih: maju ke col2!
                        -- Jika col2 tidak ada atau belum bersih: maju ke col1 jika belum di col1
                        if col2 and col2Clean and not isSolidTile(col2, walkY) then
                            if lblClearStatus then
                                lblClearStatus.Text = string.format("🚶 Maju ke X: %d (%s)", col2, bandDesc)
                            end
                            stepToColumn(col2, walkY)
                            currCol = col2
                        elseif not isSolidTile(col1, walkY) then
                            stepToColumn(col1, walkY)
                            currCol = col1
                        else
                            currCol = col2 or col1
                        end

                        if updateClearWorldUI then
                            updateClearWorldUI()
                        end
                    end
                end

                task.wait(0.015)
            end

            -- Lanjut ke band berikutnya
            bandIndex = bandIndex + 1
            local nextX, nextY = getTopmostBreakableTile(worldW, worldH)
            if not nextY then
                if lblClearStatus then
                    lblClearStatus.Text = string.format("🎉 Selesai! World berhasil dibersihkan (%d tile).", ClearWorld.totalCleared)
                    lblClearStatus.TextColor3 = C.green
                end
                stopClearWorld()
                break
            else
                currentTopY = nextY
            end

            task.wait(0.04)
        end
    end)
end

-- ═══════════════════════════════════════
--  AUTO BUILD DIRT FARM (DF) ENGINE
-- ═══════════════════════════════════════
AutoBuildDF = {
    active        = false,
    busy          = false,
    thread        = nil,
    mainBlockId   = 2,            -- Default: Dirt (ID 2)
    mainBlockName = "Dirt",
    platBlockId   = 194,          -- Default: Mushroom Platform (ID 194)
    platBlockName = "Mushroom Platform",
    platWidth     = 2,            -- 2 platform tiles pada pinggiran kiri & kanan
    bottomY       = 53,           -- Baris paling bawah (di atas bedrock 54)
    topY          = 3,            -- Baris teratas yang akan dibangun
    stepY         = 2,            -- Jarak per lantai (Y berkurang 2)
    minX          = 2,            -- Batas kiri world
    maxX          = 99,           -- Batas kanan world
    buildDelay    = 0.06,         -- Delay pemasangan blok
    totalPlaced   = 0,
    currentY      = 53,
}

local function getDFItemName(id)
    if not id then return "Unknown" end
    local it = ItemDB and ItemDB[id]
    return (it and it.name) or ("Item #" .. tostring(id))
end

local function findFirstIncompleteDFRow()
    local curY = AutoBuildDF.bottomY
    while curY >= AutoBuildDF.topY do
        for x = AutoBuildDF.minX, AutoBuildDF.maxX do
            local isEdgePlat = (x < AutoBuildDF.minX + AutoBuildDF.platWidth) or (x > AutoBuildDF.maxX - AutoBuildDF.platWidth)
            local expectedId = isEdgePlat and AutoBuildDF.platBlockId or AutoBuildDF.mainBlockId
            local tile = getRealtimeTile("fg", x, curY)
            if tile == 0 then
                return curY
            end
        end
        curY = curY - AutoBuildDF.stepY
    end
    return nil
end

stopAutoBuildDF = function()
    if not AutoBuildDF.active then return end
    AutoBuildDF.active = false
    AutoBuildDF.busy = false
    if AutoBuildDF.thread then
        pcall(task.cancel, AutoBuildDF.thread)
        AutoBuildDF.thread = nil
    end
    if updateDirtFarmUI then updateDirtFarmUI() end
end

startAutoBuildDF = function()
    if AutoBuildDF.active then return end
    if PNB and PNB.active and stopPNB then stopPNB() end
    if ClearWorld and ClearWorld.active and stopClearWorld then stopClearWorld() end
    if AutoPlant and AutoPlant.active and stopAutoPlant then stopAutoPlant() end
    if AutoHarvest and AutoHarvest.active and stopAutoHarvest then stopAutoHarvest() end
    if AutoFactory and AutoFactory.active and stopAutoFactory then stopAutoFactory() end

    AutoBuildDF.active = true
    AutoBuildDF.busy = false
    if updateDirtFarmUI then updateDirtFarmUI() end

    AutoBuildDF.thread = task.spawn(function()
        local worldW = 100
        local worldH = 60
        local w = getNativeWorld()
        if w and w.worldSize then
            worldW = w.worldSize.x or worldW
            worldH = w.worldSize.y or worldH
        end

        ensureMobilityHooks()

        -- Auto-detect baris pertama yang masih belum selesai (Smart Resume)
        local startY = findFirstIncompleteDFRow()
        if not startY then
            if lblDFStatus then
                lblDFStatus.Text = "[DONE] Dirt Farm sudah lengkap terbangun semua!"
                lblDFStatus.TextColor3 = C.green
            end
            stopAutoBuildDF()
            return
        end

        local curY = startY
        while AutoBuildDF.active and curY >= AutoBuildDF.topY do
            AutoBuildDF.currentY = curY
            local rowIndex = math.floor((AutoBuildDF.bottomY - curY) / AutoBuildDF.stepY)
            local isEvenRow = (rowIndex % 2 == 0)

            -- Arah serpentine:
            -- Genap = minX -> maxX (Kiri ke Kanan)
            -- Ganjil = maxX -> minX (Kanan ke Kiri)
            local startX  = isEvenRow and AutoBuildDF.minX or AutoBuildDF.maxX
            local endX    = isEvenRow and AutoBuildDF.maxX or AutoBuildDF.minX
            local stepDir = isEvenRow and 1 or -1

            -- Periksa apakah baris curY perlu dibangun
            local rowNeedsBuild = false
            for x = AutoBuildDF.minX, AutoBuildDF.maxX do
                local curTile = getRealtimeTile("fg", x, curY)
                if curTile == 0 then
                    rowNeedsBuild = true
                    break
                end
            end

            if not rowNeedsBuild then
                curY = curY - AutoBuildDF.stepY
            else
                -- Deteksi apakah tepat di bawah target build (curY + 1) adalah blok solid (misal bedrock di dasar world)
                -- Jika di bawahnya solid: char TIDAK BOLEH maksa nembus solid ke curY + 1!
                -- Sebaliknya: char berjalan di atasnya (walkY = curY), dan menaruh blok tepat di belakang char!
                local isBelowSolid = false
                for x = AutoBuildDF.minX, AutoBuildDF.maxX do
                    if isSolidTile(x, curY + 1) then
                        isBelowSolid = true
                        break
                    end
                end

                local walkY = isBelowSolid and curY or (curY + 1)

                -- Cari tile kosong pertama di baris ini
                local firstMissingX = startX
                local probeX = startX
                while (stepDir > 0 and probeX <= endX) or (stepDir < 0 and probeX >= endX) do
                    local curTile = getRealtimeTile("fg", probeX, curY)
                    if curTile == 0 then
                        firstMissingX = probeX
                        break
                    end
                    probeX = probeX + stepDir
                end

                if lblDFStatus then
                    local modeStr = isBelowSolid and "Place di Belakang" or "Place Overhead"
                    lblDFStatus.Text = string.format("[MOVE] Menuju baris Y: %d (%s, Mulai X: %d)...", curY, modeStr, firstMissingX)
                    lblDFStatus.TextColor3 = C.cyan
                end

                -- Posisi awal berjalan:
                -- Jika isBelowSolid: mulai berdiri di depan target pertama (firstMissingX + stepDir) agar firstMissingX ada di belakang char!
                local initStandX = firstMissingX
                if isBelowSolid then
                    local candX = firstMissingX + stepDir
                    if candX >= 0 and candX < worldW and not isSolidTile(candX, walkY) then
                        initStandX = candX
                    end
                end

                -- Menuju ke posisi awal berjalan
                local px, py = getPlayerTilePos()
                if not px or math.abs(px - initStandX) > 1 or math.abs(py - walkY) > 1 then
                    walkOrPathfindTo(initStandX, walkY, worldW, worldH)
                    task.wait(0.04)
                end

                if Mobility then
                    Mobility.suspendedY = walkY + 1.0
                end

                local currCol = firstMissingX
                while AutoBuildDF.active do
                    if (stepDir > 0 and currCol > endX) or (stepDir < 0 and currCol < endX) then
                        break
                    end

                    local isEdgePlat = (currCol < AutoBuildDF.minX + AutoBuildDF.platWidth) or (currCol > AutoBuildDF.maxX - AutoBuildDF.platWidth)
                    local expectedId = isEdgePlat and AutoBuildDF.platBlockId or AutoBuildDF.mainBlockId
                    local itemName   = isEdgePlat and AutoBuildDF.platBlockName or AutoBuildDF.mainBlockName

                    -- Periksa ketersediaan item di inventori
                    local count = getRealtimeItemCount(expectedId)
                    if count <= 0 then
                        if lblDFStatus then
                            lblDFStatus.Text = string.format("[!] Habis stock %s (ID %d)! Auto Build dihentikan.", itemName, expectedId)
                            lblDFStatus.TextColor3 = C.gold
                        end
                        stopAutoBuildDF()
                        return
                    end

                    if isBelowSolid then
                        -- MODE PLACE DI BELAKANG CHAR (Underneath is solid ground / bedrock):
                        -- 1. Posisi berdiri: berada di depan target (currCol + stepDir) sehingga target berada tepat di belakang char!
                        local standX = currCol + stepDir
                        if standX < 0 or standX >= worldW or isSolidTile(standX, walkY) then
                            standX = currCol
                        end

                        stepToColumn(standX, walkY)

                        -- 2. Tempatkan blok pada koordinat currCol (tepat di belakang char) jika masih kosong
                        local curTile = getRealtimeTile("fg", currCol, curY)
                        if curTile == 0 then
                            if lblDFStatus then
                                lblDFStatus.Text = string.format("[BUILD-BEHIND] Memasang [%s] di (%d, %d)...", itemName, currCol, curY)
                                lblDFStatus.TextColor3 = C.text
                            end
                            sendActPacket(ACT_KIND.BUILD, currCol, curY)
                            sendTilePacket("fg", currCol, curY, expectedId, false)
                            forceClientTileUpdate("fg", currCol, curY, expectedId)
                            AutoBuildDF.totalPlaced = AutoBuildDF.totalPlaced + 1
                            if updateDirtFarmUI then updateDirtFarmUI() end
                            task.wait(AutoBuildDF.buildDelay)
                        end
                    else
                        -- MODE PLACE OVERHEAD (Underneath is air):
                        -- Melangkah ke kolom target pada ketinggian walkY (curY + 1)
                        stepToColumn(currCol, walkY)

                        -- Tempatkan blok di atas kepala (curY) jika kosong
                        local curTile = getRealtimeTile("fg", currCol, curY)
                        if curTile == 0 then
                            if lblDFStatus then
                                lblDFStatus.Text = string.format("[BUILD] Memasang [%s] di (%d, %d)...", itemName, currCol, curY)
                                lblDFStatus.TextColor3 = C.text
                            end
                            sendActPacket(ACT_KIND.BUILD, currCol, curY)
                            sendTilePacket("fg", currCol, curY, expectedId, false)
                            forceClientTileUpdate("fg", currCol, curY, expectedId)
                            AutoBuildDF.totalPlaced = AutoBuildDF.totalPlaced + 1
                            if updateDirtFarmUI then updateDirtFarmUI() end
                            task.wait(AutoBuildDF.buildDelay)
                        end
                    end

                    currCol = currCol + stepDir
                    task.wait(0.015)
                end

                -- Selesai 1 baris, lanjut ke baris di atasnya
                curY = curY - AutoBuildDF.stepY
                task.wait(0.04)
            end
        end

        if lblDFStatus then
            lblDFStatus.Text = string.format("[DONE] Selesai! Dirt Farm berhasil dibangun (%d blok).", AutoBuildDF.totalPlaced)
            lblDFStatus.TextColor3 = C.green
        end
        stopAutoBuildDF()
    end)
end

-- ═══════════════════════════════════════
--  AUTO HARVEST & TREE SCANNER ENGINE (FULL WORLD & ROW-BY-ROW SERPENTINE)
-- ═══════════════════════════════════════
local itemLookup = {}
pcall(function()
    local Autotile = require(Shared:WaitForChild("Autotile"))
    if ItemDB and Autotile then
        for id = 1, 15000 do
            local it = ItemDB[id]
            if it and it.atlas then
                local ax, ay = Autotile.aloneCell(it)
                if it.kind == "cloth" and it.slot == "feet" then
                    ay = ay * 2
                end
                itemLookup[string.format("%s_%d_%d", it.atlas, ax, ay)] = id
            end
        end
    end
end)

local cachedNativeTrees = nil
local lastTreeCheck = 0
local function getNativeTrees()
    if cachedNativeTrees then return cachedNativeTrees end
    local now = os.clock()
    if now - lastTreeCheck < 1 then return nil end
    lastTreeCheck = now

    if not debug or not debug.getupvalues or not getconnections then return nil end
    local rem = WorldRemotes:FindFirstChild("TreeChanged")
    if rem and rem:IsA("RemoteEvent") then
        for _, conn in ipairs(getconnections(rem.OnClientEvent)) do
            if type(conn.Function) == "function" then
                local upvals = debug.getupvalues(conn.Function)
                -- setTree: upvals[1]=w, upvals[2]=u2962 (full world trees table)
                if type(upvals[2]) == "table" then
                    cachedNativeTrees = upvals[2]
                    return upvals[2]
                end
                for _, v in pairs(upvals) do
                    if type(v) == "table" then
                        for _, entry in pairs(v) do
                            if type(entry) == "table" and (entry.p ~= nil or entry.s ~= nil or entry.f ~= nil) then
                                cachedNativeTrees = v
                                return v
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function scanWorldTrees()
    local list = {}
    local nativeTrees = getNativeTrees()
    local w = getNativeWorld()
    local worldW = (w and w.w) or 100
    local worldH = (w and w.h) or 60
    local serverNow = workspace:GetServerTimeNow()
    local visited = {}

    -- 1. Scan semua pohon dari nativeTrees (u2962) - full world database pohon game
    if nativeTrees then
        for key, entry in pairs(nativeTrees) do
            local numKey = tonumber(key)
            if numKey and type(entry) == "table" then
                local tx = numKey % worldW
                local ty = math.floor(numKey / worldW)
                local curFg = w and w.fg and w.fg[ty] and w.fg[ty][tx]
                if curFg and curFg > 0 then
                    local seedId = curFg
                    local fruitCount = tonumber(entry.f) or 0
                    local growTime = tonumber(entry.s) or (ItemDB and ItemDB[seedId] and ItemDB[seedId].grow) or 30
                    local plantTime = tonumber(entry.p)

                    -- STRICT RIPENESS: Hanya matang jika waktu tanam terverifikasi dan elapsed >= growTime
                    local isRipe = false
                    local progress = 0
                    if plantTime and plantTime > 0 then
                        local elapsed = math.max(0, serverNow - plantTime)
                        progress = math.clamp(math.floor((elapsed / math.max(1, growTime)) * 100), 0, 100)
                        if elapsed >= growTime then
                            isRipe = true
                        end
                    end

                    local fruitId = nil
                    if seedId and ItemDB and ItemDB[seedId] then
                        fruitId = ItemDB[seedId].block or (seedId - 1)
                    end

                    local treeName = "Pohon"
                    if fruitId and ItemDB and ItemDB[fruitId] then
                        treeName = (ItemDB[fruitId].name or "Item") .. " Tree"
                    elseif seedId and ItemDB and ItemDB[seedId] then
                        treeName = (ItemDB[seedId].name or "Seed") .. " Tree"
                    end

                    visited[numKey] = true
                    table.insert(list, {
                        x = tx,
                        y = ty,
                        name = treeName,
                        seedId = seedId,
                        fruitId = fruitId,
                        fruits = isRipe and math.max(fruitCount, 1) or 0,
                        isRipe = isRipe,
                        progress = progress,
                    })
                end
            end
        end
    end

    -- 2. Scan foreground w.fg secara menyeluruh di seluruh world (100x60) untuk mendeteksi seed/tree yang belum terdata di nativeTrees
    if w and w.fg then
        for ty = 0, worldH - 1 do
            local row = w.fg[ty]
            if row then
                for tx = 0, worldW - 1 do
                    local tid = row[tx]
                    local numKey = ty * worldW + tx
                    if tid and tid > 0 and not visited[numKey] then
                        local db = ItemDB and ItemDB[tid]
                        if db and (db.kind == "seed" or db.tree ~= nil or db.grow ~= nil) then
                            local treeName = (db.name or "Seed") .. " Tree"
                            local fruitId = db.block or (tid - 1)
                            visited[numKey] = true
                            -- JANGAN PERNAH ASUMSIKAN RIPE JIKA TIDAK ADA DATA TIMER!
                            -- Pohon yang tidak memiliki konfirmasi timer dari u2962 SELALU UNREADY (isRipe = false)
                            table.insert(list, {
                                x = tx,
                                y = ty,
                                name = treeName,
                                seedId = tid,
                                fruitId = fruitId,
                                fruits = 0,
                                isRipe = false, -- STRICT UNREADY: Jangan pernah panen jika belum terkonfirmasi ripe!
                                progress = 0,
                            })
                        end
                    end
                end
            end
        end
    end

    return list
end

stopAutoHarvest = function()
    AutoHarvest.active = false
    AutoHarvest.status = "Standby"
    if AutoHarvest.thread then
        pcall(task.cancel, AutoHarvest.thread)
        AutoHarvest.thread = nil
    end
    print("[SYSHUB] Auto Harvest dihentikan.")
    if updateHarvestUI then updateHarvestUI() end
end

startAutoHarvest = function()
    if AutoHarvest.active then return end
    if AutoFactory and AutoFactory.active and stopAutoFactory then stopAutoFactory() end
    AutoHarvest.active = true
    AutoHarvest.status = "Scanning pohon ripe full world..."
    print("[SYSHUB] Auto Harvest dimulai!")
    if updateHarvestUI then updateHarvestUI() end

    AutoHarvest.thread = task.spawn(function()
        local worldW = 100
        local worldH = 60
        local w = getNativeWorld()
        if w and w.worldSize then
            worldW = w.worldSize.x or worldW
            worldH = w.worldSize.y or worldH
        end

        ensureMobilityHooks()

        while AutoHarvest.active do
            local px, py = getPlayerTilePos()
            if not px or not py then
                task.wait(0.2)
                continue
            end

            local allTrees = scanWorldTrees()
            local ripeTrees = {}
            for _, t in ipairs(allTrees) do
                if t.isRipe then
                    table.insert(ripeTrees, t)
                end
            end

            if #ripeTrees == 0 then
                AutoHarvest.status = string.format("Menunggu pohon matang (%d pohon belum ripe)", #allTrees)
                if updateHarvestUI then updateHarvestUI() end
                task.wait(1.5)
                continue
            end

            -- Kelompokkan pohon ripe per baris Y
            local rowMap = {}
            local rowList = {}
            for _, t in ipairs(ripeTrees) do
                if not rowMap[t.y] then
                    rowMap[t.y] = {}
                    table.insert(rowList, t.y)
                end
                table.insert(rowMap[t.y], t)
            end

            -- Urutkan baris dari bawah ke atas (Y descending: 59 -> 0, persis seperti pola DF)
            table.sort(rowList, function(a, b) return a > b end)

            -- Panen baris demi baris secara serpentine zigzag
            for rowIndex, rY in ipairs(rowList) do
                if not AutoHarvest.active then break end

                local isLeftToRight = (rowIndex % 2 == 1)
                local rowTrees = rowMap[rY]
                table.sort(rowTrees, function(a, b)
                    if isLeftToRight then
                        return a.x < b.x
                    else
                        return a.x > b.x
                    end
                end)

                for _, target in ipairs(rowTrees) do
                    if not AutoHarvest.active then break end

                    local curFg = getRealtimeTile("fg", target.x, target.y)
                    if curFg == 0 then
                        -- Pohon sudah dipanen / hilang
                        continue
                    end

                    -- STRICT REALTIME VERIFICATION:
                    -- Verifikasi langsung dengan timer native trees (u2962) sebelum mendekati/memukul pohon
                    local curServerNow = workspace:GetServerTimeNow()
                    local nTrees = getNativeTrees()
                    local numKey = target.y * worldW + target.x
                    local entry = nTrees and (nTrees[numKey] or nTrees[tostring(numKey)])

                    local isStillRipe = false
                    if entry and entry.p and entry.p > 0 then
                        local gTime = tonumber(entry.s) or (ItemDB and ItemDB[target.seedId] and ItemDB[target.seedId].grow) or 30
                        if (curServerNow - entry.p) >= gTime then
                            isStillRipe = true
                        end
                    end

                    if not isStillRipe then
                        -- Pohon belum 100% matang / unready! Lewati tanpa dipanen!
                        continue
                    end

                    AutoHarvest.status = string.format("Panen [%s] Baris Y:%d X:%d", target.name, target.y, target.x)
                    if updateHarvestUI then updateHarvestUI() end

                    -- Dekati pohon: jika di baris yang sama jalan langsung, jika beda baris A* pathfind
                    local reached = approachTile(target.x, target.y, worldW, worldH)
                    if not reached then
                        -- JANGAN PERNAH HIT DARI JAUH! Jika belum sampai di dekat pohon, skip pohon ini!
                        continue
                    end

                    if not AutoHarvest.active then break end

                    -- Hadapkan karakter ke arah pohon
                    local curPx, curPy = getPlayerTilePos()
                    if curPx then
                        local facingBit = (target.x >= curPx) and 1 or 0
                        safeSendMove({
                            x = (curPx + 0.5),
                            y = (curPy + 1.0),
                            vx = 0,
                            vy = 0,
                            flags = 2 + facingBit
                        })
                    end

                    -- Logika PNB Punch & Break untuk Panen Pohon (Persis Logika PNB):
                    -- 1. Kirim paket HIT ke server (tampil animasi punch ke orang lain)
                    sendActPacket(ACT_KIND.HIT, target.x, target.y)
                    task.wait(0.03)

                    -- 2. Komit pemecahan/panen ke server via ByteNet Net.tile
                    sendTilePacket("fg", target.x, target.y, 0, false)

                    -- 3. Update visual client & tree cache
                    forceClientTileUpdate("fg", target.x, target.y, 0)
                    local w_harvest = getNativeWorld and getNativeWorld()
                    if w_harvest and w_harvest.setTree then
                        pcall(w_harvest.setTree, target.x, target.y, nil)
                    end

                    AutoHarvest.totalHarvested = (AutoHarvest.totalHarvested or 0) + 1
                    if updateHarvestUI then updateHarvestUI() end

                    -- 4. Auto-sweep drops seketika jika Magnet aktif
                    if Magnet and Magnet.enabled then
                        task.spawn(function()
                            sweepDrops(Magnet.radius, Magnet.filterMode, 15)
                        end)
                    end

                    -- Delay panen kecil & responsif
                    task.wait(0.04)
                end
            end

            task.wait(0.1)
        end
    end)
end

-- ═══════════════════════════════════════
--  AUTO PLANT & SOIL SCANNER ENGINE (ROW-BY-ROW SERPENTINE & STRICT SEED LOCK)
-- ═══════════════════════════════════════
local function scanPlantableRows(worldW, worldH)
    worldW = worldW or 100
    worldH = worldH or 60
    local rowsWithSpots = {}
    local rowList = {}

    -- Scan dari baris paling bawah (di atas bedrock) ke atas
    for y = worldH - 2, 0, -1 do
        local spotsInRow = {}
        for x = 0, worldW - 1 do
            local curFg = getRealtimeTile("fg", x, y)
            -- Syarat media tanam:
            -- 1. curFg == 0: Tile target kosong di foreground (belum tertanam bibit/blok)
            -- 2. Tile target bukan area locked orang lain dan bukan solid
            if curFg == 0 and not isTileLocked(x, y) and not isSolidTile(x, y) then
                local belowFg = getRealtimeTile("fg", x, y + 1)
                -- 3. belowFg > 0: Tepat di bawahnya ADALAH BLOK FG (bukan kosong & bukan cuma BG!)
                -- 4. belowFg bukan bibit / pohon lain
                -- Apapun jenis blok FG di bawahnya (Dirt, Rock, Platform, Brick, Wood, Bedrock, dsb), GAS TANEM!
                if belowFg and belowFg > 0 and not isSeedOrTreeId(belowFg) then
                    table.insert(spotsInRow, { x = x, y = y })
                end
            end
        end
        if #spotsInRow > 0 then
            rowsWithSpots[y] = spotsInRow
            table.insert(rowList, y)
        end
    end

    return rowList, rowsWithSpots
end

local function getActiveSeed()
    if AutoPlant.selectedSeedId then
        local count = getRealtimeItemCount(AutoPlant.selectedSeedId)
        if count > 0 then
            return AutoPlant.selectedSeedId, AutoPlant.selectedSeedName or ("Seed #" .. AutoPlant.selectedSeedId), count
        else
            -- Stock bibit yang dipilih HABIS! JANGAN PERNAH PINDAH KE BIBIT LAIN!
            return nil, AutoPlant.selectedSeedName or ("Seed #" .. AutoPlant.selectedSeedId), 0
        end
    end

    -- Jika belum ada bibit yang dipilih, pilih bibit pertama di tas SEKALI SAJA dan kunci (lock)
    local items = fetchInventoryItems()
    for _, it in ipairs(items) do
        if (it.kind == "seed" or string.find((it.name or ""):lower(), "seed")) and it.count > 0 then
            AutoPlant.selectedSeedId = it.id
            AutoPlant.selectedSeedName = it.name
            if updatePlantUI then updatePlantUI() end
            return it.id, it.name, it.count
        end
    end

    return nil, nil, 0
end

stopAutoPlant = function()
    AutoPlant.active = false
    AutoPlant.status = "Standby"
    if AutoPlant.thread then
        pcall(task.cancel, AutoPlant.thread)
        AutoPlant.thread = nil
    end
    print("[SYSHUB] Auto Plant dihentikan.")
    if updatePlantUI then updatePlantUI() end
end

startAutoPlant = function()
    if AutoPlant.active then return end
    if AutoFactory and AutoFactory.active and stopAutoFactory then stopAutoFactory() end
    AutoPlant.active = true
    AutoPlant.status = "Memeriksa bibit..."
    print("[SYSHUB] Auto Plant dimulai!")
    if updatePlantUI then updatePlantUI() end

    AutoPlant.thread = task.spawn(function()
        local worldW = 100
        local worldH = 60
        local w = getNativeWorld()
        if w and w.worldSize then
            worldW = w.worldSize.x or worldW
            worldH = w.worldSize.y or worldH
        end

        ensureMobilityHooks()

        while AutoPlant.active do
            local px, py = getPlayerTilePos()
            if not px or not py then
                task.wait(0.2)
                continue
            end

            -- 1. Validasi bibit aktif (Hanya bibit terpilih, tidak boleh ganti)
            local seedId, seedName, seedCount = getActiveSeed()
            if not seedId or seedCount <= 0 then
                local sName = AutoPlant.selectedSeedName or "Bibit"
                AutoPlant.status = string.format("[!] Habis stock bibit [%s]! Auto Plant dihentikan.", sName)
                if lblPlantStatus then
                    lblPlantStatus:set(string.format("`4[!] Habis stock bibit [%s]! Auto Plant dihentikan.``", sName))
                end
                if updatePlantUI then updatePlantUI() end
                stopAutoPlant()
                return
            end

            -- 2. Scan tanah subur per baris
            local rowList, rowsWithSpots = scanPlantableRows(worldW, worldH)
            if #rowList == 0 then
                AutoPlant.status = "Semua tanah subur sudah tertanam! (Standby)"
                if updatePlantUI then updatePlantUI() end
                task.wait(1.5)
                continue
            end

            -- 3. Tanam baris per baris secara serpentine zigzag (Bawah ke Atas)
            for rowIndex, rY in ipairs(rowList) do
                if not AutoPlant.active then break end

                local isLeftToRight = (rowIndex % 2 == 1)
                local spotsInRow = rowsWithSpots[rY]

                -- Urutkan tile di baris: dari paling kiri ke kanan (atau sebaliknya)
                table.sort(spotsInRow, function(a, b)
                    if isLeftToRight then
                        return a.x < b.x
                    else
                        return a.x > b.x
                    end
                end)

                local walkY = rY

                for _, spot in ipairs(spotsInRow) do
                    if not AutoPlant.active then break end

                    -- Verifikasi sisa stock bibit terpilih
                    local curStock = getRealtimeItemCount(seedId)
                    if curStock <= 0 then
                        AutoPlant.status = string.format("[!] Habis stock bibit [%s]! Auto Plant dihentikan.", seedName)
                        if lblPlantStatus then
                            lblPlantStatus:set(string.format("`4[!] Habis stock bibit [%s]! Auto Plant dihentikan.``", seedName))
                        end
                        if updatePlantUI then updatePlantUI() end
                        stopAutoPlant()
                        return
                    end

                    -- Pastikan tile masih kosong
                    local curTile = getRealtimeTile("fg", spot.x, spot.y)
                    if curTile ~= 0 then
                        continue
                    end

                    AutoPlant.status = string.format("Tanam [%s] Baris Y:%d X:%d (Stock: %d)", seedName, spot.y, spot.x, curStock)
                    if updatePlantUI then updatePlantUI() end

                    -- Dekati spot tanam secara aman (jarak <= 2)
                    local reached = approachTile(spot.x, walkY, worldW, worldH)
                    if not reached then
                        continue
                    end

                    if not AutoPlant.active then break end

                    local checkTile = getRealtimeTile("fg", spot.x, spot.y)
                    if checkTile == 0 then
                        sendActPacket(ACT_KIND.PLANT, spot.x, spot.y)
                        sendTilePacket("fg", spot.x, spot.y, seedId, false)
                        forceClientTileUpdate("fg", spot.x, spot.y, seedId)
                        AutoPlant.totalPlanted = (AutoPlant.totalPlanted or 0) + 1
                        if updatePlantUI then updatePlantUI() end
                        task.wait(0.09)
                    end
                end
            end

            task.wait(0.1)
        end
    end)
end

-- ═══════════════════════════════════════
--  AUTO FACTORY ENGINE (Pabrik PnB & Farm Terpadu)
-- ═══════════════════════════════════════
local function factoryBreakBlock(tx, ty, blockId)
    local cur = getRealtimeTile("fg", tx, ty)
    if not cur or cur == 0 then return true end

    local hits = (ItemDB and ItemDB[blockId] and ItemDB[blockId].hits) or 3
    if hits <= 0 then hits = 3 end
    local hitDelay = (PNB and PNB.hitDelay) or 0.18

    for i = 1, hits do
        if not AutoFactory.active then return false end
        if i > 1 and getRealtimeTile("fg", tx, ty) == 0 then break end
        sendActPacket(ACT_KIND.HIT, tx, ty)
        if i < hits then
            task.wait(hitDelay)
        end
    end

    task.wait(0.015)
    sendTilePacket("fg", tx, ty, 0, false)
    forceClientTileUpdate("fg", tx, ty, 0)
    return true
end

stopAutoFactory = function()
    if not AutoFactory.active then return end
    AutoFactory.active = false
    AutoFactory.busy = false
    if AutoFactory.thread then
        pcall(task.cancel, AutoFactory.thread)
        AutoFactory.thread = nil
    end
    AutoFactory.status = "Standby"
    print("[SYSHUB] Auto Factory dihentikan.")
    if updateFactoryUI then updateFactoryUI() end
end

startAutoFactory = function()
    if AutoFactory.active then return end

    -- Validasi Setup sebelum start
    if not AutoFactory.posBreakX or not AutoFactory.posBreakY then
        AutoFactory.status = "[!] Tentukan Pos Break terlebih dahulu!"
        if lblFactoryStatus and lblFactoryStatus.set then
            lblFactoryStatus:set("`4[!] Pos Break belum ditentukan! Klik 'Set Pos Break'``")
        end
        return
    end

    if not AutoFactory.targetSeedId then
        AutoFactory.status = "[!] Pilih Seed target pabrik terlebih dahulu!"
        if lblFactoryStatus and lblFactoryStatus.set then
            lblFactoryStatus:set("`4[!] Pilih Seed target terlebih dahulu di dropdown!``")
        end
        return
    end

    -- Pastikan targetBlockId terisi
    if not AutoFactory.targetBlockId then
        local it = ItemDB and ItemDB[AutoFactory.targetSeedId]
        AutoFactory.targetBlockId = (it and it.block) or (AutoFactory.targetSeedId - 1)
        local bIt = ItemDB and ItemDB[AutoFactory.targetBlockId]
        AutoFactory.targetBlockName = (bIt and bIt.name) or ("Block #" .. tostring(AutoFactory.targetBlockId))
    end

    -- Hentikan automasi lain agar tidak bentrok
    if PNB and PNB.active and stopPNB then stopPNB() end
    if ClearWorld and ClearWorld.active and stopClearWorld then stopClearWorld() end
    if AutoBuildDF and AutoBuildDF.active and stopAutoBuildDF then stopAutoBuildDF() end
    if AutoPlant and AutoPlant.active and stopAutoPlant then stopAutoPlant() end
    if AutoHarvest and AutoHarvest.active and stopAutoHarvest then stopAutoHarvest() end
    if AutoFactory and AutoFactory.active and stopAutoFactory then stopAutoFactory() end

    AutoFactory.active = true
    AutoFactory.busy = false
    AutoFactory.status = "Memulai Auto Factory..."
    print("[SYSHUB] Auto Factory dimulai!")
    if updateFactoryUI then updateFactoryUI() end

    AutoFactory.thread = task.spawn(function()
        local worldW = 100
        local worldH = 60
        local w = getNativeWorld()
        if w and w.worldSize then
            worldW = w.worldSize.x or worldW
            worldH = w.worldSize.y or worldH
        end

        ensureMobilityHooks()

        while AutoFactory.active do
            local px, py = getPlayerTilePos()
            if not px or not py then
                task.wait(0.2)
                continue
            end

            local seedId = AutoFactory.targetSeedId
            local blockId = AutoFactory.targetBlockId
            local seedStock = getRealtimeItemCount(seedId)
            local blockStock = getRealtimeItemCount(blockId)

            -- Internal 0-based coordinates for movement & world engine (UI uses 1-based +1)
            local bX = AutoFactory.posBreakX and (AutoFactory.posBreakX - 1)
            local bY = AutoFactory.posBreakY and (AutoFactory.posBreakY - 1)
            local dX = AutoFactory.posDropX and (AutoFactory.posDropX - 1)
            local dY = AutoFactory.posDropY and (AutoFactory.posDropY - 1)

            if not bX or not bY then
                AutoFactory.status = "[!] Tentukan Pos Break terlebih dahulu!"
                if updateFactoryUI then updateFactoryUI() end
                task.wait(0.5)
                continue
            end

            local fieldStartX = bX
            local fieldEndX = math.min(worldW - 1, bX + AutoFactory.factoryLength)
            local fieldY = bY

            -- Scan spot kosong di baris pabrik yang siap ditanami
            local plantSpots = {}
            for tx = fieldStartX, fieldEndX do
                if tx >= 0 and tx < worldW then
                    local curFg = getRealtimeTile("fg", tx, fieldY)
                    if curFg == 0 and not isTileLocked(tx, fieldY) and not isSolidTile(tx, fieldY) then
                        local belowFg = getRealtimeTile("fg", tx, fieldY + 1)
                        if belowFg and belowFg > 0 and not isSeedOrTreeId(belowFg) then
                            table.insert(plantSpots, tx)
                        end
                    end
                end
            end

            -- ═════════════════════════════════════════
            --  PHASE 1: PLANT SEEDS (MODAL AWAL / PRIORITAS UTAMA)
            --  Tanam bibit dari tas ke seluruh spot kosong di area pabrik
            -- ═════════════════════════════════════════
            if seedStock > 0 and #plantSpots > 0 then
                AutoFactory.status = string.format("Phase 1: Tanam modal bibit (Stock: %d, Butuh: %d spot)...", seedStock, #plantSpots)
                if updateFactoryUI then updateFactoryUI() end

                for _, spotX in ipairs(plantSpots) do
                    if not AutoFactory.active then break end
                    if getRealtimeItemCount(seedId) <= 0 then break end

                    local curFg = getRealtimeTile("fg", spotX, fieldY)
                    if curFg == 0 then
                        local curPx, curPy = getPlayerTilePos()
                        if curPx and (math.abs(curPx - spotX) > 2 or curPy ~= fieldY) then
                            approachTile(spotX, fieldY, worldW, worldH)
                        else
                            stepToColumn(spotX, fieldY)
                        end

                        if not AutoFactory.active then break end

                        curFg = getRealtimeTile("fg", spotX, fieldY)
                        if curFg == 0 then
                            sendActPacket(ACT_KIND.PLANT, spotX, fieldY)
                            sendTilePacket("fg", spotX, fieldY, seedId, false)
                            forceClientTileUpdate("fg", spotX, fieldY, seedId)
                            AutoFactory.totalPlanted = AutoFactory.totalPlanted + 1
                            if updateFactoryUI then updateFactoryUI() end
                            task.wait(0.09)
                        end
                    end
                end

                task.wait(0.04)
                continue
            end

            -- Refresh stok bibit setelah proses tanam selesai
            seedStock = getRealtimeItemCount(seedId)

            -- ═════════════════════════════════════════
            --  PHASE 2: DROP PROFIT CHECK
            --  HANYA berjalan jika lahan pabrik sudah penuh (#plantSpots == 0)!
            --  Sisa bibit di tas setelah lahan penuh dihitung sebagai MURNI PROFIT.
            -- ═════════════════════════════════════════
            if #plantSpots == 0 and seedStock >= AutoFactory.profitLimit then
                if dX and dY then
                    AutoFactory.status = string.format("Phase 2: Buang profit %d seed ke samping Pos Drop (%d, %d)...",
                        AutoFactory.profitLimit, AutoFactory.posDropX, AutoFactory.posDropY)
                    if updateFactoryUI then updateFactoryUI() end

                    walkOrPathfindTo(dX, dY, worldW, worldH)
                    task.wait(0.08)

                    local curPx, curPy, curRawX, curRawY = getPlayerTilePos()
                    -- Tepat di sebelah kanan pos drop dan di atas permukaan block solid (bukan di dalam block)
                    local dropX = (curRawX and (curRawX + 0.85)) or (dX + 1.35)
                    local dropY = (curRawY and (curRawY - 0.45)) or (dY + 0.55)
                    local dropAmt = AutoFactory.profitLimit

                    sendDropPacket(seedId, dropAmt, dropX, dropY)
                    local inv = getNativeInventory()
                    if inv and inv.remove then
                        pcall(inv.remove, inv, seedId, dropAmt)
                    end
                    if Sfx and Sfx.play then pcall(Sfx.play, "object_spawn2") end

                    AutoFactory.totalProfitDropped = AutoFactory.totalProfitDropped + dropAmt
                    if updateFactoryUI then updateFactoryUI() end
                    task.wait(0.08)

                    -- Kembali ke Pos Break
                    walkOrPathfindTo(bX, bY, worldW, worldH)
                    task.wait(0.05)
                    continue
                else
                    AutoFactory.status = "[!] Pos Drop belum diset! Melewati drop profit..."
                    if updateFactoryUI then updateFactoryUI() end
                    task.wait(0.1)
                end
            end

            -- ═════════════════════════════════════════
            --  PHASE 3: PNB BLOCKS
            -- ═════════════════════════════════════════
            blockStock = getRealtimeItemCount(blockId)
            if (seedStock == 0 or #plantSpots == 0) and blockStock > 0 then
                -- Karakter harus berdiri tepat di posBreak (bX, bY)
                local curPx, curPy = getPlayerTilePos()
                if not curPx or curPx ~= bX or curPy ~= bY then
                    AutoFactory.status = string.format("Phase 3: Menuju Pos Break (%d, %d)...", AutoFactory.posBreakX, AutoFactory.posBreakY)
                    if updateFactoryUI then updateFactoryUI() end
                    walkOrPathfindTo(bX, bY, worldW, worldH)
                    task.wait(0.05)
                end

                local targetX = bX
                local targetY = bY - 1 -- Tepat 1 tile di atas kepala

                AutoFactory.status = string.format("Phase 3: PnB [%s] (Sisa: %d)...", AutoFactory.targetBlockName, blockStock)
                if updateFactoryUI then updateFactoryUI() end

                while AutoFactory.active and getRealtimeItemCount(blockId) > 0 do
                    -- 1. Place Block di atas kepala jika kosong
                    local curFg = getRealtimeTile("fg", targetX, targetY)
                    if curFg == 0 then
                        sendActPacket(ACT_KIND.BUILD, targetX, targetY)
                        sendTilePacket("fg", targetX, targetY, blockId, false)
                        forceClientTileUpdate("fg", targetX, targetY, blockId)
                        task.wait(0.03)
                    end

                    -- 2. Break Block
                    curFg = getRealtimeTile("fg", targetX, targetY)
                    if curFg and curFg ~= 0 then
                        factoryBreakBlock(targetX, targetY, blockId)
                        AutoFactory.totalPnB = AutoFactory.totalPnB + 1
                        if updateFactoryUI then updateFactoryUI() end
                        task.wait(0.02)
                    end

                    -- 3. Collect Drops di tile break
                    collectDropsAtTiles({{ x = targetX, y = targetY }}, bX, bY, bX + 0.5, bY + 1.0)

                    -- Cek apakah profit seed sudah mencapai limit saat PnB
                    if getRealtimeItemCount(seedId) >= AutoFactory.profitLimit then
                        break
                    end
                    task.wait(0.02)
                end

                task.wait(0.04)
                continue
            end

            -- ═════════════════════════════════════════
            --  PHASE 4: HARVEST TREES
            -- ═════════════════════════════════════════
            blockStock = getRealtimeItemCount(blockId)
            seedStock = getRealtimeItemCount(seedId)

            if blockStock == 0 and (seedStock == 0 or #plantSpots == 0) then
                local allTrees = scanWorldTrees()
                local ripeTrees = {}
                local unreadyTrees = 0

                for _, t in ipairs(allTrees) do
                    if t.y == fieldY and t.x >= fieldStartX and t.x <= fieldEndX then
                        if not AutoFactory.targetSeedId or t.seedId == AutoFactory.targetSeedId then
                            if t.isRipe then
                                table.insert(ripeTrees, t)
                            else
                                unreadyTrees = unreadyTrees + 1
                            end
                        end
                    end
                end

                if #ripeTrees > 0 then
                    AutoFactory.status = string.format("Phase 4: Memanen %d pohon matang...", #ripeTrees)
                    if updateFactoryUI then updateFactoryUI() end

                    table.sort(ripeTrees, function(a, b) return a.x < b.x end)

                    for _, tree in ipairs(ripeTrees) do
                        if not AutoFactory.active then break end

                        local curFg = getRealtimeTile("fg", tree.x, tree.y)
                        if curFg ~= 0 then
                            -- Dekati pohon
                            approachTile(tree.x, tree.y, worldW, worldH)
                            if not AutoFactory.active then break end

                            -- Pukul / Harvest
                            sendActPacket(ACT_KIND.HIT, tree.x, tree.y)
                            task.wait(0.03)
                            sendTilePacket("fg", tree.x, tree.y, 0, false)
                            forceClientTileUpdate("fg", tree.x, tree.y, 0)
                            local w_fh = getNativeWorld and getNativeWorld()
                            if w_fh and w_fh.setTree then
                                pcall(w_fh.setTree, tree.x, tree.y, nil)
                            end
                            AutoFactory.totalHarvested = AutoFactory.totalHarvested + 1
                            if updateFactoryUI then updateFactoryUI() end

                            -- Ambil drop seed & buah
                            collectDropsAtTiles({{ x = tree.x, y = tree.y }}, tree.x, tree.y, tree.x + 0.5, tree.y + 1.0)
                            task.wait(0.03)
                        end
                    end

                    task.wait(0.04)
                    continue
                end

                -- ═════════════════════════════════════════
                --  PHASE 5: STANDBY / WAIT
                -- ═════════════════════════════════════════
                local curPx, curPy = getPlayerTilePos()
                if not curPx or curPx ~= bX or curPy ~= bY then
                    walkOrPathfindTo(bX, bY, worldW, worldH)
                    task.wait(0.05)
                end

                AutoFactory.status = string.format("Waiting for trees to ripen... (%d pohon belum matang)", unreadyTrees)
                if updateFactoryUI then updateFactoryUI() end
                task.wait(1.5)
            end
        end
    end)
end

-- ═══════════════════════════════════════
--  WAYPOINT TRACKER STATE
-- ═══════════════════════════════════════
local activeWaypoint = nil

-- ═══════════════════════════════════════
--  USER INTERFACE (UI)
-- ═══════════════════════════════════════
-- ═══════════════════════════════════════
--  USER INTERFACE (UI) — GROWBLOX NATIVE STYLE v10.0
-- ═══════════════════════════════════════
if _G.CleanGrowbloxCommands then
    pcall(_G.CleanGrowbloxCommands)
    _G.CleanGrowbloxCommands = nil
end
local oldUI = PlayerGui:FindFirstChild("PNB_UI")
if oldUI then oldUI:Destroy() end

local SG = Instance.new("ScreenGui")
SG.Name           = "PNB_UI"
SG.ResetOnSpawn   = false
SG.IgnoreGuiInset = true
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.DisplayOrder   = 25
SG.Parent         = PlayerGui

-- Forward declarations of shared UI controller functions & labels
refreshMode = nil
updateLayerUI = nil
updateGridVisuals = nil
onTogglePNB = nil
btnToggleLabel = nil
lblLivePos = nil

-- ═══════════════════════════════════════
--  UI HELPER FUNCTIONS (NATIVE GAME STYLE)
-- ═══════════════════════════════════════
local function corner(inst, radius)
    local uic = Instance.new("UICorner")
    uic.CornerRadius = UDim.new(0, radius or 6)
    uic.Parent = inst
    return uic
end

local function stroke(inst, col, thickness)
    local uis = Instance.new("UIStroke")
    uis.Color = col or C.rim
    uis.Thickness = thickness or 2
    uis.Parent = inst
    return uis
end

local function dialogBorder(frame)
    local rimStroke = Instance.new("UIStroke")
    rimStroke.Color = C.rim
    rimStroke.Thickness = 4
    rimStroke.Parent = frame

    local innerEdge = Instance.new("Frame")
    innerEdge.Name = "InnerEdge"
    innerEdge.BackgroundTransparency = 1
    innerEdge.Position = UDim2.fromOffset(2, 2)
    innerEdge.Size = UDim2.new(1, -4, 1, -4)
    innerEdge.Parent = frame

    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(0, 4)
    innerCorner.Parent = innerEdge

    local innerStroke = Instance.new("UIStroke")
    innerStroke.Color = C.rimInner
    innerStroke.Thickness = 2
    innerStroke.Parent = innerEdge
end

local function makeLabel(parent, textStr, size, pos, opts)
    opts = opts or {}
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.Position = pos or UDim2.new()
    if opts.anchor then holder.AnchorPoint = opts.anchor end
    holder.Parent = parent

    local bt = nil
    if BitmapText and BitmapText.new then
        pcall(function()
            bt = BitmapText.new(holder, {
                size = size or 24,
                color = opts.color,
                plain = opts.plain,
                wrap = opts.wrap,
                outline = opts.outline,
                outlineColor = opts.outlineColor
            })
            bt:set(textStr or "")
        end)
    end

    local fallbackLbl = nil
    if not bt then
        fallbackLbl = Instance.new("TextLabel")
        fallbackLbl.BackgroundTransparency = 1
        fallbackLbl.Text = (textStr or ""):gsub("`%w", ""):gsub("``", "")
        fallbackLbl.TextSize = math.floor((size or 24) * 0.5)
        fallbackLbl.TextColor3 = opts.color or C.text
        fallbackLbl.Font = Enum.Font.GothamBold
        fallbackLbl.Size = UDim2.fromScale(1, 1)
        fallbackLbl.Parent = holder
    end

    local function syncSize()
        if bt and bt.width and bt.height then
            holder.Size = UDim2.fromOffset(math.ceil(bt.width), math.ceil(bt.height))
        elseif fallbackLbl then
            holder.Size = UDim2.fromOffset(fallbackLbl.TextBounds.X, fallbackLbl.TextBounds.Y)
        end
    end
    syncSize()

    local currentText = textStr or ""
    local wrapper = {}

    local meta = {
        __index = function(_, k)
            if k == "Text" then
                return currentText
            elseif k == "frame" or k == "holder" then
                return holder
            elseif k == "Size" then
                return holder.Size
            elseif k == "Position" then
                return holder.Position
            elseif k == "Visible" then
                return holder.Visible
            elseif k == "contentWidth" or k == "width" then
                return bt and bt.width or (fallbackLbl and fallbackLbl.TextBounds.X or 100)
            elseif k == "height" then
                return bt and bt.height or (fallbackLbl and fallbackLbl.TextBounds.Y or 24)
            elseif k == "set" then
                return function(_, str)
                    currentText = str or ""
                    if bt then bt:set(currentText) end
                    if fallbackLbl then fallbackLbl.Text = currentText:gsub("`%w", ""):gsub("``", "") end
                    syncSize()
                end
            elseif k == "Destroy" then
                return function() holder:Destroy() end
            end
            return holder[k]
        end,
        __newindex = function(_, k, v)
            if k == "Text" then
                currentText = tostring(v or "")
                if bt then bt:set(currentText) end
                if fallbackLbl then fallbackLbl.Text = currentText:gsub("`%w", ""):gsub("``", "") end
                syncSize()
            elseif k == "TextColor3" then
                if fallbackLbl then fallbackLbl.TextColor3 = v end
            elseif k == "Visible" then
                holder.Visible = v
            elseif k == "Size" then
                holder.Size = v
            elseif k == "Position" then
                holder.Position = v
            elseif k == "AnchorPoint" then
                holder.AnchorPoint = v
            else
                pcall(function() holder[k] = v end)
            end
        end
    }

    return setmetatable(wrapper, meta)
end

local function makeButton(parent, label, textSize, bgColor, padX, height, onClick, fixedWidth)
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local shadow = Instance.new("Frame")
    shadow.BackgroundColor3 = C.shadow
    shadow.BorderSizePixel = 0
    shadow.Position = UDim2.fromOffset(3, 3)
    shadow.Parent = frame
    corner(shadow, 5)

    local btn = Instance.new("TextButton")
    btn.Text = ""
    btn.AutoButtonColor = true
    btn.BackgroundColor3 = bgColor or C.button
    btn.BorderSizePixel = 0
    btn.ClipsDescendants = true
    btn.Parent = frame
    corner(btn, 5)

    local bt = makeLabel(btn, label, textSize or 26, UDim2.fromScale(0.5, 0.5), {anchor = Vector2.new(0.5, 0.5)})

    local w = fixedWidth or ((bt.contentWidth or 80) + 2 * (padX or 14))
    local h = height or 48
    btn.Size = UDim2.fromOffset(w, h)
    shadow.Size = btn.Size
    frame.Size = UDim2.fromOffset(w + 3, h + 3)

    btn.Activated:Connect(function()
        pcall(function()
            if Sfx and Sfx.play then Sfx.play("click") end
        end)
        if onClick then onClick() end
    end)

    return frame, w, btn, bt
end

local function checkbox(parent, textStr, pos, callback, initialVal)
    local TextButton = Instance.new("TextButton")
    TextButton.Text = ""
    TextButton.BackgroundTransparency = 1
    TextButton.AutoButtonColor = false
    TextButton.Position = pos or UDim2.new()
    TextButton.Parent = parent

    local ImageLabel = Instance.new("ImageLabel")
    ImageLabel.BackgroundTransparency = 1
    ImageLabel.Image = (Assets and Assets.UI and Assets.UI.checkbox) or "rbxassetid://73022818935167"
    ImageLabel.ImageRectSize = Vector2.new(32, 32)
    ImageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
    ImageLabel.Size = UDim2.fromOffset(40, 40)
    ImageLabel.Parent = TextButton

    local labelText = makeLabel(TextButton, textStr, 24, UDim2.fromOffset(48, 8))
    local totalW = 48 + (labelText.contentWidth or 120)
    TextButton.Size = UDim2.fromOffset(totalW, 40)

    local isChecked = false
    local cb = {holder = TextButton, label = labelText}

    function cb.get()
        return isChecked
    end

    function cb.set(val)
        isChecked = (val == true)
        ImageLabel.ImageRectOffset = Vector2.new(if not isChecked then 0 else 32, 0)
    end

    cb.set(initialVal == true)

    TextButton.Activated:Connect(function()
        pcall(function()
            if Sfx and Sfx.play then Sfx.play("click") end
        end)
        cb.set(not isChecked)
        if callback then
            callback(isChecked)
        end
    end)

    return cb
end

local function createSection(parent, title, defaultOpen, layoutOrder)
    local container = Instance.new("Frame", parent)
    container.Name                   = "Sec_" .. title:gsub("%s+", "_"):gsub("[^%w_]", "")
    container.Size                   = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize          = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.BorderSizePixel        = 0
    container.LayoutOrder            = layoutOrder or 1

    local secLayout = Instance.new("UIListLayout", container)
    secLayout.SortOrder = Enum.SortOrder.LayoutOrder
    secLayout.Padding   = UDim.new(0, 4)

    -- Clickable Header
    local header = Instance.new("Frame", container)
    header.Name                   = "Header"
    header.Size                   = UDim2.new(1, 0, 0, 38)
    header.BackgroundColor3       = defaultOpen and Color3.fromRGB(24, 46, 56) or C.dark
    header.BackgroundTransparency = 0.25
    header.BorderSizePixel        = 0
    header.LayoutOrder            = 1
    corner(header, 6)
    stroke(header, C.fieldRim, 1)

    local isOpen = (defaultOpen == true)

    local function getTitleText()
        return (isOpen and "v  " or ">  ") .. title
    end

    local titleLabel = makeLabel(header, getTitleText(), 20, UDim2.fromOffset(12, 9))
    local badgeLabel = makeLabel(header, isOpen and "`9[BUKA]``" or "`o[TUTUP]``", 18, UDim2.new(1, -14, 0.5, 0), {anchor = Vector2.new(1, 0.5)})

    local clickBtn = Instance.new("TextButton", header)
    clickBtn.Size                   = UDim2.fromScale(1, 1)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text                   = ""

    -- Content Body
    local body = Instance.new("Frame", container)
    body.Name                   = "Body"
    body.Size                   = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize          = Enum.AutomaticSize.Y
    body.BackgroundColor3       = C.dark
    body.BackgroundTransparency = 0.45
    body.BorderSizePixel        = 0
    body.Visible                = isOpen
    body.LayoutOrder            = 2
    corner(body, 6)
    stroke(body, C.fieldRim, 1)

    local pad = Instance.new("UIPadding", body)
    pad.PaddingLeft   = UDim.new(0, 12)
    pad.PaddingRight  = UDim.new(0, 12)
    pad.PaddingTop    = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 12)

    local bodyLayout = Instance.new("UIListLayout", body)
    bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    bodyLayout.Padding   = UDim.new(0, 8)

    local function toggle()
        isOpen = not isOpen
        body.Visible = isOpen
        header.BackgroundColor3 = isOpen and Color3.fromRGB(24, 46, 56) or C.dark
        titleLabel:set(getTitleText())
        badgeLabel:set(isOpen and "`9[BUKA]``" or "`o[TUTUP]``")
        pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
    end

    clickBtn.Activated:Connect(toggle)

    return {
        container = container,
        header = header,
        body = body,
        badge = badgeLabel,
        toggle = toggle,
        isOpen = function() return isOpen end,
        setBadge = function(text)
            badgeLabel:set(text)
        end,
    }
end

-- ═══════════════════════════════════════
--  MAIN DIALOG PANEL (GROWBLOX NATIVE STYLE)
-- ═══════════════════════════════════════

-- =======================================
--  ANTI-BOUNCE & ANTI-HAZARD CONTROLLER
-- =======================================
local AntiHazard = {
    enabled = false,
    antiLava = true,
    antiDeadly = true,
    antiLaser = true,
    antiBumper = true,
    saved = {},
    hookInstalled = false,
}

local BlocksDB = nil
pcall(function()
    BlocksDB = require(Shared:WaitForChild("BlocksDB"))
end)

local origTouchingHurt = nil
local function installTouchingHurtHook()
    if AntiHazard.hookInstalled then return end
    pcall(function()
        local w = getNativeWorld()
        if not w or not w.touchBlocks or not debug or not debug.getupvalues or not hookfunction then return end
        local upvals = debug.getupvalues(w.touchBlocks)
        for _, u in pairs(upvals) do
            if type(u) == "function" then
                local constants = debug.getconstants and debug.getconstants(u)
                local isTouchingHurt = false
                if constants then
                    for _, c in pairs(constants) do
                        if c == "hurts" then
                            isTouchingHurt = true
                            break
                        end
                    end
                end
                if isTouchingHurt then
                    origTouchingHurt = hookfunction(u, function(arg)
                        if AntiHazard.enabled then
                            if arg == nil or arg == "hurts" then
                                if AntiHazard.antiLava then return nil end
                            elseif arg == "deadly" then
                                if AntiHazard.antiDeadly then return nil end
                            elseif arg == "bumper" then
                                if AntiHazard.antiBumper then return nil end
                            end
                        end
                        return origTouchingHurt(arg)
                    end)
                    AntiHazard.hookInstalled = true
                    break
                end
            end
        end
    end)
end

local function applyAntiHazard()
    -- Attempt hook as additional resilient shield
    installTouchingHurtHook()

    local targetTables = {}
    if ItemDB then table.insert(targetTables, ItemDB) end
    if BlocksDB then table.insert(targetTables, BlocksDB) end

    for _, db in ipairs(targetTables) do
        for id, it in pairs(db) do
            if type(it) == "table" then
                if AntiHazard.saved[id] == nil then
                    AntiHazard.saved[id] = {
                        hurts  = it.hurts,
                        deadly = it.deadly,
                        laser  = it.laser,
                        bumper = it.bumper,
                    }
                end
                local orig = AntiHazard.saved[id]
                if AntiHazard.enabled then
                    -- Anti-Lava: Set hurts to nil so Game skips damage and lava bounce (u2902 = -13)
                    if AntiHazard.antiLava and orig.hurts ~= nil then
                        it.hurts = nil
                    else
                        it.hurts = orig.hurts
                    end

                    -- Anti-Deadly: Set deadly to nil so touching spikes, traps, and sharks skips die()
                    if AntiHazard.antiDeadly and orig.deadly ~= nil then
                        it.deadly = nil
                    else
                        it.deadly = orig.deadly
                    end

                    -- Anti-Laser: Set laser to nil so laser beams don't trigger die()
                    if AntiHazard.antiLaser and orig.laser ~= nil then
                        it.laser = nil
                    else
                        it.laser = orig.laser
                    end

                    -- Anti-Bumper: Set bumper to nil so pinball bumpers don't launch the player
                    if AntiHazard.antiBumper and orig.bumper ~= nil then
                        it.bumper = nil
                    else
                        it.bumper = orig.bumper
                    end
                else
                    -- Fully restore original game values
                    it.hurts  = orig.hurts
                    it.deadly = orig.deadly
                    it.laser  = orig.laser
                    it.bumper = orig.bumper
                end
            end
        end
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  UNLIMITED CAMERA ZOOM OUT
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function applyUnlimitedCameraZoom()
    pcall(function()
        Players.LocalPlayer.CameraMaxZoomDistance = 100000
    end)
    local w = getNativeWorld and getNativeWorld()
    if w and w.zoomMin ~= 0.05 then
        w.zoomMin = 0.05
        pcall(function()
            local LP = Players.LocalPlayer
            local world = LP and LP.PlayerGui and LP.PlayerGui:FindFirstChild("GameGui") and LP.PlayerGui.GameGui:FindFirstChild("World")
            if world then
                local conns = getconnections and getconnections(world:GetPropertyChangedSignal("AbsoluteSize"))
                if conns and #conns > 0 then
                    for _, c in ipairs(conns) do
                        if type(c.Function) == "function" then
                            pcall(c.Function)
                        elseif c.Fire then
                            pcall(function() c:Fire() end)
                        end
                    end
                else
                    world.Size = UDim2.new(1, 1, 1, 1)
                    task.wait()
                    world.Size = UDim2.new(1, 0, 1, 0)
                end
            end
        end)
    end
end

-- Guardian task: keep hazard properties, camera zoom & hooks active
task.spawn(function()
    while scriptAlive do
        task.wait(1.5)
        if not scriptAlive then break end
        if AntiHazard.enabled then
            applyAntiHazard()
        end
        pcall(applyUnlimitedCameraZoom)
    end
end)

local pages = {}
local switchTab = nil
local openMainDialog = nil
local closeMainDialog = nil
local toggleMainDialog = nil
local showTeamSplashDialog = nil

do
MainDialog = Instance.new("Frame", SG)
MainDialog.Name                   = "MainDialog"
MainDialog.Size                   = UDim2.fromOffset(720, 580)
MainDialog.Position               = UDim2.fromScale(0.5, 0.5)
MainDialog.AnchorPoint            = Vector2.new(0.5, 0.5)
MainDialog.BackgroundColor3       = C.box
MainDialog.BackgroundTransparency = 0.08
MainDialog.BorderSizePixel        = 0
MainDialog.Active                 = true
MainDialog.Draggable              = true
MainDialog.Visible                = (_G.SysproxySplashShown == true)
corner(MainDialog, 6)
dialogBorder(MainDialog)

local uiScale = Instance.new("UIScale", MainDialog)
uiScale.Scale = 1

openMainDialog = function()
    if Sfx and Sfx.play then Sfx.play("dialog_open") end
    MainDialog.Visible = true
    uiScale.Scale = 0.85
    TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1
    }):Play()
end

closeMainDialog = function()
    if Sfx and Sfx.play then Sfx.play("dialog_close") end
    MainDialog.Visible = false
end

toggleMainDialog = function()
    if MainDialog.Visible then
        closeMainDialog()
    else
        openMainDialog()
    end
end

-- ==============================================================================
--  SPLASH / WELCOME BANNER (TEAM SYS CASINO)
-- ==============================================================================
_G.SysproxySplashShown = _G.SysproxySplashShown or false

showTeamSplashDialog = function()
    local existing = SG:FindFirstChild("TeamSysSplashOverlay")
    if existing then existing:Destroy() end

    local splashDimmer = Instance.new("Frame", SG)
    splashDimmer.Name                   = "TeamSysSplashOverlay"
    splashDimmer.Size                   = UDim2.fromScale(1, 1)
    splashDimmer.BackgroundColor3       = Color3.new(0, 0, 0)
    splashDimmer.BackgroundTransparency = 0.45
    splashDimmer.Active                 = true
    splashDimmer.ZIndex                 = 60

    local splashDialog = Instance.new("Frame", splashDimmer)
    splashDialog.Name                   = "SplashDialog"
    splashDialog.Size                   = UDim2.fromOffset(680, 480)
    splashDialog.Position               = UDim2.fromScale(0.5, 0.5)
    splashDialog.AnchorPoint            = Vector2.new(0.5, 0.5)
    splashDialog.BackgroundColor3       = C.box
    splashDialog.BackgroundTransparency = 0.05
    splashDialog.BorderSizePixel        = 0
    splashDialog.ZIndex                 = 61
    corner(splashDialog, 8)
    dialogBorder(splashDialog)

    local splashScale = Instance.new("UIScale", splashDialog)
    splashScale.Scale = 0.85
    TweenService:Create(splashScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1
    }):Play()

    local function dismissSplash()
        pcall(function() if Sfx and Sfx.play then Sfx.play("dialog_close") end end)
        TweenService:Create(splashScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Scale = 0.8
        }):Play()
        task.delay(0.15, function()
            if splashDimmer and splashDimmer.Parent then
                splashDimmer:Destroy()
            end
            openMainDialog()
        end)
    end

    -- Header Title
    local titleLbl = Instance.new("TextLabel", splashDialog)
    titleLbl.Text = "TEAM SYS CASINO"
    titleLbl.Size = UDim2.new(1, -70, 0, 26)
    titleLbl.Position = UDim2.fromOffset(20, 14)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 20
    titleLbl.TextColor3 = C.gold
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.BackgroundTransparency = 1
    titleLbl.ZIndex = 62

    local subLbl = Instance.new("TextLabel", splashDialog)
    subLbl.Text = "OFFICIAL CASINO PARTNER | SYSPROXY v1"
    subLbl.Size = UDim2.new(1, -70, 0, 18)
    subLbl.Position = UDim2.fromOffset(20, 38)
    subLbl.Font = Enum.Font.Gotham
    subLbl.TextSize = 13
    subLbl.TextColor3 = C.muted
    subLbl.TextXAlignment = Enum.TextXAlignment.Left
    subLbl.BackgroundTransparency = 1
    subLbl.ZIndex = 62

    -- Close 'X' Button
    local btnClose = Instance.new("TextButton", splashDialog)
    btnClose.Text = "X"
    btnClose.Size = UDim2.fromOffset(36, 36)
    btnClose.Position = UDim2.new(1, -16, 0, 16)
    btnClose.AnchorPoint = Vector2.new(1, 0)
    btnClose.BackgroundColor3 = C.red
    btnClose.Font = Enum.Font.GothamBold
    btnClose.TextSize = 18
    btnClose.TextColor3 = Color3.new(1, 1, 1)
    btnClose.BorderSizePixel = 0
    btnClose.ZIndex = 63
    corner(btnClose, 6)
    btnClose.Activated:Connect(dismissSplash)

    -- Banner Image Container
    local bannerFrame = Instance.new("Frame", splashDialog)
    bannerFrame.Size = UDim2.new(1, -40, 0, 200)
    bannerFrame.Position = UDim2.fromOffset(20, 66)
    bannerFrame.BackgroundColor3 = C.dark
    bannerFrame.BackgroundTransparency = 0.4
    bannerFrame.BorderSizePixel = 0
    bannerFrame.ZIndex = 62
    corner(bannerFrame, 6)

    local bannerImg = Instance.new("ImageLabel", bannerFrame)
    bannerImg.Size = UDim2.fromScale(1, 1)
    bannerImg.BackgroundTransparency = 1
    bannerImg.ScaleType = Enum.ScaleType.Fit
    bannerImg.ZIndex = 63
    corner(bannerImg, 6)

    pcall(function()
        if getcustomasset then
            local ok, asset = pcall(getcustomasset, "teamsys_banner.jpg")
            if ok and asset then bannerImg.Image = asset end
        end
    end)

    -- Details Box
    local infoFrame = Instance.new("Frame", splashDialog)
    infoFrame.Size = UDim2.new(1, -40, 0, 120)
    infoFrame.Position = UDim2.fromOffset(20, 276)
    infoFrame.BackgroundColor3 = C.dark
    infoFrame.BackgroundTransparency = 0.5
    infoFrame.BorderSizePixel = 0
    infoFrame.ZIndex = 62
    corner(infoFrame, 6)
    stroke(infoFrame, C.rimInner, 1.5)

    local desc = Instance.new("TextLabel", infoFrame)
    desc.Size = UDim2.new(1, -32, 1, -20)
    desc.Position = UDim2.fromOffset(16, 10)
    desc.BackgroundTransparency = 1
    desc.Font = Enum.Font.GothamBold
    desc.TextSize = 16
    desc.TextColor3 = C.text
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.TextYAlignment = Enum.TextYAlignment.Center
    desc.TextWrapped = true
    desc.ZIndex = 63
    desc.Text = "WORLD : SYS\n\nTIKTOK : @sysnewera\n\nBUY/SELL WL : JOIN OUR DISCORD OFFICIAL"

    -- Action Buttons (Bottom)
    local btnDiscord = Instance.new("TextButton", splashDialog)
    btnDiscord.Size = UDim2.fromOffset(260, 42)
    btnDiscord.Position = UDim2.fromOffset(20, 412)
    btnDiscord.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
    btnDiscord.Font = Enum.Font.GothamBold
    btnDiscord.TextSize = 14
    btnDiscord.TextColor3 = Color3.new(1, 1, 1)
    btnDiscord.Text = "COPY DISCORD (dsc.gg/syshub)"
    btnDiscord.BorderSizePixel = 0
    btnDiscord.ZIndex = 63
    corner(btnDiscord, 6)
    btnDiscord.Activated:Connect(function()
        pcall(function()
            if setclipboard then
                setclipboard("https://discord.gg/syshub")
            end
        end)
        btnDiscord.Text = "LINK DISCORD TERSALIN!"
        task.delay(1.5, function()
            if btnDiscord and btnDiscord.Parent then
                btnDiscord.Text = "COPY DISCORD (dsc.gg/syshub)"
            end
        end)
    end)

    local btnOk = Instance.new("TextButton", splashDialog)
    btnOk.Size = UDim2.new(1, -315, 0, 42)
    btnOk.Position = UDim2.fromOffset(295, 412)
    btnOk.BackgroundColor3 = C.green
    btnOk.Font = Enum.Font.GothamBold
    btnOk.TextSize = 16
    btnOk.TextColor3 = Color3.new(1, 1, 1)
    btnOk.Text = "BUKA MENU SYSPROXY"
    btnOk.BorderSizePixel = 0
    btnOk.ZIndex = 63
    corner(btnOk, 6)
    btnOk.Activated:Connect(dismissSplash)
end
-- Top Header Icon (Item 1784: Legendary Wings)
do
    local HeaderIconFrame = Instance.new("Frame", MainDialog)
    HeaderIconFrame.Name                   = "HeaderIcon"
    HeaderIconFrame.Size                   = UDim2.fromOffset(56, 56)
    HeaderIconFrame.Position               = UDim2.fromOffset(18, 14)
    HeaderIconFrame.BackgroundColor3       = C.dark
    HeaderIconFrame.BackgroundTransparency = 0.35
    HeaderIconFrame.BorderSizePixel        = 0
    corner(HeaderIconFrame, 8)
    stroke(HeaderIconFrame, C.gold, 2)

    if ItemIcon and ItemIcon.new then
        local iconObj = ItemIcon.new(HeaderIconFrame, UDim2.fromOffset(46, 46), 2)
        iconObj.frame.AnchorPoint = Vector2.new(0.5, 0.5)
        iconObj.frame.Position    = UDim2.fromScale(0.5, 0.5)
        ItemIcon.set(iconObj, 1784)
    else
        local fallbackImg = Instance.new("ImageLabel", HeaderIconFrame)
        fallbackImg.Size                   = UDim2.fromScale(1, 1)
        fallbackImg.BackgroundTransparency = 1
        fallbackImg.Image                  = (Assets and Assets.UI and Assets.UI.menuButton) or "rbxassetid://111429938105367"
    end
end

-- Main Title & Spaced Subtitle
makeLabel(MainDialog, "`wSYSHUB``", 34, UDim2.fromOffset(82, 10))
makeLabel(MainDialog, "`oGROWBLOX PREMIUM VERSION``", 17, UDim2.fromOffset(84, 44))

-- Community Social Row (Discord & WhatsApp buttons)
do
    local socialRow = Instance.new("Frame", MainDialog)
    socialRow.Name                   = "SocialRow"
    socialRow.Size                   = UDim2.new(0, 480, 0, 26)
    socialRow.Position               = UDim2.fromOffset(84, 68)
    socialRow.BackgroundTransparency = 1

    local socialLayout = Instance.new("UIListLayout", socialRow)
    socialLayout.FillDirection       = Enum.FillDirection.Horizontal
    socialLayout.SortOrder           = Enum.SortOrder.LayoutOrder
    socialLayout.Padding             = UDim.new(0, 8)
    socialLayout.VerticalAlignment   = Enum.VerticalAlignment.Center

    local lblSocialFeedback = nil

    -- Discord Button
    makeButton(socialRow, "Discord", 17, C.discord, 4, 24, function()
        pcall(function()
            if setclipboard then
                setclipboard("https://discord.gg/syshub")
            end
        end)
        if lblSocialFeedback then
            lblSocialFeedback:set("`2[Discord Copied!]``")
            task.delay(2.5, function()
                if lblSocialFeedback then lblSocialFeedback:set("") end
            end)
        end
    end, 90)

    -- WhatsApp Button
    makeButton(socialRow, "WhatsApp", 17, C.whatsapp, 4, 24, function()
        pcall(function()
            if setclipboard then
                setclipboard("https://chat.whatsapp.com/syshub")
            end
        end)
        if lblSocialFeedback then
            lblSocialFeedback:set("`2[WA Copied!]``")
            task.delay(2.5, function()
                if lblSocialFeedback then lblSocialFeedback:set("") end
            end)
        end
    end, 98)

    lblSocialFeedback = makeLabel(socialRow, "", 16, UDim2.new())
end

-- Close 'X' Button
do
    local btnClose = Instance.new("ImageButton", MainDialog)
    btnClose.Name                   = "CloseX"
    btnClose.BackgroundTransparency = 1
    btnClose.Image                  = (Assets and Assets.UI and Assets.UI.cross) or "rbxassetid://91811014634834"
    btnClose.AnchorPoint            = Vector2.new(0.5, 0.5)
    btnClose.Size                   = UDim2.fromOffset(48, 48)
    btnClose.Position               = UDim2.new(1, -24, 0, 24)
    btnClose.ZIndex                 = 10

    btnClose.Activated:Connect(function()
        closeMainDialog()
    end)
end

-- ═══════════════════════════════════════
--  SIDE HUD BUTTON (NATIVE WORLD MENU STYLE)
-- ═══════════════════════════════════════
do
    local SideHud = nil
    if HudScale and HudScale.attach then
        pcall(function()
            SideHud = HudScale.attach(SG)
            SideHud.Name = "SideButtons"
        end)
    end
    if not SideHud then
        SideHud = Instance.new("Frame", SG)
        SideHud.Name = "SideButtons"
        SideHud.BackgroundTransparency = 1
        SideHud.Size = UDim2.fromScale(1, 1)
    end

    local function createSideButton(parent, name, row, dx)
        local btn = Instance.new("ImageButton")
        btn.Name                   = name
        btn.BackgroundTransparency = 0
        btn.BackgroundColor3       = Color3.fromRGB(30, 100, 120) -- u229.box (native Gazette blue)
        btn.Size                   = UDim2.fromOffset(76, 76)
        btn.AnchorPoint            = Vector2.new(1, 0)
        btn.AutoButtonColor        = false
        btn.BorderSizePixel        = 0
        btn.ZIndex                 = 15
        btn.Parent                 = parent

        corner(btn, 18)

        local stroke = Instance.new("UIStroke", btn)
        stroke.Color = Color3.fromRGB(135, 184, 204) -- u229.rim
        stroke.Thickness = 3

        local inner = Instance.new("Frame", btn)
        inner.Name                   = "InnerRim"
        inner.BackgroundTransparency = 1
        inner.Size                   = UDim2.new(1, -4, 1, -4)
        inner.Position               = UDim2.fromOffset(2, 2)
        corner(inner, 16)
        local innerStroke = Instance.new("UIStroke", inner)
        innerStroke.Color = Color3.fromRGB(4, 8, 10) -- u229.rimInner
        innerStroke.Thickness = 1.5

        -- Item 1784: Legendary Wings icon
        if ItemIcon and ItemIcon.new then
            local icon = ItemIcon.new(btn, UDim2.fromOffset(52, 52), 2)
            ItemIcon.set(icon, 1784)
            icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
            icon.frame.Position    = UDim2.fromScale(0.5, 0.42)
        end

        -- Small text label "SYS" at the bottom
        makeLabel(btn, "`wSYS``", 18, UDim2.new(0.5, 0, 1, -3), { anchor = Vector2.new(0.5, 1) })

        -- Interactive press animation (exact behavior from WorldMenu)
        local uiscale = Instance.new("UIScale", btn)

        btn.MouseButton1Down:Connect(function()
            uiscale.Scale = 0.9
            btn.BackgroundColor3 = Color3.fromRGB(20, 70, 85)
        end)

        local function up()
            uiscale.Scale = 1
            btn.BackgroundColor3 = Color3.fromRGB(30, 100, 120)
        end

        btn.MouseButton1Up:Connect(up)
        btn.MouseLeave:Connect(up)

        btn.Activated:Connect(function()
            if Sfx and Sfx.play then Sfx.play("click") end
            toggleMainDialog()
        end)

        local function updatePos()
            btn.Position = UDim2.new(1, -(8 + (dx or 0)), 0, 12 + (row or 4) * 88)
        end
        updatePos()

        if GuiService then
            pcall(function()
                GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updatePos)
            end)
        end

        return btn
    end

    createSideButton(SideHud, "SyshubButton", 4, 0)
end

-- ═══════════════════════════════════════
--  TAB NAVIGATION BAR (NATIVE GAZETTE STYLE)
-- ═══════════════════════════════════════
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  TAB NAVIGATION BAR (SYSPROXY 4-TAB EDITION)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local tabData = {
    { key = "proxy",   label = "PROXY" },
    { key = "player",  label = "PLAYER" },
    { key = "world",   label = "WORLD" },
    { key = "spam",    label = "SPAM" },
}

local TabBar = Instance.new("Frame", MainDialog)
TabBar.Name                   = "TabBar"
TabBar.Size                   = UDim2.new(1, -40, 0, 40)
TabBar.Position               = UDim2.fromOffset(20, 102)
TabBar.BackgroundTransparency = 1

local tabButtons = {}
local tabWidth = math.floor((720 - 40 - (#tabData - 1) * 8) / #tabData)

-- Container for Content Pages
local PagesContainer = Instance.new("Frame", MainDialog)
PagesContainer.Name                   = "PagesContainer"
PagesContainer.Size                   = UDim2.new(1, -40, 1, -214)
PagesContainer.Position               = UDim2.fromOffset(20, 148)
PagesContainer.BackgroundColor3       = C.dark
PagesContainer.BackgroundTransparency = 0.55
PagesContainer.BorderSizePixel        = 0
corner(PagesContainer, 8)
stroke(PagesContainer, C.rim, 2)

pages = {}

do
    local function createPage(key)
        local sf = Instance.new("ScrollingFrame", PagesContainer)
        sf.Name                   = "Page_" .. key
        sf.Size                   = UDim2.fromScale(1, 1)
        sf.BackgroundTransparency = 1
        sf.BorderSizePixel        = 0
        sf.ScrollBarThickness     = 8
        sf.ScrollBarImageColor3   = C.rim
        sf.ScrollingDirection     = Enum.ScrollingDirection.Y
        sf.AutomaticCanvasSize    = Enum.AutomaticSize.Y
        sf.CanvasSize             = UDim2.new()
        sf.Visible                = false

        local pad = Instance.new("UIPadding", sf)
        pad.PaddingLeft   = UDim.new(0, 12)
        pad.PaddingRight  = UDim.new(0, 16)
        pad.PaddingTop    = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 14)

        local layout = Instance.new("UIListLayout", sf)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding   = UDim.new(0, 8)

        pages[key] = sf
        return sf
    end

    for _, t in ipairs(tabData) do
        createPage(t.key)
    end
end

local activeTabKey = "proxy"

switchTab = function(tabKey)
    activeTabKey = tabKey
    for _, t in ipairs(tabData) do
        local isCurrent = (t.key == tabKey)
        local btnObj = tabButtons[t.key]
        if btnObj then
            btnObj.btn.BackgroundColor3 = isCurrent and C.green or C.button
        end
        if pages[t.key] then
            pages[t.key].Visible = isCurrent
        end
    end
    if not (Proxy and Proxy._isLoadingConfig) then
        if Proxy and Proxy.saveConfig then
            pcall(Proxy.saveConfig)
        end
    end
end

for i, t in ipairs(tabData) do
    local btnTuple = { makeButton(
        TabBar,
        t.label,
        22,
        (t.key == activeTabKey) and C.green or C.button,
        8,
        42,
        function()
            switchTab(t.key)
        end,
        tabWidth
    ) }
    btnTuple[1].Position = UDim2.fromOffset((i - 1) * (tabWidth + 8), 0)
    tabButtons[t.key] = { frame = btnTuple[1], btn = btnTuple[3], label = btnTuple[4] }
end
-- ═══════════════════════════════════════
--  BOTTOM PINNED FOOTER (CHAR COORDS & HP)
-- ═══════════════════════════════════════
do
    local Footer = Instance.new("Frame", MainDialog)
    Footer.Name                   = "Footer"
    Footer.Size                   = UDim2.new(1, -40, 0, 48)
    Footer.Position               = UDim2.new(0, 20, 1, -56)
    Footer.BackgroundColor3       = C.dark
    Footer.BackgroundTransparency = 0.35
    Footer.BorderSizePixel        = 0
    corner(Footer, 6)
    stroke(Footer, C.rimInner, 2)

    lblLivePos = makeLabel(Footer, "`cPos: (—, —) [World: —]``  |  `4HP: 100/100``", 20, UDim2.fromOffset(14, 6))
    lblStatus  = makeLabel(Footer, "`oStatus: Idle``", 18, UDim2.fromOffset(14, 26))
end
end

local Setups = {}
Setups.player = function(page)
    -- Section 1: Fly Mode (Default OPEN)
    local secFly = createSection(page, "Fly Mode (Flight)", true, 1)

    local btnFlyFrame, btnFly, btnFlyLabel
    btnFlyFrame, _, btnFly, btnFlyLabel = makeButton(
        secFly.body,
        "Fly Mode: OFF",
        20,
        C.button,
        8,
        38,
        function()
            Mobility.flyEnabled = not Mobility.flyEnabled
            if Mobility.flyEnabled then
                btnFly.BackgroundColor3 = C.cyan
                btnFlyLabel:set("Fly Mode: ON")
                secFly.setBadge("`c[ACTIVE]``")
            else
                Mobility.suspendedY = nil
                btnFly.BackgroundColor3 = C.button
                btnFlyLabel:set("Fly Mode: OFF")
                secFly.setBadge("`o[OFF]``")
            end
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )
    secFly.setBadge("`o[OFF]``")

    makeLabel(secFly.body, "`oKontrol: W / Space (Naik) | S (Turun) | A/D (Kiri/Kanan)``", 18, UDim2.new())

    -- Section 2: Anti-Gravity (Default CLOSED)
    local secAntiGrav = createSection(page, "Anti-Gravity & Infinite Jump", false, 2)

    local btnAntiGravFrame, btnAntiGrav, btnAntiGravLabel
    btnAntiGravFrame, _, btnAntiGrav, btnAntiGravLabel = makeButton(
        secAntiGrav.body,
        "Anti-Grav: OFF",
        20,
        C.button,
        8,
        38,
        function()
            Mobility.antiGravEnabled = not Mobility.antiGravEnabled
            if Mobility.antiGravEnabled then
                btnAntiGrav.BackgroundColor3 = Color3.fromRGB(140, 60, 210)
                btnAntiGravLabel:set("Anti-Grav: ON")
                secAntiGrav.setBadge("`d[ACTIVE]``")
            else
                btnAntiGrav.BackgroundColor3 = C.button
                btnAntiGravLabel:set("Anti-Grav: OFF")
                secAntiGrav.setBadge("`o[OFF]``")
            end
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )
    secAntiGrav.setBadge("`o[OFF]``")

    makeLabel(secAntiGrav.body, "`oGravitasi Nol: Lompat bebas di udara tanpa batas jatuh``", 18, UDim2.new())

    -- Section 3: Anti-Bounce & Hazard (Lava & Spikes)
    local secHazard = createSection(page, "Anti-Bounce & Hazard (Lava & Spikes)", false, 3)

    local lblHazardStatus = nil
    local btnHazardFrame, btnHazard, btnHazardLabel
    btnHazardFrame, _, btnHazard, btnHazardLabel = makeButton(
        secHazard.body,
        "Anti-Hazard: OFF",
        20,
        C.button,
        8,
        38,
        function()
            AntiHazard.enabled = not AntiHazard.enabled
            applyAntiHazard()
            if AntiHazard.enabled then
                btnHazard.BackgroundColor3 = C.green
                btnHazardLabel:set("Anti-Hazard: ON")
                secHazard.setBadge("`2[ACTIVE]``")
                if lblHazardStatus then
                    lblHazardStatus:set("`2Status: Aktif | Kebal Lava (No Bounce) & Spikes``")
                end
            else
                btnHazard.BackgroundColor3 = C.button
                btnHazardLabel:set("Anti-Hazard: OFF")
                secHazard.setBadge("`o[OFF]``")
                if lblHazardStatus then
                    lblHazardStatus:set("`oStatus: Nonaktif | Normal Game Physics``")
                end
            end
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )
    secHazard.setBadge("`o[OFF]``")

    local cbAntiLava = checkbox(secHazard.body, "`oAnti-Lava (No Damage & No Bounce)``", UDim2.new(), function(val)
        AntiHazard.antiLava = val
        if AntiHazard.enabled then applyAntiHazard() end
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end, AntiHazard.antiLava ~= false)

    local cbAntiSpikes = checkbox(secHazard.body, "`oAnti-Spikes & Deadly (Kebal Spikes / Mati)``", UDim2.new(), function(val)
        AntiHazard.antiDeadly = val
        if AntiHazard.enabled then applyAntiHazard() end
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end, AntiHazard.antiDeadly ~= false)

    local cbAntiLaser = checkbox(secHazard.body, "`oAnti-Laser & Pinball Bumpers``", UDim2.new(), function(val)
        AntiHazard.antiLaser = val
        AntiHazard.antiBumper = val
        if AntiHazard.enabled then applyAntiHazard() end
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end, AntiHazard.antiLaser ~= false)

    lblHazardStatus = makeLabel(secHazard.body, "`oStatus: Standby | Kebal Lava (Anti-Bounce) & Spikes``", 18, UDim2.new())

    -- Section 4: Click-to-Pathfind (Navigasi Klik Layar)
    local secClickPath = createSection(page, "Click-to-Pathfind (Navigasi Klik Layar)", false, 4)

    local btnClickPathFrame, btnClickPath, btnClickPathLabel
    btnClickPathFrame, _, btnClickPath, btnClickPathLabel = makeButton(
        secClickPath.body,
        "Shift + Click Pathfind: OFF",
        20,
        C.button,
        8,
        38,
        function()
            ClickPathfind.enabled = not ClickPathfind.enabled
            if ClickPathfind.enabled then
                btnClickPath.BackgroundColor3 = C.cyan
                if btnClickPathLabel and btnClickPathLabel.set then
                    btnClickPathLabel:set("Shift + Click Pathfind: ON")
                end
                secClickPath.setBadge("`c[ACTIVE]``")
                if lblClickPathStatus and lblClickPathStatus.set then
                    lblClickPathStatus:set("`2Status: Standby | Tahan [SHIFT] untuk memunculkan grid & klik tile``")
                end
                toggleClickPathfindGrid(true)
            else
                if ClickPathfind.thread then
                    task.cancel(ClickPathfind.thread)
                    ClickPathfind.thread = nil
                end
                ClickPathfind.busy = false
                btnClickPath.BackgroundColor3 = C.button
                if btnClickPathLabel and btnClickPathLabel.set then
                    btnClickPathLabel:set("Shift + Click Pathfind: OFF")
                end
                secClickPath.setBadge("`o[OFF]``")
                if lblClickPathStatus and lblClickPathStatus.set then
                    lblClickPathStatus:set("`oStatus: Nonaktif | Standby``")
                end
                toggleClickPathfindGrid(false)
            end
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )
    secClickPath.setBadge("`o[OFF]``")

    makeLabel(secClickPath.body, "`oTahan tombol [SHIFT] di keyboard untuk memunculkan grid tile transparan, lalu klik tile tujuan untuk jalan otomatis!``", 17, UDim2.new())
    lblClickPathStatus = makeLabel(secClickPath.body, "`oStatus: Standby | Tahan [SHIFT] lalu klik tile di layar``", 18, UDim2.new())

    -- Section 5: Speed Mode (Super Run / Multiplier)
    local secSpeed = createSection(page, "Speed Mode (Kecepatan Gerak / Run)", false, 5)

    local lblSpeedVal = nil
    local updateSpeedDisplay = function()
        if lblSpeedVal then
            lblSpeedVal:set(string.format("`wKecepatan: `2%.1fx``  `o(Normal: 1.0x)``", Mobility.speedMultiplier))
        end
    end

    local btnSpeedFrame, btnSpeed, btnSpeedLabel
    btnSpeedFrame, _, btnSpeed, btnSpeedLabel = makeButton(
        secSpeed.body,
        "Speed Mode: OFF",
        20,
        C.button,
        8,
        38,
        function()
            Mobility.speedEnabled = not Mobility.speedEnabled
            applySpeedMode()
            if Mobility.speedEnabled then
                btnSpeed.BackgroundColor3 = C.green
                btnSpeedLabel:set("Speed Mode: ON")
                secSpeed.setBadge(string.format("`2[%.1fx]``", Mobility.speedMultiplier))
            else
                btnSpeed.BackgroundColor3 = C.button
                btnSpeedLabel:set("Speed Mode: OFF")
                secSpeed.setBadge("`o[OFF]``")
            end
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )
    secSpeed.setBadge("`o[OFF]``")

    lblSpeedVal = makeLabel(secSpeed.body, string.format("`wKecepatan: `2%.1fx``  `o(Normal: 1.0x)``", Mobility.speedMultiplier), 19, UDim2.new())

    -- Preset Speed Buttons Row
    local presetRow = Instance.new("Frame", secSpeed.body)
    presetRow.Size               = UDim2.new(1, 0, 0, 32)
    presetRow.BackgroundTransparency = 1

    local speedPresets = {
        { val = 1.0, label = "1.0x" },
        { val = 1.5, label = "1.5x" },
        { val = 2.0, label = "2.0x" },
        { val = 2.5, label = "2.5x" },
        { val = 3.0, label = "3.0x" },
        { val = 4.0, label = "4.0x" },
    }
    local presetBtns = {}
    local pWidth = 88
    for i, sp in ipairs(speedPresets) do
        local isSel = math.abs(Mobility.speedMultiplier - sp.val) < 0.05
        local pf, _, pb = makeButton(
            presetRow,
            sp.label,
            18,
            isSel and C.green or C.button,
            4,
            30,
            function()
                Mobility.speedMultiplier = sp.val
                applySpeedMode()
                updateSpeedDisplay()
                if Mobility.speedEnabled then
                    secSpeed.setBadge(string.format("`2[%.1fx]``", sp.val))
                end
                for _, other in ipairs(speedPresets) do
                    if presetBtns[other.val] then
                        presetBtns[other.val].BackgroundColor3 = (math.abs(Mobility.speedMultiplier - other.val) < 0.05) and C.green or C.button
                    end
                end
                if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
            end,
            pWidth
        )
        pf.Position = UDim2.fromOffset((i - 1) * (pWidth + 6), 0)
        presetBtns[sp.val] = pb
    end

    -- Interactive Slider Bar
    local sliderBg = Instance.new("Frame", secSpeed.body)
    sliderBg.Name                   = "SpeedSliderBg"
    sliderBg.Size                   = UDim2.new(1, -20, 0, 16)
    sliderBg.BackgroundColor3       = C.dark
    sliderBg.BorderSizePixel        = 0
    corner(sliderBg, 8)
    stroke(sliderBg, C.fieldRim, 1)

    local sliderFill = Instance.new("Frame", sliderBg)
    sliderFill.Name                   = "Fill"
    local initRatio = math.clamp((Mobility.speedMultiplier - 1.0) / 4.0, 0, 1)
    sliderFill.Size                   = UDim2.new(initRatio, 0, 1, 0)
    sliderFill.BackgroundColor3       = C.cyan
    sliderFill.BorderSizePixel        = 0
    corner(sliderFill, 8)

    local sliderBtn = Instance.new("TextButton", sliderBg)
    sliderBtn.Size                   = UDim2.fromScale(1, 1)
    sliderBtn.BackgroundTransparency = 1
    sliderBtn.Text                   = ""

    local dragging = false
    local function updateSliderFromX(x)
        local relX = math.clamp(x - sliderBg.AbsolutePosition.X, 0, sliderBg.AbsoluteSize.X)
        local ratio = (sliderBg.AbsoluteSize.X > 0) and (relX / sliderBg.AbsoluteSize.X) or 0
        local newSpd = math.round((1.0 + ratio * 4.0) * 10) / 10
        Mobility.speedMultiplier = newSpd
        sliderFill.Size = UDim2.new(ratio, 0, 1, 0)
        applySpeedMode()
        updateSpeedDisplay()
        if Mobility.speedEnabled then
            secSpeed.setBadge(string.format("`2[%.1fx]``", newSpd))
        end
        for _, other in ipairs(speedPresets) do
            if presetBtns[other.val] then
                presetBtns[other.val].BackgroundColor3 = (math.abs(Mobility.speedMultiplier - other.val) < 0.05) and C.green or C.button
            end
        end
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end

    sliderBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateSliderFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSliderFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Section 6: Fast Inventory (Drop & Recycle)
    local secFastInv = createSection(page, "Fast Inventory (Drop & Recycle)", false, 6)

    local lblFastInvStatus = nil
    local function updateFastInvStatus()
        if not lblFastInvStatus then return end
        local dropMode = FastInventory.fastDrop and (FastInventory.customCountEnabled and string.format("`2ON (%d)``", FastInventory.customCount) or "`2ON (Semua)``") or "`oOFF``"
        local recMode = FastInventory.fastRecycle and (FastInventory.customCountEnabled and string.format("`2ON (%d)``", FastInventory.customCount) or "`2ON (Semua)``") or "`oOFF``"
        lblFastInvStatus:set(string.format("`oStatus: Drop: %s `o| Recycle: %s", dropMode, recMode))
    end

    local btnDropFrame, btnDrop, btnDropLabel
    btnDropFrame, _, btnDrop, btnDropLabel = makeButton(
        secFastInv.body,
        "Fast Drop: OFF",
        20,
        C.button,
        8,
        38,
        function()
            FastInventory.fastDrop = not FastInventory.fastDrop
            ensureFastInventoryOverlays()
            if FastInventory.fastDrop then
                btnDrop.BackgroundColor3 = C.green
                btnDropLabel:set("Fast Drop: ON")
                secFastInv.setBadge("`2[ACTIVE]``")
            else
                btnDrop.BackgroundColor3 = C.button
                btnDropLabel:set("Fast Drop: OFF")
                if not FastInventory.fastRecycle then
                    secFastInv.setBadge("`o[OFF]``")
                end
            end
            updateFastInvStatus()
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )

    local btnRecycleFrame, btnRecycle, btnRecycleLabel
    btnRecycleFrame, _, btnRecycle, btnRecycleLabel = makeButton(
        secFastInv.body,
        "Fast Trash / Recycle: OFF",
        20,
        C.button,
        8,
        38,
        function()
            FastInventory.fastRecycle = not FastInventory.fastRecycle
            ensureFastInventoryOverlays()
            if FastInventory.fastRecycle then
                btnRecycle.BackgroundColor3 = C.red
                btnRecycleLabel:set("Fast Trash / Recycle: ON")
                secFastInv.setBadge("`2[ACTIVE]``")
            else
                btnRecycle.BackgroundColor3 = C.button
                btnRecycleLabel:set("Fast Trash / Recycle: OFF")
                if not FastInventory.fastDrop then
                    secFastInv.setBadge("`o[OFF]``")
                end
            end
            updateFastInvStatus()
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )
    secFastInv.setBadge("`o[OFF]``")

    -- Checkbox Custom Count Drop / Recycle
    local cbCustomCount = checkbox(secFastInv.body, "`oCustom Count Drop/Recycle (Uncheck: Drop Semua Stack)``", UDim2.new(), function(val)
        FastInventory.customCountEnabled = val
        updateFastInvStatus()
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end, FastInventory.customCountEnabled == true)

    -- Row for custom count input
    local countRow = Instance.new("Frame", secFastInv.body)
    countRow.Size = UDim2.new(1, 0, 0, 36)
    countRow.BackgroundTransparency = 1

    local lblCount = makeLabel(countRow, "`wJumlah Item:``", 18, UDim2.new(0, 0, 0, 8))

    local countBox = Instance.new("TextBox", countRow)
    countBox.Size = UDim2.new(0, 100, 0, 30)
    countBox.Position = UDim2.new(0, 115, 0, 3)
    countBox.BackgroundColor3 = C.field
    countBox.BorderSizePixel = 0
    countBox.Font = Enum.Font.FredokaOne
    countBox.TextSize = 18
    countBox.TextColor3 = C.text
    countBox.Text = tostring(FastInventory.customCount or 1)
    countBox.ClearTextOnFocus = false
    corner(countBox, 6)
    stroke(countBox, C.fieldRim, 1)

    countBox.FocusLost:Connect(function()
        local num = tonumber(countBox.Text)
        if num and num > 0 then
            FastInventory.customCount = math.floor(num)
        else
            FastInventory.customCount = 1
            countBox.Text = "1"
        end
        updateFastInvStatus()
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end)

    -- Quick Adjust Buttons (+1, +10, +50, Reset)
    local function makeQuickBtn(xOff, text, w, cb)
        local f, _, b = makeButton(countRow, text, 16, C.button, 4, 30, cb, w)
        f.Position = UDim2.new(0, xOff, 0, 3)
        return b
    end

    makeQuickBtn(225, "+1", 38, function()
        FastInventory.customCount = (FastInventory.customCount or 1) + 1
        countBox.Text = tostring(FastInventory.customCount)
        updateFastInvStatus()
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end)

    makeQuickBtn(269, "+10", 46, function()
        FastInventory.customCount = (FastInventory.customCount or 1) + 10
        countBox.Text = tostring(FastInventory.customCount)
        updateFastInvStatus()
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end)

    makeQuickBtn(321, "+50", 46, function()
        FastInventory.customCount = (FastInventory.customCount or 1) + 50
        countBox.Text = tostring(FastInventory.customCount)
        updateFastInvStatus()
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end)

    makeQuickBtn(373, "Reset", 52, function()
        FastInventory.customCount = 1
        countBox.Text = "1"
        updateFastInvStatus()
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end)

    lblFastInvStatus = makeLabel(secFastInv.body, "`oStatus: Standby | Drop: OFF | Recycle: OFF``", 18, UDim2.new())
    makeLabel(secFastInv.body, "`oKlik DROP atau RECYCLE di tas/inventory langsung jalan instan tanpa konfirmasi dialog!``", 17, UDim2.new())

    updatePlayerUI = function()
        -- Fly
        if btnFly and btnFlyLabel then
            btnFly.BackgroundColor3 = Mobility.flyEnabled and C.cyan or C.button
            btnFlyLabel:set(Mobility.flyEnabled and "Fly Mode: ON" or "Fly Mode: OFF")
        end
        if secFly and secFly.setBadge then
            secFly.setBadge(Mobility.flyEnabled and "`c[ACTIVE]``" or "`o[OFF]``")
        end

        -- Anti Grav
        if btnAntiGrav and btnAntiGravLabel then
            btnAntiGrav.BackgroundColor3 = Mobility.antiGravEnabled and Color3.fromRGB(140, 60, 210) or C.button
            btnAntiGravLabel:set(Mobility.antiGravEnabled and "Anti-Grav: ON" or "Anti-Grav: OFF")
        end
        if secAntiGrav and secAntiGrav.setBadge then
            secAntiGrav.setBadge(Mobility.antiGravEnabled and "`d[ACTIVE]``" or "`o[OFF]``")
        end

        -- Hazard
        if btnHazard and btnHazardLabel then
            btnHazard.BackgroundColor3 = AntiHazard.enabled and C.green or C.button
            btnHazardLabel:set(AntiHazard.enabled and "Anti-Hazard: ON" or "Anti-Hazard: OFF")
        end
        if secHazard and secHazard.setBadge then
            secHazard.setBadge(AntiHazard.enabled and "`2[ACTIVE]``" or "`o[OFF]``")
        end
        if lblHazardStatus and lblHazardStatus.set then
            lblHazardStatus:set(AntiHazard.enabled and "`2Status: Aktif | Kebal Lava (No Bounce) & Spikes``" or "`oStatus: Nonaktif | Normal Game Physics``")
        end
        if cbAntiLava and cbAntiLava.set then cbAntiLava.set(AntiHazard.antiLava ~= false) end
        if cbAntiSpikes and cbAntiSpikes.set then cbAntiSpikes.set(AntiHazard.antiDeadly ~= false) end
        if cbAntiLaser and cbAntiLaser.set then cbAntiLaser.set(AntiHazard.antiLaser ~= false) end

        -- Click Pathfind
        if btnClickPath and btnClickPathLabel then
            btnClickPath.BackgroundColor3 = ClickPathfind.enabled and C.cyan or C.button
            btnClickPathLabel:set(ClickPathfind.enabled and "Shift + Click Pathfind: ON" or "Shift + Click Pathfind: OFF")
        end
        if secClickPath and secClickPath.setBadge then
            secClickPath.setBadge(ClickPathfind.enabled and "`c[ACTIVE]``" or "`o[OFF]``")
        end
        if lblClickPathStatus and lblClickPathStatus.set then
            lblClickPathStatus:set(ClickPathfind.enabled and "`2Status: Standby | Tahan [SHIFT] untuk memunculkan grid & klik tile``" or "`oStatus: Nonaktif | Standby``")
        end

        -- Speed
        if btnSpeed and btnSpeedLabel then
            btnSpeed.BackgroundColor3 = Mobility.speedEnabled and C.green or C.button
            btnSpeedLabel:set(Mobility.speedEnabled and "Speed Mode: ON" or "Speed Mode: OFF")
        end
        if secSpeed and secSpeed.setBadge then
            secSpeed.setBadge(Mobility.speedEnabled and string.format("`2[%.1fx]``", Mobility.speedMultiplier) or "`o[OFF]``")
        end
        if updateSpeedDisplay then updateSpeedDisplay() end
        if sliderFill then
            local ratio = math.clamp((Mobility.speedMultiplier - 1.0) / 4.0, 0, 1)
            sliderFill.Size = UDim2.new(ratio, 0, 1, 0)
        end
        for _, other in ipairs(speedPresets) do
            if presetBtns[other.val] then
                presetBtns[other.val].BackgroundColor3 = (math.abs(Mobility.speedMultiplier - other.val) < 0.05) and C.green or C.button
            end
        end

        -- Fast Inv
        if btnDrop and btnDropLabel then
            btnDrop.BackgroundColor3 = FastInventory.fastDrop and C.green or C.button
            btnDropLabel:set(FastInventory.fastDrop and "Fast Drop: ON" or "Fast Drop: OFF")
        end
        if btnRecycle and btnRecycleLabel then
            btnRecycle.BackgroundColor3 = FastInventory.fastRecycle and C.red or C.button
            btnRecycleLabel:set(FastInventory.fastRecycle and "Fast Trash / Recycle: ON" or "Fast Trash / Recycle: OFF")
        end
        if secFastInv and secFastInv.setBadge then
            secFastInv.setBadge((FastInventory.fastDrop or FastInventory.fastRecycle) and "`2[ACTIVE]``" or "`o[OFF]``")
        end
        if cbCustomCount and cbCustomCount.set then cbCustomCount.set(FastInventory.customCountEnabled == true) end
        if countBox then countBox.Text = tostring(FastInventory.customCount or 1) end
        if updateFastInvStatus then updateFastInvStatus() end
    end
end

Setups.worldGrowScan = function(body)
    makeLabel(body, "`9GrowScan Bawaan Game (Owner Mode):``", 20, UDim2.new())

    local scanBtnRow = Instance.new("Frame", body)
    scanBtnRow.Size               = UDim2.new(1, 0, 0, 36)
    scanBtnRow.BackgroundTransparency = 1

    local scanThirdW = 180

    local f1 = makeButton(scanBtnRow, "World Blocks", 18, C.button, 6, 34, function()
        openNativeGrowScan("blocks")
    end, scanThirdW)
    f1.Position = UDim2.fromOffset(0, 0)

    local f2 = makeButton(scanBtnRow, "Floating Drops", 18, C.button, 6, 34, function()
        openNativeGrowScan("floating")
    end, scanThirdW)
    f2.Position = UDim2.fromOffset(scanThirdW + 8, 0)

    local f3 = makeButton(scanBtnRow, "Menu GrowScan", 18, C.button, 6, 34, function()
        openNativeGrowScan("menu")
    end, scanThirdW)
    f3.Position = UDim2.fromOffset((scanThirdW + 8) * 2, 0)

    local wpRow = Instance.new("Frame", body)
    wpRow.Size               = UDim2.new(1, 0, 0, 36)
    wpRow.BackgroundTransparency = 1

    lblWpStatus = makeLabel(wpRow, "`oWaypoint: Tidak ada waypoint aktif``", 18, UDim2.fromOffset(0, 8))

    local btnCancelWpFrame = makeButton(
        wpRow,
        "[X] Batal Waypoint",
        18,
        C.red,
        8,
        32,
        function()
            clearWaypoint()
            if lblWpStatus then lblWpStatus:set("`oWaypoint dibatalkan.``") end
        end,
        160
    )
    btnCancelWpFrame.AnchorPoint = Vector2.new(1, 0.5)
    btnCancelWpFrame.Position    = UDim2.new(1, 0, 0.5, 0)
end

Setups.world = function(page)
    local secGrowScan = createSection(page, "GrowScan World Scanner", true, 1)
    Setups.worldGrowScan(secGrowScan.body)
end
-- ═══════════════════════════════════════
--  AUTO CHAT SPAMMER CONTROLLER & UI
-- ═══════════════════════════════════════
local SpamConfig = {
    active = false,
    delay = 3.0,
    thread = nil,
    messages = {
        "SELL WORLD / DROP ITEMS!",
        "BUY DL / ITEMS PROMO!",
        "VISIT MY SHOP NOW!",
    },
    currentIndex = 1,
}

local function sendGameChatMessage(msg)
    if not msg or msg == "" then return false end
    local sent = false

    -- Method 1: Modern Roblox TextChatService WorldChannels (Used natively by Growblox)
    pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local worldChannels = TextChatService:FindFirstChild("WorldChannels")
        if worldChannels then
            for _, ch in ipairs(worldChannels:GetChildren()) do
                if ch:IsA("TextChannel") then
                    ch:SendAsync(msg)
                    sent = true
                    return
                end
            end
        end
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels then
            local rbxGeneral = textChannels:FindFirstChild("RBXGeneral") or textChannels:GetChildren()[1]
            if rbxGeneral and rbxGeneral:IsA("TextChannel") then
                rbxGeneral:SendAsync(msg)
                sent = true
                return
            end
        end
    end)
    if sent then return true end

    -- Method 2: Legacy SayMessageRequest fallback
    pcall(function()
        local DefaultChatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        if DefaultChatEvents then
            local SayReq = DefaultChatEvents:FindFirstChild("SayMessageRequest")
            if SayReq then
                SayReq:FireServer(msg, "All")
                sent = true
            end
        end
    end)
    return sent
end

lblSpamStatus = nil
btnToggleSpam = nil
btnToggleSpamLabel = nil
secSpamRef = nil

local function stopSpam()
    SpamConfig.active = false
    if SpamConfig.thread then
        pcall(task.cancel, SpamConfig.thread)
        SpamConfig.thread = nil
    end
    if btnToggleSpam then
        btnToggleSpam.BackgroundColor3 = C.green
    end
    if btnToggleSpamLabel and btnToggleSpamLabel.set then
        btnToggleSpamLabel:set("START AUTO SPAM")
    end
    if secSpamRef and secSpamRef.setBadge then
        secSpamRef.setBadge("`o[OFF]``")
    end
    if lblSpamStatus and lblSpamStatus.set then
        lblSpamStatus:set("`oStatus: Idle | Chat Spammer Standby``")
    end
end

local function startSpam()
    if SpamConfig.active then return end

    local validMessages = {}
    for _, m in ipairs(SpamConfig.messages) do
        local trimmed = string.match(m or "", "^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
            table.insert(validMessages, trimmed)
        end
    end

    if #validMessages == 0 then
        if lblSpamStatus and lblSpamStatus.set then
            lblSpamStatus:set("`4[!] Masukkan minimal 1 pesan chat!``")
        end
        return
    end

    SpamConfig.active = true
    if btnToggleSpam then
        btnToggleSpam.BackgroundColor3 = C.red
    end
    if btnToggleSpamLabel and btnToggleSpamLabel.set then
        btnToggleSpamLabel:set("STOP AUTO SPAM")
    end
    if secSpamRef and secSpamRef.setBadge then
        secSpamRef.setBadge("`2[ACTIVE]``")
    end

    SpamConfig.thread = task.spawn(function()
        SpamConfig.currentIndex = 1
        while SpamConfig.active do
            local currentValid = {}
            for _, m in ipairs(SpamConfig.messages) do
                local trimmed = string.match(m or "", "^%s*(.-)%s*$")
                if trimmed and #trimmed > 0 then
                    table.insert(currentValid, trimmed)
                end
            end

            if #currentValid == 0 then
                if lblSpamStatus and lblSpamStatus.set then
                    lblSpamStatus:set("`4[!] Tidak ada pesan valid untuk dikirim.``")
                end
                break
            end

            if SpamConfig.currentIndex > #currentValid then
                SpamConfig.currentIndex = 1
            end

            local msg = currentValid[SpamConfig.currentIndex]
            local ok = sendGameChatMessage(msg)
            if lblSpamStatus and lblSpamStatus.set then
                local displayMsg = msg
                if #displayMsg > 26 then
                    displayMsg = displayMsg:sub(1, 26) .. "..."
                end
                if ok then
                    lblSpamStatus:set(string.format("`2[#%d] Terkirim: \"%s\"``", SpamConfig.currentIndex, displayMsg))
                else
                    lblSpamStatus:set(string.format("`e[#%d] Mencoba kirim: \"%s\"...``", SpamConfig.currentIndex, displayMsg))
                end
            end

            SpamConfig.currentIndex = (SpamConfig.currentIndex % #currentValid) + 1

            task.wait(math.max(1.0, SpamConfig.delay))
        end
        stopSpam()
    end)
end

Setups.spam = function(page)
    -- Section 1: Main Toggle & Status
    local secSpam = createSection(page, "Auto Chat Spammer", true, 1)
    secSpamRef = secSpam

    lblSpamStatus = makeLabel(secSpam.body, "`oStatus: Idle | Chat Spammer Standby``", 18, UDim2.new())

    local btnFrame
    btnFrame, _, btnToggleSpam, btnToggleSpamLabel = makeButton(
        secSpam.body,
        "START AUTO SPAM",
        22,
        C.green,
        8,
        42,
        function()
            if SpamConfig.active then
                stopSpam()
            else
                startSpam()
            end
        end
    )
    secSpam.setBadge("`o[OFF]``")

    makeLabel(secSpam.body, "`oMenggunakan chat native game (World Chat). Otomatis kirim bergantian.``", 16, UDim2.new())

    -- Section 2: Delay Configuration
    local secDelay = createSection(page, "Pengaturan Delay Chat", true, 2)

    local lblDelayValue = makeLabel(
        secDelay.body,
        string.format("`wInterval Delay: `2%.1f detik``", SpamConfig.delay),
        18,
        UDim2.new()
    )

    local minDelay = 1.0
    local maxDelay = 15.0

    -- Interactive Delay Slider Bar
    local sliderBg = Instance.new("Frame", secDelay.body)
    sliderBg.Name                   = "DelaySliderBg"
    sliderBg.Size                   = UDim2.new(1, -20, 0, 16)
    sliderBg.BackgroundColor3       = C.dark
    sliderBg.BorderSizePixel        = 0
    corner(sliderBg, 8)
    stroke(sliderBg, C.fieldRim, 1)

    local initRatio = math.clamp((SpamConfig.delay - minDelay) / (maxDelay - minDelay), 0, 1)

    local sliderFill = Instance.new("Frame", sliderBg)
    sliderFill.Name                   = "Fill"
    sliderFill.Size                   = UDim2.new(initRatio, 0, 1, 0)
    sliderFill.BackgroundColor3       = C.cyan
    sliderFill.BorderSizePixel        = 0
    corner(sliderFill, 8)

    local sliderBtn = Instance.new("TextButton", sliderBg)
    sliderBtn.Size                   = UDim2.fromScale(1, 1)
    sliderBtn.BackgroundTransparency = 1
    sliderBtn.Text                   = ""

    makeLabel(secDelay.body, "`oGeser slider di atas atau klik preset tombol di bawah:``", 16, UDim2.new())

    local presetRow = Instance.new("Frame", secDelay.body)
    presetRow.Name                   = "DelayPresetRow"
    presetRow.Size                   = UDim2.new(1, 0, 0, 36)
    presetRow.BackgroundTransparency = 1
    presetRow.BorderSizePixel        = 0

    local presetLayout = Instance.new("UIListLayout", presetRow)
    presetLayout.FillDirection       = Enum.FillDirection.Horizontal
    presetLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    presetLayout.SortOrder           = Enum.SortOrder.LayoutOrder
    presetLayout.Padding             = UDim.new(0, 6)

    local delayPresets = { 1.5, 2.5, 3.0, 5.0, 10.0 }
    local presetBtns = {}

    local function updateDelayUI(newDelay)
        SpamConfig.delay = newDelay
        local ratio = math.clamp((newDelay - minDelay) / (maxDelay - minDelay), 0, 1)
        if sliderFill then sliderFill.Size = UDim2.new(ratio, 0, 1, 0) end
        if lblDelayValue and lblDelayValue.set then
            lblDelayValue:set(string.format("`wInterval Delay: `2%.1f detik``", SpamConfig.delay))
        end
        for d, btnData in pairs(presetBtns) do
            if btnData and btnData.btn then
                if math.abs(d - newDelay) < 0.05 then
                    btnData.btn.BackgroundColor3 = C.green
                else
                    btnData.btn.BackgroundColor3 = C.button
                end
            end
        end
    end

    local dragging = false
    local function updateSliderFromX(x)
        local relX = math.clamp(x - sliderBg.AbsolutePosition.X, 0, sliderBg.AbsoluteSize.X)
        local ratio = (sliderBg.AbsoluteSize.X > 0) and (relX / sliderBg.AbsoluteSize.X) or 0
        local newDelay = math.round((minDelay + ratio * (maxDelay - minDelay)) * 10) / 10
        updateDelayUI(newDelay)
        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
    end

    sliderBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateSliderFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSliderFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    for _, d in ipairs(delayPresets) do
        local isCur = math.abs(d - SpamConfig.delay) < 0.05
        local pFrame, _, pBtn, _ = makeButton(
            presetRow,
            string.format("%.1fs", d),
            18,
            isCur and C.green or C.button,
            6,
            34,
            function()
                updateDelayUI(d)
                if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
            end,
            80
        )
        presetBtns[d] = { frame = pFrame, btn = pBtn }
    end

    makeLabel(secDelay.body, "`sTip: Disarankan >= 2.5s agar tidak terkena flood limit chat game.``", 16, UDim2.new())

    -- Section 3: Multi-Message Editor
    local secMessages = createSection(page, "Daftar Pesan Chat (Multi-Pesan)", true, 3)

    makeLabel(secMessages.body, "`oPesan akan dikirim berurutan (Round-Robin) sesuai nomor slot.``", 16, UDim2.new())

    local messagesContainer = Instance.new("Frame", secMessages.body)
    messagesContainer.Name                   = "MessagesContainer"
    messagesContainer.Size                   = UDim2.new(1, 0, 0, 0)
    messagesContainer.AutomaticSize          = Enum.AutomaticSize.Y
    messagesContainer.BackgroundTransparency = 1
    messagesContainer.BorderSizePixel        = 0

    local mListLayout = Instance.new("UIListLayout", messagesContainer)
    mListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mListLayout.Padding   = UDim.new(0, 6)

    local function renderMessageRows()
        for _, child in ipairs(messagesContainer:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        for i, textVal in ipairs(SpamConfig.messages) do
            local row = Instance.new("Frame", messagesContainer)
            row.Name                   = "MsgRow_" .. i
            row.Size                   = UDim2.new(1, 0, 0, 38)
            row.BackgroundColor3       = C.box
            row.BackgroundTransparency = 0.35
            row.BorderSizePixel        = 0
            row.LayoutOrder            = i
            corner(row, 6)
            stroke(row, C.rim, 1)

            -- Index badge
            local badge = Instance.new("Frame", row)
            badge.Name                   = "Badge"
            badge.Size                   = UDim2.fromOffset(36, 38)
            badge.Position               = UDim2.new(0, 0, 0, 0)
            badge.BackgroundColor3       = Color3.fromRGB(24, 46, 56)
            badge.BorderSizePixel        = 0
            corner(badge, 6)
            makeLabel(badge, string.format("`w#%d``", i), 18, UDim2.fromScale(0.5, 0.5), { anchor = Vector2.new(0.5, 0.5) })

            -- Has delete button if > 1 message
            local canDelete = (#SpamConfig.messages > 1)
            local rightPad = canDelete and 46 or 10

            -- Text input box
            local inpBox = Instance.new("TextBox", row)
            inpBox.Name                   = "InpMessage"
            inpBox.Size                   = UDim2.new(1, -(42 + rightPad), 1, -8)
            inpBox.Position               = UDim2.fromOffset(42, 4)
            inpBox.BackgroundColor3       = C.field
            inpBox.BorderSizePixel        = 0
            inpBox.Font                   = Enum.Font.FredokaOne
            inpBox.TextSize               = 16
            inpBox.TextColor3             = C.text
            inpBox.PlaceholderColor3      = C.placeholder
            inpBox.PlaceholderText        = "Ketik pesan chat di sini..."
            inpBox.Text                   = textVal or ""
            inpBox.ClearTextOnFocus       = false
            corner(inpBox, 6)
            stroke(inpBox, C.fieldRim, 1)

            inpBox:GetPropertyChangedSignal("Text"):Connect(function()
                SpamConfig.messages[i] = inpBox.Text
            end)
            inpBox.FocusLost:Connect(function()
                SpamConfig.messages[i] = inpBox.Text
                if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
            end)

            if canDelete then
                local delFrame, _, delBtn, _ = makeButton(
                    row,
                    "✕",
                    18,
                    C.red,
                    6,
                    30,
                    function()
                        table.remove(SpamConfig.messages, i)
                        renderMessageRows()
                        if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
                    end,
                    32
                )
                delFrame.Position = UDim2.new(1, -38, 0, 4)
            end
        end
    end

    renderMessageRows()

    -- Add new slot button (Max 10 slots)
    local btnAddFrame, _, btnAdd, _ = makeButton(
        secMessages.body,
        "➕ TAMBAH KOLOM PESAN",
        18,
        C.button,
        6,
        34,
        function()
            if #SpamConfig.messages >= 10 then
                if lblSpamStatus then
                    lblSpamStatus:set("`e[!] Maksimal 10 kolom pesan chat!``")
                end
                return
            end
            table.insert(SpamConfig.messages, "")
            renderMessageRows()
            if Proxy and Proxy.saveConfig then pcall(Proxy.saveConfig) end
        end
    )

    updateSpamUI = function()
        if updateDelayUI then updateDelayUI(SpamConfig.delay or 3.0) end
        if renderMessageRows then renderMessageRows() end
        if SpamConfig.active then
            if btnToggleSpam then btnToggleSpam.BackgroundColor3 = C.red end
            if btnToggleSpamLabel and btnToggleSpamLabel.set then btnToggleSpamLabel:set("STOP AUTO SPAM") end
            if secSpamRef and secSpamRef.setBadge then secSpamRef.setBadge("`2[ACTIVE]``") end
        else
            if btnToggleSpam then btnToggleSpam.BackgroundColor3 = C.green end
            if btnToggleSpamLabel and btnToggleSpamLabel.set then btnToggleSpamLabel:set("START AUTO SPAM") end
            if secSpamRef and secSpamRef.setBadge then secSpamRef.setBadge("`o[OFF]``") end
        end
    end
end
local Proxy = {
    fastPKEnabled = true,
    punchGemsCheck = false,
    lastWorldName = "",
    casino = {
        hostPos = nil,             -- { x, y }
        positions = {},            -- [1]..[4] = { x, y, facing }
        taxRate = 10,              -- 10% default
        lastGame = nil,            -- { lockId, lockName, total, tax, payout }
        busy = false,
    },
    roulette = {
        instant = true,            -- Instant Roulette Fast Spin (Animasi 0s, Default ON)
        verify = true,             -- Anti-Scam Verification REAL vs FAKE (Default ON)
    },
    lastSpunNumbers = {},          -- [userId or name:lower()] = last spun number
    rouletteLogs = {},             -- live roulette spin history entries
    LOCKS = {
        ds   = { id = 202,  name = "Small Lock" },
        db   = { id = 204,  name = "Big Lock" },
        dh   = { id = 206,  name = "Huge Lock" },
        dw   = { id = 242,  name = "World Lock" },
        dd   = { id = 1796, name = "Diamond Lock" },
        dbgl = { id = 7188, name = "Blue Gem Lock" },
    },
    LOCK_NAMES = {
        [202]  = "Small Lock",
        [204]  = "Big Lock",
        [206]  = "Huge Lock",
        [242]  = "World Lock",
        [1796] = "Diamond Lock",
        [7188] = "Blue Gem Lock",
    },
    onDropFn = nil,
    invRef = nil,
    dieFn = nil,
    enterWorldFn = nil,
    chatTableRef = nil,
    activePosMarkers = {},
    _uiRefs = nil,
    logger = {
        logs = {},
        filter = "locks",
        search = "",
        maxLogs = 250,
    },
    cachedDrops = {},
}

function Proxy.addLog(logType, playerName, itemId, count, x, y)
    if type(count) ~= "number" or count <= 0 then return end
    local isLock = (Proxy.LOCK_NAMES and Proxy.LOCK_NAMES[itemId] ~= nil)
    if not isLock then return end -- ONLY LOCKS!

    local itemName = Proxy.LOCK_NAMES[itemId] or ("Item #" .. tostring(itemId))

    local entry = {
        time = os.date("%H:%M:%S"),
        type = logType, -- "DROP" / "TAKE"
        player = (type(playerName) == "string" and playerName ~= "") and playerName or "Unknown",
        itemId = itemId,
        itemName = itemName,
        count = count,
        x = math.floor(x or 0),
        y = math.floor(y or 0),
        isLock = true,
        isGem = false
    }

    table.insert(Proxy.logger.logs, 1, entry)
    if #Proxy.logger.logs > Proxy.logger.maxLogs then
        table.remove(Proxy.logger.logs)
    end

    if Proxy.updateLoggerUI then
        pcall(Proxy.updateLoggerUI)
    end
end

local CONFIG_FILE = "sysproxy_config.json"
local HttpService = game:GetService("HttpService")

function Proxy.notify(str)
    pcall(function()
        if Proxy.chatTableRef and Proxy.chatTableRef.add then
            Proxy.chatTableRef.add(str)
        else
            print("[Proxy Notify]", str)
        end
    end)
end

function Proxy.getOwnedCount(itemId)
    if Proxy.invRef and type(Proxy.invRef.count) == "function" then
        local success, count = pcall(function() return Proxy.invRef:count(itemId) end)
        if success and type(count) == "number" then return count end
    end
    if Proxy.invRef and type(Proxy.invRef.slots) == "table" then
        for _, slot in ipairs(Proxy.invRef.slots) do
            if type(slot) == "table" and slot[1] == itemId then
                return slot[2] or 0
            end
        end
    end
    local inv = getNativeInventory()
    if inv and type(inv.count) == "function" then
        local s, c = pcall(function() return inv:count(itemId) end)
        if s and type(c) == "number" then return c end
    end
    if inv and type(inv.slots) == "table" then
        for _, slot in ipairs(inv.slots) do
            if type(slot) == "table" and slot[1] == itemId then
                return slot[2] or 0
            end
        end
    end
    return 0
end

local _saveConfigTimer = nil
function Proxy.saveConfig(immediate)
    local function doSave()
        _saveConfigTimer = nil
        pcall(function()
            if not writefile then return end

            local curNick = (Players.LocalPlayer and Players.LocalPlayer:GetAttribute("Nick")) or nil

            local cfg = {
                -- Active Tab
                activeTab = activeTabKey or "player",

                -- Tab 1: PLAYER
                player = {
                    flyEnabled = (Mobility and Mobility.flyEnabled == true),
                    flySpeed = (Mobility and Mobility.flySpeed) or 10,
                    antiGravEnabled = (Mobility and Mobility.antiGravEnabled == true),
                    hazardEnabled = (AntiHazard and AntiHazard.enabled == true),
                    antiLava = (AntiHazard and AntiHazard.antiLava ~= false),
                    antiDeadly = (AntiHazard and AntiHazard.antiDeadly ~= false),
                    antiLaser = (AntiHazard and AntiHazard.antiLaser ~= false),
                    antiBumper = (AntiHazard and AntiHazard.antiBumper ~= false),
                    clickPathfind = (ClickPathfind and ClickPathfind.enabled == true),
                    speedEnabled = (Mobility and Mobility.speedEnabled == true),
                    speedMultiplier = (Mobility and Mobility.speedMultiplier) or 2.0,
                    fastDrop = (FastInventory and FastInventory.fastDrop == true),
                    fastRecycle = (FastInventory and FastInventory.fastRecycle == true),
                    customCountEnabled = (FastInventory and FastInventory.customCountEnabled == true),
                    customCount = (FastInventory and FastInventory.customCount) or 1,
                },

                -- Tab 2: FARM
                farm = {
                    pnb = {
                        targets = (PNB and type(PNB.targets) == "table") and PNB.targets or {},
                        itemId = PNB and (PNB.itemId or PNB.targetItemId) or 2,
                        itemName = PNB and PNB.itemName or "Dirt",
                        itemKind = PNB and PNB.itemKind or "block",
                        hits = PNB and (PNB.hits or PNB.hitsPerBlock) or 3,
                        hitDelay = PNB and PNB.hitDelay or 0.18,
                        loopDelay = PNB and PNB.loopDelay or 0.12,
                        mode = PNB and PNB.mode or "PNB",
                        layer = PNB and PNB.layer or "fg",
                    },
                    plant = {
                        selectedSeedId = AutoPlant and AutoPlant.selectedSeedId or nil,
                        selectedSeedName = AutoPlant and AutoPlant.selectedSeedName or "Bibit Otomatis (Tas)",
                        radius = AutoPlant and AutoPlant.radius or 50,
                    },
                    harvest = {
                        radius = AutoHarvest and AutoHarvest.radius or 999,
                    },
                    magnet = {
                        enabled = Magnet and (Magnet.enabled == true) or false,
                        radius = Magnet and Magnet.radius or 12,
                        filterMode = Magnet and Magnet.filterMode or "ALL",
                        delay = Magnet and Magnet.delay or 0.25,
                    },
                },

                -- Tab 3: FACTORY
                factory = {
                    posBreakX = AutoFactory and AutoFactory.posBreakX or nil,
                    posBreakY = AutoFactory and AutoFactory.posBreakY or nil,
                    posDropX = AutoFactory and AutoFactory.posDropX or nil,
                    posDropY = AutoFactory and AutoFactory.posDropY or nil,
                    factoryLength = AutoFactory and AutoFactory.factoryLength or 30,
                    profitLimit = AutoFactory and AutoFactory.profitLimit or 100,
                    targetSeedId = AutoFactory and AutoFactory.targetSeedId or nil,
                    targetSeedName = AutoFactory and AutoFactory.targetSeedName or "Pilih Seed",
                    targetBlockId = AutoFactory and AutoFactory.targetBlockId or nil,
                    targetBlockName = AutoFactory and AutoFactory.targetBlockName or "Block",
                },

                -- Tab 4: WORLD
                world = {
                    dirtFarm = {
                        mainBlockId = AutoBuildDF and AutoBuildDF.mainBlockId or 2,
                        mainBlockName = AutoBuildDF and AutoBuildDF.mainBlockName or "Dirt",
                        platBlockId = AutoBuildDF and AutoBuildDF.platBlockId or 194,
                        platBlockName = AutoBuildDF and AutoBuildDF.platBlockName or "Mushroom Platform",
                        platWidth = AutoBuildDF and AutoBuildDF.platWidth or 2,
                        bottomY = AutoBuildDF and AutoBuildDF.bottomY or 53,
                        topY = AutoBuildDF and AutoBuildDF.topY or 3,
                        stepY = AutoBuildDF and AutoBuildDF.stepY or 2,
                        minX = AutoBuildDF and AutoBuildDF.minX or 0,
                        maxX = AutoBuildDF and AutoBuildDF.maxX or 99,
                        buildDelay = AutoBuildDF and AutoBuildDF.buildDelay or 0.12,
                    },
                    clearWorld = {
                        clearBG = ClearWorld and (ClearWorld.clearBG ~= false),
                        autoSweep = ClearWorld and (ClearWorld.autoSweep ~= false),
                        autoTrash = ClearWorld and (ClearWorld.autoTrash == true),
                        hitDelay = ClearWorld and ClearWorld.hitDelay or 0.14,
                    },
                },

                -- Tab 5: SPAM
                spam = {
                    delay = SpamConfig and SpamConfig.delay or 3.0,
                    messages = SpamConfig and SpamConfig.messages or {
                        "SELL WORLD / DROP ITEMS!",
                        "BUY DL / ITEMS PROMO!",
                        "VISIT MY SHOP NOW!",
                    },
                },

                -- Tab 6: PROXY
                proxy = {
                    fastPK = (Proxy and Proxy.fastPKEnabled == true),
                    punchGemsCheck = (Proxy and Proxy.punchGemsCheck == true),
                    casino = {
                        hostPos = Proxy and Proxy.casino and Proxy.casino.hostPos or nil,
                        positions = Proxy and Proxy.casino and Proxy.casino.positions or {},
                        taxRate = Proxy and Proxy.casino and Proxy.casino.taxRate or 10,
                    },
                    roulette = {
                        instant = (Proxy and Proxy.roulette and Proxy.roulette.instant ~= false),
                        verify = (Proxy and Proxy.roulette and Proxy.roulette.verify ~= false),
                    },
                    nick = curNick,
                    lastWorldName = Proxy and Proxy.lastWorldName or "",
                },

                -- Root level backwards compatibility
                pnb = {
                    targets = (PNB and type(PNB.targets) == "table") and PNB.targets or {},
                    itemId = PNB and (PNB.itemId or PNB.targetItemId) or 2,
                    itemName = PNB and PNB.itemName or "Dirt",
                    itemKind = PNB and PNB.itemKind or "block",
                    hits = PNB and (PNB.hits or PNB.hitsPerBlock) or 3,
                    hitDelay = PNB and PNB.hitDelay or 0.18,
                    loopDelay = PNB and PNB.loopDelay or 0.12,
                    mode = PNB and PNB.mode or "PNB",
                    layer = PNB and PNB.layer or "fg",
                },
                casino = {
                    hostPos = Proxy and Proxy.casino and Proxy.casino.hostPos or nil,
                    positions = Proxy and Proxy.casino and Proxy.casino.positions or {},
                    taxRate = Proxy and Proxy.casino and Proxy.casino.taxRate or 10,
                },
                nick = curNick,
                fastPK = (Proxy and Proxy.fastPKEnabled == true),
                punchGemsCheck = (Proxy and Proxy.punchGemsCheck == true),
            }

            writefile(CONFIG_FILE, HttpService:JSONEncode(cfg))
        end)
    end

    if immediate then
        if _saveConfigTimer then
            task.cancel(_saveConfigTimer)
            _saveConfigTimer = nil
        end
        doSave()
    else
        if _saveConfigTimer then task.cancel(_saveConfigTimer) end
        _saveConfigTimer = task.delay(0.35, doSave)
    end
end

function Proxy.loadConfig()
    pcall(function()
        if not isfile or not isfile(CONFIG_FILE) or not readfile then return end
        local raw = readfile(CONFIG_FILE)
        if not raw or raw == "" then return end
        local cfg = HttpService:JSONDecode(raw)
        if type(cfg) ~= "table" then return end

        Proxy._isLoadingConfig = true

        -- 1. PLAYER TAB
        if cfg.player and type(cfg.player) == "table" then
            local p = cfg.player
            if p.flyEnabled ~= nil and Mobility then Mobility.flyEnabled = p.flyEnabled end
            if p.flySpeed ~= nil and Mobility then Mobility.flySpeed = p.flySpeed end
            if p.antiGravEnabled ~= nil and Mobility then Mobility.antiGravEnabled = p.antiGravEnabled end
            if p.hazardEnabled ~= nil and AntiHazard then AntiHazard.enabled = p.hazardEnabled end
            if p.antiLava ~= nil and AntiHazard then AntiHazard.antiLava = p.antiLava end
            if p.antiDeadly ~= nil and AntiHazard then AntiHazard.antiDeadly = p.antiDeadly end
            if p.antiLaser ~= nil and AntiHazard then AntiHazard.antiLaser = p.antiLaser end
            if p.antiBumper ~= nil and AntiHazard then AntiHazard.antiBumper = p.antiBumper end
            if p.clickPathfind ~= nil and ClickPathfind then ClickPathfind.enabled = p.clickPathfind end
            if p.speedEnabled ~= nil and Mobility then Mobility.speedEnabled = p.speedEnabled end
            if p.speedMultiplier ~= nil and Mobility then Mobility.speedMultiplier = p.speedMultiplier end
            if p.fastDrop ~= nil and FastInventory then FastInventory.fastDrop = p.fastDrop end
            if p.fastRecycle ~= nil and FastInventory then FastInventory.fastRecycle = p.fastRecycle end
            if p.customCountEnabled ~= nil and FastInventory then FastInventory.customCountEnabled = p.customCountEnabled end
            if p.customCount ~= nil and FastInventory then FastInventory.customCount = p.customCount end

            -- Apply player systems
            if applyAntiHazard then pcall(applyAntiHazard) end
            if applySpeedMode then pcall(applySpeedMode) end
            if toggleClickPathfindGrid and ClickPathfind then pcall(toggleClickPathfindGrid, ClickPathfind.enabled) end
            if ensureFastInventoryOverlays then pcall(ensureFastInventoryOverlays) end
        end

        -- 2. FARM TAB
        local farmCfg = cfg.farm or {}
        local pnbCfg = farmCfg.pnb or cfg.pnb
        if pnbCfg and PNB then
            if type(pnbCfg.targets) == "table" and next(pnbCfg.targets) ~= nil then
                PNB.targets = pnbCfg.targets
            end
            if pnbCfg.itemId then
                PNB.itemId = pnbCfg.itemId
                PNB.targetItemId = pnbCfg.itemId
            end
            if pnbCfg.itemName then PNB.itemName = pnbCfg.itemName end
            if pnbCfg.itemKind then PNB.itemKind = pnbCfg.itemKind end
            if pnbCfg.hits then
                PNB.hits = pnbCfg.hits
                PNB.hitsPerBlock = pnbCfg.hits
            end
            if pnbCfg.hitDelay then PNB.hitDelay = pnbCfg.hitDelay end
            if pnbCfg.loopDelay then PNB.loopDelay = pnbCfg.loopDelay end
            if pnbCfg.mode then PNB.mode = pnbCfg.mode end
            if pnbCfg.layer then PNB.layer = pnbCfg.layer end
            PNB.active = false
        end

        if farmCfg.plant and AutoPlant then
            if farmCfg.plant.selectedSeedId ~= nil then AutoPlant.selectedSeedId = farmCfg.plant.selectedSeedId end
            if farmCfg.plant.selectedSeedName ~= nil then AutoPlant.selectedSeedName = farmCfg.plant.selectedSeedName end
            if farmCfg.plant.radius ~= nil then AutoPlant.radius = farmCfg.plant.radius end
        end

        if farmCfg.harvest and AutoHarvest then
            if farmCfg.harvest.radius ~= nil then AutoHarvest.radius = farmCfg.harvest.radius end
        end

        -- Sysproxy Edition: Auto-Collect & Farm loops are strictly disabled
        if Magnet then
            Magnet.enabled = false
            if stopMagnetLoop then stopMagnetLoop() end
        end
        if AutoPlant then AutoPlant.active = false end
        if AutoHarvest then AutoHarvest.active = false end
        if AutoFactory then AutoFactory.active = false end

        -- 3. FACTORY TAB
        if cfg.factory and AutoFactory then
            local fac = cfg.factory
            if fac.posBreakX ~= nil then AutoFactory.posBreakX = fac.posBreakX end
            if fac.posBreakY ~= nil then AutoFactory.posBreakY = fac.posBreakY end
            if fac.posDropX ~= nil then AutoFactory.posDropX = fac.posDropX end
            if fac.posDropY ~= nil then AutoFactory.posDropY = fac.posDropY end
            if fac.factoryLength ~= nil then AutoFactory.factoryLength = fac.factoryLength end
            if fac.profitLimit ~= nil then AutoFactory.profitLimit = fac.profitLimit end
            if fac.targetSeedId ~= nil then AutoFactory.targetSeedId = fac.targetSeedId end
            if fac.targetSeedName ~= nil then AutoFactory.targetSeedName = fac.targetSeedName end
            if fac.targetBlockId ~= nil then AutoFactory.targetBlockId = fac.targetBlockId end
            if fac.targetBlockName ~= nil then AutoFactory.targetBlockName = fac.targetBlockName end
        end

        -- 4. WORLD TAB
        if cfg.world and type(cfg.world) == "table" then
            local w = cfg.world
            if w.dirtFarm and AutoBuildDF then
                local df = w.dirtFarm
                if df.mainBlockId ~= nil then AutoBuildDF.mainBlockId = df.mainBlockId end
                if df.mainBlockName ~= nil then AutoBuildDF.mainBlockName = df.mainBlockName end
                if df.platBlockId ~= nil then AutoBuildDF.platBlockId = df.platBlockId end
                if df.platBlockName ~= nil then AutoBuildDF.platBlockName = df.platBlockName end
                if df.platWidth ~= nil then AutoBuildDF.platWidth = df.platWidth end
                if df.bottomY ~= nil then AutoBuildDF.bottomY = df.bottomY end
                if df.topY ~= nil then AutoBuildDF.topY = df.topY end
                if df.stepY ~= nil then AutoBuildDF.stepY = df.stepY end
                if df.minX ~= nil then AutoBuildDF.minX = df.minX end
                if df.maxX ~= nil then AutoBuildDF.maxX = df.maxX end
                if df.buildDelay ~= nil then AutoBuildDF.buildDelay = df.buildDelay end
            end
            if w.clearWorld and ClearWorld then
                local cw = w.clearWorld
                if cw.clearBG ~= nil then ClearWorld.clearBG = cw.clearBG end
                if cw.autoSweep ~= nil then ClearWorld.autoSweep = cw.autoSweep end
                if cw.autoTrash ~= nil then ClearWorld.autoTrash = cw.autoTrash end
                if cw.hitDelay ~= nil then ClearWorld.hitDelay = cw.hitDelay end
            end
        end

        -- 5. SPAM TAB
        if cfg.spam and SpamConfig then
            if cfg.spam.delay ~= nil then SpamConfig.delay = cfg.spam.delay end
            if type(cfg.spam.messages) == "table" and #cfg.spam.messages > 0 then
                SpamConfig.messages = cfg.spam.messages
            end
        end

        -- 6. PROXY TAB
        local proxyCfg = cfg.proxy or {}
        local casinoCfg = proxyCfg.casino or cfg.casino
        if casinoCfg and Proxy.casino then
            if type(casinoCfg.hostPos) == "table" then Proxy.casino.hostPos = casinoCfg.hostPos end
            if type(casinoCfg.positions) == "table" then
                Proxy.casino.positions = {}
                for k, v in pairs(casinoCfg.positions) do
                    local n = tonumber(k)
                    if n then
                        Proxy.casino.positions[n] = v
                    else
                        Proxy.casino.positions[k] = v
                    end
                end
            end
            if type(casinoCfg.taxRate) == "number" then Proxy.casino.taxRate = casinoCfg.taxRate end
        end

        local rouletteCfg = proxyCfg.roulette or cfg.roulette
        if rouletteCfg and Proxy.roulette then
            if rouletteCfg.instant ~= nil then Proxy.roulette.instant = rouletteCfg.instant end
            if rouletteCfg.verify ~= nil then Proxy.roulette.verify = rouletteCfg.verify end
        end

        local fastPKVal = (proxyCfg.fastPK ~= nil and proxyCfg.fastPK) or cfg.fastPK
        if fastPKVal ~= nil then
            Proxy.fastPKEnabled = fastPKVal
        end

        local punchVal = (proxyCfg.punchGemsCheck ~= nil and proxyCfg.punchGemsCheck) or cfg.punchGemsCheck
        if punchVal ~= nil then
            Proxy.punchGemsCheck = punchVal
        end

        local nickVal = proxyCfg.nick or cfg.nick
        if nickVal and type(nickVal) == "string" and nickVal ~= "" and Players.LocalPlayer then
            Players.LocalPlayer:SetAttribute("Nick", nickVal)
        end

        if proxyCfg.lastWorldName and proxyCfg.lastWorldName ~= "" then
            Proxy.lastWorldName = proxyCfg.lastWorldName
        end

        -- 7. TAB RESTORATION
        if cfg.activeTab and switchTab then
            pcall(switchTab, cfg.activeTab)
        end

        -- 8. REFRESH ALL UI MODULES
        if updatePlayerUI then pcall(updatePlayerUI) end
        if updateFarmUI then pcall(updateFarmUI) end
        if updatePlantUI then pcall(updatePlantUI) end
        if updateHarvestUI then pcall(updateHarvestUI) end
        if updateMagnetUI then pcall(updateMagnetUI) end
        if updateGridVisuals then pcall(updateGridVisuals) end
        if updateFactoryUI then pcall(updateFactoryUI) end
        if updateDirtFarmUI then pcall(updateDirtFarmUI) end
        if updateClearWorldUI then pcall(updateClearWorldUI) end
        if updateSpamUI then pcall(updateSpamUI) end
        if Proxy.updateUI then pcall(Proxy.updateUI) end
        if Proxy.notify then
            Proxy.notify("`2[Config] Auto-load konfigurasi berhasil!``")
        end
        Proxy._isLoadingConfig = false
    end)
    Proxy._isLoadingConfig = false
end

local convertLockRemote = true

function Proxy.autoPecahForPayout(targetLockId, neededAmt)
    if not convertLockRemote then return end
    if targetLockId == 242 then -- World Lock
        local current = Proxy.getOwnedCount(242)
        if current < neededAmt then
            local deficit = neededAmt - current
            local dlsNeeded = math.ceil(deficit / 100)
            local ownedDL = Proxy.getOwnedCount(1796)
            if ownedDL < dlsNeeded and Proxy.getOwnedCount(7188) > 0 then
                local bglsNeeded = math.ceil((dlsNeeded - ownedDL) / 100)
                for i = 1, bglsNeeded do
                    sendConvertLock(7188, 1796)
                    task.wait(0.08)
                end
            end
            for i = 1, dlsNeeded do
                if Proxy.getOwnedCount(1796) > 0 then
                    sendConvertLock(1796, 242)
                    task.wait(0.08)
                end
            end
            task.wait(0.12)
        end
    elseif targetLockId == 1796 then -- Diamond Lock
        local current = Proxy.getOwnedCount(1796)
        if current < neededAmt then
            local deficit = neededAmt - current
            local bglsNeeded = math.ceil(deficit / 100)
            for i = 1, bglsNeeded do
                if Proxy.getOwnedCount(7188) > 0 then
                    sendConvertLock(7188, 1796)
                    task.wait(0.08)
                end
            end
            task.wait(0.12)
        end
    end
end

function Proxy.autoCompressLocks()
    if not convertLockRemote or Proxy.casino.busy then return end
    if Proxy.casino.lastGame and Proxy.casino.lastGame.payout and Proxy.casino.lastGame.payout > 0 then
        return
    end
    while Proxy.getOwnedCount(242) >= 100 do
        sendConvertLock(242, 1796)
        task.wait(0.1)
    end
    while Proxy.getOwnedCount(1796) >= 100 do
        sendConvertLock(1796, 7188)
        task.wait(0.1)
    end
end

function Proxy.dismissCasinoBanner()
    local old = PlayerGui:FindFirstChild("CasinoPopupBanner")
    if old then
        pcall(function() old:Destroy() end)
    end
end

function Proxy.showCasinoBanner(totalAmt, taxAmt, payoutAmt, lockName, taxPercent)
    Proxy.dismissCasinoBanner()

    local sg = Instance.new("ScreenGui")
    sg.Name = "CasinoPopupBanner"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 10000
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.fromOffset(360, 200)
    main.Position = UDim2.new(0.5, -180, 0.26, 0)
    main.BackgroundColor3 = C.box
    main.BorderSizePixel = 0
    main.Parent = sg

    corner(main, 8)
    dialogBorder(main)

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundTransparency = 1
    header.Parent = main

    makeLabel(header, "`3CASINO ROUND SUMMARY``", 22, UDim2.fromOffset(12, 7))

    local btnClose = Instance.new("ImageButton", header)
    btnClose.Name = "CloseX"
    btnClose.BackgroundTransparency = 1
    local crossImg = "rbxassetid://91811014634834"
    pcall(function()
        if Assets and Assets.UI and Assets.UI.cross then
            crossImg = Assets.UI.cross
        end
    end)
    btnClose.Image = crossImg
    btnClose.AnchorPoint = Vector2.new(1, 0.5)
    btnClose.Size = UDim2.fromOffset(28, 28)
    btnClose.Position = UDim2.new(1, -8, 0.5, 0)
    btnClose.Activated:Connect(function()
        pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
        Proxy.dismissCasinoBanner()
    end)

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -20, 0, 96)
    content.Position = UDim2.fromOffset(10, 42)
    content.BackgroundColor3 = C.dark
    content.BorderSizePixel = 0
    content.Parent = main
    corner(content, 6)

    local function addRow(yOffset, label, val, valColor)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 24)
        row.Position = UDim2.fromOffset(8, yOffset)
        row.BackgroundTransparency = 1
        row.Parent = content

        local tL = Instance.new("TextLabel")
        tL.Size = UDim2.new(0.48, 0, 1, 0)
        tL.BackgroundTransparency = 1
        tL.Text = label
        tL.TextColor3 = C.muted
        tL.Font = Enum.Font.GothamBold
        tL.TextSize = 12
        tL.TextXAlignment = Enum.TextXAlignment.Left
        tL.Parent = row

        local tR = Instance.new("TextLabel")
        tR.Size = UDim2.new(0.52, 0, 1, 0)
        tR.Position = UDim2.new(0.48, 0, 0, 0)
        tR.BackgroundTransparency = 1
        tR.Text = ": " .. val
        tR.TextColor3 = valColor or C.text
        tR.Font = Enum.Font.GothamBold
        tR.TextSize = 13
        tR.TextXAlignment = Enum.TextXAlignment.Left
        tR.Parent = row
    end

    addRow(6, "Total Taruhan", totalAmt .. " " .. lockName, C.cyan)
    addRow(34, "Tax Bandar (" .. taxPercent .. "%)", taxAmt .. " " .. lockName, C.gold)
    addRow(62, "Hadiah Pemenang", payoutAmt .. " " .. lockName, C.green)

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -20, 0, 28)
    hint.Position = UDim2.new(0, 10, 1, -34)
    hint.BackgroundTransparency = 1
    hint.Text = "Ketik /win1 - /win4 atau klik tombol WIN untuk antar hadiah!"
    hint.TextColor3 = C.cyan
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 10
    hint.Parent = main

    sg.Parent = PlayerGui
    task.delay(5, function()
        if sg and sg.Parent then
            pcall(function() sg:Destroy() end)
        end
    end)
end

function Proxy.showCasinoWarningBanner(posData, maxBet, lockName, activeIndices)
    Proxy.dismissCasinoBanner()

    local sg = Instance.new("ScreenGui")
    sg.Name = "CasinoPopupBanner"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 10000
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local main = Instance.new("Frame")
    main.Name = "Main"
    local rowCount = #activeIndices
    local h = 82 + (rowCount * 26) + 36
    main.Size = UDim2.fromOffset(360, math.max(190, h))
    main.Position = UDim2.new(0.5, -180, 0.24, 0)
    main.BackgroundColor3 = C.box
    main.BorderSizePixel = 0
    main.Parent = sg

    corner(main, 8)
    dialogBorder(main)

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundTransparency = 1
    header.Parent = main

    makeLabel(header, "`4TARUHAN TIDAK SAMA!``", 22, UDim2.fromOffset(12, 7))

    local btnClose = Instance.new("ImageButton", header)
    btnClose.Name = "CloseX"
    btnClose.BackgroundTransparency = 1
    local crossImg = "rbxassetid://91811014634834"
    pcall(function()
        if Assets and Assets.UI and Assets.UI.cross then
            crossImg = Assets.UI.cross
        end
    end)
    btnClose.Image = crossImg
    btnClose.AnchorPoint = Vector2.new(1, 0.5)
    btnClose.Size = UDim2.fromOffset(28, 28)
    btnClose.Position = UDim2.new(1, -8, 0.5, 0)
    btnClose.Activated:Connect(function()
        pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
        Proxy.dismissCasinoBanner()
    end)

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -20, 0, rowCount * 26 + 10)
    content.Position = UDim2.fromOffset(10, 42)
    content.BackgroundColor3 = C.dark
    content.BorderSizePixel = 0
    content.Parent = main
    corner(content, 6)

    local y = 6
    for _, idx in ipairs(activeIndices) do
        local d = posData[idx]
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 22)
        row.Position = UDim2.fromOffset(8, y)
        row.BackgroundTransparency = 1
        row.Parent = content

        local tL = Instance.new("TextLabel")
        tL.Size = UDim2.new(0.35, 0, 1, 0)
        tL.BackgroundTransparency = 1
        tL.Text = "Pos " .. idx
        tL.TextColor3 = C.cyan
        tL.Font = Enum.Font.GothamBold
        tL.TextSize = 12
        tL.TextXAlignment = Enum.TextXAlignment.Left
        tL.Parent = row

        local tR = Instance.new("TextLabel")
        tR.Size = UDim2.new(0.65, 0, 1, 0)
        tR.Position = UDim2.new(0.35, 0, 0, 0)
        tR.BackgroundTransparency = 1

        if d.amount == maxBet and maxBet > 0 then
            tR.Text = ": " .. d.amount .. " " .. lockName .. " (OK)"
            tR.TextColor3 = C.green
        elseif d.amount == 0 then
            tR.Text = ": Kosong! (Kurang " .. maxBet .. ")"
            tR.TextColor3 = C.red
        else
            local diff = maxBet - d.amount
            tR.Text = ": " .. d.amount .. " " .. lockName .. " (Kurang " .. diff .. "!)"
            tR.TextColor3 = C.red
        end

        tR.Font = Enum.Font.GothamBold
        tR.TextSize = 11
        tR.TextXAlignment = Enum.TextXAlignment.Left
        tR.Parent = row

        y = y + 26
    end

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -20, 0, 28)
    hint.Position = UDim2.new(0, 10, 1, -34)
    hint.BackgroundTransparency = 1
    hint.Text = "Samakan nominal taruhan tiap player lalu validasi lagi!"
    hint.TextColor3 = C.gold
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 10
    hint.Parent = main

    sg.Parent = PlayerGui
    task.delay(5, function()
        if sg and sg.Parent then
            pcall(function() sg:Destroy() end)
        end
    end)
end

function Proxy.showPosMarker(idx, tx, ty)
    if not tx or not ty then return end
    if Proxy.activePosMarkers[idx] and Proxy.activePosMarkers[idx].Parent then
        pcall(function() Proxy.activePosMarkers[idx]:Destroy() end)
        Proxy.activePosMarkers[idx] = nil
    end

    local camera, tiles, _ = getCameraAndTiles()
    if not camera or not tiles then return end

    local DISPLAY_SIZE = 64
    if Assets and Assets.TileSize then
        DISPLAY_SIZE = Assets.TileSize * 2
    end

    local box = Instance.new("Frame")
    box.Name = "PosMarker_" .. tostring(idx)
    box.Size = UDim2.fromOffset(DISPLAY_SIZE, DISPLAY_SIZE)
    box.Position = UDim2.fromOffset(tx * DISPLAY_SIZE, ty * DISPLAY_SIZE)
    box.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    box.BackgroundTransparency = 0.72
    box.BorderSizePixel = 0
    box.ZIndex = 25
    box.Parent = tiles

    corner(box, 4)

    local strk = Instance.new("UIStroke")
    strk.Color = Color3.fromRGB(0, 255, 120)
    strk.Thickness = 2.5
    strk.Transparency = 0.1
    strk.Parent = box

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text = "P" .. tostring(idx)
    lbl.Font = Enum.Font.FredokaOne
    lbl.TextSize = 22
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0
    lbl.ZIndex = 26
    lbl.Parent = box

    Proxy.activePosMarkers[idx] = box

    task.spawn(function()
        task.wait(2.2)
        if box and box.Parent then
            local tInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            pcall(function()
                TweenService:Create(box, tInfo, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(strk, tInfo, { Transparency = 1 }):Play()
                TweenService:Create(lbl, tInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
            end)
            task.wait(0.8)
            if box and box.Parent then
                box:Destroy()
            end
            if Proxy.activePosMarkers[idx] == box then
                Proxy.activePosMarkers[idx] = nil
            end
        end
    end)
end

function Proxy.casinoGlideTo(targetTileX, targetTileY)
    local px, py, rawX, rawY = getPlayerTilePos()
    if not px or not py then return false end
    if px == targetTileX and py == targetTileY then return true end

    -- Cari rute pathfinding A* yang otomatis respect pintu / entrance locked
    local path = findPath(px, py, targetTileX, targetTileY, 25000)
    if path and #path > 0 then
        ClickPathfind.busy = true
        followPath(path, 0.85, rawX or (px + 0.5), rawY or (py + 1.0))
        ClickPathfind.busy = false
        task.wait(0.08)
        return true
    else
        -- Jika target persis terhalang atau berada di samping, cari pijakan terbuka di sekitarnya
        local altPath = nil
        for _, off in ipairs({{0, -1}, {-1, 0}, {1, 0}, {0, 1}}) do
            local ax = targetTileX + off[1]
            local ay = targetTileY + off[2]
            if ax >= 0 and ax < 100 and ay >= 0 and ay < 60 and not isSolidTile(ax, ay) then
                local p = findPath(px, py, ax, ay, 25000)
                if p and #p > 0 then
                    altPath = p
                    break
                end
            end
        end

        if altPath and #altPath > 0 then
            ClickPathfind.busy = true
            followPath(altPath, 0.85, rawX or (px + 0.5), rawY or (py + 1.0))
            ClickPathfind.busy = false
            task.wait(0.08)
            return true
        else
            -- Terhalang penuh oleh pintu locked atau dinding tanpa celah
            Proxy.notify(string.format("`4[TP] Jalur ke (%d, %d) terhalang oleh pintu locked atau dinding!``", targetTileX + 1, targetTileY + 1))
            return false
        end
    end
end

function Proxy.getPositionDrops(pos)
    local w = getNativeWorld()
    if not w or not w.dropList then return 0, nil, "" end
    local drops = w.dropList()
    if not drops or #drops == 0 then return 0, nil, "" end

    local centerX = pos.x + 0.5
    local centerY = pos.y + 1.0
    local total = 0
    local lockId = nil
    local lockName = ""

    for _, drop in ipairs(drops) do
        if drop and drop.id and drop.n and drop.n > 0 then
            local dx = (drop.x or centerX) - centerX
            local dy = (drop.y or centerY) - centerY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 1.5 then
                total = total + drop.n
                lockId = drop.id
                lockName = Proxy.LOCK_NAMES[drop.id] or ("Item #" .. drop.id)
            end
        end
    end
    return total, lockId, lockName
end

function Proxy.sweepTileDrops(tileX, tileY)
    local w = getNativeWorld()
    if not w or not w.dropList then return {} end
    local drops = w.dropList()
    if not drops or #drops == 0 then return {} end

    local inv = getNativeInventory()
    local collected = {}
    local centerX = tileX + 0.5
    local centerY = tileY + 1.0

    for i = #drops, 1, -1 do
        local drop = drops[i]
        if drop and drop.uid and drop.n and drop.n > 0 and not drop.taking then
            local dx = (drop.x or centerX) - centerX
            local dy = (drop.y or centerY) - centerY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 1.5 then
                local dropId = drop.id
                local taken = tryPickupDrop(drop, inv)
                if taken > 0 then
                    collected[dropId] = (collected[dropId] or 0) + taken
                end
            end
        end
    end
    return collected
end

function Proxy.runCasinoCollect()
    if Proxy.casino.busy then
        Proxy.notify("`4[Casino] Bot sedang berjalan! Tunggu sebentar...``")
        return
    end

    local activeIndices = {}
    for i = 1, 4 do
        if Proxy.casino.positions[i] then
            table.insert(activeIndices, i)
        end
    end

    if #activeIndices == 0 then
        Proxy.notify("`4[Casino] Belum ada posisi yang di-set! Gunakan tombol Set Pos atau /pos1 - /pos4 dulu.``")
        return
    end

    local posData = {}
    local maxBet = 0
    local mainLockId = nil
    local mainLockName = ""
    local allEqual = true
    local firstBet = nil

    for _, idx in ipairs(activeIndices) do
        local amt, lid, lname = Proxy.getPositionDrops(Proxy.casino.positions[idx])
        posData[idx] = { amount = amt, lockId = lid, lockName = lname }
        if amt > maxBet then
            maxBet = amt
            mainLockId = lid
            mainLockName = lname
        end
        if firstBet == nil then
            firstBet = amt
        elseif amt ~= firstBet then
            allEqual = false
        end
    end

    if maxBet == 0 then
        Proxy.notify("`o[Casino] Tidak ada taruhan yang ditemukan di meja (Pos 1 - 4 kosong).``")
        return
    end

    if not allEqual or firstBet == 0 then
        Proxy.showCasinoWarningBanner(posData, maxBet, mainLockName, activeIndices)
        local details = {}
        for _, idx in ipairs(activeIndices) do
            local d = posData[idx]
            if d.amount < maxBet then
                local diff = maxBet - d.amount
                table.insert(details, "Pos " .. idx .. " kurang " .. diff)
            end
        end
        Proxy.notify("`4[Casino] Gagal! Taruhan tidak sama: " .. table.concat(details, ", ") .. "!``")
        pcall(function() if Sfx and Sfx.play then Sfx.play("trash") end end)
        return
    end

    local totalPool = maxBet * #activeIndices
    local rawTax = totalPool * (Proxy.casino.taxRate / 100)
    local taxAmt = math.ceil(rawTax)
    local payoutAmt = totalPool - taxAmt

    Proxy.casino.lastGame = {
        lockId = mainLockId,
        lockName = mainLockName,
        total = totalPool,
        tax = taxAmt,
        payout = payoutAmt
    }

    Proxy.showCasinoBanner(totalPool, taxAmt, payoutAmt, mainLockName, Proxy.casino.taxRate)
    Proxy.notify("`2[Casino] Taruhan sama! Terkumpul: " .. totalPool .. " " .. mainLockName .. " | Tax " .. Proxy.casino.taxRate .. "%: " .. taxAmt .. " | Hadiah: " .. payoutAmt .. "``")

    Proxy.casino.busy = true
    for _, idx in ipairs(activeIndices) do
        local pos = Proxy.casino.positions[idx]
        if pos then
            Proxy.casinoGlideTo(pos.x, pos.y)
            task.wait(0.12)
            Proxy.sweepTileDrops(pos.x, pos.y)
        end
    end

    Proxy.casino.busy = false

    Proxy.notify("`2[Casino] Selesai sweep! Klik tombol WIN atau ketik /win1 - /win" .. #activeIndices .. " untuk bayar pemenang!``")
    Proxy.updateUI()
end

function Proxy.runCasinoPayout(slotIndex, customAmount)
    Proxy.dismissCasinoBanner()

    if Proxy.casino.busy then
        Proxy.notify("`4[Casino] Bot sedang berjalan! Tunggu sebentar...``")
        return
    end

    local pos = Proxy.casino.positions[slotIndex]
    if not pos then
        Proxy.notify("`4[Casino] Pos " .. slotIndex .. " belum di-set!``")
        return
    end

    local lockId = (Proxy.casino.lastGame and Proxy.casino.lastGame.lockId) or 242
    local lockName = (Proxy.casino.lastGame and Proxy.casino.lastGame.lockName) or "World Lock"
    local payoutAmt = customAmount or (Proxy.casino.lastGame and Proxy.casino.lastGame.payout) or 0

    if payoutAmt <= 0 then
        Proxy.notify("`4[Casino] Belum ada data taruhan! Validasi taruhan dulu (/tp) atau isi nominal custom.``")
        return
    end

    Proxy.autoPecahForPayout(lockId, payoutAmt)

    local owned = Proxy.getOwnedCount(lockId)
    if owned < payoutAmt then
        Proxy.notify("`4[Casino] Gagal! " .. lockName .. " di tas kurang (" .. owned .. "/" .. payoutAmt .. ")!``")
        return
    end

    Proxy.casino.busy = true
    Proxy.notify("`2[Casino] Mengantar hadiah " .. payoutAmt .. " " .. lockName .. " ke Pos " .. slotIndex .. "...``")

    Proxy.casinoGlideTo(pos.x, pos.y)
    task.wait(0.12)

    local targetFacing = pos.facing or 1
    local facingBit = (targetFacing == 1) and 1 or 0
    local targetX = pos.x + 0.5
    local targetY = pos.y + 1.0

    if Proxy.onDropFn and debug and debug.setupvalue then
        pcall(debug.setupvalue, Proxy.onDropFn, 2, targetFacing)
    end

    safeSendMove({
        x = targetX,
        y = targetY,
        vx = (targetFacing == 1 and 0.05 or -0.05),
        vy = 0,
        flags = 2 + facingBit,
    })
    task.wait(0.08)

    if Proxy.onDropFn then
        Proxy.onDropFn(lockId, payoutAmt)
    end
    task.wait(0.2)

    if Proxy.casino.hostPos then
        Proxy.casinoGlideTo(Proxy.casino.hostPos.x, Proxy.casino.hostPos.y)
    end
    Proxy.casino.busy = false
    Proxy.casino.lastGame = nil

    Proxy.notify("`2[Casino] Sukses! Pemenang Pos " .. slotIndex .. " dibayar " .. payoutAmt .. " " .. lockName .. "!``")
    Proxy.updateUI()

    task.spawn(function()
        task.wait(0.4)
        pcall(Proxy.autoCompressLocks)
    end)
end

-- Floating Drop & Gem Text on Block Break / Drop Spawn (Strict 1-Grid Tile & Total Ground Accumulation)
local activeTileLabels = {}
local pendingTileUpdates = {}
local gameDropsTable = nil

local function findGameDropsTable()
    if gameDropsTable then return gameDropsTable end
    local w = getNativeWorld and getNativeWorld()
    if w and type(w.dropList) == "function" then
        local drops = w.dropList()
        if drops then
            gameDropsTable = drops
            return drops
        end
    end
    if Net and Net.dropAdded and Net.dropAdded.getListeners then
        for _, fn in ipairs(Net.dropAdded.getListeners()) do
            local ups = debug.getupvalues(fn)
            for _, v in pairs(ups) do
                if type(v) == "table" and type(v.dropList) == "function" then
                    gameDropsTable = v.dropList()
                    return gameDropsTable
                end
            end
        end
    end
    local wr = ReplicatedStorage:FindFirstChild("WorldRemotes")
    local dtr = wr and wr:FindFirstChild("DropTaken")
    if dtr and getconnections then
        local conns = getconnections(dtr.OnClientEvent)
        for _, c in ipairs(conns or {}) do
            local fn = c.Function
            if type(fn) == "function" then
                local ok1, u1 = pcall(debug.getupvalue, fn, 1)
                if ok1 and type(u1) == "table" then
                    gameDropsTable = u1
                    return gameDropsTable
                end
            end
        end
    end
    return nil
end

local function getTotalDropsOnTile(tx, ty, itemId)
    local drops = nil
    local w = getNativeWorld and getNativeWorld()
    if w and type(w.dropList) == "function" then
        drops = w.dropList()
    end
    if not drops then
        drops = gameDropsTable or findGameDropsTable()
    end
    if not drops then return 0 end
    local total = 0
    for _, drop in ipairs(drops) do
        if type(drop) == "table" and drop.id == itemId and type(drop.x) == "number" and type(drop.y) == "number" then
            if math.floor(drop.x) == tx and math.floor(drop.y) == ty then
                total = total + (drop.n or 0)
            end
        end
    end
    return total
end

local function spawnFloatingDropText(tx, ty, itemId, count)
    local pgui = PlayerGui
    local gameGui = pgui:FindFirstChild("GameGui")
    local camera = gameGui and gameGui:FindFirstChild("Camera", true)
    local tiles = camera and camera:FindFirstChild("Tiles")
    if not camera or not tiles then return nil end

    local uiScale = 1
    local s = camera:FindFirstChild("UIScale")
    if s and s:IsA("UIScale") then uiScale = s.Scale end

    local DISPLAY_SIZE = 64
    local tileSize = DISPLAY_SIZE * uiScale
    local absPos = tiles.AbsolutePosition

    -- Exact center of that 1 grid box (ngepass di tile nya, tidak terlalu naik)
    local screenX = absPos.X + (tx + 0.5) * tileSize
    local screenY = absPos.Y + (ty + 0.5) * tileSize

    local screenSize = gameGui.AbsoluteSize
    if screenX < -60 or screenX > screenSize.X + 60 or screenY < -60 or screenY > screenSize.Y + 60 then
        return nil
    end

    local floatGui = pgui:FindFirstChild("SyshubDropFloatGui")
    if not floatGui then
        floatGui = Instance.new("ScreenGui")
        floatGui.Name = "SyshubDropFloatGui"
        floatGui.DisplayOrder = 9999
        floatGui.IgnoreGuiInset = true
        floatGui.ResetOnSpawn = false
        floatGui.Parent = pgui
    end

    local key = tx .. "," .. ty .. ":" .. itemId
    if activeTileLabels[key] and activeTileLabels[key].Parent then
        activeTileLabels[key]:Destroy()
        activeTileLabels[key] = nil
    end

    local isGem = (itemId == 112)
    local gemChar = utf8.char(0x1F48E)
    local itemName = isGem and "Gems" or (ItemDB and ItemDB[itemId] and ItemDB[itemId].name or "Item")
    local textColor = isGem and Color3.fromRGB(60, 255, 140) or Color3.fromRGB(255, 230, 100)

    local lbl = Instance.new("TextLabel")
    lbl.Name = "FloatDrop"
    lbl.BackgroundTransparency = 1
    lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.Size = UDim2.fromOffset(160, 30)
    lbl.Position = UDim2.fromOffset(screenX, screenY)
    lbl.Font = Enum.Font.FredokaOne
    lbl.TextSize = isGem and 20 or 16
    lbl.TextColor3 = textColor
    lbl.Text = tostring(count) .. " " .. (isGem and (gemChar .. " Gems") or itemName)
    lbl.ZIndex = 10000
    lbl.Parent = floatGui
    activeTileLabels[key] = lbl

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 2.5
    stroke.Parent = lbl

    local scaleComp = Instance.new("UIScale")
    scaleComp.Scale = 0.75
    scaleComp.Parent = lbl

    -- Animasi pop OUT (zoom outward) bukan UP, posisi tetap ngepass di tile
    local outTween = TweenService:Create(scaleComp, TweenInfo.new(0.95, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.35 })
    local fadeTween = TweenService:Create(lbl, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
    local strokeFade = TweenService:Create(stroke, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })

    outTween:Play()
    fadeTween:Play()
    strokeFade:Play()

    task.delay(1.0, function()
        if activeTileLabels[key] == lbl then
            activeTileLabels[key] = nil
        end
        pcall(function() lbl:Destroy() end)
    end)

    return lbl
end

local function handleTileDropUpdate(tx, ty, itemId, fallbackCount)
    local key = tx .. "," .. ty .. ":" .. itemId
    if pendingTileUpdates[key] then return end
    pendingTileUpdates[key] = true

    task.delay(0.08, function()
        pendingTileUpdates[key] = nil
        local total = getTotalDropsOnTile(tx, ty, itemId)
        if total <= 0 then
            total = fallbackCount
        end
        spawnFloatingDropText(tx, ty, itemId, total)
    end)
end

Proxy.findGameDropsTable = findGameDropsTable
Proxy.getTotalDropsOnTile = getTotalDropsOnTile
Proxy.spawnFloatingDropText = spawnFloatingDropText
Proxy.handleTileDropUpdate = handleTileDropUpdate
Proxy.activeTileLabels = activeTileLabels

function Proxy.updateUI()
    if not Proxy._uiRefs then return end
    local r = Proxy._uiRefs

    -- 1. Fast Wrench
    if r.btnFastWrench and r.lblFastWrench then
        r.btnFastWrench.BackgroundColor3 = Proxy.fastPKEnabled and C.cyan or C.button
        r.lblFastWrench:set(Proxy.fastPKEnabled and "Fast Wrench: ON (LMB=Pull | RMB=Kick)" or "Fast Wrench: OFF (Klik untuk Aktifkan)")
    end
    if r.secWrench and r.secWrench.setBadge then
        r.secWrench.setBadge(Proxy.fastPKEnabled and "`c[ACTIVE]``" or "`o[OFF]``")
    end

    -- Punch to Check Gems Toggle
    if r.btnPunchGems and r.lblPunchGems then
        r.btnPunchGems.BackgroundColor3 = Proxy.punchGemsCheck and C.green or C.button
        r.lblPunchGems:set(Proxy.punchGemsCheck and "Punch to Check Gems: ON (/pgems)" or "Punch to Check Gems: OFF (/pgems)")
    end

    -- 2. Casino Host & Pos
    if r.lblHost then
        if Proxy.casino.hostPos then
            r.lblHost:set(string.format("`2Titik Bandar: (%d, %d)``", Proxy.casino.hostPos.x + 1, Proxy.casino.hostPos.y + 1))
        else
            r.lblHost:set("`oTitik Bandar: Belum di-set (Gunakan tombol Set Host atau /host)``")
        end
    end

    if r.lblPositions then
        local pStr = {}
        for i = 1, 4 do
            local p = Proxy.casino.positions[i]
            if p then
                local fStr = (p.facing == 1) and "Kanan" or "Kiri"
                table.insert(pStr, string.format("`cP%d:(%d,%d|%s)``", i, p.x + 1, p.y + 1, fStr))
            else
                table.insert(pStr, string.format("`oP%d:(-)``", i))
            end
        end
        r.lblPositions:set("`wMeja 1-4: ``" .. table.concat(pStr, "  "))
    end

    if r.lblTax then
        r.lblTax:set(string.format("`ePotongan Tax Bandar: %d%%``", Proxy.casino.taxRate))
    end

    if r.lblLastGame then
        local g = Proxy.casino.lastGame
        if g then
            r.lblLastGame:set(string.format("`3Ronde Terakhir: Total %d %s | Tax %d%% (%d) | Hadiah: %d``",
                g.total, g.lockName, Proxy.casino.taxRate, g.tax, g.payout))
        else
            r.lblLastGame:set("`oRonde Terakhir: Belum ada permainan``")
        end
    end

    -- 3. Streamer Nick
    if r.lblNickStatus then
        local nick = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("Nick")
        if nick and nick ~= "" then
            r.lblNickStatus:set(string.format("`2Streamer Nick: %s`` `o(Asli: %s)``", nick, Players.LocalPlayer.Name))
        else
            r.lblNickStatus:set(string.format("`oNickname Asli: %s (Belum disamarkan)``", Players.LocalPlayer.Name))
        end
    end

    -- 4. Roulette Toggles
    if r.btnInstant and r.btnInstantLbl then
        r.btnInstant.BackgroundColor3 = Proxy.roulette.instant and C.green or C.button
        r.btnInstantLbl:set(Proxy.roulette.instant and "Instant Spin: ON" or "Instant Spin: OFF")
    end
    if r.btnVerify and r.btnVerifyLbl then
        r.btnVerify.BackgroundColor3 = Proxy.roulette.verify and C.green or C.button
        r.btnVerifyLbl:set(Proxy.roulette.verify and "Anti-Scam REAL/FAKE: ON" or "Anti-Scam REAL/FAKE: OFF")
    end
end

-- ==============================================================================
--  SETUPS.PROXY: UI INITIALIZER FOR PROXY TAB
-- ==============================================================================
Setups.proxy = function(page)
    Proxy._uiRefs = {}
    local r = Proxy._uiRefs

    -- Section 1: Fast Wrench & Player Combat (Default OPEN)
    local secWrench = createSection(page, "Fast Action Wrench (Pull & Kick)", true, 1)
    r.secWrench = secWrench

    makeLabel(secWrench.body, "`oFast Wrench Intercept: LMB otomatis PULL player, RMB otomatis KICK!``", 16, UDim2.new())

    local btnFWFrame, _, btnFW, btnFWLabel = makeButton(
        secWrench.body,
        Proxy.fastPKEnabled and "Fast Wrench: ON (LMB=Pull | RMB=Kick)" or "Fast Wrench: OFF (Klik untuk Aktifkan)",
        15,
        Proxy.fastPKEnabled and C.cyan or C.button,
        8,
        36,
        function()
            Proxy.fastPKEnabled = not Proxy.fastPKEnabled
            pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
            Proxy.notify(Proxy.fastPKEnabled and "`2[Fast Wrench] Diaktifkan (LMB = Pull, RMB = Kick)``" or "`4[Fast Wrench] Dimatikan``")
            Proxy.saveConfig()
            Proxy.updateUI()
        end
    )
    r.btnFastWrench = btnFW
    r.lblFastWrench = btnFWLabel
    secWrench.setBadge(Proxy.fastPKEnabled and "`c[ACTIVE]``" or "`o[OFF]``")

    local rowWrenchQuick = Instance.new("Frame", secWrench.body)
    rowWrenchQuick.Size = UDim2.new(1, 0, 0, 36)
    rowWrenchQuick.BackgroundTransparency = 1
    rowWrenchQuick.BorderSizePixel = 0

    local lWrench = Instance.new("UIListLayout", rowWrenchQuick)
    lWrench.FillDirection = Enum.FillDirection.Horizontal
    lWrench.Padding = UDim.new(0, 10)

    makeButton(rowWrenchQuick, "Respawn (/res)", 15, C.button, 6, 34, function()
        if Proxy.dieFn then
            Proxy.dieFn()
            Proxy.notify("`2[Respawn] Normal respawn dijalankan...``")
        else
            Proxy.notify("`4[Respawn] Fungsi die/respawn belum terdeteksi!``")
        end
    end, 180)

    makeButton(rowWrenchQuick, "Re-Warp (/rw)", 15, C.button, 6, 34, function()
        if Proxy.lastWorldName ~= "" and Proxy.enterWorldFn then
            if Proxy.setupAutoReloadOnTeleport then Proxy.setupAutoReloadOnTeleport() end
            Proxy.enterWorldFn(Proxy.lastWorldName)
            Proxy.notify("`2[Re-warp] Kembali ke world " .. Proxy.lastWorldName .. "...``")
        else
            Proxy.notify("`4[Re-warp] Belum ada world sebelumnya!``")
        end
    end, 180)


    -- Section 2: Casino Controller (Bandar Otomatis) (Default OPEN)
    local secCasino = createSection(page, "Casino Controller (Auto Bet & Payout)", true, 2)

    local cardStatus = Instance.new("Frame", secCasino.body)
    cardStatus.Size = UDim2.new(1, 0, 0, 118)
    cardStatus.BackgroundColor3 = C.dark
    cardStatus.BackgroundTransparency = 0.35
    cardStatus.BorderSizePixel = 0
    corner(cardStatus, 6)
    stroke(cardStatus, C.fieldRim, 1)

    local padCard = Instance.new("UIPadding", cardStatus)
    padCard.PaddingLeft = UDim.new(0, 10)
    padCard.PaddingRight = UDim.new(0, 10)
    padCard.PaddingTop = UDim.new(0, 8)
    padCard.PaddingBottom = UDim.new(0, 8)

    local lCard = Instance.new("UIListLayout", cardStatus)
    lCard.SortOrder = Enum.SortOrder.LayoutOrder
    lCard.Padding = UDim.new(0, 4)

    r.lblHost = makeLabel(cardStatus, "`oTitik Bandar: Belum di-set (Gunakan tombol Set Host atau /host)``", 15, UDim2.new())
    r.lblPositions = makeLabel(cardStatus, "`wMeja 1-4: `` `oP1:(-)  P2:(-)  P3:(-)  P4:(-)``", 15, UDim2.new())
    r.lblTax = makeLabel(cardStatus, string.format("`ePotongan Tax Bandar: %d%%``", Proxy.casino.taxRate), 15, UDim2.new())
    r.lblLastGame = makeLabel(cardStatus, "`oRonde Terakhir: Belum ada permainan``", 15, UDim2.new())

    -- Row Setup Posisi & Reset
    local rowSetup = Instance.new("Frame", secCasino.body)
    rowSetup.Size = UDim2.new(1, 0, 0, 36)
    rowSetup.BackgroundTransparency = 1
    rowSetup.BorderSizePixel = 0

    local lSetup = Instance.new("UIListLayout", rowSetup)
    lSetup.FillDirection = Enum.FillDirection.Horizontal
    lSetup.Padding = UDim.new(0, 8)

    makeButton(rowSetup, "Set Host (/host)", 15, C.button, 6, 34, function()
        local px, py = getPlayerTilePos()
        if px and py then
            Proxy.casino.hostPos = { x = px, y = py }
            Proxy.saveConfig()
            Proxy.notify(string.format("`2[Casino] Titik Bandar tersimpan di (X: %d, Y: %d)``", px + 1, py + 1))
            pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
            Proxy.updateUI()
        else
            Proxy.notify("`4[Casino] Gagal mendeteksi koordinat karakter!``")
        end
    end, 190)

    makeButton(rowSetup, "Cek Info (/cinfo)", 15, C.button, 6, 34, function()
        local count = 0
        for i = 1, 4 do
            local p = Proxy.casino.positions[i]
            if p then
                count = count + 1
                Proxy.showPosMarker(i, p.x, p.y)
            end
        end
        if count > 0 then
            Proxy.notify(string.format("`2[Casino] Menampilkan visual marker untuk %d meja selama 3 detik.``", count))
        else
            Proxy.notify("`4[Casino] Belum ada posisi meja yang di-set!``")
        end
    end, 160)

    makeButton(rowSetup, "Reset Meja (/creset)", 15, C.red, 6, 34, function()
        Proxy.casino.positions = {}
        Proxy.casino.lastGame = nil
        Proxy.dismissCasinoBanner()
        for i = 1, 4 do
            if Proxy.activePosMarkers[i] and Proxy.activePosMarkers[i].Parent then
                pcall(function() Proxy.activePosMarkers[i]:Destroy() end)
                Proxy.activePosMarkers[i] = nil
            end
        end
        Proxy.saveConfig()
        Proxy.notify("`2[Casino] Semua posisi taruhan & data game berhasil di-reset!``")
        Proxy.updateUI()
    end, 170)

    -- Row 4 Buttons for Pos 1-4
    local rowPosBtns = Instance.new("Frame", secCasino.body)
    rowPosBtns.Size = UDim2.new(1, 0, 0, 36)
    rowPosBtns.BackgroundTransparency = 1
    rowPosBtns.BorderSizePixel = 0

    local lPos = Instance.new("UIListLayout", rowPosBtns)
    lPos.FillDirection = Enum.FillDirection.Horizontal
    lPos.Padding = UDim.new(0, 8)

    local function setupPosButton(idx)
        makeButton(rowPosBtns, string.format("Pos %d (/pos%d)", idx, idx), 14, C.button, 6, 34, function()
            local px, py = getPlayerTilePos()
            if px and py then
                local curFacing = 1
                if Proxy.onDropFn and debug and debug.getupvalue then
                    local f = debug.getupvalue(Proxy.onDropFn, 2)
                    if f == -1 or f == 1 then curFacing = f end
                end
                Proxy.casino.positions[idx] = { x = px, y = py, facing = curFacing }
                Proxy.saveConfig()
                Proxy.showPosMarker(idx, px, py)
                local dirText = (curFacing == 1) and "Kanan" or "Kiri"
                Proxy.notify(string.format("`2[Casino] Pos %d tersimpan di (X: %d, Y: %d) [Hadap: %s]``", idx, px + 1, py + 1, dirText))
                pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
                Proxy.updateUI()
            else
                Proxy.notify("`4[Casino] Gagal mendeteksi koordinat karakter!``")
            end
        end, 145)
    end

    for i = 1, 4 do
        setupPosButton(i)
    end

    -- Setting Tax Bandar
    local rowTax = Instance.new("Frame", secCasino.body)
    rowTax.Size = UDim2.new(1, 0, 0, 36)
    rowTax.BackgroundTransparency = 1
    rowTax.BorderSizePixel = 0

    local lTax = Instance.new("UIListLayout", rowTax)
    lTax.FillDirection = Enum.FillDirection.Horizontal
    lTax.VerticalAlignment = Enum.VerticalAlignment.Center
    lTax.Padding = UDim.new(0, 8)

    makeLabel(rowTax, "`eTax (%): ``", 16, UDim2.new())

    local taxPresets = { 5, 10, 15, 20 }
    for _, tVal in ipairs(taxPresets) do
        makeButton(rowTax, tVal .. "%", 14, C.button, 6, 30, function()
            Proxy.casino.taxRate = tVal
            Proxy.saveConfig()
            Proxy.notify(string.format("`2[Casino] Tax diset ke: %d%%``", tVal))
            Proxy.updateUI()
        end, 55)
    end

    -- Big Action: VALIDASI & COLLECT TARUHAN (/tp)
    makeButton(
        secCasino.body,
        "VALIDASI & COLLECT TARUHAN MEJA (/tp)",
        17,
        C.green,
        8,
        40,
        function()
            task.spawn(Proxy.runCasinoCollect)
        end
    )

    -- Antar Hadiah Pemenang
    makeLabel(secCasino.body, "`3Antar Hadiah Pemenang (/win1 - /win4):``", 16, UDim2.new())

    local rowWin = Instance.new("Frame", secCasino.body)
    rowWin.Size = UDim2.new(1, 0, 0, 36)
    rowWin.BackgroundTransparency = 1
    rowWin.BorderSizePixel = 0

    local lWin = Instance.new("UIListLayout", rowWin)
    lWin.FillDirection = Enum.FillDirection.Horizontal
    lWin.Padding = UDim.new(0, 8)

    for i = 1, 4 do
        makeButton(rowWin, string.format("Win %d (/win%d)", i, i), 14, C.button, 6, 34, function()
            task.spawn(function()
                Proxy.runCasinoPayout(i)
            end)
        end, 145)
    end

    -- Roulette Wheel: Instant Fast Spin & Anti-Scam Verification
    local cardRoulette = Instance.new("Frame", secCasino.body)
    cardRoulette.Size = UDim2.new(1, 0, 0, 72)
    cardRoulette.BackgroundColor3 = C.dark
    cardRoulette.BackgroundTransparency = 0.35
    cardRoulette.BorderSizePixel = 0
    corner(cardRoulette, 6)
    stroke(cardRoulette, C.fieldRim, 1)

    local padRoulette = Instance.new("UIPadding", cardRoulette)
    padRoulette.PaddingLeft = UDim.new(0, 10)
    padRoulette.PaddingRight = UDim.new(0, 10)
    padRoulette.PaddingTop = UDim.new(0, 8)
    padRoulette.PaddingBottom = UDim.new(0, 8)

    local lRoulette = Instance.new("UIListLayout", cardRoulette)
    lRoulette.SortOrder = Enum.SortOrder.LayoutOrder
    lRoulette.Padding = UDim.new(0, 6)

    makeLabel(cardRoulette, "`bFitur Roulette Wheel & Anti-Scam:``", 15, UDim2.new())

    local rowRoulToggles = Instance.new("Frame", cardRoulette)
    rowRoulToggles.Size = UDim2.new(1, 0, 0, 32)
    rowRoulToggles.BackgroundTransparency = 1
    rowRoulToggles.BorderSizePixel = 0

    local lRoulToggles = Instance.new("UIListLayout", rowRoulToggles)
    lRoulToggles.FillDirection = Enum.FillDirection.Horizontal
    lRoulToggles.Padding = UDim.new(0, 12)

    local btnInstantFrame, _, btnInstant, btnInstantLbl
    local btnVerifyFrame, _, btnVerify, btnVerifyLbl

    btnInstantFrame, _, btnInstant, btnInstantLbl = makeButton(
        rowRoulToggles,
        Proxy.roulette.instant and "Instant Spin: ON" or "Instant Spin: OFF",
        14,
        Proxy.roulette.instant and C.green or C.button,
        6,
        32,
        function()
            Proxy.roulette.instant = not Proxy.roulette.instant
            if Proxy.applyInstantRoulette then pcall(Proxy.applyInstantRoulette, Proxy.roulette.instant) end
            if Proxy.roulette.instant then
                btnInstant.BackgroundColor3 = C.green
                btnInstantLbl:set("Instant Spin: ON")
                Proxy.notify("`2[Roulette] Instant Spin ON! (Animasi 0s)``")
            else
                btnInstant.BackgroundColor3 = C.button
                btnInstantLbl:set("Instant Spin: OFF")
                Proxy.notify("`4[Roulette] Instant Spin OFF (Normal).``")
            end
            pcall(Proxy.saveConfig)
        end,
        185
    )

    btnVerifyFrame, _, btnVerify, btnVerifyLbl = makeButton(
        rowRoulToggles,
        Proxy.roulette.verify and "Anti-Scam REAL/FAKE: ON" or "Anti-Scam REAL/FAKE: OFF",
        14,
        Proxy.roulette.verify and C.green or C.button,
        6,
        32,
        function()
            Proxy.roulette.verify = not Proxy.roulette.verify
            if Proxy.roulette.verify then
                btnVerify.BackgroundColor3 = C.green
                btnVerifyLbl:set("Anti-Scam REAL/FAKE: ON")
                Proxy.notify("`2[Anti-Scam] Verifikasi Roll REAL/FAKE ON!``")
            else
                btnVerify.BackgroundColor3 = C.button
                btnVerifyLbl:set("Anti-Scam REAL/FAKE: OFF")
                Proxy.notify("`4[Anti-Scam] Verifikasi Roll OFF.``")
            end
            pcall(Proxy.saveConfig)
        end,
        210
    )

    r.btnInstant = btnInstant
    r.btnInstantLbl = btnInstantLbl
    r.btnVerify = btnVerify
    r.btnVerifyLbl = btnVerifyLbl

    -- Card: Live Roulette Wheel Logs (Histori Spin Real vs Fake)
    local cardRoulLog = Instance.new("Frame", secCasino.body)
    cardRoulLog.Size = UDim2.new(1, 0, 0, 195)
    cardRoulLog.BackgroundColor3 = C.dark
    cardRoulLog.BackgroundTransparency = 0.35
    cardRoulLog.BorderSizePixel = 0
    corner(cardRoulLog, 6)
    stroke(cardRoulLog, C.fieldRim, 1)

    local padRoulLog = Instance.new("UIPadding", cardRoulLog)
    padRoulLog.PaddingLeft = UDim.new(0, 10)
    padRoulLog.PaddingRight = UDim.new(0, 10)
    padRoulLog.PaddingTop = UDim.new(0, 8)
    padRoulLog.PaddingBottom = UDim.new(0, 8)

    local lRoulLog = Instance.new("UIListLayout", cardRoulLog)
    lRoulLog.SortOrder = Enum.SortOrder.LayoutOrder
    lRoulLog.Padding = UDim.new(0, 6)

    local rowRoulHeader = Instance.new("Frame", cardRoulLog)
    rowRoulHeader.Size = UDim2.new(1, 0, 0, 28)
    rowRoulHeader.BackgroundTransparency = 1
    rowRoulHeader.BorderSizePixel = 0

    local lRoulH = Instance.new("UIListLayout", rowRoulHeader)
    lRoulH.FillDirection = Enum.FillDirection.Horizontal
    lRoulH.VerticalAlignment = Enum.VerticalAlignment.Center
    lRoulH.Padding = UDim.new(0, 8)

    local lblRoulStats = makeLabel(rowRoulHeader, "`bHistori Spin Roulette:`` `oTotal: 0 | `2Real: 0`` | `4Fake: 0``", 14, UDim2.new())
    lblRoulStats.LayoutOrder = 1

    local fClearRoul = makeButton(rowRoulHeader, "Bersihkan", 12, C.button, 4, 26, function()
        Proxy.rouletteLogs = {}
        if Proxy.updateRouletteLogUI then Proxy.updateRouletteLogUI() end
        Proxy.notify("`2[Roulette] Riwayat spin berhasil dibersihkan!``")
    end, 85)
    fClearRoul.LayoutOrder = 2

    local fCopyRoul = makeButton(rowRoulHeader, "Salin Log", 12, Color3.fromRGB(88, 101, 242), 4, 26, function()
        local lines = {}
        for _, l in ipairs(Proxy.rouletteLogs or {}) do
            local status = l.isReal and "[REAL]" or "[FAKE]"
            table.insert(lines, string.format("[%s] %s %s -> #%d %s", l.timeStr, status, l.player, l.number, (l.x and l.y) and string.format("(%d, %d)", l.x, l.y) or ""))
        end
        if #lines == 0 then
            Proxy.notify("`4[Roulette] Tidak ada data log spin untuk disalin!``")
            return
        end
        local fullText = table.concat(lines, "\n")
        pcall(function()
            if setclipboard then setclipboard(fullText) end
        end)
        Proxy.notify(string.format("`2[Roulette] %d log spin tersalin ke clipboard!``", #lines))
    end, 85)
    fCopyRoul.LayoutOrder = 3

    local roulScroll = Instance.new("ScrollingFrame", cardRoulLog)
    roulScroll.Size = UDim2.new(1, 0, 0, 140)
    roulScroll.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
    roulScroll.BackgroundTransparency = 0.5
    roulScroll.BorderSizePixel = 0
    roulScroll.ScrollBarThickness = 5
    roulScroll.ScrollBarImageColor3 = C.rim
    roulScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    corner(roulScroll, 4)
    stroke(roulScroll, C.rimInner, 1)

    local lRoulItems = Instance.new("UIListLayout", roulScroll)
    lRoulItems.SortOrder = Enum.SortOrder.LayoutOrder
    lRoulItems.Padding = UDim.new(0, 2)

    Proxy.updateRouletteLogUI = function()
        if not roulScroll or not roulScroll.Parent then return end

        for _, ch in ipairs(roulScroll:GetChildren()) do
            if ch:IsA("Frame") then ch:Destroy() end
        end

        local logs = Proxy.rouletteLogs or {}
        local realCount = 0
        local fakeCount = 0
        for _, l in ipairs(logs) do
            if l.isReal then realCount = realCount + 1 else fakeCount = fakeCount + 1 end
        end

        lblRoulStats:set(string.format("`bHistori Spin Roulette:`` `oTotal: %d | `2Real: %d`` | `4Fake: %d``", #logs, realCount, fakeCount))

        local itemHeight = 22
        for i = #logs, 1, -1 do
            local l = logs[i]
            local fRow = Instance.new("Frame", roulScroll)
            fRow.Size = UDim2.new(1, -6, 0, itemHeight)
            fRow.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(26, 32, 40) or Color3.fromRGB(20, 25, 32)
            fRow.BackgroundTransparency = 0.2
            fRow.BorderSizePixel = 0
            corner(fRow, 4)

            local padRow = Instance.new("UIPadding", fRow)
            padRow.PaddingLeft = UDim.new(0, 8)
            padRow.PaddingRight = UDim.new(0, 8)

            local lRowLayout = Instance.new("UIListLayout", fRow)
            lRowLayout.FillDirection = Enum.FillDirection.Horizontal
            lRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

            local tagCol = l.isReal and "`2[REAL]``" or "`4[FAKE]``"
            local numCol = (l.number == 0) and "`2" or ((l.number <= 18) and "`w" or "`4")
            local tileStr = (l.x and l.y) and string.format("`o(%d, %d)``", l.x, l.y) or ""
            local lineText = string.format("`w[%s]`` %s `w%-12s`` -> %s`*%d*`` %s", l.timeStr, tagCol, l.player, numCol, l.number, tileStr)

            makeLabel(fRow, lineText, 13, UDim2.new())
        end

        roulScroll.CanvasSize = UDim2.new(0, 0, 0, #logs * (itemHeight + 2) + 6)
    end


    -- Section 3: Quick Drop Locks (Default CLOSED)
    local secDrop = createSection(page, "Quick Drop Locks (/dw, /dd, /dbgl)", false, 3)

    makeLabel(secDrop.body, "`oPilih jenis lock dan jumlah yang ingin di-drop ke lantai:``", 16, UDim2.new())

    local rowDropAmt = Instance.new("Frame", secDrop.body)
    rowDropAmt.Size = UDim2.new(1, 0, 0, 36)
    rowDropAmt.BackgroundTransparency = 1
    rowDropAmt.BorderSizePixel = 0

    local lDropAmt = Instance.new("UIListLayout", rowDropAmt)
    lDropAmt.FillDirection = Enum.FillDirection.Horizontal
    lDropAmt.VerticalAlignment = Enum.VerticalAlignment.Center
    lDropAmt.Padding = UDim.new(0, 8)

    makeLabel(rowDropAmt, "`wJumlah Drop: ``", 16, UDim2.new())

    local inpDropAmount = Instance.new("TextBox", rowDropAmt)
    inpDropAmount.Size = UDim2.fromOffset(70, 30)
    inpDropAmount.BackgroundColor3 = C.field
    inpDropAmount.BorderSizePixel = 0
    inpDropAmount.Font = Enum.Font.GothamBold
    inpDropAmount.TextSize = 14
    inpDropAmount.TextColor3 = C.text
    inpDropAmount.Text = "1"
    inpDropAmount.ClearTextOnFocus = false
    corner(inpDropAmount, 6)
    stroke(inpDropAmount, C.fieldRim, 1)

    local function getDropCount()
        local t = inpDropAmount.Text:lower():match("^%s*(.-)%s*$")
        if t == "all" then return "all" end
        local n = tonumber(t)
        return (n and n > 0) and n or 1
    end

    local amtPresets = { "1", "5", "10", "all" }
    for _, ap in ipairs(amtPresets) do
        makeButton(rowDropAmt, ap:upper(), 14, C.button, 6, 30, function()
            inpDropAmount.Text = ap
        end, 48)
    end

    local function makeLockRow(locksList)
        local row = Instance.new("Frame", secDrop.body)
        row.Size = UDim2.new(1, 0, 0, 38)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0

        local lRow = Instance.new("UIListLayout", row)
        lRow.FillDirection = Enum.FillDirection.Horizontal
        lRow.Padding = UDim.new(0, 10)

        for _, lk in ipairs(locksList) do
            local lockInfo = Proxy.LOCKS[lk]
            if lockInfo then
                makeButton(row, lockInfo.name, 15, C.button, 6, 36, function()
                    local cnt = getDropCount()
                    local owned = Proxy.getOwnedCount(lockInfo.id)
                    if owned <= 0 then
                        Proxy.notify("`4[Drop] Kamu tidak punya " .. lockInfo.name .. " di tas!``")
                        return
                    end
                    local amtToDrop = (cnt == "all") and owned or math.min(owned, cnt)
                    if Proxy.onDropFn then
                        local ok, err = pcall(function() Proxy.onDropFn(lockInfo.id, amtToDrop) end)
                        if ok then
                            Proxy.notify(string.format("`2[Drop] Berhasil drop %d %s!``", amtToDrop, lockInfo.name))
                            pcall(function() if Sfx and Sfx.play then Sfx.play("object_spawn2") end end)
                            task.delay(0.2, Proxy.updateUI)
                        else
                            Proxy.notify("`4[Drop] Gagal: " .. tostring(err) .. "``")
                        end
                    end
                end, 195)
            end
        end
    end

    makeLockRow({ "dw", "dd", "dbgl" })
    makeLockRow({ "ds", "db", "dh" })

    local rowDaw = Instance.new("Frame", secDrop.body)
    rowDaw.Size = UDim2.new(1, 0, 0, 36)
    rowDaw.BackgroundTransparency = 1
    rowDaw.BorderSizePixel = 0

    makeButton(rowDaw, "DROP ALL LOCKS IN BP (/daw)", 15, Color3.fromRGB(200, 60, 60), 6, 36, function()
        if chatTableRef and chatTableRef.onCommand then
            chatTableRef.onCommand("/daw")
        end
    end, 400)


    -- Section 4: Streamer Mode & Utilities (Default CLOSED)
    local secStreamer = createSection(page, "Streamer Mode & Utility", false, 4)

    makeLabel(secStreamer.body, "`oSamarkan nickname di atas kepala untuk live streaming / video (/nick <nama>):``", 16, UDim2.new())

    local rowNick = Instance.new("Frame", secStreamer.body)
    rowNick.Size = UDim2.new(1, 0, 0, 36)
    rowNick.BackgroundTransparency = 1
    rowNick.BorderSizePixel = 0

    local lNick = Instance.new("UIListLayout", rowNick)
    lNick.FillDirection = Enum.FillDirection.Horizontal
    lNick.Padding = UDim.new(0, 8)

    local inpNick = Instance.new("TextBox", rowNick)
    inpNick.Size = UDim2.fromOffset(200, 32)
    inpNick.BackgroundColor3 = C.field
    inpNick.BorderSizePixel = 0
    inpNick.Font = Enum.Font.Gotham
    inpNick.TextSize = 13
    inpNick.TextColor3 = C.text
    inpNick.PlaceholderText = "Ketik nickname palsu..."
    inpNick.PlaceholderColor3 = C.muted
    inpNick.ClearTextOnFocus = false
    corner(inpNick, 6)
    stroke(inpNick, C.fieldRim, 1)

    makeButton(rowNick, "Set Fake Nick (/nick)", 14, C.button, 6, 32, function()
        local txt = inpNick.Text:match("^%s*(.-)%s*$")
        if txt and txt ~= "" then
            Players.LocalPlayer:SetAttribute("Nick", txt)
            Proxy.saveConfig()
            Proxy.notify("`2[Nick] Streamer mode aktif! Nama disamarkan menjadi: " .. txt .. "``")
        else
            Players.LocalPlayer:SetAttribute("Nick", nil)
            Proxy.saveConfig()
            Proxy.notify("`2[Nick] Nickname di-reset ke nama asli (" .. Players.LocalPlayer.Name .. ")!``")
        end
        Proxy.updateUI()
    end, 175)

    makeButton(rowNick, "Reset Asli (/unnick)", 14, C.button, 6, 32, function()
        Players.LocalPlayer:SetAttribute("Nick", nil)
        inpNick.Text = ""
        Proxy.saveConfig()
        Proxy.notify("`2[Nick] Nickname di-reset ke nama asli (" .. Players.LocalPlayer.Name .. ")!``")
        Proxy.updateUI()
    end, 160)

    r.lblNickStatus = makeLabel(secStreamer.body, "`oNickname Asli: " .. Players.LocalPlayer.Name .. "``", 15, UDim2.new())

    -- Row 1: Floating Gems Re-scan button
    local rowGems = Instance.new("Frame", secStreamer.body)
    rowGems.Size = UDim2.new(1, 0, 0, 36)
    rowGems.BackgroundTransparency = 1
    rowGems.BorderSizePixel = 0

    local lGems = Instance.new("UIListLayout", rowGems)
    lGems.FillDirection = Enum.FillDirection.Horizontal
    lGems.Padding = UDim.new(0, 8)

    makeButton(rowGems, "Tampilkan Floating Gems (/gems)", 15, C.cyan, 8, 34, function()
        local drops = gameDropsTable or findGameDropsTable()
        local gemTiles = {}
        local totalGemsFound = 0
        if drops then
            for _, drop in ipairs(drops) do
                if type(drop) == "table" and drop.id == 112 and type(drop.x) == "number" and type(drop.y) == "number" then
                    local tx = math.floor(drop.x)
                    local ty = math.floor(drop.y)
                    local key = tx .. "," .. ty
                    if not gemTiles[key] then
                        gemTiles[key] = { tx = tx, ty = ty, total = 0 }
                    end
                    local count = drop.n or 0
                    gemTiles[key].total = gemTiles[key].total + count
                    totalGemsFound = totalGemsFound + count
                end
            end
        end

        local pileCount = 0
        for _, tileData in pairs(gemTiles) do
            if tileData.total > 0 then
                pileCount = pileCount + 1
                Proxy.spawnFloatingDropText(tileData.tx, tileData.ty, 112, tileData.total)
            end
        end

        if pileCount > 0 then
            Proxy.notify(string.format("`2[Gems] Menampilkan ulang floating text untuk %d Gems (%d tumpukan).``", totalGemsFound, pileCount))
        else
            Proxy.notify("`4[Gems] Tidak ada drop gems yang tergeletak di tanah saat ini!``")
        end
    end, 270)

    local btnPGFrame, _, btnPG, btnPGLabel = makeButton(
        rowGems,
        Proxy.punchGemsCheck and "Punch to Check Gems: ON (/pgems)" or "Punch to Check Gems: OFF (/pgems)",
        14,
        Proxy.punchGemsCheck and C.green or C.button,
        6,
        34,
        function()
            Proxy.punchGemsCheck = not Proxy.punchGemsCheck
            pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
            Proxy.notify(Proxy.punchGemsCheck and "`2[Proxy] Punch to Check Gems: ON``" or "`4[Proxy] Punch to Check Gems: OFF``")
            Proxy.saveConfig()
            Proxy.updateUI()
        end,
        270
    )
    r.btnPunchGems = btnPG
    r.lblPunchGems = btnPGLabel

    -- Row 2: Config Save & Load
    local rowCfg = Instance.new("Frame", secStreamer.body)
    rowCfg.Size = UDim2.new(1, 0, 0, 36)
    rowCfg.BackgroundTransparency = 1
    rowCfg.BorderSizePixel = 0

    local lCfg = Instance.new("UIListLayout", rowCfg)
    lCfg.FillDirection = Enum.FillDirection.Horizontal
    lCfg.Padding = UDim.new(0, 8)

    makeButton(rowCfg, "Simpan Config (/savecfg)", 15, C.button, 6, 34, function()
        Proxy.saveConfig()
        Proxy.notify("`2[Config] Seluruh konfigurasi fitur & state berhasil disimpan!``")
    end, 200)

    makeButton(rowCfg, "Muat Config (/loadcfg)", 15, C.button, 6, 34, function()
        Proxy.loadConfig()
        Proxy.notify("`2[Config] Seluruh konfigurasi fitur & state berhasil dimuat!``")
    end, 200)

    -- Row 3: Banner Promo Button
    local rowBannerBtn = Instance.new("Frame", secStreamer.body)
    rowBannerBtn.Size = UDim2.new(1, 0, 0, 36)
    rowBannerBtn.BackgroundTransparency = 1
    rowBannerBtn.BorderSizePixel = 0

    makeButton(rowBannerBtn, "Lihat Banner Iklan Team (/banner)", 15, Color3.fromRGB(88, 101, 242), 6, 36, function()
        if showTeamSplashDialog then showTeamSplashDialog() end
    end, 320)


    -- Section 5: Live Drop & Collect Logger with Player Search
    local secLogger = createSection(page, "Live Drop & Collect Logger (History Transaksi)", true, 5)

    -- Row 1: Search Player Bar
    local rowSearch = Instance.new("Frame", secLogger.body)
    rowSearch.Size = UDim2.new(1, 0, 0, 36)
    rowSearch.BackgroundTransparency = 1
    rowSearch.BorderSizePixel = 0

    local lSearch = Instance.new("UIListLayout", rowSearch)
    lSearch.FillDirection = Enum.FillDirection.Horizontal
    lSearch.VerticalAlignment = Enum.VerticalAlignment.Center
    lSearch.SortOrder = Enum.SortOrder.LayoutOrder
    lSearch.Padding = UDim.new(0, 8)

    local lblSearch = makeLabel(rowSearch, "`wCari Player: ``", 15, UDim2.new())
    lblSearch.LayoutOrder = 1

    local inpSearch = Instance.new("TextBox", rowSearch)
    inpSearch.LayoutOrder = 2
    inpSearch.Size = UDim2.fromOffset(360, 32)
    inpSearch.BackgroundColor3 = C.field
    inpSearch.BorderSizePixel = 0
    inpSearch.Font = Enum.Font.Gotham
    inpSearch.TextSize = 14
    inpSearch.TextColor3 = C.text
    inpSearch.PlaceholderColor3 = C.muted
    inpSearch.PlaceholderText = "Ketik nama player untuk cek history..."
    inpSearch.Text = Proxy.logger.search or ""
    corner(inpSearch, 6)
    stroke(inpSearch, C.rimInner, 1.5)

    local fReset = makeButton(rowSearch, "Reset", 14, C.red, 6, 32, function()
        inpSearch.Text = ""
        Proxy.logger.search = ""
        if Proxy.updateLoggerUI then Proxy.updateLoggerUI() end
    end, 75)
    fReset.LayoutOrder = 3

    -- Row 2: Mode Badge & Clear Button (Only Locks)
    local rowFilter = Instance.new("Frame", secLogger.body)
    rowFilter.Size = UDim2.new(1, 0, 0, 34)
    rowFilter.BackgroundTransparency = 1
    rowFilter.BorderSizePixel = 0

    local lFilter = Instance.new("UIListLayout", rowFilter)
    lFilter.FillDirection = Enum.FillDirection.Horizontal
    lFilter.SortOrder = Enum.SortOrder.LayoutOrder
    lFilter.VerticalAlignment = Enum.VerticalAlignment.Center
    lFilter.Padding = UDim.new(0, 10)

    local lblMode = makeLabel(rowFilter, "`9Filter:`` `2Khusus Locks (WL, DL, BGL, SL, BL, HL)``", 14, UDim2.new())
    lblMode.LayoutOrder = 1

    local fClear = makeButton(rowFilter, "Bersihkan Log", 13, C.button, 6, 30, function()
        Proxy.logger.logs = {}
        if Proxy.updateLoggerUI then Proxy.updateLoggerUI() end
        Proxy.notify("`2[Logger] Riwayat transaksi lock berhasil dibersihkan!``")
    end, 120)
    fClear.LayoutOrder = 2

    -- Row 3: Player Summary Badge
    local lblSummary = makeLabel(secLogger.body, "`oTotal Histori: 0 transaksi Lock``", 15, UDim2.new())

    -- Row 4: Log Scrolling Container
    local logScroll = Instance.new("ScrollingFrame", secLogger.body)
    logScroll.Size = UDim2.new(1, 0, 0, 210)
    logScroll.BackgroundColor3 = C.dark
    logScroll.BackgroundTransparency = 0.5
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 6
    logScroll.ScrollBarImageColor3 = C.rim
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    corner(logScroll, 6)
    stroke(logScroll, C.rimInner, 1.5)

    local logLayout = Instance.new("UIListLayout", logScroll)
    logLayout.SortOrder = Enum.SortOrder.LayoutOrder
    logLayout.Padding = UDim.new(0, 2)

    -- Row 5: Action Copy Log to Clipboard
    local rowCopy = Instance.new("Frame", secLogger.body)
    rowCopy.Size = UDim2.new(1, 0, 0, 36)
    rowCopy.BackgroundTransparency = 1
    rowCopy.BorderSizePixel = 0

    local lCopy = Instance.new("UIListLayout", rowCopy)
    lCopy.FillDirection = Enum.FillDirection.Horizontal
    lCopy.Padding = UDim.new(0, 8)

    makeButton(rowCopy, "Salin Log ke Clipboard", 14, Color3.fromRGB(88, 101, 242), 6, 34, function()
        local lines = {}
        for _, l in ipairs(Proxy.logger.logs) do
            table.insert(lines, string.format("[%s] [%s] %s -> %d %s di (%d, %d)", l.time, l.type, l.player, l.count, l.itemName, l.x, l.y))
        end
        if #lines == 0 then
            Proxy.notify("`4[Logger] Tidak ada data log untuk disalin!``")
            return
        end
        local fullText = table.concat(lines, "\n")
        pcall(function()
            if setclipboard then
                setclipboard(fullText)
            end
        end)
        Proxy.notify(string.format("`2[Logger] %d catatan transaksi tersalin ke clipboard!``", #lines))
    end, 210)

    makeButton(rowCopy, "Refresh Tampilan", 14, C.button, 6, 34, function()
        if Proxy.updateLoggerUI then Proxy.updateLoggerUI() end
    end, 150)

    Proxy.setLoggerSearch = function(str)
        inpSearch.Text = str or ""
        Proxy.logger.search = str or ""
        if Proxy.updateLoggerUI then Proxy.updateLoggerUI() end
    end

    Proxy.updateLoggerUI = function()
        if not logScroll or not logScroll.Parent then return end

        for _, ch in ipairs(logScroll:GetChildren()) do
            if ch:IsA("Frame") then
                ch:Destroy()
            end
        end

        local filterText = string.lower(string.gsub(inpSearch.Text or "", "^%s*(.-)%s*$", "%1"))
        local mode = Proxy.logger.filter or "all"

        local filtered = {}
        local totalDropCount = 0
        local totalTakeCount = 0

        for _, entry in ipairs(Proxy.logger.logs) do
            local matchFilter = true
            if mode == "locks" and not entry.isLock then matchFilter = false end
            if mode == "gems" and not entry.isGem then matchFilter = false end

            local matchSearch = true
            if filterText ~= "" then
                local pLower = string.lower(entry.player or "")
                if not string.find(pLower, filterText, 1, true) then
                    matchSearch = false
                end
            end

            if matchFilter and matchSearch then
                table.insert(filtered, entry)
                if entry.type == "DROP" then
                    totalDropCount = totalDropCount + (entry.count or 0)
                elseif entry.type == "TAKE" then
                    totalTakeCount = totalTakeCount + (entry.count or 0)
                end
            end
        end

        if filterText ~= "" then
            lblSummary:set(string.format("`wPlayer: `` `2%s``  |  `9Drop:`` `w%d Locks``  |  `9Take:`` `w%d Locks``  |  `o(%d log)``", filterText, totalDropCount, totalTakeCount, #filtered))
        else
            lblSummary:set(string.format("`oTotal Histori: %d transaksi Lock``", #Proxy.logger.logs))
        end

        local yOffset = 0
        for i, entry in ipairs(filtered) do
            local row = Instance.new("Frame", logScroll)
            row.Size = UDim2.new(1, -6, 0, 26)
            row.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(24, 28, 38) or Color3.fromRGB(18, 22, 30)
            row.BackgroundTransparency = 0.3
            row.BorderSizePixel = 0
            corner(row, 4)

            local tagCol = (entry.type == "DROP") and "`2[DROP]``" or "`e[TAKE]``"
            local textStr = string.format("`o[%s]`` %s `w%s`` `9âžœ`` `w%d %s`` `o(%d, %d)``", entry.time, tagCol, entry.player, entry.count, entry.itemName, entry.x, entry.y)
            makeLabel(row, textStr, 14, UDim2.fromOffset(8, 5))

            yOffset = yOffset + 28
        end

        if #filtered == 0 then
            local emptyRow = Instance.new("Frame", logScroll)
            emptyRow.Size = UDim2.new(1, -6, 0, 26)
            emptyRow.BackgroundTransparency = 1
            local emptyMsg = (filterText ~= "") and ("`oTidak ada transaksi untuk player '" .. filterText .. "'``") or "`oBelum ada transaksi drop / collect yang tercatat.``"
            makeLabel(emptyRow, emptyMsg, 14, UDim2.fromOffset(10, 5))
            yOffset = 30
        end

        logScroll.CanvasSize = UDim2.fromOffset(0, yOffset + 8)
    end

    inpSearch:GetPropertyChangedSignal("Text"):Connect(function()
        Proxy.logger.search = inpSearch.Text
        Proxy.updateLoggerUI()
    end)

    Proxy.updateLoggerUI()

    -- Section 6: Commands Cheat-Sheet (Default CLOSED)
    local secCmd = createSection(page, "Daftar Perintah Chat Proxy (Cheat-Sheet)", false, 6)

    local cmdList = {
        { cmd = "/proxy", desc = "Buka tab PROXY di GUI Syshub" },
        { cmd = "/tp [x y / nama]", desc = "Casino sweep atau meluncur ke koordinat / player" },
        { cmd = "/win1 - /win4", desc = "Antar hadiah kemenangan bersih ke meja 1-4" },
        { cmd = "/pos1 - /pos4", desc = "Kunci titik koordinat & arah hadap meja 1-4" },
        { cmd = "/host", desc = "Kunci titik berdiri bandar saat ini" },
        { cmd = "/tax <persen>", desc = "Ubah potongan tax bandar (default: 10%)" },
        { cmd = "/cinfo", desc = "Cek info status meja & tampilkan box marker" },
        { cmd = "/creset", desc = "Reset semua data meja & ronde taruhan" },
        { cmd = "/rw", desc = "Re-warp ke nama world sebelumnya" },
        { cmd = "/res", desc = "Normal respawn tanpa delay / lag" },
        { cmd = "/fpk", desc = "Toggle Fast Pull & Kick (LMB Pull, RMB Kick)" },
        { cmd = "/pgems", desc = "Toggle punch manual tile untuk cek floating gems" },
        { cmd = "/gems", desc = "Tampilkan ulang hitungan floating gems di tanah" },
        { cmd = "/daw",           desc = "Drop SEMUA lock yang ada di tas sekaligus (BGL, DL, WL, HL, BL, SL)" },
        { cmd = "/dw, /dd, /dbgl", desc = "Drop World Lock, Diamond Lock, BGL" },
        { cmd = "/ds, /db, /dh", desc = "Drop Small Lock, Big Lock, Huge Lock" },
        { cmd = "/nick <nama>", desc = "Ubah nickname palsu di atas kepala" },
        { cmd = "/unnick", desc = "Kembalikan nickname ke nama asli Roblox" },
        { cmd = "/banner",        desc = "Buka ulang pop-up banner iklan TEAM SYS Casino" },
        { cmd = "/savecfg, /loadcfg", desc = "Simpan / muat setelan ke sysgt_config.json" },
    }

    for _, cItem in ipairs(cmdList) do
        local row = Instance.new("Frame", secCmd.body)
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundColor3 = C.field
        row.BackgroundTransparency = 0.5
        row.BorderSizePixel = 0
        corner(row, 4)

        local tC = Instance.new("TextLabel", row)
        tC.Size = UDim2.new(0.35, -8, 1, 0)
        tC.Position = UDim2.fromOffset(8, 0)
        tC.BackgroundTransparency = 1
        tC.Text = cItem.cmd
        tC.TextColor3 = C.cyan
        tC.Font = Enum.Font.GothamBold
        tC.TextSize = 12
        tC.TextXAlignment = Enum.TextXAlignment.Left

        local tD = Instance.new("TextLabel", row)
        tD.Size = UDim2.new(0.65, -8, 1, 0)
        tD.Position = UDim2.new(0.35, 0, 0, 0)
        tD.BackgroundTransparency = 1
        tD.Text = cItem.desc
        tD.TextColor3 = C.muted
        tD.Font = Enum.Font.Gotham
        tD.TextSize = 11
        tD.TextXAlignment = Enum.TextXAlignment.Left
    end

    Proxy.updateUI()
end


Setups.player(pages["player"])
Setups.world(pages["world"])
Setups.spam(pages["spam"])
Setups.proxy(pages["proxy"])

-- ═══════════════════════════════════════
--  DRAGGABLE WAYPOINT HUD OVERLAY
-- ═══════════════════════════════════════
WaypointHUD = nil
lblWpInfo = nil
lblWpDist = nil

do
    WaypointHUD = Instance.new("Frame", SG)
    WaypointHUD.Name                   = "WaypointHUD"
    WaypointHUD.Size                   = UDim2.fromOffset(400, 56)
    WaypointHUD.Position               = UDim2.new(0.5, -200, 1, -66)
    WaypointHUD.BackgroundColor3       = C.box
    WaypointHUD.BackgroundTransparency = 0.1
    WaypointHUD.BorderSizePixel        = 0
    WaypointHUD.Active                 = true
    WaypointHUD.Draggable              = true
    WaypointHUD.Visible                = false
    corner(WaypointHUD, 6)
    dialogBorder(WaypointHUD)

    lblWpInfo = makeLabel(WaypointHUD, "[*] Target: (-, -)", 22, UDim2.fromOffset(14, 8))
    lblWpDist = makeLabel(WaypointHUD, "Jarak: -", 18, UDim2.fromOffset(14, 30))

    do
        local btnWpCancelFrame = (makeButton(
            WaypointHUD,
            "X",
            22,
            C.red,
            4,
            38,
            function()
                clearWaypoint()
            end,
            46
        ))
        btnWpCancelFrame.AnchorPoint = Vector2.new(1, 0.5)
        btnWpCancelFrame.Position    = UDim2.new(1, -10, 0.5, 0)
    end

    setWaypoint = function(name, x, y)
        activeWaypoint = {
            name = name,
            x = x,
            y = y
        }
        if WaypointHUD then
            WaypointHUD.Visible = true
        end
        if lblWpStatus and lblWpStatus.set then
            lblWpStatus:set(string.format("`9Melacak: %s di (X: %d, Y: %d)``", name, x, y))
        end
    end

    clearWaypoint = function()
        activeWaypoint = nil
        if WaypointHUD then
            WaypointHUD.Visible = false
        end
        if lblWpStatus and lblWpStatus.set then
            lblWpStatus:set("`oTidak ada waypoint aktif. Klik item di menu GrowScan untuk melacak!``")
        end
    end
end

-- ═══════════════════════════════════════
--  START & STOP PNB LOGIC
-- ═══════════════════════════════════════
stopPNB = function()
    PNB.active = false
    PNB.busy   = false
    if PNB.thread then
        pcall(task.cancel, PNB.thread)
        PNB.thread = nil
    end

    if btnToggle then
        btnToggle.BackgroundColor3 = C.green
    end
    if btnToggleLabel then
        btnToggleLabel:set("START PNB")
    end
    if lblStatus then
        lblStatus:set("`oStatus: Idle``")
    end
end

startPNB = function()
    if ClearWorld and ClearWorld.active and stopClearWorld then
        stopClearWorld()
    end
    if AutoFactory and AutoFactory.active and stopAutoFactory then
        stopAutoFactory()
    end

    local targets = getSortedTargetList()
    if #targets == 0 then
        if lblStatus then
            lblStatus:set("`4[!] Pilih minimal 1 target pada grid 5x5!``")
        end
        return
    end

    PNB.itemId   = (inpItemId and tonumber(inpItemId.Text)) or PNB.targetItemId or PNB.itemId or 2
    PNB.hits     = (inpHits and tonumber(inpHits.Text)) or PNB.hitsPerBlock or PNB.hits or 3
    PNB.hitDelay = math.max(0.05, (inpHitDelay and tonumber(inpHitDelay.Text)) or PNB.hitDelay or 0.18)

    PNB.layer = string.lower(tostring(PNB.layer or "fg"))
    if PNB.layer ~= "fg" and PNB.layer ~= "bg" then
        PNB.layer = "fg"
    end

    if PNB.mode == "PLACE" or PNB.mode == "PNB" then
        local stock = getRealtimeItemCount(PNB.itemId)
        if stock <= 0 then
            if lblStatus then
                lblStatus:set(string.format("`4[!] Item '%s' (#%d) kosong di tas!``", PNB.itemName or "Target", PNB.itemId))
            end
            return
        end
    end

    hookRealtimeInventory()

    PNB.active = true
    if btnToggle then
        btnToggle.BackgroundColor3 = C.red
    end
    if btnToggleLabel then
        btnToggleLabel:set("STOP PNB")
    end
    if lblStatus then
        lblStatus:set(string.format("`2Status: Running (%s - %d Target)``", PNB.mode, #targets))
    end

    PNB.thread = task.spawn(function()
        while PNB.active do
            executeCycle(function(idx, total, tx, ty)
                if PNB.active then
                    lblStatus:set(string.format("`2● Running: [%d/%d] Target (%d, %d) - %s``",
                        idx, total, tx + 1, ty + 1, PNB.mode))
                end
            end)
            task.wait(PNB.loopDelay)
        end
    end)
end

onTogglePNB = function()
    if PNB.active then
        stopPNB()
    else
        startPNB()
    end
end

-- Render loop for diagnostics & Waypoint HUD
local renderConn = nil
renderConn = RunService.RenderStepped:Connect(function()
    if not scriptAlive then return end
    local px, py, rx, ry = getPlayerTilePos()
    local curHp = 5
    pcall(function()
        local gg = PlayerGui:FindFirstChild("GameGui")
        local dbg = gg and gg:FindFirstChild("Debug")
        if dbg and dbg.Text and #dbg.Text > 0 then
            local hpMatch = string.match(dbg.Text, "hp%s+(%d+)")
            if hpMatch then
                curHp = tonumber(hpMatch) or 5
            end
        end
    end)
    local hpText = string.format("%d/5", curHp)
    local w = getNativeWorld()
    local worldName = (w and w.name) or "World"

    if px and py then
        if lblLivePos and lblLivePos.set then
            lblLivePos:set(string.format("`cPos: (%d, %d) [%s]``  |  `4HP: %s``", px + 1, py + 1, worldName, hpText))
        end
    else
        if lblLivePos and lblLivePos.set then
            lblLivePos:set(string.format("`oPos: (-, -) [%s]``  |  `4HP: %s``", worldName, hpText))
        end
    end

    if activeWaypoint and px and py then
        local dx = activeWaypoint.x - px
        local dy = activeWaypoint.y - py
        local totalDist = math.abs(dx) + math.abs(dy)

        if lblWpInfo and lblWpInfo.set then
            lblWpInfo:set(string.format("`9[*] %s (X: %d, Y: %d)``", activeWaypoint.name, activeWaypoint.x + 1, activeWaypoint.y + 1))
        end

        if lblWpDist and lblWpDist.set then
            if totalDist <= 1 then
                lblWpDist:set("`2[DONE] Sampai di target!``")
            else
                local dirX = (dx > 0) and (dx .. " Kanan") or (dx < 0 and (-dx .. " Kiri") or "0")
                local dirY = (dy > 0) and (dy .. " Bawah") or (dy < 0 and (-dy .. " Atas") or "0")
                lblWpDist:set(string.format("`oArah: %s, %s (Jarak: %d tile)``", dirX, dirY, totalDist))
            end
        end
    end
end)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  INITIALIZATION & CLEANUP (SYSPROXY)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
if refreshMode then pcall(refreshMode) end
if updateLayerUI then pcall(updateLayerUI) end
if updateGridVisuals then pcall(updateGridVisuals) end
if refreshInventory then pcall(refreshInventory) end
if hookRealtimeInventory then pcall(hookRealtimeInventory) end
if ensureLocateHook then pcall(ensureLocateHook) end
if not _G.SysproxySplashShown then
    _G.SysproxySplashShown = true
    task.defer(showTeamSplashDialog)
else
    MainDialog.Visible = true
end
switchTab("proxy")
if updatePlayerUI then updatePlayerUI() end
if updateSpamUI then updateSpamUI() end
if Proxy and Proxy.loadConfig then pcall(Proxy.loadConfig) end

SG.Destroying:Connect(function()
    scriptAlive = false
    if Proxy and Proxy.saveConfig then
        pcall(Proxy.saveConfig, true)
    end
    if renderConn then pcall(function() renderConn:Disconnect() end); renderConn = nil end
    if mobilityHeartbeatConn then pcall(function() mobilityHeartbeatConn:Disconnect() end); mobilityHeartbeatConn = nil end
    if gridConnection then pcall(function() gridConnection:Disconnect() end); gridConnection = nil end
    Mobility.flyEnabled = false
    Mobility.antiGravEnabled = false
    Mobility.speedEnabled = false
    applySpeedMode()
    ClickPathfind.enabled = false
    toggleClickPathfindGrid(false)
    if gridContainer then
        pcall(function() gridContainer:Destroy() end)
        gridContainer = nil
    end
    if ClickPathfind.thread then
        task.cancel(ClickPathfind.thread)
        ClickPathfind.thread = nil
    end
    if stopSpam then stopSpam() end
    if _G.CleanGrowbloxCommands then
        pcall(_G.CleanGrowbloxCommands)
    end
end)

if Proxy.updateUI then pcall(Proxy.updateUI) end

print("[SYSHUB Proxy] âœ… Loaded successfully - Syshub Proxy Edition!")
print("[SYSHUB Proxy] Proxy, Player, World (GrowScan) & Spam Modules Active.")
-- ==============================================================================
--  PROXY BACKGROUND SERVICES, HOOKS & CHAT CONTROLLER
-- ==============================================================================
task.spawn(function()
    local LP = Players.LocalPlayer

    -- 1. Grab native hooks
    pcall(function()
        local fns = filtergc("function", { Constants = {"object_spawn2"} })
        for _, f in ipairs(fns or {}) do
            if debug.info(f, "a") == 2 then
                Proxy.onDropFn = f
                break
            end
        end
        if Proxy.onDropFn then
            local ups = debug.getupvalues(Proxy.onDropFn)
            for _, u in ipairs(ups or {}) do
                if type(u) == "table" and (type(u.count) == "function" or type(u.slots) == "table") then
                    Proxy.invRef = u
                    break
                end
            end
        end
    end)

    pcall(function()
        Proxy.dieFn = filtergc("function", { Constants = {"male_scream"} }, true)
        Proxy.enterWorldFn = filtergc("function", { Name = "enterWorld" }, true)
    end)

    local worldRemotesRef = ReplicatedStorage:WaitForChild("WorldRemotes", 5)
    local worldCommandRef = worldRemotesRef and worldRemotesRef:FindFirstChild("WorldCommand")
    local dropAddedRemote = worldRemotesRef and worldRemotesRef:FindFirstChild("DropAdded")
    local dropTakenRemote = worldRemotesRef and worldRemotesRef:FindFirstChild("DropTaken")

    local wmList = filtergc("table", { Keys = {"openPlayer", "openPicker"} }, false)
    local worldMenuRef = wmList and wmList[1]

    -- Periodic auto-save every 15s
    task.spawn(function()
        while scriptAlive do
            task.wait(15)
            if not scriptAlive then break end
            pcall(Proxy.saveConfig)
        end
    end)

    -- Auto-reload on teleport (queue_on_teleport)
    local function setupAutoReloadOnTeleport()
        local qot = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if qot then
            pcall(function()
                qot([[
                    task.spawn(function()
                        if _G.__SYSPROXY_JOBID == game.JobId then return end
                        _G.__SYSPROXY_JOBID = game.JobId
                        local start = os.clock()
                        while not game:IsLoaded() and (os.clock() - start) < 30 do
                            task.wait(0.2)
                        end
                        task.wait(1.2)
                        if isfile and isfile("sysproxy.lua") and readfile then
                            local ok, err = pcall(function()
                                loadstring(readfile("sysproxy.lua"))()
                            end)
                            if not ok then warn("[SYSPROXY Auto-Load Error]", err) end
                        end
                    end)
                ]])
            end)
        end
    end
    Proxy.setupAutoReloadOnTeleport = setupAutoReloadOnTeleport

    -- Pre-queue immediately on load
    setupAutoReloadOnTeleport()

    -- Auto-load saved config on startup
    task.spawn(function()
        task.wait(0.3)
        if scriptAlive and Proxy.loadConfig then
            pcall(Proxy.loadConfig)
        end
    end)

    -- Auto-save on teleport
    pcall(function()
        local LP = Players.LocalPlayer
        if LP and LP.OnTeleport then
            LP.OnTeleport:Connect(function()
                scriptAlive = false
                setupAutoReloadOnTeleport()
                pcall(Proxy.saveConfig, true)
            end)
        end
    end)

    -- Auto compress loop (100 WL -> 1 DL, 100 DL -> 1 BGL)
    local autoConvertRunning = true
    task.spawn(function()
        while scriptAlive and autoConvertRunning do
            task.wait(2.5)
            if not scriptAlive or not autoConvertRunning then break end
            pcall(Proxy.autoCompressLocks)
        end
    end)

    -- Helper sendWorldCommand (Legit ByteNet RPC pipeline to prevent kick)
    local function sendWorldCommand(cmd, targetArg)
        local w = getNativeWorld and getNativeWorld()
        if w and type(w.call) == "function" then
            local ok, err, res = pcall(w.call, "WorldCommand", cmd, targetArg)
            if ok then return true, err, res end
        end
        if Net and type(Net.call) == "function" then
            local ok, err, res = pcall(Net.call, "WorldCommand", cmd, targetArg)
            if ok then return true, err, res end
        end
        return false
    end

    -- Floating gems text listener (Strict 1-Grid Tile & Total Ground Accumulation)
    local gemFloatConn = nil
    local dropTakenConn = nil

    -- Pre-cache drops table on load
    gameDropsTable = findGameDropsTable()

    -- Growblox native character name & players resolver
    local function getGrowbloxNameResolver()
        local list = filtergc and filtergc("table", { Keys = {"wrenchAt"} }, false)
        local ref = list and list[1]
        if ref and type(ref.wrenchAt) == "function" then
            local ups = debug.getupvalues(ref.wrenchAt)
            local others = ups and ups[1]
            local nameOf = ups and ups[2] and ups[2].nameOf
            return others, nameOf
        end
        return nil, nil
    end

    local function getActiveNick()
        if not LP then return nil end
        local nick = LP:GetAttribute("Nick")
        if nick and type(nick) == "string" and nick ~= "" then
            return nick
        end
        return nil
    end

    local function getLocalRealNames()
        local list = {}
        if LP then
            local gn = LP:GetAttribute("GameName")
            if gn and gn ~= "" then table.insert(list, gn) end
            if LP.Name and LP.Name ~= "" then table.insert(list, LP.Name) end
            if LP.DisplayName and LP.DisplayName ~= "" then table.insert(list, LP.DisplayName) end
        end
        return list
    end

    local function applyNickToString(str)
        if type(str) ~= "string" then return str end
        local nick = getActiveNick()
        if not nick then return str end

        for _, realName in ipairs(getLocalRealNames()) do
            if realName and realName ~= "" and realName ~= nick then
                str = str:gsub(realName, nick)
            end
        end
        return str
    end
    Proxy.applyNickToString = applyNickToString

    local function resolveGrowbloxName(playerOrUserId)
        if not playerOrUserId then return "Unknown" end
        local activeNick = getActiveNick()
        if (playerOrUserId == LP or playerOrUserId == LP.UserId) and activeNick then
            return activeNick
        end
        local others, nameOf = getGrowbloxNameResolver()

        -- If Player instance
        if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
            if nameOf then
                local ok, n = pcall(nameOf, playerOrUserId)
                if ok and n and n ~= "" then return n end
            end
            if others then
                for _, op in pairs(others) do
                    if op.who == playerOrUserId and op.name and op.name ~= "" then
                        return op.name
                    end
                end
            end
            return playerOrUserId.DisplayName or playerOrUserId.Name
        end

        -- If UserId number
        if type(playerOrUserId) == "number" then
            if playerOrUserId == LP.UserId then
                if nameOf then
                    local ok, n = pcall(nameOf, LP)
                    if ok and n and n ~= "" then return n end
                end
                return LP.DisplayName or LP.Name
            end

            local p = Players:GetPlayerByUserId(playerOrUserId)
            if p and nameOf then
                local ok, n = pcall(nameOf, p)
                if ok and n and n ~= "" then return n end
            end

            if others then
                for _, op in pairs(others) do
                    if op.userId == playerOrUserId or (op.who and op.who.UserId == playerOrUserId) then
                        if op.name and op.name ~= "" then return op.name end
                        if op.who and nameOf then
                            local ok, n = pcall(nameOf, op.who)
                            if ok and n and n ~= "" then return n end
                        end
                    end
                end
            end

            if p then return p.DisplayName or p.Name end
            local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(playerOrUserId) end)
            return (ok and n) or ("User_" .. tostring(playerOrUserId))
        end

        -- If string
        if type(playerOrUserId) == "string" then
            if others then
                for _, op in pairs(others) do
                    if op.name and op.name:lower() == playerOrUserId:lower() then
                        return op.name
                    end
                    if op.who and (op.who.Name:lower() == playerOrUserId:lower() or op.who.DisplayName:lower() == playerOrUserId:lower()) then
                        if op.name and op.name ~= "" then return op.name end
                        if nameOf then
                            local ok, n = pcall(nameOf, op.who)
                            if ok and n and n ~= "" then return n end
                        end
                    end
                end
            end
            if playerOrUserId:lower() == LP.Name:lower() or playerOrUserId:lower() == LP.DisplayName:lower() then
                if nameOf then
                    local ok, n = pcall(nameOf, LP)
                    if ok and n and n ~= "" then return n end
                end
                return LP.DisplayName
            end
            local p = Players:FindFirstChild(playerOrUserId)
            if p and nameOf then
                local ok, n = pcall(nameOf, p)
                if ok and n and n ~= "" then return n end
            end
            return playerOrUserId
        end

        return "Unknown"
    end

    local function findCollectorAt(tx, ty, prevDropperUserId)
        local bestName = nil
        local bestDist = 999999

        -- 1. Check LocalPlayer distance
        local myPx, myPy = getPlayerTilePos()
        if myPx and myPy then
            local d = math.sqrt((myPx - tx)^2 + (myPy - ty)^2)
            if d < bestDist then
                bestDist = d
                bestName = resolveGrowbloxName(LP)
            end
        end

        -- 2. Check other players from live table
        local others, nameOf = getGrowbloxNameResolver()
        if others then
            for _, op in pairs(others) do
                if op.x and op.y then
                    local d = math.sqrt((op.x - tx)^2 + (op.y - ty)^2)
                    if d < bestDist then
                        bestDist = d
                        bestName = op.name or (op.who and nameOf and nameOf(op.who)) or (op.who and op.who.DisplayName) or "Player"
                    end
                end
            end
        end

        -- Close match within reasonable range
        if bestDist <= 4.5 and bestName then
            return bestName
        end

        -- Fallback to dropper if drop happened in place
        if prevDropperUserId then
            local dropperName = resolveGrowbloxName(prevDropperUserId)
            if dropperName and dropperName ~= "Unknown" then
                return dropperName
            end
        end

        return bestName or "Unknown"
    end

    local recentTakes = {}
    local function recordTake(collectorName, itemId, count, tx, ty)
        if type(count) ~= "number" or count <= 0 or not itemId or itemId <= 0 then return end
        local key = tostring(collectorName or "") .. "_" .. tostring(itemId) .. "_" .. tostring(count) .. "_" .. tostring(tx) .. "_" .. tostring(ty)
        local now = os.clock()
        if recentTakes[key] and (now - recentTakes[key]) < 0.8 then
            return
        end
        recentTakes[key] = now

        Proxy.addLog("TAKE", collectorName, itemId, count, tx, ty)
    end
    Proxy.recordTake = recordTake

    -- Hook native world collection systems (both dropTaken for other players & takeDrop for LocalPlayer)
    local function hookWorldDropSystem()
        local w = getNativeWorld and getNativeWorld()
        if not w then return end

        if not w._nativeDropTaken and not w._sysproxyDropTakenHooked then
            w._nativeDropTaken = w.dropTaken
        end
        if not w._nativeTakeDrop and not w._sysproxyTakeDropHooked then
            w._nativeTakeDrop = w.takeDrop
        end
        w._sysproxyDropTakenHooked = true
        w._sysproxyTakeDropHooked = true

        local function callNativeTakeDrop(uid, want)
            if type(w._nativeTakeDrop) == "function" then
                return w._nativeTakeDrop(uid, want)
            end
            if type(w.ask) == "function" then
                local v1 = w.ask("take", "took", { uid = uid, want = math.clamp(math.floor(want or 1), 0, 65535) })
                return v1 and v1.got
            end
            return 0
        end

        -- 1. Hook dropTaken (Server broadcast, mainly other players taking items)
        w.dropTaken = function(uid, newCount)
            local drop = nil
            if type(w.dropList) == "function" then
                local dl = w.dropList()
                if dl then
                    for _, d in ipairs(dl) do
                        if d.uid == uid then
                            drop = d
                            break
                        end
                    end
                end
            end
            if not drop and Proxy.cachedDrops[uid] then
                drop = Proxy.cachedDrops[uid]
            end

            if drop and drop.id then
                local oldCount = drop.n or 1
                local newC = newCount or 0
                local takenAmt = (oldCount > newC) and (oldCount - newC) or oldCount
                if takenAmt <= 0 then takenAmt = 1 end

                local tx = math.floor(drop.x or 0)
                local ty = math.floor(drop.y or 0)
                local collectorName = findCollectorAt(tx, ty, drop.by)

                recordTake(collectorName, drop.id, takenAmt, tx, ty)
            end

            if type(w._nativeDropTaken) == "function" then
                return w._nativeDropTaken(uid, newCount)
            end
        end

        -- 2. Hook takeDrop (LocalPlayer taking items)
        w.takeDrop = function(uid, want)
            local drop = nil
            if type(w.dropList) == "function" then
                local dl = w.dropList()
                if dl then
                    for _, d in ipairs(dl) do
                        if d.uid == uid then
                            drop = d
                            break
                        end
                    end
                end
            end
            if not drop and Proxy.cachedDrops[uid] then
                drop = Proxy.cachedDrops[uid]
            end

            local result = callNativeTakeDrop(uid, want)

            if type(result) == "number" and result > 0 and drop and drop.id then
                local myName = resolveGrowbloxName(LP)
                local tx = math.floor(drop.x or 0)
                local ty = math.floor(drop.y or 0)
                recordTake(myName, drop.id, result, tx, ty)
            end

            return result
        end
    end

    hookWorldDropSystem()

    -- 1. ByteNet Net.dropAdded (Auto-Display gems + Live Transaction Logger)
    if Net and Net.dropAdded and type(Net.dropAdded.listen) == "function" then
        Net.dropAdded.listen(function(pkt)
            if type(pkt) == "table" and pkt.id and pkt.n and pkt.x and pkt.y then
                local tx = math.floor(pkt.x)
                local ty = math.floor(pkt.y)

                if pkt.uid then
                    Proxy.cachedDrops[pkt.uid] = {
                        id = pkt.id,
                        n = pkt.n,
                        x = tx,
                        y = ty,
                        by = pkt.by
                    }
                end

                if pkt.id == 112 then
                    handleTileDropUpdate(tx, ty, 112, pkt.n)
                end

                local pName = resolveGrowbloxName(pkt.by)
                Proxy.addLog("DROP", pName, pkt.id, pkt.n, tx, ty)
            end
        end)
    end

    -- 2. ByteNet Net.dropTaken (Ensure hook & fallback logging)
    if Net and Net.dropTaken and type(Net.dropTaken.listen) == "function" then
        Net.dropTaken.listen(function(pkt)
            hookWorldDropSystem()
            if type(pkt) == "table" and pkt.uid then
                local prev = Proxy.cachedDrops[pkt.uid]
                if prev and prev.id then
                    local tx = prev.x or 0
                    local ty = prev.y or 0
                    local prevN = prev.n or 1
                    local takenAmt = (prevN > (pkt.n or 0)) and (prevN - (pkt.n or 0)) or prevN
                    if takenAmt <= 0 then takenAmt = 1 end
                    if prev.id == 112 then
                        handleTileDropUpdate(tx, ty, 112, pkt.n or 0)
                    end
                    if pkt.n and pkt.n > 0 then
                        prev.n = pkt.n
                    else
                        Proxy.cachedDrops[pkt.uid] = nil
                    end
                end
            end
        end)
    end

    -- 3. ByteNet Net.wheelSpun (Instant Roulette Fast Spin & Anti-Scam Verification)
    local recentRealSpins = {}
    local function applyInstantRoulette(enable)
        pcall(function()
            if not Net or not Net.wheelSpun or not Net.wheelSpun.getListeners then return end
            local list = Net.wheelSpun.getListeners()
            local fn = list and list[1]
            if not fn then return end
            local u4 = debug.getupvalue(fn, 4)
            if not u4 then return end
            local itemDb = debug.getupvalue(u4, 2)
            if not itemDb then return end
            if itemDb[758] then
                itemDb[758].rollTime = enable and 0.05 or nil -- 758 = Roulette Wheel
            end
            if itemDb[456] then
                itemDb[456].rollTime = enable and 0.05 or 1.2 -- 456 = Dice Block
            end
            if itemDb[1300] then
                itemDb[1300].rollTime = enable and 0.05 or 1.2 -- 1300 = Roshambo Block
            end
        end)
    end
    Proxy.applyInstantRoulette = applyInstantRoulette

    -- Initialize instant spin on load if enabled
    if Proxy.roulette and Proxy.roulette.instant then
        task.spawn(function()
            for attempt = 1, 10 do
                applyInstantRoulette(true)
                task.wait(0.5)
            end
        end)
    end

    -- Roulette Wheel Log & Last Number History Tracker
    local function recordRouletteSpin(pName, num, isReal, tx, ty)
        if not Proxy.rouletteLogs then Proxy.rouletteLogs = {} end
        local displayName = applyNickToString(pName or "Unknown")
        table.insert(Proxy.rouletteLogs, {
            timeStr = os.date("%H:%M:%S"),
            timestamp = os.clock(),
            player = displayName,
            number = tonumber(num) or 0,
            isReal = (isReal == true),
            x = tx,
            y = ty,
        })
        while #Proxy.rouletteLogs > 100 do
            table.remove(Proxy.rouletteLogs, 1)
        end
        if Proxy.updateRouletteLogUI then
            pcall(Proxy.updateRouletteLogUI)
        end
    end
    Proxy.recordRouletteSpin = recordRouletteSpin

    local cachedOthersRef = nil
    local cachedNameTagBm = nil
    local function updateAllPlayerNameTags()
        if not scriptAlive then return end
        pcall(function()
            if not Proxy.lastSpunNumbers then return end

            -- 1. Other players overhead tag
            if not cachedOthersRef then
                local listOthers = filtergc and filtergc("table", { Keys = {"wrenchAt", "say"} }, false)
                cachedOthersRef = listOthers and listOthers[1]
            end
            local othersRef = cachedOthersRef
            local u5 = othersRef and debug.getupvalue(othersRef.showNames, 1)
            if u5 then
                for _, j in pairs(u5) do
                    if j.tagName and j.tagName.set then
                        local lastNum = (j.userId and Proxy.lastSpunNumbers[tostring(j.userId)])
                            or (j.name and Proxy.lastSpunNumbers[j.name:lower()])
                        if lastNum ~= nil then
                            local baseName = j.name or ""
                            local cleanBase = baseName:gsub("%s*`%w*%[%d+%]`*`*", ""):gsub("%s*%[%d+%]", "")
                            j.tagName:set(string.format("%s `p[%d]``", cleanBase, lastNum))
                        end
                    end
                end
            end

            -- 2. Local player overhead tag
            local LP = game:GetService("Players").LocalPlayer
            local PlayerGui = LP and LP:FindFirstChild("PlayerGui")
            local gameGui = PlayerGui and PlayerGui:FindFirstChild("GameGui")
            local world = gameGui and gameGui:FindFirstChild("World")
            local camera = world and world:FindFirstChild("Camera")
            local nameTag = camera and camera:FindFirstChild("NameTag")
            local bmFrame = nameTag and nameTag:FindFirstChild("BitmapText")

            if bmFrame then
                local lastNum = (LP and Proxy.lastSpunNumbers[tostring(LP.UserId)])
                    or (LP and Proxy.lastSpunNumbers[LP.Name:lower()])
                local myName = getActiveNick() or (resolveGrowbloxName and resolveGrowbloxName(LP)) or LP.Name
                if cachedNameTagBm and cachedNameTagBm.frame == bmFrame and cachedNameTagBm.set then
                    if lastNum ~= nil then
                        cachedNameTagBm:set(string.format("%s `p[%d]``", myName, lastNum))
                    else
                        cachedNameTagBm:set(myName)
                    end
                elseif filtergc then
                    for _, t in ipairs(filtergc("table", { Keys = {"align", "atlas", "size"} }, false)) do
                        if t.frame == bmFrame and t.set then
                            cachedNameTagBm = t
                            if lastNum ~= nil then
                                t:set(string.format("%s `p[%d]``", myName, lastNum))
                            else
                                t:set(myName)
                            end
                            break
                        end
                    end
                end
            end
        end)
    end
    Proxy.updateAllPlayerNameTags = updateAllPlayerNameTags

    -- Hook Roles.tagText for native nameplate redraws
    pcall(function()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Shared = ReplicatedStorage:FindFirstChild("Shared")
        local RolesModule = Shared and Shared:FindFirstChild("Roles")
        local Roles = RolesModule and require(RolesModule)
        if Roles and type(Roles.tagText) == "function" and not Roles._origTagText then
            Roles._origTagText = Roles.tagText
            Roles.tagText = function(name, userId, ...)
                local base = Roles._origTagText(name, userId, ...)
                base = applyNickToString(base)
                if Proxy.lastSpunNumbers then
                    local lastNum = (userId and Proxy.lastSpunNumbers[tostring(userId)])
                        or (name and Proxy.lastSpunNumbers[name:lower()])
                    if lastNum ~= nil and not base:find("%[%d+%]") then
                        return string.format("%s `p[%d]``", base, lastNum)
                    end
                end
                return base
            end
        end
    end)

    if Net and Net.wheelSpun and type(Net.wheelSpun.listen) == "function" then
        Net.wheelSpun.listen(function(pkt)
            if type(pkt) == "table" and pkt.n and pkt.x and pkt.y then
                local num = tonumber(pkt.n) or 0
                local pName = tostring(pkt.name or "Unknown")
                local uId = pkt.userId
                local tx = math.floor(pkt.x)
                local ty = math.floor(pkt.y)

                -- 1. Store last spun number for player overhead history [N]
                if Proxy.lastSpunNumbers then
                    Proxy.lastSpunNumbers[pName:lower()] = num
                    if uId then Proxy.lastSpunNumbers[tostring(uId)] = num end
                    updateAllPlayerNameTags()
                end

                -- 2. Record to live roulette logs
                recordRouletteSpin(pName, num, true, tx, ty)

                -- 3. Record verified server roll
                table.insert(recentRealSpins, {
                    x = tx,
                    y = ty,
                    number = num,
                    name = pName,
                    userId = uId,
                    time = os.clock(),
                    claimedBubble = false,
                    claimedChat = false,
                })

                while #recentRealSpins > 30 do
                    table.remove(recentRealSpins, 1)
                end

                -- Instant spin fast-forward if enabled
                if Proxy.roulette and Proxy.roulette.instant then
                    pcall(function()
                        local list = Net.wheelSpun.getListeners()
                        local fn = list and list[1]
                        if fn then
                            local u4 = debug.getupvalue(fn, 4)
                            local u4204 = u4 and debug.getupvalue(u4, 3)
                            if u4204 then
                                local w = getNativeWorld and getNativeWorld()
                                local width = (w and w.w) or 100
                                local key = ty * width + tx
                                if u4204[key] then
                                    u4204[key].ends = 0
                                    u4204[key].n = num
                                    u4204[key].name = pName
                                    u4204[key].userId = uId
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- Speech Bubble Hooks for Overhead Popups (Gambar 2 / Gambar 3)
    local function verifyWheelMessage(text, userId)
        if not (Proxy.roulette and Proxy.roulette.verify and type(text) == "string") then
            return text
        end
        local clean = text:gsub("``", ""):gsub("`%w", ""):gsub("`%*", ""):gsub("`", "")
        if clean:find("spun the wheel and got") then
            if text:find("%[REAL%]") or text:find("%[FAKE%]") then
                return text
            end
            local numStr = clean:match("spun the wheel and got.-(%d+)")
            local pName = clean:match("%[([^%[%]:]-)%s+spun the wheel and got")
            if not pName then
                pName = clean:match("%[([^:]-):")
            end
            if pName then
                pName = pName:match("^%s*(.-)%s*$")
            end
            local num = tonumber(numStr)
            if num then
                local foundReal = false
                local now = os.clock()
                local activeNick = getActiveNick()
                for idx = #recentRealSpins, 1, -1 do
                    local sp = recentRealSpins[idx]
                    if sp and sp.number == num and (now - sp.time) <= 6.0 and not sp.claimedBubble then
                        local isMatch = false
                        if not pName or pName == "" then
                            isMatch = true
                        elseif (sp.name and sp.name:lower():find(pName:lower(), 1, true)) or (sp.name and pName:lower():find(sp.name:lower(), 1, true)) then
                            isMatch = true
                        elseif (sp.userId and userId and sp.userId == userId) or (sp.userId and LP and sp.userId == LP.UserId and activeNick and pName:lower() == activeNick:lower()) then
                            isMatch = true
                        end
                        if isMatch then
                            foundReal = true
                            sp.claimedBubble = true
                            break
                        end
                    end
                end
                if foundReal then
                    return applyNickToString("`2[REAL]`` " .. text)
                else
                    recordRouletteSpin(pName or "Player", num, false, nil, nil)
                    return applyNickToString("`4[FAKE]`` " .. text)
                end
            end
        end
        return applyNickToString(text)
    end

    local function hookOthersSay()
        if Proxy._sysproxySayHooked then return end
        pcall(function()
            if not cachedOthersRef then
                local listOthers = filtergc and filtergc("table", { Keys = {"wrenchAt", "say"} }, false)
                cachedOthersRef = listOthers and listOthers[1]
            end
            local othersRef = cachedOthersRef
            if othersRef and type(othersRef.say) == "function" then
                if not Proxy._sysproxySayHooked then
                    Proxy._origOthersSay = othersRef.say
                    othersRef.say = function(userId, text, ...)
                        text = verifyWheelMessage(text, userId)
                        text = applyNickToString(text)
                        if Proxy._origOthersSay then
                            return Proxy._origOthersSay(userId, text, ...)
                        end
                    end
                    Proxy._sysproxySayHooked = true
                end
            end
        end)
    end

    local cachedPlayerCtrl = nil
    local function hookLocalBubble()
        if Proxy._sysproxyBubbleHooked then return end
        pcall(function()
            if not cachedPlayerCtrl then
                local listPlayer = filtergc and filtergc("table", { Keys = {"onSay", "console", "bubble"} }, false)
                cachedPlayerCtrl = listPlayer and listPlayer[1]
            end
            local pCtrl = cachedPlayerCtrl
            if pCtrl then
                local target = (type(pCtrl.onSay) == "function" and debug.getupvalue(pCtrl.onSay, 1))
                    or (type(pCtrl.bubble) == "function" and debug.getupvalue(pCtrl.bubble, 5))
                if type(target) == "function" and not Proxy._sysproxyBubbleHooked then
                    Proxy._origShowBubble = hookfunction(target, function(text, ...)
                        text = verifyWheelMessage(text, LP and LP.UserId)
                        text = applyNickToString(text)
                        if Proxy._origShowBubble then
                            return Proxy._origShowBubble(text, ...)
                        end
                    end)
                    Proxy._sysproxyBubbleHooked = true
                end
            end
        end)
    end

    hookOthersSay()
    hookLocalBubble()

    -- 3. Legacy RemoteEvent fallback (just in case)
    if dropAddedRemote and dropAddedRemote:IsA("RemoteEvent") then
        gemFloatConn = dropAddedRemote.OnClientEvent:Connect(function(uid, itemId, count, x, y, userId)
            if itemId ~= 112 then return end
            if type(count) ~= "number" or count <= 0 or type(x) ~= "number" or type(y) ~= "number" then return end
            local tx = math.floor(x)
            local ty = math.floor(y)
            handleTileDropUpdate(tx, ty, 112, count)
        end)
    end

    if dropTakenRemote and dropTakenRemote:IsA("RemoteEvent") then
        dropTakenConn = dropTakenRemote.OnClientEvent:Connect(function(uid, newCount)
            if type(newCount) ~= "number" or newCount <= 0 then return end
            local drops = gameDropsTable or findGameDropsTable()
            if drops then
                for _, drop in ipairs(drops) do
                    if type(drop) == "table" and drop.uid == uid and drop.id == 112 and type(drop.n) == "number" and newCount > drop.n then
                        local tx = math.floor(drop.x)
                        local ty = math.floor(drop.y)
                        handleTileDropUpdate(tx, ty, 112, newCount)
                        break
                    end
                end
            end
        end)
    end

    -- Hook Fast Action Wrench (LMB = Pull, RMB = Kick)
    if not othersPlayerTable then
        local oth = getGrowbloxNameResolver()
        othersPlayerTable = oth
    end

    local function isWrenchActive()
        local nameTag = PlayerGui:FindFirstChild("NameTag", true)
        local wrenchIcon = nameTag and nameTag:FindFirstChild("Wrench")
        if wrenchIcon and wrenchIcon.Visible == true then return true end
        if othersPlayerTable then
            for _, p in pairs(othersPlayerTable) do
                if p.wrench and p.wrench.frame and p.wrench.frame.Visible then
                    return true
                end
            end
        end
        return false
    end

    local function getPlayerAtScreen(pos)
        if othersRef and type(othersRef.wrenchAt) == "function" then
            local t = othersRef.wrenchAt(pos)
            if t and t.userId then return t end
        end
        local closest = nil
        local closestDist = math.huge
        if othersPlayerTable then
            for _, p in pairs(othersPlayerTable) do
                if p.seen and p.tag then
                    local tPos = p.tag.AbsolutePosition
                    local tSize = p.tag.AbsoluteSize
                    local center = Vector2.new(tPos.X + tSize.X / 2, tPos.Y + 45)
                    local minX = tPos.X - 25
                    local maxX = tPos.X + tSize.X + 25
                    local minY = tPos.Y - 15
                    local maxY = tPos.Y + 120
                    if pos.X >= minX and pos.X <= maxX and pos.Y >= minY and pos.Y <= maxY then
                        local dist = (pos - center).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closest = { id = p.id, userId = p.userId, name = p.name }
                        end
                    end
                end
            end
        end
        return closest
    end

    local oldOpenPlayer = worldMenuRef and worldMenuRef.openPlayer
    if worldMenuRef then
        worldMenuRef.openPlayer = function(target)
            if Proxy.fastPKEnabled and target and target.userId then
                task.spawn(function()
                    local ok = sendWorldCommand("pull", "#" .. tostring(target.userId))
                    if ok then
                        pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
                    else
                        if oldOpenPlayer then oldOpenPlayer(target) end
                    end
                end)
                return nil
            end
            if oldOpenPlayer then
                return oldOpenPlayer(target)
            end
            return nil
        end
    end

    local kickConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if not Proxy.fastPKEnabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            local mousePos = Vector2.new(input.Position.X, input.Position.Y)
            local target = getPlayerAtScreen(mousePos)
            if target and target.userId then
                task.spawn(function()
                    local ok = sendWorldCommand("kick", "#" .. tostring(target.userId))
                    if ok and Sfx and Sfx.play then pcall(Sfx.play, "punch_hit") end
                end)
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not gpe then
            if isWrenchActive() then
                local mousePos = Vector2.new(input.Position.X, input.Position.Y)
                local target = getPlayerAtScreen(mousePos)
                if target and target.userId then
                    task.spawn(function()
                        local ok = sendWorldCommand("pull", "#" .. tostring(target.userId))
                        if ok and Sfx and Sfx.play then pcall(Sfx.play, "click") end
                    end)
                end
            end
        end
    end)

    -- Hook Punch to Check Gems (via Net.act.send + UserInput click fallback)
    if Net and Net.act and type(Net.act.send) == "function" and not Net.act._syshubPunchGemsHookInstalled then
        Net.act._syshubPunchGemsHookInstalled = true
        local origActSend = Net.act.send
        Net.act.send = function(pkt)
            if Proxy.punchGemsCheck and type(pkt) == "table" then
                local kind = pkt.kind
                if kind == 1 or kind == 6 or kind == ACT_KIND.PUNCH or kind == ACT_KIND.HIT then
                    local tx = math.floor(pkt.x or 0)
                    local ty = math.floor(pkt.y or 0)
                    task.spawn(function()
                        local count = getTotalDropsOnTile(tx, ty, 112)
                        if count and count > 0 then
                            spawnFloatingDropText(tx, ty, 112, count)
                        end
                    end)
                end
            end
            return origActSend(pkt)
        end
    end

    local punchClickConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not Proxy.punchGemsCheck then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local pgui = PlayerGui
            local gameGui = pgui:FindFirstChild("GameGui")
            local camera = gameGui and gameGui:FindFirstChild("Camera", true)
            local tiles = camera and camera:FindFirstChild("Tiles")
            if camera and tiles then
                local uiScale = 1
                local s = camera:FindFirstChild("UIScale")
                if s and s:IsA("UIScale") then uiScale = s.Scale end
                local DISPLAY_SIZE = 64
                local tileSize = DISPLAY_SIZE * uiScale
                local absPos = tiles.AbsolutePosition
                local mouseX = input.Position.X
                local mouseY = input.Position.Y
                local tx = math.floor((mouseX - absPos.X) / tileSize)
                local ty = math.floor((mouseY - absPos.Y) / tileSize)
                task.delay(0.05, function()
                    local count = getTotalDropsOnTile(tx, ty, 112)
                    if count and count > 0 then
                        spawnFloatingDropText(tx, ty, 112, count)
                    end
                end)
            end
        end
    end)

    -- Hook Chat Controller
    local chatTableRef = nil
    for attempt = 1, 30 do
        local chatGui = PlayerGui:FindFirstChild("ChatGui")
        local chatInput = chatGui and chatGui:FindFirstChild("Input", true)
        if chatInput then
            local conns = getconnections(chatInput.FocusLost)
            for _, c in ipairs(conns or {}) do
                local fn = c.Function
                if type(fn) == "function" then
                    local ok4, sendFn = pcall(debug.getupvalue, fn, 4)
                    if ok4 and type(sendFn) == "function" then
                        local ok1, tbl = pcall(debug.getupvalue, sendFn, 1)
                        if ok1 and type(tbl) == "table" and type(tbl.onCommand) == "function" then
                            chatTableRef = tbl
                            Proxy.chatTableRef = tbl
                            break
                        end
                    end
                end
            end
            if chatTableRef then break end
        end
        task.wait(0.5)
    end

    if not chatTableRef then
        warn("[SYSHUB Proxy] Chat controller could not be hooked!")
        return
    end

    local oldOnCommand = chatTableRef.onCommand
    if not chatTableRef._origAdd then
        chatTableRef._origAdd = chatTableRef.add
    end

    local myAdd = function(msg, ...)
        if type(msg) == "string" and msg:find("You collected") then
            local clean = msg:gsub("``", ""):gsub("`%w", ""):gsub("`", "")
            local countStr, nameStr = clean:match("You collected (%d+)%s+([^!]+)")
            if nameStr then
                nameStr = nameStr:gsub("!.*$", ""):match("^%s*(.-)%s*$")
            end
            local count = tonumber(countStr)
            if count and count > 0 and nameStr then
                local foundId = nil
                for id, lockName in pairs(Proxy.LOCK_NAMES) do
                    if string.lower(lockName) == string.lower(nameStr) then
                        foundId = id
                        break
                    end
                end
                if foundId then
                    local myName = resolveGrowbloxName(LP)
                    local myPx, myPy = getPlayerTilePos()
                    recordTake(myName, foundId, count, myPx or 0, myPy or 0)
                end
            end
        end

        -- 2. Anti-Scam Roulette Wheel Verification (REAL vs FAKE)
        if Proxy.roulette and Proxy.roulette.verify and type(msg) == "string" then
            local clean = msg:gsub("``", ""):gsub("`%w", ""):gsub("`%*", ""):gsub("`", "")
            if clean:find("spun the wheel and got") then
                if not (msg:find("%[REAL%]") or msg:find("%[FAKE%]") or msg:find("%[FAKE")) then
                    local numStr = clean:match("spun the wheel and got.-(%d+)")
                    local pName = clean:match("%[?([^%[%]:]-)%s+spun the wheel and got")
                    if not pName then
                        pName = clean:match("%[?([^:]-):")
                    end
                    if pName then
                        pName = pName:match("^%s*(.-)%s*$")
                    end
                    local num = tonumber(numStr)

                    if num then
                        local foundReal = false
                        local now = os.clock()
                        local activeNick = getActiveNick()
                        for idx = #recentRealSpins, 1, -1 do
                            local sp = recentRealSpins[idx]
                            if sp and sp.number == num and (now - sp.time) <= 6.0 and not sp.claimedChat then
                                local isMatch = false
                                if not pName or pName == "" then
                                    isMatch = true
                                elseif (sp.name and sp.name:lower():find(pName:lower(), 1, true)) or (sp.name and pName:lower():find(sp.name:lower(), 1, true)) then
                                    isMatch = true
                                elseif (sp.userId and LP and sp.userId == LP.UserId and activeNick and pName:lower() == activeNick:lower()) then
                                    isMatch = true
                                end
                                if isMatch then
                                    foundReal = true
                                    sp.claimedChat = true
                                    break
                                end
                            end
                        end

                        if foundReal then
                            -- Verified REAL server roll
                            msg = "`2[REAL]`` " .. msg
                        else
                            -- FAKE roll typed manually in chat
                            recordRouletteSpin(pName or "Player", num, false, nil, nil)
                            msg = "`4[FAKE]`` " .. msg
                        end
                    end
                end
            end
        end

        msg = applyNickToString(msg)

        if type(chatTableRef._origAdd) == "function" then
            return chatTableRef._origAdd(msg, ...)
        end
    end
    chatTableRef.add = myAdd

    chatTableRef.onCommand = function(msg)
        if type(msg) ~= "string" then
            return oldOnCommand(msg)
        end

        local trimmed = msg:match("^%s*(.-)%s*$")
        local cmd, rest = trimmed:match("^/(%S+)%s*(.*)$")
        if not cmd then
            return oldOnCommand(msg)
        end

        cmd = cmd:lower()
        local args = {}
        for a in rest:gmatch("%S+") do
            table.insert(args, a)
        end

        -- 1. PROXY GUI TOGGLE / TAB SWITCH
        if cmd == "proxy" then
            if openMainDialog then openMainDialog() end
            if switchTab then switchTab("proxy") end
            return true
        end

        -- 2. CASINO COMMANDS
        local posIdx = cmd:match("^pos([1-4])$")
        if posIdx then
            local idx = tonumber(posIdx)
            local px, py = getPlayerTilePos()
            if px and py then
                local curFacing = 1
                if Proxy.onDropFn and debug and debug.getupvalue then
                    local f = debug.getupvalue(Proxy.onDropFn, 2)
                    if f == -1 or f == 1 then curFacing = f end
                end
                Proxy.casino.positions[idx] = { x = px, y = py, facing = curFacing }
                Proxy.saveConfig()
                local dirText = (curFacing == 1) and "Kanan" or "Kiri"
                Proxy.showPosMarker(idx, px, py)
                Proxy.notify(string.format("`2[Casino] Pos %d tersimpan di (X: %d, Y: %d) [Hadap: %s]``", idx, px + 1, py + 1, dirText))
                pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
                Proxy.updateUI()
            else
                Proxy.notify("`4[Casino] Gagal mendeteksi koordinat karakter!``")
            end
            return true
        end

        if cmd == "host" then
            local px, py = getPlayerTilePos()
            if px and py then
                Proxy.casino.hostPos = { x = px, y = py }
                Proxy.saveConfig()
                Proxy.notify(string.format("`2[Casino] Titik Bandar tersimpan di (X: %d, Y: %d)``", px + 1, py + 1))
                pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
                Proxy.updateUI()
            else
                Proxy.notify("`4[Casino] Gagal mendeteksi koordinat karakter!``")
            end
            return true
        end

        if cmd == "tax" then
            local rate = tonumber(args[1])
            if rate and rate >= 0 and rate <= 100 then
                Proxy.casino.taxRate = rate
                Proxy.saveConfig()
                Proxy.notify(string.format("`2[Casino] Tax diset ke: %d%%``", rate))
                Proxy.updateUI()
            else
                Proxy.notify(string.format("`o[Casino] Tax saat ini: %d%% (Format: /tax <angka>)``", Proxy.casino.taxRate))
            end
            return true
        end

        local tpDirectIdx = cmd:match("^tp([1-4])$")
        if cmd == "tp" or tpDirectIdx then
            local arg1 = args[1]
            local arg2 = args[2]

            -- 1. /tp <1-4> atau /tp1 - /tp4: Meluncur ke pos yang di-set dan langsung bebas gerak
            local posIdx = tonumber(tpDirectIdx) or (arg1 and not arg2 and tonumber(arg1))
            if posIdx and posIdx >= 1 and posIdx <= 4 then
                local p = Proxy.casino.positions[posIdx]
                if p then
                    task.spawn(function()
                        Proxy.casino.busy = true
                        Proxy.casinoGlideTo(p.x, p.y)
                        task.wait(0.12)
                        pcall(Proxy.sweepTileDrops, p.x, p.y)
                        Proxy.casino.busy = false
                        Proxy.updateUI()
                    end)
                    Proxy.notify(string.format("`2[TP] Meluncur ke Pos %d (%d, %d)...``", posIdx, p.x + 1, p.y + 1))
                    return true
                else
                    Proxy.notify(string.format("`4[TP] Pos %d belum di-set! Gunakan /pos%d dulu.``", posIdx, posIdx))
                    return true
                end
            end

            if arg1 and arg2 and tonumber(arg1) and tonumber(arg2) then
                -- /tp <x> <y>: Meluncur ke koordinat tile tertentu
                local rawX = tonumber(arg1)
                local rawY = tonumber(arg2)
                local w = getNativeWorld()
                local maxW = (w and w.w) or 100
                local maxH = (w and w.h) or 60

                -- Mendukung koordinat 1-based (sesuai tampilan UI 1..100) maupun 0-based
                local targetX = (rawX >= 1 and rawX <= maxW) and (rawX - 1) or rawX
                local targetY = (rawY >= 1 and rawY <= maxH) and (rawY - 1) or rawY
                targetX = math.clamp(math.floor(targetX), 0, maxW - 1)
                targetY = math.clamp(math.floor(targetY), 0, maxH - 1)

                task.spawn(function()
                    Proxy.casinoGlideTo(targetX, targetY)
                end)
                Proxy.notify(string.format("`2[TP] Meluncur ke koordinat (%d, %d)...``", targetX + 1, targetY + 1))
                return true
            elseif arg1 and not tonumber(arg1) then
                -- /tp <nama_player>: Meluncur ke posisi player
                local targetPlr = nil
                local searchName = arg1:lower()
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer then
                        if p.Name:lower():find(searchName, 1, true) or p.DisplayName:lower():find(searchName, 1, true) then
                            targetPlr = p
                            break
                        end
                    end
                end
                if targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart") then
                    local hrp = targetPlr.Character.HumanoidRootPart
                    local targetX = math.clamp(math.floor(hrp.Position.X / DISPLAY_SIZE), 0, 99)
                    local targetY = math.clamp(math.floor(-hrp.Position.Y / DISPLAY_SIZE), 0, 59)
                    task.spawn(function()
                        Proxy.casinoGlideTo(targetX, targetY)
                    end)
                    Proxy.notify(string.format("`2[TP] Meluncur ke player %s (%d, %d)...``", targetPlr.DisplayName, targetX + 1, targetY + 1))
                    return true
                else
                    Proxy.notify(string.format("`4[TP] Player '%s' tidak ditemukan di world!``", arg1))
                    return true
                end
            else
                -- /tp tanpa argumen: Jalankan validasi & sweep taruhan meja kasino (berhenti di meja terakhir tanpa balik ke host)
                task.spawn(Proxy.runCasinoCollect)
                return true
            end
        end

        local winIdx = cmd:match("^win([1-4])$")
        if winIdx then
            local idx = tonumber(winIdx)
            local customAmt = tonumber(args[1])
            task.spawn(function()
                Proxy.runCasinoPayout(idx, customAmt)
            end)
            return true
        end

        if cmd == "cinfo" then
            local pStr = {}
            for i = 1, 4 do
                local p = Proxy.casino.positions[i]
                if p then
                    local fStr = (p.facing == 1) and "Kanan" or "Kiri"
                    table.insert(pStr, string.format("P%d:(%d,%d|%s)", i, p.x + 1, p.y + 1, fStr))
                    Proxy.showPosMarker(i, p.x, p.y)
                end
            end
            local posList = #pStr > 0 and table.concat(pStr, " ") or "Belum ada pos di-set"
            local hostStr = Proxy.casino.hostPos and string.format("(%d,%d)", Proxy.casino.hostPos.x + 1, Proxy.casino.hostPos.y + 1) or "Belum di-set"
            Proxy.notify(string.format("`3[Casino Info] Host: %s | %s | Tax: %d%%``", hostStr, posList, Proxy.casino.taxRate))
            return true
        end

        if cmd == "creset" then
            Proxy.casino.positions = {}
            Proxy.casino.lastGame = nil
            Proxy.dismissCasinoBanner()
            for i = 1, 4 do
                if Proxy.activePosMarkers[i] and Proxy.activePosMarkers[i].Parent then
                    pcall(function() Proxy.activePosMarkers[i]:Destroy() end)
                    Proxy.activePosMarkers[i] = nil
                end
            end
            Proxy.saveConfig()
            Proxy.notify("`2[Casino] Semua posisi taruhan & data game berhasil di-reset!``")
            Proxy.updateUI()
            return true
        end

        -- 3. UTILITY COMMANDS
        if cmd == "warp" then
            local targetWorld = args[1]
            if targetWorld and targetWorld ~= "" and Proxy.enterWorldFn then
                Proxy.lastWorldName = targetWorld
                if Proxy.setupAutoReloadOnTeleport then Proxy.setupAutoReloadOnTeleport() end
                Proxy.enterWorldFn(targetWorld)
                Proxy.notify("`2[Warp] Berpindah ke world " .. targetWorld .. "...``")
                return true
            else
                Proxy.notify("`4[Warp] Gunakan: /warp <nama world>``")
                return true
            end
        elseif cmd == "rw" then
            if Proxy.lastWorldName ~= "" and Proxy.enterWorldFn then
                if Proxy.setupAutoReloadOnTeleport then Proxy.setupAutoReloadOnTeleport() end
                Proxy.enterWorldFn(Proxy.lastWorldName)
                Proxy.notify("`2[Re-warp] Kembali ke world " .. Proxy.lastWorldName .. "...``")
                return true
            else
                Proxy.notify("`4[Re-warp] Belum ada world sebelumnya!``")
                return true
            end
        elseif cmd == "res" then
            if Proxy.dieFn then
                Proxy.dieFn()
                Proxy.notify("`2[Respawn] Normal respawn dijalankan...``")
                return true
            end
            return true
        elseif cmd == "fpk" then
            Proxy.fastPKEnabled = not Proxy.fastPKEnabled
            pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
            Proxy.notify(Proxy.fastPKEnabled and "`2[Fast Wrench] Diaktifkan (LMB = Pull, RMB = Kick)``" or "`4[Fast Wrench] Dimatikan``")
            Proxy.saveConfig()
            Proxy.updateUI()
            return true
        end

        -- 4. DROP LOCKS
        if cmd == "daw" or cmd == "dropall" or cmd == "dropalllocks" then
            task.spawn(function()
                if not Proxy.onDropFn then
                    Proxy.notify("`4[Drop All] Error: Native drop function belum siap!``")
                    return
                end
                local lockOrder = { "dbgl", "dd", "dw", "dh", "db", "ds" }
                local droppedAny = false
                local summary = {}

                for _, lk in ipairs(lockOrder) do
                    local info = Proxy.LOCKS[lk]
                    if info then
                        local owned = Proxy.getOwnedCount(info.id)
                        if owned > 0 then
                            local ok = pcall(Proxy.onDropFn, info.id, owned)
                            task.wait(0.35)
                            local after = Proxy.getOwnedCount(info.id)
                            local dropped = owned - after
                            if ok and (dropped > 0 or after == 0) then
                                droppedAny = true
                                table.insert(summary, string.format("%d %s", (dropped > 0 and dropped or owned), info.name))
                                pcall(function() if Sfx and Sfx.play then Sfx.play("object_spawn2") end end)
                            end
                        end
                    end
                end

                if droppedAny then
                    Proxy.notify("`2[Drop All] Berhasil drop: " .. table.concat(summary, ", ") .. "!``")
                    task.delay(0.2, Proxy.updateUI)
                else
                    Proxy.notify("`4[Drop All] Kamu tidak memiliki lock apapun di tas!``")
                end
            end)
            return true
        end

        local lockInfo = Proxy.LOCKS[cmd]
        if lockInfo then
            local dropArg = (args[1] or "1"):lower()
            local dropCount = 1
            local owned = Proxy.getOwnedCount(lockInfo.id)
            if owned == 0 then
                Proxy.notify("`4[Drop] Kamu tidak punya " .. lockInfo.name .. " di tas!``")
                return true
            end

            if dropArg == "all" then
                dropCount = owned
            else
                local parsed = tonumber(dropArg)
                if parsed and parsed > 0 then
                    dropCount = math.floor(parsed)
                end
            end

            if dropCount > owned then
                Proxy.notify(string.format("`4[Drop] Jumlah kurang! %s lu cuma ada %d di tas!``", lockInfo.name, owned))
                return true
            end

            if dropCount > 0 and Proxy.onDropFn then
                local ok, err = pcall(function() Proxy.onDropFn(lockInfo.id, dropCount) end)
                if ok then
                    Proxy.notify(string.format("`2[Drop] Berhasil drop %d %s!``", dropCount, lockInfo.name))
                    task.delay(0.2, Proxy.updateUI)
                else
                    Proxy.notify("`4[Drop] Gagal drop: " .. tostring(err) .. "``")
                end
                return true
            end
            return true
        end

        -- 5. GEMS & CONFIG COMMANDS
        if cmd == "rlog" or cmd == "rlogs" then
            Proxy.notify("`b--- HISTORI SPIN ROULETTE ---``")
            local logs = Proxy.rouletteLogs or {}
            if #logs == 0 then
                Proxy.notify("`oBelum ada riwayat spin roulette.``")
            else
                local startIdx = math.max(1, #logs - 9)
                for idx = startIdx, #logs do
                    local l = logs[idx]
                    local tagCol = l.isReal and "`2[REAL]``" or "`4[FAKE]``"
                    local numCol = (l.number == 0) and "`2" or ((l.number <= 18) and "`w" or "`4")
                    Proxy.notify(string.format("[%s] %s `w%s`` -> %s`*%d*``", l.timeStr, tagCol, l.player, numCol, l.number))
                end
            end
            return true
        end

        if cmd == "check" or cmd == "cek" or cmd == "log" or cmd == "logs" or cmd == "history" then
            local targetName = args[1] or ""
            if openMainDialog then openMainDialog() end
            if switchTab then switchTab("proxy") end
            if Proxy.setLoggerSearch then
                Proxy.setLoggerSearch(targetName)
            end
            if targetName ~= "" then
                Proxy.notify(string.format("`2[Logger] Menampilkan catatan histori untuk '%s'``", targetName))
            else
                Proxy.notify("`2[Logger] Menampilkan seluruh catatan histori drop & collect``")
            end
            return true
        end
        if cmd == "banner" or cmd == "promo" or cmd == "teamsys" then
            if showTeamSplashDialog then showTeamSplashDialog() end
            return true
        end
        if cmd == "pgems" or cmd == "pgem" then
            Proxy.punchGemsCheck = not Proxy.punchGemsCheck
            pcall(function() if Sfx and Sfx.play then Sfx.play("click") end end)
            Proxy.notify(Proxy.punchGemsCheck and "`2[Proxy] Punch to Check Gems: ON``" or "`4[Proxy] Punch to Check Gems: OFF``")
            Proxy.saveConfig()
            Proxy.updateUI()
            return true
        end

        if cmd == "gems" then
            local drops = gameDropsTable or findGameDropsTable()
            local gemTiles = {}
            local totalGemsFound = 0
            if drops then
                for _, drop in ipairs(drops) do
                    if type(drop) == "table" and drop.id == 112 and type(drop.x) == "number" and type(drop.y) == "number" then
                        local tx = math.floor(drop.x)
                        local ty = math.floor(drop.y)
                        local key = tx .. "," .. ty
                        if not gemTiles[key] then gemTiles[key] = { tx = tx, ty = ty, total = 0 } end
                        local count = drop.n or 0
                        gemTiles[key].total = gemTiles[key].total + count
                        totalGemsFound = totalGemsFound + count
                    end
                end
            end

            local pileCount = 0
            for _, tileData in pairs(gemTiles) do
                if tileData.total > 0 then
                    pileCount = pileCount + 1
                    Proxy.spawnFloatingDropText(tileData.tx, tileData.ty, 112, tileData.total)
                end
            end

            if pileCount > 0 then
                Proxy.notify(string.format("`2[Gems] Menampilkan ulang floating text untuk %d Gems (%d tumpukan).``", totalGemsFound, pileCount))
            else
                Proxy.notify("`4[Gems] Tidak ada drop gems yang tergeletak di tanah saat ini!``")
            end
            return true
        end

        if cmd == "saveconfig" or cmd == "savecfg" then
            Proxy.saveConfig()
            Proxy.notify("`2[Config] Seluruh konfigurasi fitur & state berhasil disimpan!``")
            return true
        end

        if cmd == "loadconfig" or cmd == "loadcfg" then
            Proxy.loadConfig()
            Proxy.notify("`2[Config] Seluruh konfigurasi fitur & state berhasil dimuat!``")
            return true
        end

        if cmd == "nick" then
            local newNick = rest:match("^%s*(.-)%s*$")
            if not newNick or newNick == "" or newNick:lower() == "reset" then
                LP:SetAttribute("Nick", nil)
                Proxy.saveConfig()
                Proxy.notify("`2[Nick] Nickname berhasil di-reset ke nama asli (" .. LP.Name .. ")!``")
            else
                LP:SetAttribute("Nick", newNick)
                Proxy.saveConfig()
                Proxy.notify("`2[Nick] Streamer mode aktif! Nama disamarkan menjadi: " .. newNick .. "``")
            end
            if Proxy.updateAllPlayerNameTags then
                Proxy.updateAllPlayerNameTags()
            end
            Proxy.updateUI()
            return true
        end

        if cmd == "unnick" then
            LP:SetAttribute("Nick", nil)
            Proxy.saveConfig()
            Proxy.notify("`2[Nick] Nickname berhasil di-reset ke nama asli (" .. LP.Name .. ")!``")
            if Proxy.updateAllPlayerNameTags then
                Proxy.updateAllPlayerNameTags()
            end
            Proxy.updateUI()
            return true
        end

        if oldOnCommand then
            return oldOnCommand(msg)
        end
        return true
    end

    local myOnCommand = chatTableRef.onCommand
    task.spawn(function()
        while scriptAlive do
            task.wait(2.0)
            if not scriptAlive then break end
            if chatTableRef and chatTableRef.onCommand ~= myOnCommand then
                oldOnCommand = chatTableRef.onCommand
                chatTableRef.onCommand = myOnCommand
            end
            if chatTableRef and chatTableRef.add ~= myAdd then
                chatTableRef._origAdd = chatTableRef.add
                chatTableRef.add = myAdd
            end
            if not Proxy._sysproxySayHooked then
                hookOthersSay()
            end
            if not Proxy._sysproxyBubbleHooked then
                hookLocalBubble()
            end
        end
    end)

    _G.CleanGrowbloxCommands = function()
        scriptAlive = false
        autoConvertRunning = false
        Proxy.dismissCasinoBanner()
        if chatTableRef and oldOnCommand then
            chatTableRef.onCommand = oldOnCommand
        end
        if chatTableRef and chatTableRef._origAdd then
            chatTableRef.add = chatTableRef._origAdd
        end
        if worldMenuRef and oldOpenPlayer then
            worldMenuRef.openPlayer = oldOpenPlayer
        end
        if kickConn then
            pcall(function() kickConn:Disconnect() end)
            kickConn = nil
        end
        if gemFloatConn then
            pcall(function() gemFloatConn:Disconnect() end)
            gemFloatConn = nil
        end
        if dropTakenConn then
            pcall(function() dropTakenConn:Disconnect() end)
            dropTakenConn = nil
        end
        pcall(function()
            local pgui = PlayerGui
            local floatGui = pgui and pgui:FindFirstChild("SyshubDropFloatGui")
            if floatGui then floatGui:Destroy() end
        end)
    end

    print("[GrowbloxCommands] ✅ Chat, Casino (v4 Smart Facing Record) & Wrench loaded!")
end)
