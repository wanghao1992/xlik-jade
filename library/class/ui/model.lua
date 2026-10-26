--- current class name
UIModelClass = "UIModel"

--- 模型UI
---@class UIModel:UI
local _index = UI(UIModelClass, {
    _autoCast = true,
})

--- 平台原生是否提供模型渲染相关JAPI
--- 线上玩家环境由平台注入的jass.dll原生提供这些方法；本地开发环境缺少，改用 yd_wh_model.dll 桥接
local _native = nil

---@protected
---@return boolean
local function isNative()
    if (nil == _native) then
        _native = japi.Has("FrameSetModelColor")
    end
    return _native
end

--- 平台原生队伍颜色：按贴图槽替换
--- 1=队伍颜色 2=光晕 31=树皮
---@protected
---@return void
local function _nativeTeamColor(self, color)
    local h = self._handle
    japi.FrameSetModelTexture(h, string.format("ReplaceableTextures\\TeamColor\\TeamColor%02d.blp", color), 1)
    japi.FrameSetModelTexture(h, string.format("ReplaceableTextures\\TeamGlow\\TeamGlow%02d.blp", color), 2)
    japi.FrameSetModelTexture(h, "ReplaceableTextures\\LordaeronTree\\LordaeronSummerTree.blp", 31)
end

--- 重设换模型后会丢失的 sprite 级设置
---@protected
---@return void
local function _applySprite(self)
    local h = self._handle
    if (isNative()) then
        --- 平台原生：模型颜色即顶点色，设白色保持贴图原色；原生渲染自带光照，无需挂设置对象
        japi.FrameSetModelColor(h, 0xFFFFFFFF)
    else
        --- 开启光照/粒子
        japi.WhFix(h)
        --- 顶点色保持默认白色，否则模型偏灰
        japi.WhVertexColor(h, 0xFFFFFFFF)
    end
    if (nil ~= self._scale) then
        if (isNative()) then
            japi.FrameSetModelScale(h, self._scale, self._scale, self._scale)
        else
            japi.WhScale(h, self._scale)
        end
    end
    if (nil ~= self._teamColor) then
        if (isNative()) then
            _nativeTeamColor(self, self._teamColor)
        else
            japi.WhTeamColor(h, self._teamColor)
        end
    end
    local r = self._rotate
    if (nil ~= r) then
        --- 应用顺序必须是 Z→Y→X，Z90/Y90 才是已验证的正面朝向
        if (type(r[3]) == "number") then japi.WhRotateZ(h, r[3]) end
        if (type(r[2]) == "number") then japi.WhRotateY(h, r[2]) end
        if (type(r[1]) == "number") then japi.WhRotateX(h, r[1]) end
    end
end

--- 设置模型
---@param path string 模型路径
---@return self
function _index:model(path)
    if (nil ~= path and self._model ~= path) then
        self._model = path
        path = japi.AssetsModel(path)
        japi.DZ_FrameSetModel(self._handle, path, 0, 0)
        --- SPRITE 帧没有光照设置会显示为黑白灰度，本地需挂上与原生头像帧相同的渲染/光照设置
        --- 平台原生环境自带光照，不需要挂；设置挂在帧上，只需挂一次
        if (false == isNative() and true ~= self._lit) then
            self._lit = true
            japi.WhAttachLit(self._handle)
        end
        _applySprite(self)
    end
    return self
end

--- 设置模型缩放比例
---@param ratio number 相对原始尺寸的比例
---@return self
function _index:scale(ratio)
    if (type(ratio) == "number" and self._scale ~= ratio) then
        self._scale = ratio
        if (isNative()) then
            japi.FrameSetModelScale(self._handle, ratio, ratio, ratio)
        else
            japi.WhScale(self._handle, ratio)
        end
    end
    return self
end

--- 设置模型旋转角度，单位角度制；传 nil 表示该项保持原样
---@param x number|nil 滚转
---@param y number|nil 俯仰（90 为正面视角）
---@param z number|nil 水平朝向（90 修正默认朝向）
---@return self
function _index:rotate(x, y, z)
    local last = self._rotate
    --- 换模型时 _applySprite 已重放过同样的旋转，这里跳过以免叠加两次
    if (nil ~= last and last[1] == x and last[2] == y and last[3] == z) then
        return self
    end
    self._rotate = { x, y, z }
    --- 应用顺序必须是 Z→Y→X，Z90/Y90 才是已验证的正面朝向
    if (type(z) == "number") then japi.WhRotateZ(self._handle, z) end
    if (type(y) == "number") then japi.WhRotateY(self._handle, y) end
    if (type(x) == "number") then japi.WhRotateX(self._handle, x) end
    return self
end

--- 设置队伍颜色
---@param color number 玩家颜色索引
---@return self
function _index:teamColor(color)
    if (type(color) == "number" and self._teamColor ~= color) then
        self._teamColor = color
        if (isNative()) then
            _nativeTeamColor(self, color)
        else
            japi.WhTeamColor(self._handle, color)
        end
    end
    return self
end

--- 设置动画
---@param animateId string 动画ID
---@param autoCast boolean 是否自动播放
---@return self
function _index:animate(animateId, autoCast)
    if (type(animateId) == "string" and type(autoCast) == "boolean") then
        self._animateId = animateId
        self._autoCast = autoCast
        japi.DZ_FrameSetAnimate(self._handle, animateId, autoCast)
    end
    return self
end

--- 构造UI模型对象
---@param key string 索引名
---@param parent UI|nil 默认 UI_Game
---@return UIModel
function UIModel(key, parent)
    must(type(key) == "string", "key@string")
    local cache = class.cache(UIModelClass)
    if (nil == cache[key]) then
        cache[key] = oUI({
            _key = key,
            _parent = parent or UIGame,
            _fdfName = "LK_MODEL",
            _fdfType = "SPRITE"
        }, _index)
    end
    return cache[key]
end