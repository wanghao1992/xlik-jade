# xlik 接入内置 JAPI 适配层方案

> 范围：**只做 Lua 适配层**（不改 `exe/**` 的 Go 工具与运行时模板）
> 目标环境：**发布到对战平台**（平台 JAPI 仍为第一优先，内置 JAPI 作为可解析的第二来源）

---

## 一、Summary

xlik 目前把所有「原生 UI 能力」硬编码绑定到 **DZ 平台 JAPI**（`japi.DZ_*` → `japi.Exec("Dz*")`）。本方案在**不改变平台上线行为**的前提下，新增一层「平台无关的归一化入口」，让同一份 `class/ui` 代码可以在 **DZ 平台 JAPI** 或 **内置 JAPI 插件（wenhao_plugin）** 上运行。

核心思路：

```
class/ui  ──►  japi.FrameSetSize(...)          ← 归一化名（新增）
                    │
                    ├─ 解析可用性（惰性 + 缓存）
                    ├─ 平台优先：DzFrameSetSize   （发布到平台，行为不变）
                    └─ 其次：   FrameSetSize      （内置 JAPI 插件）
```

**为什么可行**：xlik 底层 `J.Japi = require("jass.japi")`（`exe/lib/embeds/lua/engine/engine.lua:9`）本身就是**按名字取 native** 的表；而内置 JAPI 与 DZ 的 native **名字只差一个 `Dz` 前缀**（`DzFrameSetSize` ↔ `FrameSetSize`），所以归一化成本很低。

---

## 二、Current State Analysis

### 2.1 现有 japi 分层

| 位置 | 作用 |
|---|---|
| `J.Japi = require("jass.japi")` | Lua 引擎暴露的 native 表（**唯一的真实来源**） |
| `library/japi/_japi.lua` | 门面：`japi.Exec(method, ...)` → `J.Japi[method]`，含存在性检查与 Tips |
| `library/japi/dz.lua` | DZ 平台别名：`japi.DZ_FrameSetSize(...)` → `japi.Exec("DzFrameSetSize", ...)` |
| `library/japi/yd.lua` / `kk.lua` / `lk.lua` | YD / KK / 自实现别名 |
| `library/library.yaml` | 加载顺序 `common → japi → ability → class` + 各文件的混淆规则 |
| `exe/lib/war3.go:88-119` | 生成 `call Cheat("exec-lua:<sha1>")` 注入 `InitGlobals` —— **xlik 已经在用 `exec-lua` 机制启动 Lua** |

### 2.2 UI 层对 DZ 原生的实际依赖（44 处，10 个文件）

| 文件 | 处数 |
|---|---|
| `library/class/ui/_ui.lua` | 21 |
| `library/class/ui/text.lua` | 8 |
| `library/class/ui/_uiNative.lua` | 6 |
| `library/class/ui/drag.lua` | 2 |
| `library/class/ui/model.lua` | 2 |
| `library/class/ui/button.lua` / `backdrop.lua` / `bar.lua` / `label.lua` / `_object.lua` | 各 1 |

去重后**实际用到的 DZ native 只有 17 个**：

| 用途 | DZ native | 内置 JAPI 对应 | 参数一致性 |
|---|---|---|---|
| 根 UI | `DzGetGameUI` | `GetGameUI` | ✅ 均 0 参 |
| 建控件 | `DzCreateFrameByTagName(frameType,name,parent,template,id)` | `CreateFrameByTagName` | ✅ `(SSISI)I` |
| 销毁 | `DzDestroyFrame` | `DestroyFrame` | ✅ |
| 锚点 | `DzFrameClearAllPoints` / `DzFrameSetPoint` | `FrameClearAllPoints` / `FrameSetPoint` | ✅ `(IIIIRR)V` |
| 尺寸 | `DzFrameSetSize` | `FrameSetSize` | ✅ `(IRR)V` |
| 显隐 | `DzFrameShow` | `FrameShow` | ✅ `(IB)V` |
| 透明度 | `DzFrameSetAlpha` | `FrameSetAlpha` | ✅ `(II)V` |
| 贴图 | `DzFrameSetTexture` | `FrameSetTexture` | ✅ `(ISI)V` |
| 文本 | `DzFrameSetText` / `DzFrameSetTextColor` | `FrameSetText` / `FrameSetTextColor` | ✅ |
| 字体 | `DzFrameSetFont(frame,file,height,flag)` | `FrameSetTextFont(frame,file,height)` | ⚠️ **参数个数不同** |
| 文本对齐 | `DzFrameSetTextAlignment` | **无** | ❌ **缺口** |
| 模型 | `DzFrameSetModel(frame,path,type,flag)` | `FrameSetModel` | ✅ `(ISII)V` |
| 模型动画 | `DzFrameSetAnimate(frame,id,auto)` | `FrameSetAnimate` | ✅ `(IIB)V` |
| 鼠标焦点 | `DzGetMouseFocus` | `GetMouseFocus` | ✅ |
| 加载 toc | `DzLoadToc` | `LoadToc` | ✅ `(S)V`（在 `lk.lua:521` 内被调用） |

