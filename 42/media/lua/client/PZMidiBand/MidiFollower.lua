-- PZMidiBand - MidiFollower
-- Receives MIDI events (via OnServerCommand relay) for a band the local player
-- has joined. Renders ONLY the player's claimed channel. This allows multiple players to play together without stepping on each other's programs, at the cost of some flexibility (e.g. no channel switching mid-song).
-- "one channel per follower" model.

require "PZMidiBand/Constants"
PZMidiBand = PZMidiBand or {}
local EV = PZMidiBand.EV

local MidiFollower = {}
MidiFollower.__index = MidiFollower
PZMidiBand.MidiFollower = MidiFollower

function MidiFollower.new(renderer)
    local self = setmetatable({}, MidiFollower)
    self.renderer = renderer
    self.bandId = nil
    self.channel = nil
    self.program = nil      -- local program override (defaults to item's program)
    return self
end

function MidiFollower:join(bandId, channel, programOverride)
    self:leave()
    self.bandId  = bandId
    self.channel = channel
    self.program = programOverride
    if self.renderer and channel and programOverride then
        self.renderer:programChange(channel, programOverride)
    end
end

function MidiFollower:leave()
    if self.renderer then self.renderer:allNotesOff() end
    self.bandId = nil
    self.channel = nil
end

function MidiFollower:isIn(bandId) return self.bandId == bandId end

--- Incoming server-relayed MIDI event.
function MidiFollower:onEvent(e)
    if self.bandId ~= e.bandId then return end
    if e.ev == EV.AllNotesOff then
        if self.renderer then self.renderer:allNotesOff() end
        return
    end
    if e.ch ~= self.channel then return end  -- only our channel
    local r = self.renderer; if not r then return end

    -- Use locally-overridden program, ignore any ProgramChange from master
    if e.ev == EV.NoteOn       then r:noteOn(e.ch, e.d1, e.d2)
    elseif e.ev == EV.NoteOff  then r:noteOff(e.ch, e.d1)
    elseif e.ev == EV.ProgramChange then
        -- Master tried to switch program - ignore, our override wins
    elseif e.ev == EV.ControlChange then r:controlChange(e.ch, e.d1, e.d2)
    elseif e.ev == EV.PitchBend then r:pitchBend(e.ch, (e.d2 * 128 + e.d1) - 8192)
    end
end

return MidiFollower
