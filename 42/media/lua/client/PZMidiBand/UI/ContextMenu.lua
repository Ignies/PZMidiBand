-- PZMidiBand - ContextMenu
-- Adds "Play MIDI..." and "Change Instrument Sound" to right-click context
-- menus of any item whose fullType is in PZMidiBand.INSTRUMENTS.

require "PZMidiBand/Constants"
require "PZMidiBand/InstrumentMap"
require "PZMidiBand/GMPrograms"
require "PZMidiBand/UI/ISMidiBandWindow"

PZMidiBand = PZMidiBand or {}

local function onPlayMidi(playerNum, item, program)
    local w = ISMidiBandWindow.open(program)
    -- store the item association for later "Change Instrument Sound" persistence
    w.instrumentItem = item
end

local function onChangeSound(playerNum, item, program)
    if not item then return end
    local md = item:getModData()
    md.PZMidiBand_Program = program
    -- apply live if we're already in a band
    local info = PZMidiBand and PZMidiBand.Client and PZMidiBand.Client.bandInfo
    if info and not info.isMaster and PZMidiBand.Client.renderer then
        for _, f in ipairs(info.followers or {}) do
            if f.onlineId == getPlayer(playerNum):getOnlineID() then
                PZMidiBand.Client.renderer:programChange(f.channel, program)
                break
            end
        end
    end
end

local function addChangeSoundSubmenu(parentMenu, playerNum, item)
    local sub = ISContextMenu:getNew(parentMenu)
    local parent = parentMenu:addOption(getText and getText("ContextMenu_PZMidiBand_ChangeSound") or "Change Instrument Sound", item, nil)
    parentMenu:addSubMenu(parent, sub)
    -- Grouped by GM family
    local groups = {
        {"Piano / Keys",     {0,1,2,3,4,5,6,7}},
        {"Chromatic Perc.",  {8,9,10,11,12,13,14,15}},
        {"Organ",            {16,17,18,19,20,21,22,23}},
        {"Guitar",           {24,25,26,27,28,29,30,31}},
        {"Bass",             {32,33,34,35,36,37,38,39}},
        {"Strings",          {40,41,42,43,44,45,46,47,48,49,50,51}},
        {"Brass",            {56,57,58,59,60,61,62,63}},
        {"Reed",             {64,65,66,67,68,69,70,71}},
        {"Pipe",             {72,73,74,75,76,77,78,79}},
        {"Synth Lead",       {80,81,82,83,84,85,86,87}},
        {"Synth Pad",        {88,89,90,91,92,93,94,95}},
        {"Ethnic",           {104,105,106,107,108,109,110,111}},
    }
    for _, g in ipairs(groups) do
        local gsub = ISContextMenu:getNew(sub)
        local gparent = sub:addOption(g[1], item, nil)
        sub:addSubMenu(gparent, gsub)
        for _, p in ipairs(g[2]) do
            gsub:addOption(string.format("%03d %s", p, PZMidiBand.gmName(p)), playerNum, onChangeSound, item, p)
        end
    end
end

local function onFillInventoryContextMenu(playerNum, context, items)
    if not items or #items == 0 then return end
    local item = items[1]
    if instanceof and instanceof(item, "InventoryItem") == false and item.items then
        item = item.items[1]
    end
    if not item or not item.getFullType then return end
    local fullType = item:getFullType()
    if not PZMidiBand.isInstrument(fullType) then return end

    local md = item:getModData()
    local program = md.PZMidiBand_Program or PZMidiBand.getDefaultProgram(fullType) or 0

    context:addOption(getText and getText("ContextMenu_PZMidiBand_Play") or "Play MIDI...", playerNum, onPlayMidi, item, program)
    addChangeSoundSubmenu(context, playerNum, item)
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryContextMenu)