### 2.3 关键约束

1. **`library/**` 是构建期从磁盘读取合并的**（`library.yaml` 的 `require` 直接列目录），因此只改 `library/**` **不需要重新编译 `xlik.exe`**。
2. **`exe/lib/embeds/lua/**` 是 Go embed 的运行时模板**（含 `setup/mouse*.lua`、`keyboard.lua`、`start/start.lua`），里面的 10 处 `J.Japi["DzTrigger*ByCode"]` / `DzFrameSetUpdateCallbackByCode` **改了要重编 exe** → 本次**不动**。
3. **输入事件是真正的架构成差异**：平台用 `DzTriggerRegister*EventByCode` 注册回调；内置 JAPI 是 hook `WndProc` + `GetTriggerKey/GetWheelDelta` 轮询。若目标环境**只有**内置 JAPI，鼠标/键盘层需要另做适配（超出本次范围，见「六、风险」）。

---

## 三、Proposed Changes

### 变更 1：新增 `library/japi/wh.lua`（内置 JAPI provider）

**做什么**：新建文件，与 `dz.lua`/`yd.lua` 同构，把内置 JAPI 的 native 包成 `japi.WH_*`。

**为什么**：保持「一个 provider 一个文件」的既有约定；便于检索、便于后续扩展到其它内置 native（`EXSetUnitInteger`、`UnlockFps` 等）。

**怎么做**（只列关键条目，其余按同构补齐）：

```lua
--- JAPI自 wh 库，内置 JAPI 插件（wenhao_plugin）方法，方法以 WH_ 开头
--- 该插件的 native 无平台前缀，直接透传给 japi.Exec

---@return number integer
function japi.WH_GetGameUI()
    return japi.Exec("GetGameUI")
end

---@param frameType string
---@param name string
---@param parent number integer
---@param template string
---@param id number integer
---@return number integer
function japi.WH_CreateFrameByTagName(frameType, name, parent, template, id)
    return japi.Exec("CreateFrameByTagName", frameType, name, parent, template, id)
end

---@param frame number integer
function japi.WH_DestroyFrame(frame)
    return japi.Exec("DestroyFrame", frame)
end

---@param frame number integer
function japi.WH_FrameClearAllPoints(frame)
    return japi.Exec("FrameClearAllPoints", frame)
end

---@param frame number integer
---@param point number integer
---@param relativeFrame number integer
---@param relativePoint number integer
---@param x number
---@param y number
function japi.WH_FrameSetPoint(frame, point, relativeFrame, relativePoint, x, y)
    return japi.Exec("FrameSetPoint", frame, point, relativeFrame, relativePoint, x, y)
end

---@param frame number integer
---@param w number
---@param h number
function japi.WH_FrameSetSize(frame, w, h)
    return japi.Exec("FrameSetSize", frame, w, h)
end

---@param frame number integer
---@param enable boolean
function japi.WH_FrameShow(frame, enable)
    return japi.Exec("FrameShow", frame, enable)
end

---@param frame number integer
---@param alpha number integer
function japi.WH_FrameSetAlpha(frame, alpha)
    return japi.Exec("FrameSetAlpha", frame, alpha)
end

---@param frame number integer
---@param texture string
---@param flag number integer
function japi.WH_FrameSetTexture(frame, texture, flag)
    return japi.Exec("FrameSetTexture", frame, texture, flag)
end

---@param frame number integer
---@param text string
function japi.WH_FrameSetText(frame, text)
    return japi.Exec("FrameSetText", frame, text)
end

---@param frame number integer
---@param color number integer
function japi.WH_FrameSetTextColor(frame, color)
    return japi.Exec("FrameSetTextColor", frame, color)
end

---@param frame number integer
---@param fileName string
---@param height number
function japi.WH_FrameSetTextFont(frame, fileName, height)
    return japi.Exec("FrameSetTextFont", frame, fileName, height)
end

---@param frame number integer
---@param modelFile string
---@param modelType number integer
---@param flag number integer
function japi.WH_FrameSetModel(frame, modelFile, modelType, flag)
    return japi.Exec("FrameSetModel", frame, modelFile, modelType, flag)
end

---@param frame number integer
---@param animId number integer
---@param autoCast boolean
function japi.WH_FrameSetAnimate(frame, animId, autoCast)
    return japi.Exec("FrameSetAnimate", frame, animId, autoCast)
end

---@return number integer
function japi.WH_GetMouseFocus()
    return japi.Exec("GetMouseFocus")
end

---@param fileName string
function japi.WH_LoadToc(fileName)
    return japi.Exec("LoadToc", fileName)
end
```

