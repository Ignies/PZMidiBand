-- PZMidiBand - ISMidiBandWindow
-- The main UI shown when a player right-clicks an instrument and chooses
-- "Play MIDI..." (as master) or "Join Nearby Band" (as follower).
--
-- Layout:
--   [ Song label              ]  [ Load ] [ Play ] [ Stop ]
--   [ Band role / id          ]
--   +-- Channels (scrollable) --+    +-- Nearby Bands --+
--   | ch#  program   claim/own |    | master  song  ...|
--   +--------------------------+    +------------------+
--   [ Program override: [dropdown] ]
--   [ Volume --------O---------- ]
--   [ Create Band ] [ Leave Band ] [ Refresh Nearby ]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTickBox"
require "PZMidiBand/Constants"
require "PZMidiBand/GMPrograms"
require "PZMidiBand/MidiParser"
require "PZMidiBand/UI/ISMidiFilePicker"

PZMidiBand = PZMidiBand or {}
local CMD = PZMidiBand.CMD

ISMidiBandWindow = ISCollapsableWindow:derive("ISMidiBandWindow")
PZMidiBand.ISMidiBandWindow = ISMidiBandWindow

local WIN_W, WIN_H = 620, 440

function ISMidiBandWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

local function programItemText(ch, prog, claimant)
    local name = prog and PZMidiBand.gmName(prog) or "(none)"
    local owner = claimant and (" <" .. claimant .. ">") or ""
    return string.format("Ch %2d  %s%s", ch + 1, name, owner)
end

function ISMidiBandWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setTitle("MIDI Band")
    local pad = 8
    local th = self:titleBarHeight()
    local y = th + pad

    -- Header labels
    self.songLabel = ISLabel:new(pad, y, 18, "Song: (none)", 1,1,1,1, UIFont.Medium, true)
    self.songLabel:initialise(); self:addChild(self.songLabel)

    self.roleLabel = ISLabel:new(pad, y + 22, 18, "Solo (offline)", 0.8,0.8,0.8,1, UIFont.Small, true)
    self.roleLabel:initialise(); self:addChild(self.roleLabel)

    -- Top-right buttons
    local btnW = 70
    self.loadBtn = ISButton:new(self.width - pad - 3*btnW - 8, y, btnW, 24, "Load", self, self.onLoad)
    self.loadBtn:initialise(); self:addChild(self.loadBtn)
    self.playBtn = ISButton:new(self.width - pad - 2*btnW - 4, y, btnW, 24, "Play", self, self.onPlay)
    self.playBtn:initialise(); self:addChild(self.playBtn)
    self.stopBtn = ISButton:new(self.width - pad - 1*btnW,     y, btnW, 24, "Stop", self, self.onStop)
    self.stopBtn:initialise(); self:addChild(self.stopBtn)

    y = y + 50

    -- Channel list (left)
    self.channelList = ISScrollingListBox:new(pad, y, 300, 240)
    self.channelList:initialise(); self.channelList:instantiate()
    self.channelList.itemheight = 22
    self.channelList.drawBorder = true
    self:addChild(self.channelList)

    -- Nearby band list (right)
    self.nearbyList = ISScrollingListBox:new(pad + 316, y, self.width - pad - 316 - pad, 240)
    self.nearbyList:initialise(); self.nearbyList:instantiate()
    self.nearbyList.itemheight = 22
    self.nearbyList.drawBorder = true
    self:addChild(self.nearbyList)

    -- Channel actions
    self.claimBtn = ISButton:new(pad, y + 248, 140, 22, "Claim Channel", self, self.onClaim)
    self.claimBtn:initialise(); self:addChild(self.claimBtn)

    -- Program override dropdown
    self.programCombo = ISComboBox:new(pad + 150, y + 248, 150, 22, self, self.onProgramChanged)
    self.programCombo:initialise(); self:addChild(self.programCombo)
    for i = 0, 127 do self.programCombo:addOption(string.format("%03d %s", i, PZMidiBand.gmName(i))) end
    self.programCombo.selected = 1

    -- Nearby actions
    self.joinBtn = ISButton:new(pad + 316, y + 248, 120, 22, "Join Band", self, self.onJoinNearby)
    self.joinBtn:initialise(); self:addChild(self.joinBtn)
    self.refreshBtn = ISButton:new(pad + 316 + 130, y + 248, 100, 22, "Refresh", self, self.onRefreshNearby)
    self.refreshBtn:initialise(); self:addChild(self.refreshBtn)

    y = y + 280

    -- Band control buttons
    self.createBtn = ISButton:new(pad, y, 120, 24, "Create Band", self, self.onCreateBand)
    self.createBtn:initialise(); self:addChild(self.createBtn)
    self.leaveBtn  = ISButton:new(pad + 128, y, 120, 24, "Leave Band", self, self.onLeaveBand)
    self.leaveBtn:initialise(); self:addChild(self.leaveBtn)

    -- Volume slider
    self.volLabel = ISLabel:new(pad + 270, y + 4, 16, "Volume", 1,1,1,1, UIFont.Small, true)
    self.volLabel:initialise(); self:addChild(self.volLabel)

    self:rebuildChannelList()
    self:refreshRole()
