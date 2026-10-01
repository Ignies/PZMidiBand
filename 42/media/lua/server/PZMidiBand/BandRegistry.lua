-- PZMidiBand - BandRegistry (server-authoritative)
-- Tracks every active band keyed by bandId. Handles OnClientCommand dispatch
-- for the PZMidiBand module: create/join/leave/event-relay/nearby-query.
--
-- Wire contract (client -> server):
--   createBand      { session }                            -> server assigns bandId, replies with bandInfo
--   joinBand        { bandId, channel, programOverride }   -> replies bandInfo on success
--   leaveBand       { bandId }
--   channelClaim    { bandId, channel }
--   midiEvent       { bandId, ev, ch, d1, d2 }             -> relayed to followers + nearby listeners
--   bandStart       { bandId, programs, songName }         -> relayed verbatim
--   bandStop        { bandId }                             -> relayed verbatim
--   nearbyRequest   {}                                     -> replies nearbyList
--
-- (server -> client):
--   bandInfo    { bandId, masterOnlineId, followers, songName, isMaster }
--   nearbyList  { bands = [{ bandId, masterName, songName, distance, claimed(mask) }] }
--   bandEnded   { bandId }
--   midiEvent   same as incoming (relayed)
--   bandStart   same
--   bandStop    same

require "PZMidiBand/Constants"

PZMidiBand = PZMidiBand or {}
local CMD = PZMidiBand.CMD

local BandRegistry = {}
PZMidiBand.BandRegistry = BandRegistry

-- bands[bandId] = { masterOnlineId, followers = { [onlineId] = channel }, songName, claimedMask }
local bands = {}
-- playersToBand[onlineId] = bandId (only one band per player)
local playersToBand = {}

local function findPlayerByOnlineId(onlineId)
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getOnlineID() == onlineId then return p end
    end
    return nil
end

local function channelMask(followers)
    local mask = 0
    for _, ch in pairs(followers) do
        if ch and ch >= 0 and ch <= 15 then
            mask = mask + (2 ^ ch) - (mask % (2 ^ (ch + 1))) % (2 ^ ch)  -- set bit ch
            -- simpler: recompute
        end
    end
    -- recompute robustly
    mask = 0
    for _, ch in pairs(followers) do
        if ch and ch >= 0 and ch <= 15 then
            local bit = 2 ^ ch
            if (mask % (bit * 2)) - (mask % bit) < bit then mask = mask + bit end
        end
    end
    return mask
end

