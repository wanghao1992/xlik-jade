# 移除管理员 / 铁匠铺 / 杂货铺 NPC

## 摘要（Summary）
彻底移除地图中的「管理员」「铁匠铺」「杂货铺」三个功能 NPC：停止在游戏流程中刷出、删除创建脚本、删除 `NPC.lua` 中对应的单位模板，并删除仅被这三个 NPC 使用的技能文件（铁匠铺技能、杂货店技能、刷怪数量增减技能）。与上次移除「铁匠」NPC 的做法保持一致。生命之泉、四角挑战、存档BOSS / 爬塔挑战 NPC 均不受影响。

## 现状分析（Current State Analysis）

### 刷出链路
[游戏流程.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/游戏流程.lua#L11-L13) 的 `game.flow` 顺序启动 `npcAdmin` → `npcForge` → `npcGrocery`，三个进程各自创建 1 个 NPC：

| 进程 | 创建脚本 | 单位模板 | 技能 |
| --- | --- | --- | --- |
| `npcAdmin` | [管理员.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/管理员.lua) | `TPL_UNIT.ADMIN` | `INCREASE_ENEMY` / `DECREASE_ENEMY`（[刷怪数量增减.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/ability/npc/刷怪数量增减.lua)） |
| `npcForge` | [铁匠铺.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/铁匠铺.lua) | `TPL_UNIT.FORGE` | `RecastExclusive` / `SwapUniqueExclusive`（[铁匠铺.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/ability/npc/铁匠铺.lua)） |
| `npcGrocery` | [杂货店.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/杂货店.lua) | `TPL_UNIT.GROCERY` | `ZaHuoDian_1` ~ `ZaHuoDian_11`（[杂货店.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/ability/npc/杂货店.lua)） |

三个 NPC 的坐标为 `管理员(-600,600)`、`铁匠铺(200,600)`、`杂货店(600,600)`，`properName` 分别为「管理一些事情」「重铸专属，替换专属唯一被动」「鞋子与重生」。

### 引用检查（全工程 Grep 结果）
以下标识符**仅**在上述 NPC 创建脚本、`NPC.lua` 模板、对应技能文件自身中出现，无其它模块引用：
- `TPL_UNIT.ADMIN` / `TPL_UNIT.FORGE` / `TPL_UNIT.GROCERY`
- `npcAdmin` / `npcForge` / `npcGrocery`
- `INCREASE_ENEMY` / `DECREASE_ENEMY`
- `RecastExclusive` / `SwapUniqueExclusive`
- `ZaHuoDian_1` ~ `ZaHuoDian_11`

因此移除后不会产生悬空引用。

### 目录现状
- [创建NPC](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC) 目录删除 3 个文件后仍保留 [生命之泉.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建NPC/生命之泉.lua)。
- `globals/tpl/ability/npc` 目录删除 3 个文件后仍保留 `存档BOSS挑战.lua`、`团队BOSS.lua`、`爬塔挑战.lua`。

## 变更方案（Proposed Changes）

### 1. 移除游戏流程中的三个 NPC 进程
[游戏流程.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/游戏流程.lua#L11-L13)：删除以下三行（含缩进与逗号）：

```lua
        "npcAdmin",
        "npcForge",
        "npcGrocery",
```

其余顺序（`save` → `inithero` → `cornerChallenge` → `npcFountain` …）保持不变。

### 2. 删除三个 NPC 创建脚本
删除文件：
- `projects/demo/scripts/process/创建NPC/管理员.lua`
- `projects/demo/scripts/process/创建NPC/铁匠铺.lua`
- `projects/demo/scripts/process/创建NPC/杂货店.lua`

### 3. 删除 `NPC.lua` 中的三个单位模板
[NPC.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/NPC.lua#L9-L52)：删除「管理员」（第 9–19 行）、「铁匠铺」（第 21–31 行）、「杂货店」（第 33–52 行）三块定义，保留文件开头的「生命之泉」以及后面的「存档BOSS」「爬塔挑战」模板。删除后文件内容为：

```lua
--- 生命之泉
TPL_UNIT.FOUNTAIN = UnitTpl('FountainOfHealth', "avatar")
    :name("生命之泉")
    :model("FountainOfHealth")
    :preNoAbilitySlot()
    :preNoAttack()
    :preInvulnerable()

--- 存档BOSS(通关后在地图中心创建, 12 档挑战入口技能挂在它身上; 技能见 tpl/ability/npc/存档BOSS挑战.lua)
--- 模型照老图 物编图/table/unit.ini [n01K]: buildings\other\DragonBuilding\DragonBuilding.mdl
local saveBossAbilities = {}
for i = 1, saveChallenge.count do
    saveBossAbilities[i] = TPL_ABILITY[('CunDangTiaoZhan_%d'):format(i)]
end
TPL_UNIT.SAVE_CHALLENGE_NPC = UnitTpl('DragonRoost', "avatar")
    :name("存档BOSS")
    :model("DragonBuilding")
    :preAbility(saveBossAbilities)
    :preNoAttack()
    :preInvulnerable()

--- 爬塔挑战(通关后在地图中心创建; 1=逐层爬塔, 2=团队BOSS(团本))
--- 模型照老图: buildings\other\DragonBuildingBlue\DragonBuildingBlue.mdl
TPL_UNIT.TOWER_CHALLENGE_NPC = UnitTpl('DragonRoost', "blue")
    :name("爬塔挑战")
    :model("DragonBuildingBlue")
    :preAbility({
        [1] = TPL_ABILITY.PaTaTiaoZhan,
        [2] = TPL_ABILITY.TeamBossTiaoZhan,
    })
    :preNoAttack()
    :preInvulnerable()
```

（实际操作使用 Edit 删除对应段落，不做整文件重写。）

### 4. 删除三个仅供上述 NPC 使用的技能文件
删除文件：
- `projects/demo/scripts/globals/tpl/ability/npc/铁匠铺.lua`（`RecastExclusive` / `SwapUniqueExclusive`）
- `projects/demo/scripts/globals/tpl/ability/npc/杂货店.lua`（`ZaHuoDian_1` ~ `ZaHuoDian_11`）
- `projects/demo/scripts/globals/tpl/ability/npc/刷怪数量增减.lua`（`INCREASE_ENEMY` / `DECREASE_ENEMY`）

## 假设与决定（Assumptions & Decisions）
- 清理范围：用户确认「彻底移除」——流程、创建脚本、单位模板、对应技能文件全部删除。
- 历史文档 [NPC集中布置与BOSS出生下移.md](file:///d:/Lua/xlik-jade/.trae/documents/NPC集中布置与BOSS出生下移.md) 为历史变更记录，**不修改**。
- 不删除 `TPL_ITEM` 中的鞋子 / 重生十字章等物品定义（可能被商城或其它系统复用），只删除杂货店的购买技能。
- 不修改生命之泉、四角挑战、存档BOSS、爬塔挑战相关代码与坐标。
- 遵循项目既有约定：脚本目录自动打包加载，删除文件即不再注册；不运行 `xlik.exe run demo -l!`，打包与进图测试由用户完成。

## 验证方式（Verification）
1. 静态语法检查：对修改后的 `游戏流程.lua`、`globals/tpl/unit/NPC.lua` 执行 `luac -p`（若环境有 luac），确保无语法错误。
2. 全局搜索确认无残留引用：
   - `TPL_UNIT\.(ADMIN|FORGE|GROCERY)`
   - `npcAdmin|npcForge|npcGrocery`
   - `ZaHuoDian|INCREASE_ENEMY|DECREASE_ENEMY|RecastExclusive|SwapUniqueExclusive`
   预期结果：0 条匹配。
3. 确认目录剩余文件：`创建NPC/生命之泉.lua`、`ability/npc/存档BOSS挑战.lua`、`团队BOSS.lua`、`爬塔挑战.lua` 仍存在。
4. 由用户打包进图验证：地图中间偏上不再出现管理员 / 铁匠铺 / 杂货铺；生命之泉、四角挑战、通关后的存档BOSS / 爬塔挑战均正常创建；游戏流程无卡住或报错。
