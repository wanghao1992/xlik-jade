--- current class name
DialogClass = "Dialog"

--- 魔兽自带对话框
--- 单人游戏时弹出此框会暂停游戏
---@class Dialog:Meta
local _index = Meta(DialogClass)

local _evt = J.Condition(function()
    ---@type Dialog
    local triggerDialog = class.h2o(J.GetClickedDialog())
    ---@type Array
    local buttons = triggerDialog._buttons
    local evtData = buttons:get(tostring(J.GetClickedButton()))
    local action = triggerDialog._action
    if (type(evtData) == "table" and evtData.type == "nav") then
        if (evtData.action == "prev") then
            triggerDialog:prevPage()
        elseif (evtData.action == "next") then
            triggerDialog:nextPage()
        end
    elseif (type(evtData) == "table" and type(action) == "function") then
        evtData.triggerDialog = triggerDialog
        evtData.triggerPlayer = Player(1 + J.GetPlayerId(J.GetTriggerPlayer()))
        action(evtData)
        class.destroy(triggerDialog)
    end
end)

---@protected
function _index:destruct()
    ---@type Array
    local buttons = self._buttons
    local keys = buttons:keys()
    if (#keys > 0) then
        for _, k in ipairs(keys) do
            J.HandleUnRef(math.round(tonumber(k)))
        end
    end
    self._buttons = nil
    if (self._navButtons) then
        for _, btn in ipairs(self._navButtons) do
            if (btn.handle) then
                J.HandleUnRef(btn.handle)
            end
        end
        self._navButtons = nil
    end
    J.DialogClear(self._handle)
    J.DialogDestroy(self._handle)
    J.HandleUnRef(self._handle)
    class.handle(self, nil)
end

--- 展示，可指定给某玩家
---@param whichPlayer Player|nil
---@return void
function _index:display(whichPlayer)
    if (class.isObject(whichPlayer, PlayerClass)) then
        J.DialogDisplay(whichPlayer:handle(), self._handle, true)
    else
        J.DialogDisplay(Player1st():handle(), self._handle, true)
    end
end

--- 渲染指定页面的按钮
---@param page number
---@return void
function _index:renderPage(page)
    local allButtons = self._allButtons
    local pageSize = self._pageSize
    local totalPages = math.ceil(#allButtons / pageSize)
    
    if (page < 1) then
        page = 1
    elseif (page > totalPages) then
        page = totalPages
    end
    
    self._currentPage = page
    
    local startIndex = (page - 1) * pageSize + 1
    local endIndex = math.min(startIndex + pageSize - 1, #allButtons)
    
    local buttons = self._buttons
    local keys = buttons:keys()
    for _, k in ipairs(keys) do
        J.HandleUnRef(math.round(tonumber(k)))
    end
    buttons:reset()
    
    J.DialogClear(self._handle)
    J.DialogSetMessage(self._handle, self._title)
    
    for i = startIndex, endIndex do
        local bt = allButtons[i]
        local label, value, hotkey
        if (type(bt) == "table") then
            label = bt.label
            value = bt.value
            hotkey = bt.hotkey or bt.value
        else
            label = bt
            value = bt
            hotkey = bt
        end
        local hk = 0
        if (type(hotkey) == "number") then
            hk = hotkey
        elseif (type(hotkey) == "string") then
            hk = string.byte(hotkey, 1)
        end
        local b = J.DialogAddButton(self._handle, label, hk)
        J.HandleRef(b)
        buttons:set(tostring(b), { label = label, value = value })
    end
    
    if (self._navButtons) then
        for _, btn in ipairs(self._navButtons) do
            if (btn.handle) then
                J.HandleUnRef(btn.handle)
            end
        end
    end
    self._navButtons = {}
    
    if (totalPages > 1) then
        if (page > 1) then
            local prevBtn = J.DialogAddButton(self._handle, "上一页", 0)
            J.HandleRef(prevBtn)
            buttons:set(tostring(prevBtn), { type = "nav", action = "prev" })
            table.insert(self._navButtons, { handle = prevBtn, type = "prev" })
        end
        if (page < totalPages) then
            local nextBtn = J.DialogAddButton(self._handle, "下一页", 0)
            J.HandleRef(nextBtn)
            buttons:set(tostring(nextBtn), { type = "nav", action = "next" })
            table.insert(self._navButtons, { handle = nextBtn, type = "next" })
        end
    end
end

--- 下一页
---@return void
function _index:nextPage()
    local totalPages = math.ceil(#self._allButtons / self._pageSize)
    if (self._currentPage < totalPages) then
        self:renderPage(self._currentPage + 1)
        self:display()
    end
end

--- 上一页
---@return void
function _index:prevPage()
    if (self._currentPage > 1) then
        self:renderPage(self._currentPage - 1)
        self:display()
    end
end

--- 构造对话框对象
--[[
    buttons = {
        "第1个",
        "第2个",
        "第3个",
    }
    或
    buttons = {
        { value = "Q", label = "第1个" },
        { value = "W", label = "第2个" },
        { value = "D", label = "第3个" },
    }
]]
---@param title string
---@param buttons string[]|table<number,{value:string,label:string,hotkey:string|number}>
---@param pageSize number|nil 每页按钮数量，默认10
---@param action fun(evtData:{triggerPlayer:Player,triggerDialog:Dialog,label:"标签",value:"值"}):void
---@return Dialog
function Dialog(title, buttons, pageSize, action)
    sync.must()
    must(#buttons > 0, "#buttons must to be greater than 1")
    must(type(action) == "function", "action@DialogFunc")
    local o = oMeta({ _action = action }, _index)
    o._handle = J.DialogCreate()
    class.handle(o, o._handle)
    J.HandleRef(o._handle)
    J.DialogSetMessage(o._handle, title or "标题")
    
    o._allButtons = buttons
    o._pageSize = pageSize or 10
    o._currentPage = 1
    o._navButtons = {}
    o._title = title or "标题"
    
    local bs = Array()
    o._buttons = bs
    
    o:renderPage(1)
    
    event.condition(_evt, function(tgr)
        J.TriggerRegisterDialogEvent(tgr, o._handle)
    end)
    return o
end