end

------------------------------------------------------------
-- Data sync
------------------------------------------------------------

function ISMidiBandWindow:refreshRole()
    local info = PZMidiBand.Client.bandInfo
    if not info then
        self.roleLabel:setName(isClient() and "Solo (no band)" or "Singleplayer")
    elseif info.isMaster then
        self.roleLabel:setName("Master of band " .. tostring(info.bandId))
    else
        self.roleLabel:setName("Follower in band " .. tostring(info.bandId)
            .. " (master online id " .. tostring(info.masterOnlineId) .. ")")
    end
end

function ISMidiBandWindow:rebuildChannelList()
    self.channelList:clear()
    local m = PZMidiBand.Client.master
    if not m or not m:hasSong() then
        self.channelList:addItem("(no song loaded)", nil)
        return
    end
    local info = PZMidiBand.Client.bandInfo
    local byCh = {}  -- ch -> follower-onlineId
    if info and info.followers then
        for _, f in ipairs(info.followers) do byCh[f.channel] = f.onlineId end
    end
    local claimedMask = info and info.claimedMask or 0
    -- list every channel that has events OR a program
    local used = {}
    for ch, _ in pairs(m.song.channelPrograms) do used[ch] = true end
    for _, e in ipairs(m.song.events) do used[e.ch] = true end
    local chs = {}
    for ch, _ in pairs(used) do chs[#chs+1] = ch end
    table.sort(chs)
    for _, ch in ipairs(chs) do
        local prog = m.song.channelPrograms[ch] or 0
        local ownerOid = byCh[ch]
        local ownerName = ownerOid and ("player#" .. tostring(ownerOid)) or nil
        self.channelList:addItem(programItemText(ch, prog, ownerName), { channel = ch, program = prog, ownerOid = ownerOid })
    end
end

------------------------------------------------------------
-- Button handlers
------------------------------------------------------------

function ISMidiBandWindow:onLoad()
    local folder = PZMidiBand.Client.midiFolder
    if not folder or folder == "" then
        self.songLabel:setName("ERROR: midi folder not initialised - check console")
        print("[PZMidiBand] Client.midiFolder is nil - OnGameStart may not have fired")
        return
    end
    ISMidiFilePicker.open(folder, self, function(target, item)
        local parsed, err = PZMidiBand.MidiParser.load(item.path)
        if not parsed then
            print("[PZMidiBand] parse failed: " .. tostring(err))
            if target then target.songLabel:setName("Load failed: " .. tostring(err)) end
            return
        end
        PZMidiBand.Client.master:load(parsed, item.name)
        if target then
            target.songLabel:setName("Song: " .. item.name)
            target:rebuildChannelList()
        end
    end)
end

function ISMidiBandWindow:onPlay()
    PZMidiBand.Client.playLoaded()
end

function ISMidiBandWindow:onStop()
    if PZMidiBand.Client.master then PZMidiBand.Client.master:stop() end
end

function ISMidiBandWindow:onCreateBand()
    if not isClient() then
        self.songLabel:setName((self.songLabel:getName() or "") .. "  (singleplayer - no band needed)")
        return
    end
    sendClientCommand(PZMidiBand.MODULE, CMD.CreateBand, { session = PZMidiBand.Client.newSessionId() })
end

function ISMidiBandWindow:onLeaveBand()
    local info = PZMidiBand.Client.bandInfo
    if not info then return end
    sendClientCommand(PZMidiBand.MODULE, CMD.LeaveBand, { bandId = info.bandId })
end

function ISMidiBandWindow:onClaim()
    local sel = self.channelList.items and self.channelList.items[self.channelList.selected]
    if not sel or not sel.item then return end
    local info = PZMidiBand.Client.bandInfo
    if not info then
        -- not yet in any band; if we're looking at a nearby list selection user should use Join Band instead
        return
    end
    local prog = self.programCombo.selected - 1
    if info.isMaster then
        -- master doesn't "claim" - channels not claimed by followers are master's by default
        return
    end
    -- Re-join our current band on the new channel
    sendClientCommand(PZMidiBand.MODULE, CMD.JoinBand, {
        bandId = info.bandId,
        channel = sel.item.channel,
        programOverride = prog,
    })
    if PZMidiBand.Client.follower then
        PZMidiBand.Client.follower:join(info.bandId, sel.item.channel, prog)
    end
end

function ISMidiBandWindow:onProgramChanged()
    local info = PZMidiBand.Client.bandInfo
    if not info or info.isMaster then return end
    local me
    for _, f in ipairs(info.followers or {}) do
        if f.onlineId == getPlayer():getOnlineID() then me = f; break end
    end
    if not me then return end
    local prog = self.programCombo.selected - 1
    if PZMidiBand.Client.renderer then
        PZMidiBand.Client.renderer:programChange(me.channel, prog)
    end
end

function ISMidiBandWindow:onRefreshNearby()
    if not isClient() then
        self.nearbyList:clear()
        self.nearbyList:addItem("(singleplayer)", nil)
        return
    end
    sendClientCommand(PZMidiBand.MODULE, CMD.NearbyRequest, {})
end

function ISMidiBandWindow:onJoinNearby()
    local sel = self.nearbyList.items and self.nearbyList.items[self.nearbyList.selected]
    if not sel or not sel.item then return end
    -- ask user to pick a free channel - simplest: open the channel list and require a selection
    local chSel = self.channelList.items and self.channelList.items[self.channelList.selected]
    local channel = chSel and chSel.item and chSel.item.channel or 0
    local prog = self.programCombo.selected - 1
    sendClientCommand(PZMidiBand.MODULE, CMD.JoinBand, {
        bandId = sel.item.bandId,
        channel = channel,
        programOverride = prog,
    })
    if PZMidiBand.Client.follower then
        PZMidiBand.Client.follower:join(sel.item.bandId, channel, prog)
    end
end

------------------------------------------------------------
-- Server -> UI callbacks (invoked by Bootstrap)
------------------------------------------------------------

function ISMidiBandWindow:onBandInfo(info)
    self:refreshRole()
    self:rebuildChannelList()
    PZMidiBand.Client.onMaybeAutoStart()
end

function ISMidiBandWindow:onBandEnded(_)
    self:refreshRole()
    self:rebuildChannelList()
end

function ISMidiBandWindow:onNearbyList(payload)
    self.nearbyList:clear()
    if not payload.bands or #payload.bands == 0 then
        self.nearbyList:addItem("(no nearby bands)", nil)
        return
    end
    for _, b in ipairs(payload.bands) do
        local text = string.format("%s  |  %s  (%.1f t, %d members)",
            b.masterName or "?", b.songName ~= "" and b.songName or "(silent)", b.distance or 0, b.followerCount or 0)
        self.nearbyList:addItem(text, b)
    end
end

------------------------------------------------------------
-- Open helper
------------------------------------------------------------

function ISMidiBandWindow.open(defaultProgram)
    if PZMidiBand.Client.window and PZMidiBand.Client.window:getIsVisible() then
        PZMidiBand.Client.window:bringToTop()
        return PZMidiBand.Client.window
    end
    local core = getCore()
    local x = (core:getScreenWidth() - WIN_W) / 2
    local y = (core:getScreenHeight() - WIN_H) / 2
    local o = ISMidiBandWindow:new(x, y, WIN_W, WIN_H)
    o:initialise()
    o:addToUIManager()
    if defaultProgram and defaultProgram >= 0 and defaultProgram <= 127 then
        o.programCombo.selected = defaultProgram + 1
    end
    PZMidiBand.Client.window = o
    -- kick off nearby query
    o:onRefreshNearby()
    return o
end

return ISMidiBandWindow
