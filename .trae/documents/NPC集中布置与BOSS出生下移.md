# NPC 集中布置与 BOSS 出生下移

## 摘要（Summary）
1. 把地图**四角重复**的 4 种功能 NPC（管理员 / 铁匠 / 铁匠铺 / 杂货店）各由 **4 份减为 1 份**，统一横排摆放在**地图中间、偏上**的位置。
2. 新位置需**避开通关后在地图中心生成的两个 NPC**（存档BOSS、爬塔挑战）。
3. 把游戏流程中 **BOSS 出生区域整体下移约 800**（中心 y 由 `-256` → `-1056`）。

## 现状分析（Current State Analysis）

### 四角重复 NPC（每种刷 4 份）
四个 `创建NPC` 进程均由 `游戏流程.lua` 的 `game.flow` 顺序启动，每个进程内 `for i = 1, 4` 在各角落各创建 1 个：

| 进程 | 文件 | 模板 | 当前四角坐标 |
| --- | --- | --- | --- |
| `npcAdmin` | [管理员.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/管理员.lua) | `TPL_UNIT.ADMIN` | (-2818,3712) (2690,3712) (2690,-4160) (-2818,-4160) |
| `npcBlacksmith` | [铁匠.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/铁匠.lua) | `TPL_UNIT.BLACKSMITH` | (-3968,3362) (3840,3362) (3840,-3810) (-3968,-3810) |
| `npcForge` | [铁匠铺.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/铁匠铺.lua) | `TPL_UNIT.FORGE` | (-3968,2962) (3840,2962) (3840,-3410) (-3968,-3410) |
| `npcGrocery` | [杂货店.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/杂货店.lua) | `TPL_UNIT.GROCERY` | (-3968,3712) (3840,3712) (3840,-4160) (-3968,-4160) |

> 说明：用户已确认**只处理这 4 种功能 NPC**；[生命之泉.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/生命之泉.lua)（4 个）与 [四角挑战.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/四角挑战.lua)（4 个挑战怪）**本次不动**。

### 通关后中心两个 NPC（不能受影响）
[存档挑战.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/存档挑战.lua#L899-L913) `saveChallenge.createNpcs()`，通关当刻创建：
- 存档BOSS：`Unit(Player(5), SAVE_CHALLENGE_NPC, -200, 0, 270)`
- 爬塔挑战：`Unit(Player(5), TOWER_CHALLENGE_NPC, 200, 0, 270)`

两者位于 **y = 0**。因此新 NPC 横排需整体放在 y > 0 的上方。

### BOSS 出生区域
[BOSS.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L205-L206)：
```lua
local boss_born_region = Region("boss_born", "square", 0, -256, 2048, 2112)
```
创建 BOSS 时取其中心 `:x()` / `:y()`（`BOSS.lua:210-211`）。
该 `boss_born` 区域仅在本文件内使用，无其它引用。

## 变更方案（Proposed Changes）

### 1. 四个功能 NPC 各保留 1 个，横排于地图中间偏上
**目标坐标（统一 y = 600，x 居中横排）：**

| NPC | 新坐标 |
| --- | --- |
| 管理员 | `(-1200, 600)` |
| 铁匠 | `(-400, 600)` |
| 铁匠铺 | `(400, 600)` |
| 杂货店 | `(1200, 600)` |

- y = 600：在中心（y=0）上方，避开通关后的两个 NPC（y=0）；也在下移后的 BOSS 出生区（顶部 y≈0）之上。
- x 间距 800：容纳较大的建筑模型（杂货店 `Marketplace`、铁匠铺 `Blacksmith`），互不重叠，保持以 x=0 对称居中。
- 朝向 face 保持 270 不变。

**逐文件改动（每个文件：把 4 元素数组改成单个坐标，去掉 `for i = 1, 4` 循环，直接创建 1 个单位）：**

- [管理员.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/管理员.lua)：`adminData` 改为 `{ x = -1200, y = 600, face = 270 }`，`onStart` 内直接创建 1 个 `TPL_UNIT.ADMIN`，`properName` / `teamColor(8)` 保留。
- [铁匠.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/铁匠.lua)：`npcData` 改为 `{ x = -400, y = 600, face = 270 }`，直接创建 1 个 `TPL_UNIT.BLACKSMITH`。
- [铁匠铺.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/铁匠铺.lua)：`npcData` 改为 `{ x = 400, y = 600, face = 270 }`，直接创建 1 个 `TPL_UNIT.FORGE`。
- [杂货店.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/杂货店.lua)：`npcData` 改为 `{ x = 1200, y = 600, face = 270 }`，直接创建 1 个 `TPL_UNIT.GROCERY`。

> `游戏流程.lua` 的 `game.flow` 顺序（`npcAdmin` → `npcBlacksmith` → `npcForge` → `npcGrocery`）**不改动**；进程名不变，链路不受影响。

**示例（管理员.lua 改动后）：**
```lua
local process = Process("npcAdmin")

local npcData = { x = -1200, y = 600, face = 270 }

function process:onStart()
    local npc = Unit(Player(5), TPL_UNIT.ADMIN, npcData.x, npcData.y, npcData.face)

    npc:properName("|cffc0ff11管理一些事情|r")
    npc:teamColor(8)

    self:next()
end
```

### 2. BOSS 出生区域下移约 800
[BOSS.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L205-L206)：中心 y 由 `-256` 改为 `-1056`（下移 800），宽高保持不变：
```lua
--- BOSS出生区域（源 gg_rct_dfjd = Rect(-1024, -1312, 1024, 800)，换算为中心点+宽高; 已整体下移 800）
local boss_born_region = Region("boss_born", "square", 0, -1056, 2048, 2112)
```
同步更新该行上方注释，说明已下移，避免与原始坐标注释矛盾。

## 假设与决定（Assumptions & Decisions）
- 「重复 NPC」范围：**仅**管理员 / 铁匠 / 铁匠铺 / 杂货店（用户确认）。生命之泉、四角挑战怪保持不变。
- 「统一的、只需要一份」理解为：**每种 NPC 各保留 1 个**，横向一字排开（用户确认），而非合并成单个万能 NPC。
- 横排 y 取 **600**（“中间偏上一点”的合理取值），x 取 `-1200 / -400 / 400 / 1200`（间距 800，以 x=0 对称）。若实际观感偏挤/偏散，仅需调整这 4 个 x 值。
- BOSS 下移幅度：**约 800**（用户确认），即中心 y `-256 → -1056`。
- 不改动 `游戏流程.lua` 的进程顺序、NPC 模板（`NPC.lua`）与 NPC 技能逻辑。

## 验证方式（Verification）
1. 静态检查 4 个 `创建NPC` 文件与 `BOSS.lua` 的改动是否符合上表（坐标、无残留 4 元素数组/循环）。
2. 启动 demo 地图（GameFlow 正常跑完 `npcAdmin`~`npcGrocery`）：
   - 四角**不再**出现管理员/铁匠/铁匠铺/杂货店；地图中间偏上出现**各 1 个**、横向排开。
   - 各 NPC 的交互（洗练专属 / 重铸 / 杂货店商品 / 管理员技能）功能正常。
3. 正常流程等待 BOSS 刷新：BOSS 出现在**下移后**的位置（地图中心偏下），出生特效 `AnimateDeadTarget.mdl` 与 BOSS 同点。
4. 通关后确认中心两个 NPC（存档BOSS 于 `(-200,0)`、爬塔挑战于 `(200,0)`）**未被新 NPC 遮挡/侵占**，可正常点击交互。