### 变更 2：在 `library/japi/_japi.lua` 追加「归一化层」

**做什么**：在 `japi.Exec` 之后追加：解析顺序常量 + 惰性解析函数 + 显式归一化 shim。

**为什么**：这是整个方案的枢纽——UI 层只依赖归一化名，具体走哪个 provider 由这里决定。

**怎么做**：

```lua
--- 原生实现解析顺序：靠前者优先
--- 发布到平台时保持 { "DZ", "WH" }；若目标环境只有内置 JAPI 可改为 { "WH" }
---@type table
japi._nativeOrder = japi._nativeOrder or { "DZ", "WH" }

---@protected
japi._nativeCache = japi._nativeCache or {}

--- 按候选名解析出「真实存在的 native 名」，结果缓存
---@param uniq string  归一化名（仅作缓存 key）
---@param cands table<string,string>  候选：{ providerPrefix, nativeName }
---@return string
local function resolveNative(uniq, cands)
    local hit = japi._nativeCache[uniq]
    if (hit ~= nil) then
        return hit
    end
    for _, provider in ipairs(japi._nativeOrder) do
        for _, item in ipairs(cands) do
            if (item[1] == provider and type(J.Japi[item[2]]) == "function") then
                japi._nativeCache[uniq] = item[2]
                return item[2]
            end
        end
    end
    -- 全部不可用：退回第一个候选名，交由 japi.Exec 打印一次 Tips
    japi._nativeCache[uniq] = cands[1][2]
    return cands[1][2]
end

--- 平台无关：设置控件尺寸
---@param frame number integer
---@param w number
---@param h number
function japi.FrameSetSize(frame, w, h)
    local n = resolveNative("FrameSetSize", { { "DZ", "DzFrameSetSize" }, { "WH", "FrameSetSize" } })
    return japi.Exec(n, frame, w, h)
end
```

同构补齐其余 16 个归一化 shim：`GetGameUI`、`CreateFrameByTagName`、`DestroyFrame`、`FrameClearAllPoints`、`FrameSetPoint`、`FrameShow`、`FrameSetAlpha`、`FrameSetTexture`、`FrameSetText`、`FrameSetTextColor`、`FrameSetModel`、`FrameSetAnimate`、`GetMouseFocus`、`FrameLoadToc`、以及下面两个「带适配」的：

```lua
--- 平台无关：设置字体（内置 JAPI 无 flag 参数，此处丢弃）
function japi.FrameSetFont(frame, fileName, height, flag)
    local n = resolveNative("FrameSetFont", { { "DZ", "DzFrameSetFont" }, { "WH", "FrameSetTextFont" } })
    if (n == "FrameSetTextFont") then
        return japi.Exec(n, frame, fileName, height)
    end
    return japi.Exec(n, frame, fileName, height, flag)
end

--- 平台无关：设置文本对齐（内置 JAPI 无此能力 → 静默降级）
function japi.FrameSetTextAlignment(frame, align)
    local n = resolveNative("FrameSetTextAlignment", { { "DZ", "DzFrameSetTextAlignment" } })
    if (n == "DzFrameSetTextAlignment" and type(J.Japi[n]) == "function") then
        return japi.Exec(n, frame, align)
    end
    japi.Tips("FrameSetTextAlignmentUnsupported")
    return false
end
```