local function sendBandInfo(band, bandId, targetPlayer)
    local followers = {}
    for oid, ch in pairs(band.followers) do followers[#followers+1] = {onlineId=oid, channel=ch} end
    sendServerCommand(targetPlayer, PZMidiBand.MODULE, CMD.BandInfo, {
        bandId = bandId,
        masterOnlineId = band.masterOnlineId,
        followers = followers,
        songName = band.songName or "",
        claimedMask = band.claimedMask,
        isMaster = targetPlayer:getOnlineID() == band.masterOnlineId,
    })
end

local function endBand(bandId)
    local band = bands[bandId]
    if not band then return end
    -- Notify master + all followers
    local master = findPlayerByOnlineId(band.masterOnlineId)
    if master then
        sendServerCommand(master, PZMidiBand.MODULE, CMD.BandEnded, {bandId=bandId})
        playersToBand[band.masterOnlineId] = nil
    end
    for oid, _ in pairs(band.followers) do
        local p = findPlayerByOnlineId(oid)
        if p then sendServerCommand(p, PZMidiBand.MODULE, CMD.BandEnded, {bandId=bandId}) end
        playersToBand[oid] = nil
    end
    bands[bandId] = nil
end

-- Relay a MIDI event / band-start / band-stop to all band members AND to any
-- non-member listeners within RELAY_CUTOFF of the master (so passers-by hear it).
local function relay(bandId, commandName, args, exceptOnlineId)
    local band = bands[bandId]; if not band then return end
    local master = findPlayerByOnlineId(band.masterOnlineId)
    if not master then endBand(bandId); return end
    args.bandId = bandId

    -- band members
    for oid, _ in pairs(band.followers) do
        if oid ~= exceptOnlineId then
            local p = findPlayerByOnlineId(oid)
            if p then sendServerCommand(p, PZMidiBand.MODULE, commandName, args) end
        end
    end
    if band.masterOnlineId ~= exceptOnlineId then
        sendServerCommand(master, PZMidiBand.MODULE, commandName, args)
    end

    -- passive listeners within range who are NOT in this band
    local players = getOnlinePlayers(); if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local oid = p:getOnlineID()
            if oid ~= band.masterOnlineId and band.followers[oid] == nil then
                local dist = PZMidiBand.distTiles(master, p)
                if dist <= PZMidiBand.RELAY_CUTOFF then
                    sendServerCommand(p, PZMidiBand.MODULE, commandName, args)
                end
            end
        end
    end
end

------------------------------------------------------------
-- Command handlers
------------------------------------------------------------

local handlers = {}

function handlers.createBand(player, args)
    local oid = player:getOnlineID()
    if playersToBand[oid] then return end -- already in a band
    local bandId = PZMidiBand.makeBandId(player, args and args.session or 0)
    bands[bandId] = {
        masterOnlineId = oid,
        followers      = {},
        songName       = "",
        claimedMask    = 0,
    }
    playersToBand[oid] = bandId
    sendBandInfo(bands[bandId], bandId, player)
end

function handlers.joinBand(player, args)
    if not args or not args.bandId then return end
    local band = bands[args.bandId]; if not band then return end
    local oid = player:getOnlineID()
    if playersToBand[oid] and playersToBand[oid] ~= args.bandId then return end
    local ch = tonumber(args.channel)
    if not ch or ch < 0 or ch > 15 then return end

    -- Range check
    local master = findPlayerByOnlineId(band.masterOnlineId)
    if not master or PZMidiBand.distTiles(master, player) > PZMidiBand.MAX_RANGE then return end

    -- Check channel isn't taken
    for _, c in pairs(band.followers) do
        if c == ch then return end
    end
    band.followers[oid] = ch
    band.claimedMask = channelMask(band.followers)
    playersToBand[oid] = args.bandId

    -- Everyone in the band gets an updated bandInfo
    sendBandInfo(band, args.bandId, player)
    local masterP = findPlayerByOnlineId(band.masterOnlineId)
    if masterP then sendBandInfo(band, args.bandId, masterP) end
    for foid, _ in pairs(band.followers) do
        if foid ~= oid then
            local p = findPlayerByOnlineId(foid)
            if p then sendBandInfo(band, args.bandId, p) end
        end
    end
end

function handlers.leaveBand(player, args)
    local oid = player:getOnlineID()
    local bandId = args and args.bandId or playersToBand[oid]
    if not bandId then return end
    local band = bands[bandId]; if not band then return end

    if band.masterOnlineId == oid then
        -- Master left => band ends
        endBand(bandId)
    else
        band.followers[oid] = nil
        band.claimedMask = channelMask(band.followers)
        playersToBand[oid] = nil
        local master = findPlayerByOnlineId(band.masterOnlineId)
        if master then sendBandInfo(band, bandId, master) end
    end
end

function handlers.midiEvent(player, args)
    if not args or not args.bandId then return end
    local band = bands[args.bandId]; if not band then return end
    if band.masterOnlineId ~= player:getOnlineID() then return end -- only master drives
    relay(args.bandId, CMD.MidiEvent, args, player:getOnlineID())
end

function handlers.bandStart(player, args)
    if not args or not args.bandId then return end
    local band = bands[args.bandId]; if not band then return end
    if band.masterOnlineId ~= player:getOnlineID() then return end
    band.songName = tostring(args.songName or "")
    relay(args.bandId, CMD.BandStart, args, player:getOnlineID())
end

function handlers.bandStop(player, args)
    if not args or not args.bandId then return end
    local band = bands[args.bandId]; if not band then return end
    if band.masterOnlineId ~= player:getOnlineID() then return end
    relay(args.bandId, CMD.BandStop, args, player:getOnlineID())
end

function handlers.nearbyRequest(player, args)
    local out = { bands = {} }
    for bandId, band in pairs(bands) do
        local master = findPlayerByOnlineId(band.masterOnlineId)
        if master then
            local d = PZMidiBand.distTiles(master, player)
            if d <= PZMidiBand.NEARBY_QUERY_R then
                out.bands[#out.bands+1] = {
                    bandId      = bandId,
                    masterName  = master:getUsername(),
                    songName    = band.songName or "",
                    distance    = d,
                    claimedMask = band.claimedMask,
                    followerCount = (function()
                        local n = 0; for _ in pairs(band.followers) do n = n + 1 end; return n
                    end)(),
                }
            end
        end
    end
    sendServerCommand(player, PZMidiBand.MODULE, CMD.NearbyList, out)
end

------------------------------------------------------------
-- Event dispatch
------------------------------------------------------------

local function onClientCommand(module, command, player, args)
    if module ~= PZMidiBand.MODULE then return end
    local h = handlers[command]
    if h then h(player, args or {}) end
end

local function onPlayerDisconnect(player)
    if not player then return end
    local oid = player:getOnlineID()
    local bandId = playersToBand[oid]
    if not bandId then return end
    local band = bands[bandId]
    if not band then playersToBand[oid] = nil; return end
    if band.masterOnlineId == oid then
        endBand(bandId)
    else
        band.followers[oid] = nil
        band.claimedMask = channelMask(band.followers)
        playersToBand[oid] = nil
    end
end

Events.OnClientCommand.Add(onClientCommand)
if Events.OnDisconnect         then Events.OnDisconnect.Add(onPlayerDisconnect) end
if Events.OnPlayerDeath        then Events.OnPlayerDeath.Add(onPlayerDisconnect) end
if Events.OnCharacterDeath     then Events.OnCharacterDeath.Add(onPlayerDisconnect) end

return BandRegistry
