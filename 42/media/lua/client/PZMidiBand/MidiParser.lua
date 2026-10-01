-- PZMidiBand - MidiParser
-- Calls into PZMidiBridge to parse a .mid file. The bridge already converts
-- ticks -> absolute microseconds and rejects malformed/oversized files.
--
-- Returned shape (kept compatible with MidiMaster):
--   { events          = { {tick=microseconds, ev, ch, d1, d2}, ... },  -- sorted
--     tempos          = { {tick=0, mpq=1000000} },                     -- synthetic
--     ppq             = 1000000,                                       -- => 1 tick = 1us
--     durationTicks   = totalMicros,
--     channelPrograms = { [0..15] = program },
--     filePath        = path }
-- With ppq=1000000 and mpq=1000000, MidiMaster's existing `secondsToTicks`
-- math degenerates to `seconds * 1000000`, which is exactly what we want.

require "PZMidiBand/Constants"

PZMidiBand = PZMidiBand or {}

local MidiParser = {}
PZMidiBand.MidiParser = MidiParser

local function bridge() return _G.PZMidiBridge end

function MidiParser.load(path)
    local B = bridge()
    if not B then return nil, "PZMidiBridge unavailable - install ZombieBuddy" end

    local n = B.loadMidiFile(path,
        PZMidiBand.MAX_EVENTS,
        PZMidiBand.MAX_TRACKS,
        PZMidiBand.MAX_MIDI_BYTES)
    if n < 0 then return nil, B.getLastError() end

    local events = {}
    for i = 0, n - 1 do
        local t = B.getEventType(i)
        if t ~= 7 then  -- skip embedded tempo markers
            events[#events+1] = {
                tick = B.getEventTimeMicros(i),
                ev   = t,
                ch   = B.getEventCh(i),
                d1   = B.getEventD1(i),
                d2   = B.getEventD2(i),
            }
        end
    end

    local channelPrograms = {}
    for ch = 0, 15 do
        local p = B.getInitialProgram(ch)
        if p > 0 then channelPrograms[ch] = p end
    end

    local totalMicros = B.getTotalMicros()
    B.clearLoaded()

    return {
        events          = events,
        tempos          = { {tick = 0, mpq = 1000000} },
        ppq             = 1000000,
        durationTicks   = totalMicros,
        channelPrograms = channelPrograms,
        filePath        = path,
    }
end

--- Compatibility helper. With our synthetic ppq=1000000 / mpq=1000000,
--- 1 tick == 1 microsecond, so we can just convert directly.
function MidiParser.tickToSeconds(_, _, tick)
    return tick / 1000000
end

return MidiParser