> `FrameLoadToc` 归一化名**有意避开 `japi.LoadToc`**：后者已被 `lk.lua:516` 占用（且其内部调 `japi.DZ_LoadToc`）。

### 变更 3：改写 UI 层的 44 处调用

**做什么**：把 `library/class/ui/**` 里所有 `japi.DZ_Xxx` 机械替换为归一化名：

| 原调用 | 替换为 |
|---|---|
| `japi.DZ_GetGameUI` | `japi.GetGameUI` |
| `japi.DZ_CreateFrameByTagName` | `japi.CreateFrameByTagName` |
| `japi.DZ_DestroyFrame` | `japi.DestroyFrame` |
| `japi.DZ_FrameClearAllPoints` | `japi.FrameClearAllPoints` |
| `japi.DZ_FrameSetPoint` | `japi.FrameSetPoint` |
| `japi.DZ_FrameSetSize` | `japi.FrameSetSize` |
| `japi.DZ_FrameShow` | `japi.FrameShow` |
| `japi.DZ_FrameSetAlpha` | `japi.FrameSetAlpha` |
| `japi.DZ_FrameSetTexture` | `japi.FrameSetTexture` |
| `japi.DZ_FrameSetText` | `japi.FrameSetText` |
| `japi.DZ_FrameSetTextColor` | `japi.FrameSetTextColor` |
| `japi.DZ_FrameSetFont` | `japi.FrameSetFont` |
| `japi.DZ_FrameSetTextAlignment` | `japi.FrameSetTextAlignment` |
| `japi.DZ_FrameSetModel` | `japi.FrameSetModel` |
| `japi.DZ_FrameSetAnimate` | `japi.FrameSetAnimate` |
| `japi.DZ_GetMouseFocus` | `japi.GetMouseFocus` |

**为什么**：这是「解绑平台」的落地动作；只动函数名，不动逻辑。

**怎么做**：逐文件替换（10 个文件，44 处，均为纯标识符替换）。

**注意**：`library/class/ui/_uiNative.lua:110` 是**模块顶层立即执行**的
`UIGame = UINative("Game", japi.DZ_GetGameUI())`，替换后必须确认归一化层在 `class` 之前已加载（见变更 5）。

### 变更 4：`library/japi/lk.lua:521` 的 toc 加载

**做什么**：把 `japi.DZ_LoadToc(tocFilePath)` 改为归一化调用。

**怎么做**（二选一，推荐前者，改动最小）：
- 改为 `japi.FrameLoadToc(tocFilePath)`；
- 或保持 `japi.LoadToc` 签名不变，仅替换其内部第 521 行。

### 变更 5：`library/japi/wh.lua` 的函数名需补一条混淆规则

**做什么**：在 `library/library.yaml` 的 `encrypt.rules` 末尾追加：

```yaml
    - path: "japi/wh"
      repl: "^function (japi\\.\\w+)\\("
      del: ""
```

**为什么**：现有规则只覆盖 `japi/_japi`、`japi/dz`、`japi/kk`、`japi/lk`、`japi/yd`；新文件不加规则会**漏混淆**（可运行但不符合项目约定）。
**注**：`library.yaml` 的 `require` 已按目录加载 `japi`，**无需**新增 require 项。

---

## 四、Assumptions & Decisions

