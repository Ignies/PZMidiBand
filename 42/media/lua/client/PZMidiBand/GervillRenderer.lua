-- PZMidiBand - GervillRenderer
-- Wrapper around the PZMidiBridge Java synth. The bridge keeps a single shared
-- Synthesizer; this Lua object holds per-renderer state (volume, channel mask,
-- program cache) and routes calls through the global PZMidiBridge.
--
-- If the bridge is not available (ZombieBuddy missing / mod load failure),
-- every method becomes a silent no-op.

require "PZMidiBand/Constants"

PZMidiBand = PZMidiBand or {}

local function bridge() return _G.PZMidiBridge end

local GervillRenderer = {}
GervillRenderer.__index = GervillRenderer
PZMidiBand.GervillRenderer = GervillRenderer

--- Open the synth (if not already) and load the soundfont. sf2Path may be nil.
function GervillRenderer.new(sf2Path)
    local self = setmetatable({}, GervillRenderer)
    self.open        = false
    self.volume      = 1.0
    self.channelMask = 0xFFFF
    self.programs    = {}

    local B = bridge()
    if not B then
        print("[PZMidiBand] GervillRenderer: PZMidiBridge missing")
        return self
    end

    if not B.openSynth(sf2Path or "") then
        print("[PZMidiBand] openSynth failed: " .. tostring(B.getLastError()))
        return self
    end
    self.open = true
    print("[PZMidiBand] synth open: " .. tostring(B.getSynthName()))
    return self
end

function GervillRenderer:isOpen() return self.open == true end

local function maskAllows(mask, ch)
    local bit = 2 ^ ch
    return ((mask % (bit * 2)) - (mask % bit)) >= bit
end

function GervillRenderer:noteOn(ch, note, vel)
    if not self.open then return end
    if ch < 0 or ch > 15 then return end
    if not maskAllows(self.channelMask, ch) then return end
    local v = math.floor(vel * self.volume + 0.5)
    if v < 0 then v = 0 elseif v > 127 then v = 127 end
    bridge().noteOn(ch, note, v)
end

function GervillRenderer:noteOff(ch, note)
    if not self.open or ch < 0 or ch > 15 then return end
    bridge().noteOff(ch, note)
end

function GervillRenderer:programChange(ch, program)
    if not self.open or ch < 0 or ch > 15 then return end
    self.programs[ch] = program
    bridge().programChange(ch, program)
end

function GervillRenderer:controlChange(ch, controller, value)
    if not self.open or ch < 0 or ch > 15 then return end
    bridge().controlChange(ch, controller, value)
end

--- Lua receives -8192..+8191 from MIDI parser; bridge expects 0..16383 (14-bit).
function GervillRenderer:pitchBend(ch, value)
    if not self.open or ch < 0 or ch > 15 then return end
    local v14 = value + 8192
    if v14 < 0 then v14 = 0 elseif v14 > 16383 then v14 = 16383 end
    bridge().pitchBend(ch, v14)
end

function GervillRenderer:allNotesOff()
    if not self.open then return end
    bridge().allNotesOffAll()
end

function GervillRenderer:setMasterVolume(v)
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    self.volume = v
    if not self.open then return end
    bridge().setMasterVolume(v)
end

function GervillRenderer:setChannelMask(mask)
    self.channelMask = mask
    if not self.open then return end
    for ch = 0, 15 do
        if not maskAllows(mask, ch) then bridge().allNotesOff(ch) end
    end
end

function GervillRenderer:close()
    if not self.open then return end
    self:allNotesOff()
    -- Don't actually close the shared synth here - other Lua-side renderers
    -- may still be using it. Bridge.closeSynth() is reserved for shutdown.
    self.open = false
end

return GervillRenderer
