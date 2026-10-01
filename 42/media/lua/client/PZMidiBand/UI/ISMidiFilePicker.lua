-- PZMidiBand - ISFilePicker
-- Minimalist file browser scoped to the PZ Zomboid/midi/ folder.
-- All filesystem access goes through PZMidiBridge.listDir / parentDir.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"

PZMidiBand = PZMidiBand or {}

local function bridge() return _G.PZMidiBridge end

ISMidiFilePicker = ISCollapsableWindow:derive("ISMidiFilePicker")

function ISMidiFilePicker:initialise()
    ISCollapsableWindow.initialise(self)
end

function ISMidiFilePicker:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.currentFolder = self.currentFolder or self.folder
    self:updateTitle()

    local th = self:titleBarHeight()
    local pad = 8
    local y = th + pad

    self.list = ISScrollingListBox:new(pad, y, self.width - 2*pad, self.height - y - 64)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 22
    self.list.doDrawItem = self.drawFileItem
    self.list.drawBorder = true
    self.list.target = self
    self.list.onmousedblclick = function(target, item) target:onActivate({ item = item }) end
    self:addChild(self.list)

    self.loadBtn = ISButton:new(self.width - 180, self.height - 32, 80, 24, "Load", self, ISMidiFilePicker.onLoad)
    self.loadBtn:initialise(); self:addChild(self.loadBtn)
    self.cancelBtn = ISButton:new(self.width - 90, self.height - 32, 80, 24, "Cancel", self, ISMidiFilePicker.onCancel)
    self.cancelBtn:initialise(); self:addChild(self.cancelBtn)

    self:refresh()
end

function ISMidiFilePicker:updateTitle()
    local rel = string.sub(self.currentFolder or "", #self.folder + 1)
    if rel == "" then rel = "/" end
    self:setTitle("Load MIDI - midi" .. rel)
end

function ISMidiFilePicker:refresh()
    self.list:clear()
    local B = bridge()
    if not B then
        self.list:addItem("ERROR: PZMidiBridge missing (install ZombieBuddy)", nil)
        return
    end

    -- ".." entry if we're below the root
    if self.currentFolder ~= self.folder then
        local parent = B.parentDir(self.currentFolder)
        if parent and parent ~= "" then
            self.list:addItem("[..]  (up one folder)", { isDir = true, path = parent })
        end
    end

    local arr = B.listDir(self.currentFolder)
    if not arr then
        self.list:addItem("(folder does not exist: " .. tostring(self.currentFolder) .. ")", nil)
        return
    end

    -- arr is a Java Object[] of [name, kind, name, kind, ...]. Determine
    -- length: Java arrays expose `.length` when bridged, but Kahlua's
    -- handling varies, so we fall back to walking until nil.
    local size = 0
    pcall(function() size = arr.length or 0 end)
    if size == 0 then
        local i = 0
        while true do
            local v = nil
            local ok = pcall(function() v = arr[i] end)
            if not ok or v == nil then break end
            size = size + 1; i = i + 1
        end
    end

    local function get(i)
        local v
        local ok = pcall(function() v = arr[i] end)
        if ok then return v end
        return nil
    end

    local dirs, midis = {}, {}
    local n = 1
    while arr and arr[n] do
        local name = arr[n]
        local kind = arr[n+1]
        n = n + 2
        if name and kind then
            local path = self.currentFolder .. "/" .. tostring(name)
            if tostring(kind) == "D" then
                dirs[#dirs+1] = { name = tostring(name), path = path }
            elseif tostring(kind) == "F" then
                local lower = string.lower(tostring(name))
                if string.sub(lower, -4) == ".mid" or string.sub(lower, -5) == ".midi" then
                    midis[#midis+1] = { name = tostring(name), path = path }
                end
            end
        end
    end

    table.sort(dirs,  function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    table.sort(midis, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    for _, d in ipairs(dirs)  do self.list:addItem("[+] " .. d.name, { isDir = true,  path = d.path }) end
    for _, m in ipairs(midis) do self.list:addItem(m.name,         { isDir = false, name = m.name, path = m.path }) end

    if self.list.items and #self.list.items == 0 then
        self.list:addItem("(no .mid files or subfolders here)", nil)
    end
    self:updateTitle()
end

function ISMidiFilePicker:onActivate(item)
    if not item or not item.item then return end
    if item.item.isDir then
        self.currentFolder = item.item.path
        self:refresh()
    else
        if self.onPick then self.onPick(self.pickTarget, item.item) end
        self:setVisible(false); self:removeFromUIManager()
    end
end

function ISMidiFilePicker:drawFileItem(y, item, alt)
    local a = 0.9
    self:drawRectBorder(0, (y), self:getWidth(), self.itemheight - 1, a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    self:drawText(item.text, 8, y + 3, 1, 1, 1, a, UIFont.Small)
    return y + self.itemheight
end

function ISMidiFilePicker:onLoad()
    local sel = self.list.items and self.list.items[self.list.selected]
    if not sel or not sel.item then return end
    self:onActivate(sel)
end

function ISMidiFilePicker:onCancel()
    self:setVisible(false); self:removeFromUIManager()
end

function ISMidiFilePicker.open(folder, target, callback)
    local core = getCore()
    local w, h = 480, 360
    local x = (core:getScreenWidth() - w) / 2
    local y = (core:getScreenHeight() - h) / 2
    local o = ISMidiFilePicker:new(x, y, w, h)
    o.folder = folder
    o.pickTarget = target
    o.onPick = callback
    o:initialise()
    o:addToUIManager()
    return o
end

return ISMidiFilePicker