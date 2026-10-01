-- PZMidiBand - MidiMaster
-- Drives the tempo clock for a loaded sequence, dispatches events to the
-- local GervillRenderer AND broadcasts them to the server for relay to band
-- followers. Only one master exists per player (you can't lead two bands).

require "PZMidiBand/Constants"
require "PZMidiBand/GMPrograms"

PZMidiBand = PZMidiBand or {}
local EV = PZMidiBand.EV
local CMD = PZMidiBand.CMD

local MidiMaster = {}
MidiMaster.__index = MidiMaster
PZMidiBand.MidiMaster = MidiMaster

local sessionCounter = 0

-- cheap 16-bit bitwise NOT (Kahlua has no bit ops built in on all builds)
local function bit_notmask(mask)
    return (0xFFFF - (mask % 0x10000))
end

function MidiMaster.new(renderer)
    local self = setmetatable({}, MidiMaster)
    self.renderer = renderer
    self.song     = nil   -- parsed sequence data
    self.playing  = false
    self.paused   = false
    self.songTime = 0.0   -- seconds since start of song
    self.cursor   = 1     -- next event index
    self.tempoCursor = 1
    self.mpq      = 500000
    self.lastTempoTick = 0
    self.lastTempoSeconds = 0
    self.bandId   = nil
    self.claimedChannels = 0  -- bitmask of channels claimed by followers
    self.songName = ""
    self.lastDispatchSeconds = 0
    return self
end

function MidiMaster:hasSong() return self.song ~= nil end

function MidiMaster:load(parsed, songName)
    self:stop()
    self.song = parsed
    self.songName = songName or ""
    self.cursor = 1
    self.tempoCursor = 1
    self.mpq = parsed.tempos[1].mpq
    self.lastTempoTick = 0
    self.lastTempoSeconds = 0
    self.songTime = 0
    -- Pre-apply initial program per channel to local renderer
    for ch, prog in pairs(parsed.channelPrograms) do
        if self.renderer then self.renderer:programChange(ch, prog) end
    end
end

function MidiMaster:setBand(bandId, claimedMask)
    self.bandId = bandId
    self.claimedChannels = claimedMask or 0
    -- Mute locally any channels a follower is playing
    if self.renderer then
        self.renderer:setChannelMask(bit_notmask(self.claimedChannels))
    end
end

function MidiMaster:start()
    if not self.song then return end
    self.playing = true
    self.paused = false
    if self.bandId then
        -- Tell followers to reset
        local progs = {}
        for ch, prog in pairs(self.song.channelPrograms) do progs[#progs+1] = {ch=ch, prog=prog} end
        sendClientCommand(PZMidiBand.MODULE, CMD.BandStart, {
            bandId = self.bandId,
            programs = progs,
            songName = self.songName,
        })
    end
end

function MidiMaster:pause() self.paused = true end
function MidiMaster:resume() self.paused = false end

function MidiMaster:stop()
    self.playing = false
    self.paused = false
    self.cursor = 1
    self.tempoCursor = 1
    self.songTime = 0
    if self.renderer then self.renderer:allNotesOff() end
    if self.bandId then
        sendClientCommand(PZMidiBand.MODULE, CMD.MidiEvent, {
            bandId = self.bandId, ev = EV.AllNotesOff, ch = 0, d1 = 0, d2 = 0,
        })
        sendClientCommand(PZMidiBand.MODULE, CMD.BandStop, {bandId = self.bandId})
    end
end

--- Convert elapsed seconds to current tick using tempo map.
local function secondsToTicks(self, seconds)
    local song = self.song
    -- Advance tempoCursor as we pass tempo markers
    while self.tempoCursor + 1 <= #song.tempos do
        local nextTempo = song.tempos[self.tempoCursor + 1]
        local nextSecs = self.lastTempoSeconds
            + ((nextTempo.tick - self.lastTempoTick) * self.mpq) / (song.ppq * 1000000)
        if nextSecs > seconds then break end
        self.lastTempoSeconds = nextSecs
        self.lastTempoTick = nextTempo.tick
        self.mpq = nextTempo.mpq
        self.tempoCursor = self.tempoCursor + 1
    end
    local deltaSecs = seconds - self.lastTempoSeconds
    local deltaTicks = (deltaSecs * song.ppq * 1000000) / self.mpq
    return self.lastTempoTick + deltaTicks
end

local function dispatch(self, e)
    local r = self.renderer
    local bit = 2 ^ e.ch
    local claimed = (self.claimedChannels % (bit * 2)) - (self.claimedChannels % bit) >= bit

    -- Local playback: master only plays channels nobody claimed
    if r and not claimed then
        if e.ev == EV.NoteOn       then r:noteOn(e.ch, e.d1, e.d2)
        elseif e.ev == EV.NoteOff  then r:noteOff(e.ch, e.d1)
        elseif e.ev == EV.ProgramChange then r:programChange(e.ch, e.d1)
        elseif e.ev == EV.ControlChange then r:controlChange(e.ch, e.d1, e.d2)
        elseif e.ev == EV.PitchBend then r:pitchBend(e.ch, (e.d2 * 128 + e.d1) - 8192)
        end
    end

    -- Network: always forward so followers (claimants) can render their channel
    if self.bandId then
        sendClientCommand(PZMidiBand.MODULE, CMD.MidiEvent, {
            bandId = self.bandId, ev = e.ev, ch = e.ch, d1 = e.d1, d2 = e.d2,
        })
    end
end

--- Called every tick from Bootstrap.
function MidiMaster:update(dt)
    if not self.playing or self.paused or not self.song then return end
    self.songTime = self.songTime + dt
    local song = self.song
    local curTick = secondsToTicks(self, self.songTime)

    local events = song.events
    while self.cursor <= #events and events[self.cursor].tick <= curTick do
        dispatch(self, events[self.cursor])
        self.cursor = self.cursor + 1
    end

    -- End of song
    if self.cursor > #events and self.songTime > 0.5 then
        self:stop()
    end
end

return MidiMaster
