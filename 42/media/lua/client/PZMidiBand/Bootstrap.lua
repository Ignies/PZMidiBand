-- PZMidiBand - Bootstrap
-- Initialises per-player client state. All Java interop goes through the
-- PZMidiBridge global supplied by the mod's companion JAR (loaded by
-- ZombieBuddy).

require "PZMidiBand/Constants"
require "PZMidiBand/GMPrograms"
require "PZMidiBand/InstrumentMap"
require "PZMidiBand/GervillRenderer"
require "PZMidiBand/MidiParser"
require "PZMidiBand/MidiMaster"
require "PZMidiBand/MidiFollower"

PZMidiBand = PZMidiBand or {}
local CMD = PZMidiBand.CMD

PZMidiBand.Client = PZMidiBand.Client or {
    renderer = nil,
    master   = nil,
    follower = nil,
    bandInfo = nil,
    window   = nil,
    sessionCounter = 0,
    midiFolder = nil,
    soundfontPath = nil,
    lastTickTime = 0,
}

local Client = PZMidiBand.Client

------------------------------------------------------------
-- Bridge resolver (set once at OnGameStart)
------------------------------------------------------------

local function resolveBridge()
    if _G.PZMidiBridge then return _G.PZMidiBridge end
    if _G.Packages then
        local ok, b = pcall(function() return Packages.com.ports.pzmidiband.PZMidiBridge end)
        if ok and b then return b end
    end
    return nil
end

------------------------------------------------------------
-- Paths
------------------------------------------------------------

local function ensureMidiFolder(B)
    local zomboid = B.getZomboidDir()
    local folder = tostring(zomboid) .. "/midi"
    B.mkdirs(folder)
    Client.midiFolder = folder
    print("[PZMidiBand] midi folder: " .. folder)
    return folder
end

