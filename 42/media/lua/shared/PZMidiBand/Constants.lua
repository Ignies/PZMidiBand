-- PZMidiBand - shared constants
-- Loaded on both client and server. Keep this file data-only.

PZMidiBand = PZMidiBand or {}

PZMidiBand.MODULE  = "PZMidiBand"
PZMidiBand.VERSION = "0.1.0"

-- Band geometry
PZMidiBand.MAX_RANGE      = 30   -- tiles, band follower cutoff (matches SS14 InstrumentRange)
PZMidiBand.RELAY_CUTOFF   = 36   -- server stops relaying events beyond this
PZMidiBand.NEARBY_QUERY_R = 32   -- radius for "Nearby Bands" search

-- Parser sanitisation (ported from SS14 MidiParser PR #38806)
PZMidiBand.MAX_MIDI_BYTES   = 1024 * 1024   -- 1 MB
PZMidiBand.MAX_TRACKS       = 32
PZMidiBand.MAX_EVENTS       = 100000
PZMidiBand.MAX_CHANNELS     = 16

-- Networking command names (kept short; both directions share this table)
PZMidiBand.CMD = {
    -- client -> server
    CreateBand     = "createBand",
    JoinBand       = "joinBand",
    LeaveBand      = "leaveBand",
    MidiEvent      = "midiEvent",
    BandStart      = "bandStart",
    BandStop       = "bandStop",
    NearbyRequest  = "nearbyRequest",
    ChannelClaim   = "channelClaim",

    -- server -> client
    BandInfo       = "bandInfo",
    NearbyList     = "nearbyList",
    BandEnded      = "bandEnded",
}

-- Wire-format MIDI event kinds (single byte, no string alloc per event)
PZMidiBand.EV = {
    NoteOn         = 1,
    NoteOff        = 2,
    ProgramChange  = 3,
    ControlChange  = 4,
    PitchBend      = 5,
    AllNotesOff    = 6,
    Tempo          = 7, -- d1d2 = microseconds-per-quarter
}

-- One "band" in the world is identified by its master's online-id + a session number
function PZMidiBand.makeBandId(player, session)
    return tostring(player:getOnlineID()) .. "#" .. tostring(session)
end

function PZMidiBand.distTiles(a, b)
    if not a or not b then return math.huge end
    local dx = a:getX() - b:getX()
    local dy = a:getY() - b:getY()
    local dz = a:getZ() - b:getZ()
    if dz ~= 0 then return math.huge end
    return math.sqrt(dx*dx + dy*dy)
end
