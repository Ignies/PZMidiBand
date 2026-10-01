-- PZMidiBand - Instrument item whitelist and default GM program per item.
-- Keys are PZ fullType strings. Values are GM program numbers (0-127).
-- Nade's Craftable Instruments (Workshop 3564084857) entries are included but
-- only activate if that mod is loaded - we simply probe ScriptManager at runtime.

PZMidiBand = PZMidiBand or {}

PZMidiBand.INSTRUMENTS = {
    -- Base Project Zomboid (B41 + B42 names)
    ["Base.Guitar"]                          = 25, -- Acoustic Steel
    ["Base.GuitarElectric"]                  = 27, -- B42 plain electric
    ["Base.GuitarElectricBlack"]             = 27, -- B41 color variants
    ["Base.GuitarElectricRed"]               = 27,
    ["Base.GuitarElectricBlue"]              = 27,
    ["Base.GuitarAcoustic"]                  = 24, -- Nylon
    ["Base.GuitarElectricBass"]              = 33, -- B42 plain bass
    ["Base.GuitarElectricBassBlack"]         = 33,
    ["Base.GuitarElectricBassBlue"]          = 33,
    ["Base.GuitarElectricBassRed"]           = 33,
    ["Base.Banjo"]                           = 105,
    ["Base.Ukulele"]                         = 24,

    -- Nade's Craftable Instruments (Mod ID: NadesCraftableInstruments)
    ["NadesCraftableInstruments.AcousticGuitar"]     = 24,
    ["NadesCraftableInstruments.ElectricGuitar"]     = 27,
    ["NadesCraftableInstruments.ElectricBassGuitar"] = 33,
    ["NadesCraftableInstruments.Trumpet"]            = 56,
    ["NadesCraftableInstruments.Saxophone"]          = 66, -- Tenor Sax
    ["NadesCraftableInstruments.Harmonica"]          = 22,
    ["NadesCraftableInstruments.Keytar"]             = 80, -- Lead Square
    ["NadesCraftableInstruments.Flute"]              = 73,
    ["NadesCraftableInstruments.Banjo"]              = 105,
    ["NadesCraftableInstruments.Violin"]             = 40,
}

function PZMidiBand.getDefaultProgram(fullType)
    return PZMidiBand.INSTRUMENTS[fullType]
end

function PZMidiBand.isInstrument(fullType)
    return PZMidiBand.INSTRUMENTS[fullType] ~= nil
end
