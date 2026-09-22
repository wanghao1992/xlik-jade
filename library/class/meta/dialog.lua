--- current class name
DialogClass = "Dialog"

--- 魔兽自带对话框
--- 单人游戏时弹出此框会暂停游戏
---@class Dialog:Meta
local _index = Meta(DialogClass)

--- 对话框(原生)状态
--- 用途: 原生对话框弹出时(单人会暂停游戏)框架记录的鼠标坐标可能停留在弹窗之前的旧位置,
---   于是"点击对话框按钮"的那一次点击会被自定义UI当成"点在弹窗前的UI上"再触发一次
---   (典型: 转生成功的宝物三选一 + 是否继续转职弹窗同时出现时, 三选一被误选/误关)
---   故由UI层(library/japi/lk.lua)在对话期间屏蔽自定义UI的鼠标点击
---@class dialog
dialog = dialog or {}

---@protected 玩家索引 -> 正在向其显示的对话框数量
dialog._shown = dialog._shown or {}

--- 某玩家当前是否有对话框正在显示
---@param player Player
---@return boolean
function dialog.showing(player)
    if (false == class.isObject(player, PlayerClass)) then
        return false
    end
    return (dialog._shown[player:index()] or 0) > 0
end

---@private 记录"本对话框已向该玩家显示"
---@param whichPlayer Player
---@return void
local _markShown = function(self, whichPlayer)
    self._shownTo = self._shownTo or {}
    local index = whichPlayer:index()
    if (nil == self._shownTo[index]) then
        self._shownTo[index] = true
        dialog._shown[index] = (dialog._shown[index] or 0) + 1
    end
end

---@private 注销"本对话框已向该玩家显示"
--- 延迟一个时钟刻度再解除: "点掉对话框按钮"的这一次点击可能同时还在往自定义UI派发,
--- 若在同一瞬间解除, 对话框关闭的那一次点击又会漏到UI上(参见 library/japi/lk.lua 的屏蔽)
---@return void
local _unmarkShown = function(self)
    if (nil == self._shownTo) then
        return
    end
    local shownTo = self._shownTo
    self._shownTo = nil
    local clear = function()
        for index, _ in pairs(shownTo) do
            local left = (dialog._shown[index] or 0) - 1
            if (left > 0) then
                dialog._shown[index] = left
            else
                dialog._shown[index] = nil
            end
        end
    end
    if (sync.is()) then
        time.setTimeout(0, clear)
    else
        clear()
    end
end

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
        --- 回调抛错也必须先销毁对话框: 否则它会留在玩家屏幕上, 且"对话中"的UI点击屏蔽
        --- (见 library/japi/lk.lua)会一直生效, 表现为"鼠标点击不生效"
        local ok, err = pcall(action, evtData)
        class.destroy(triggerDialog)
        if (false == ok) then
            error(err)
        end
    end
end)

---@protected
function _index:destruct()
    _unmarkShown(self)
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
    local pla = whichPlayer
    if (false == class.isObject(pla, PlayerClass)) then
        pla = Player1st()
    end
    J.DialogDisplay(pla:handle(), self._handle, true)
    --- 进入"对话中"状态(该对话框销毁时解除)
    _markShown(self, pla)
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