| 类型 | 内容 |
|---|---|
| 决策 | **平台优先**：`japi._nativeOrder = { "DZ", "WH" }`，保证对战平台上线行为与改动前**完全一致**（回归安全）；只有平台缺席的能力才落到内置 JAPI。切换为内置优先只需改这一个常量。 |
| 决策 | 归一化 shim **显式逐个书写**，不用表驱动 `for` 循环注册。原因：`library.yaml` 的混淆规则是 `^(japi\.\w+) = \|^function (japi\.\w+)\(`，显式函数能被命中，且便于检索与 IDE 跳转。 |
| 决策 | 归一化名 = DZ 名去掉 `Dz` 前缀（如 `DzFrameSetSize` → `FrameSetSize`），与内置 JAPI 原生名一致，便于对照。 |
| 决策 | toc 归一化名用 `japi.FrameLoadToc`，避开已被占用的 `japi.LoadToc`。 |
| 假设 | `library/**` 为构建期从磁盘读取合并，改它**不需要重新编译 `xlik.exe`**（依据：`library.yaml` 的 `require` 直接列目录）。 |
| 假设 | 发布到平台时平台 JAPI 存在；内置 JAPI 是否随图打包由用户现有流程解决（**本方案不改打包**）。 |
| 假设 | 内置 JAPI 的 native 名与其注册表一致（已在二进制层面确认：`CreateFrameByTagName`/`FrameSetSize`/… 无前缀）。 |
| 范围外 | `exe/**`（Go 代码 + `embeds/lua` 运行时模板）与插件打包方式一律不改。 |

---

## 五、Verification

1. **静态检查**
   - `library/` 内 `rg "japi\.DZ_" library/class/ui` 应仅剩 **0 命中**（`japi/dz.lua` 自身的定义不算）。
   - 新文件 `library/japi/wh.lua` 与 `_japi.lua` 的归一化 shim 一一对应，无遗漏（对照变更 1/2 的 17 个名）。
2. **回归（平台环境，必做）**
   - `japi._nativeOrder` 保持 `{ "DZ", "WH" }`，跑 `xlik.exe run <project>`；
   - 打开任一 UI 套件（如 `vendor/assets/war3mapUI/xlik_job`），确认布局/显示/交互与改动前一致。
3. **内置环境**
   - 临时把 `japi._nativeOrder` 改为 `{ "WH" }`，在带插件的环境下跑同一套件，确认控件能创建、能显示、能设尺寸/贴图/文本/模型。
4. **缺口验证**
   - 内置环境下 `japi.FrameSetTextAlignment` 应打印一次 `FrameSetTextAlignmentUnsupported` 且**不报错、不中断**；文本仍能显示（仅对齐可能不符预期）。

---

## 六、风险与后续

| 风险 | 说明 | 建议 |
|---|---|---|
| **输入事件不可归一化** | 平台用 `DzTriggerRegisterMouseEventByCode` / `DzTriggerRegisterKeyEventByCode` / `DzTriggerRegisterMouseWheelEventByCode` / `DzTriggerRegisterWindowResizeEventByCode` / `DzFrameSetUpdateCallbackByCode`（位于 `exe/lib/embeds/lua/**`，共 10 处）；内置 JAPI 走 `WndProc` hook + `GetTriggerKey`/`GetWheelDelta` 轮询，**接口形态不同** | 若目标环境只有内置 JAPI，需单独做「事件层适配」，且需**重编 `xlik.exe`**（超出本方案范围） |
| **文本对齐能力缺口** | 内置 JAPI 无 `FrameSetTextAlignment` 对应 | 已按「静默降级 + Tips 一次」处理；若必须对齐，需在内置环境改用其它方式（如 fdf 模板预置对齐） |
| **字体参数不一致** | `DzFrameSetFont` 有 `flag`，内置 `FrameSetTextFont` 无 | 已在 `japi.FrameSetFont` 内按解析结果丢参 |
| **`UIGame` 顶层求值** | `_uiNative.lua:110` 在模块加载时即调用 `japi.DZ_GetGameUI()` | 归一化层必须在 `class` 之前可用；`library.yaml` 顺序 `common → japi → … → class` 已满足，实施时需复验 |
| **漏改风险** | 44 处分散在 10 个文件 | 用变更 5 的静态检查兜底 |

---

## 七、执行顺序（实施清单）

1. 新建 `library/japi/wh.lua`（变更 1）
2. 在 `library/japi/_japi.lua` 追加归一化层（变更 2）
3. 替换 `library/class/ui/**` 的 44 处调用（变更 3）
4. 改 `library/japi/lk.lua:521`（变更 4）
5. `library/library.yaml` 追加 `japi/wh` 混淆规则（变更 5）
6. 跑「五、Verification」的 1–4 项