local function resolveSoundfont(B)
    local zomboid = tostring(B.getZomboidDir())
    local candidates = {
        -- User override: drop any .sf2 as Zomboid/midi/soundfont.sf2
        zomboid .. "/midi/soundfont.sf2",
        -- Bundled SF2 inside the mod (B42 versioned layout)
        zomboid .. "/mods/PZMidiBand/42/media/soundfonts/soundfont.sf2",
        -- Fallback for non-versioned layouts
        zomboid .. "/mods/PZMidiBand/media/soundfonts/soundfont.sf2",
        zomboid .. "/Workshop/PZMidiBand/42/media/soundfonts/soundfont.sf2",
    }
    for _, p in ipairs(candidates) do
        if B.fileExists(p) then
            print("[PZMidiBand] soundfont -> " .. p)
            return p
        end
    end
    print("[PZMidiBand] no soundfont found (tried " .. #candidates .. " paths); falling back to Gervill default")
    return nil
end

------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------

local function onGameStart()
    local B = resolveBridge()
    if not B then
        print("[PZMidiBand] FATAL: PZMidiBridge not available - is ZombieBuddy installed and enabled?")
        return
    end
    PZMidiBand.Bridge = B
    ensureMidiFolder(B)
    Client.soundfontPath = resolveSoundfont(B)
    Client.renderer = PZMidiBand.GervillRenderer.new(Client.soundfontPath)
    Client.master   = PZMidiBand.MidiMaster.new(Client.renderer)
    Client.follower = PZMidiBand.MidiFollower.new(Client.renderer)
    Client.lastTickTime = getTimestampMs and getTimestampMs() or 0
    print("[PZMidiBand] client initialised (sf2=" .. tostring(Client.soundfontPath or "builtin") .. ")")
end

local function onGameEnd()
    if Client.master then Client.master:stop() end
    if Client.follower then Client.follower:leave() end
    if Client.renderer then Client.renderer:close() end
    Client.renderer = nil
    Client.master = nil
    Client.follower = nil
end

------------------------------------------------------------
-- Tick loop (drives MidiMaster playback)
------------------------------------------------------------

local function onTick()
    if not Client.master then return end
    local nowMs
    if getTimestampMs then nowMs = getTimestampMs()
    else nowMs = os.time() * 1000 end
    local last = Client.lastTickTime or nowMs
    local dtMs = nowMs - last
    if dtMs < 0 or dtMs > 250 then dtMs = 16 end
    Client.lastTickTime = nowMs
    local dt = dtMs / 1000.0

    Client.master:update(dt)

    if Client.bandInfo and not Client.bandInfo.isMaster and Client.renderer then
        local me = getPlayer()
        local master = nil
        if Client.bandInfo.masterOnlineId then
            local players = getOnlinePlayers()
            if players then
                for i = 0, players:size() - 1 do
                    local p = players:get(i)
                    if p and p:getOnlineID() == Client.bandInfo.masterOnlineId then master = p; break end
                end
            end
        end
        if me and master then
            local d = PZMidiBand.distTiles(me, master)
            local t = d / PZMidiBand.MAX_RANGE
            if t > 1 then t = 1 end
            local v = (1 - t); v = v * v
            Client.renderer:setMasterVolume(v)
        end
    end
end

------------------------------------------------------------
-- Server -> client dispatch
------------------------------------------------------------

local serverHandlers = {}

function serverHandlers.bandInfo(args)
    Client.bandInfo = args
    if args.isMaster and Client.master then
        Client.master.bandId = args.bandId
        Client.master.claimedChannels = args.claimedMask or 0
        if Client.renderer then
            local notMask = 0xFFFF - (args.claimedMask or 0)
            Client.renderer:setChannelMask(notMask)
        end
    end
    if Client.window and Client.window.onBandInfo then Client.window:onBandInfo(args) end
end

function serverHandlers.bandEnded(args)
    if Client.follower then Client.follower:leave() end
    if Client.master and Client.master.bandId == args.bandId then
        Client.master:stop()
        Client.master.bandId = nil
        Client.master.claimedChannels = 0
    end
    Client.bandInfo = nil
    if Client.window and Client.window.onBandEnded then Client.window:onBandEnded(args) end
end

function serverHandlers.bandStart(args)
    if Client.follower and Client.follower:isIn(args.bandId) then
        if Client.renderer then Client.renderer:allNotesOff() end
    end
end

function serverHandlers.bandStop(args)
    if Client.follower and Client.follower:isIn(args.bandId) then
        if Client.renderer then Client.renderer:allNotesOff() end
    end
end

function serverHandlers.midiEvent(args)
    if Client.follower and Client.follower:isIn(args.bandId) then
        Client.follower:onEvent(args)
    else
        if not Client.renderer then return end
        local r = Client.renderer
        local EV = PZMidiBand.EV
        if args.ev == EV.AllNotesOff then r:allNotesOff()
        elseif args.ev == EV.NoteOn then r:noteOn(args.ch, args.d1, args.d2)
        elseif args.ev == EV.NoteOff then r:noteOff(args.ch, args.d1)
        elseif args.ev == EV.ProgramChange then r:programChange(args.ch, args.d1)
        elseif args.ev == EV.ControlChange then r:controlChange(args.ch, args.d1, args.d2)
        elseif args.ev == EV.PitchBend then r:pitchBend(args.ch, (args.d2 * 128 + args.d1) - 8192)
        end
    end
end

function serverHandlers.nearbyList(args)
    if Client.window and Client.window.onNearbyList then Client.window:onNearbyList(args) end
end

local function onServerCommand(module, command, args)
    if module ~= PZMidiBand.MODULE then return end
    local h = serverHandlers[command]
    if h then h(args or {}) end
end

------------------------------------------------------------
-- Solo / band control
------------------------------------------------------------

function PZMidiBand.Client.newSessionId()
    Client.sessionCounter = Client.sessionCounter + 1
    return Client.sessionCounter
end

function PZMidiBand.Client.playLoaded()
    local m = Client.master
    if not m or not m:hasSong() then return end
    if isClient() and not (Client.bandInfo and Client.bandInfo.isMaster) then
        sendClientCommand(PZMidiBand.MODULE, CMD.CreateBand, { session = PZMidiBand.Client.newSessionId() })
        m._pendingStart = true
    else
        m:start()
    end
end

function PZMidiBand.Client.onMaybeAutoStart()
    local m = Client.master
    if m and m._pendingStart and Client.bandInfo and Client.bandInfo.isMaster then
        m._pendingStart = nil
        m:start()
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onGameEnd)
Events.OnTick.Add(onTick)
Events.OnServerCommand.Add(onServerCommand)
-- PZMidiBand - Bootstrap