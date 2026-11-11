# 英雄平衡 P1（机制上限）实施规格

- 状态：已完成（2026-11-11）
- 范围：只做 P1「收顶部 + 叠层上限统一」，即报告第五节第 6~12 项
- 不在本轮：P0/P2 已完成的改动不回退；底部 14 名 1253~1486 的英雄不做二次微调
- 验收口径：L30、攻击 300、2.0 APS、暴击 25%/150%、HP 8000、60 秒单体木桩
- 目标：4 个顶部英雄与死骑回到 1600~2600；神灵武士因「木桩可长期残血」单独放宽到 2600~3000

## 1. 验收步骤

1. 在 `d:\Lua\xlik-jade\tools\hero_dps_sim` 运行：
   - `python sim.py --kills 1000 --csv results_1000_fixed.csv`
   - `python sim.py --kills 0 --csv results_0_fixed.csv`
2. 核对：大法师/风暴之灵/月骑/死骑落在 1600~2600，神灵武士落在 2600~3000，其余英雄不因叠层统一而跌出原区间
3. 更新 `d:\Lua\xlik-jade\.trae\documents\英雄同属性秒伤模拟报告.md` 的「一、结论摘要」「三、结果总表」「五、调整建议 P1 状态」
4. 环境无 Lua 解释器，只能人工核对语法；结论中提示进游戏验收

## 2. 逐项改动

### 2.1 神灵武士·狂战士之血：给残血收益加硬上限

**文件：`projects/demo/scripts/globals/tpl/ability/职业/神灵武士/狂战士之血.lua`**

```lua
local lv = job.level(hero)
--- 攻速最多 +100（3.0 APS），攻击最多 +150
local speed = math.min(lost * 3, 100)
local attack = math.min(hero:str() * (0.01 + 0.002 * lv) * lost, 150)
```

描述改为：

```lua
"每损失1%的生命值增加3%的攻击速度与力量*(1% + 0.2% * 英雄等级)的攻击力",
"攻击速度最多增加100,攻击力最多增加150",
```

> 与报告建议的 +300/+150 不同：实测 +300/+150 在木桩下仍有 3869，超出 2600~3000。取 +150/+100 后约 2799。

### 2.2 神灵武士·沸血之矛：DoT 计时器与 Buff 生命周期解耦

**文件：`projects/demo/scripts/globals/tpl/ability/职业/神灵武士/沸血之矛.lua`**

现状：每次普攻 `ignite` 先 `BuffClear` 再重新 `Buff`，`rollback` 会销毁 `_bloodSpearTimer`，新 Buff 再建一个 1/3 秒计时器 → 攻击间隔 < 1/3 秒时 DoT 永远跳不出来。

改法：

1. 新增 `local function ensureBurnTimer(hero, target)`，只在目标身上没有计时器时创建一次：
   ```lua
   local function ensureBurnTimer(hero, target)
       if (class.isObject(target._bloodSpearTimer, TimerClass)) then
           return
       end
       target._bloodSpearTimer = time.setInterval(1 / 3, function(curTimer)
           if (false == class.isObject(hero, UnitClass) or true == hero:isDead()
               or false == class.isObject(target, UnitClass) or true == target:isDead()
               or nil == target._bloodSpear) then
               class.destroy(curTimer)
               target._bloodSpearTimer = nil
               return
           end
           local per = (hero:str() * (0.3 + 0.004 * job.level(hero)) + 25) / 3
           job.damage(hero, target, per * (target._bloodSpear or 1), job.magic)
       end)
   end
   ```
2. `ignite` 写完 `target._bloodSpear = stacks` 后调用 `ensureBurnTimer(hero, target)`。
3. Buff 的 `purpose` 只保留 `effector.attach`，删除其中的 `time.setInterval` 创建逻辑。
4. Buff 的 `rollback` 删除「销毁 `_bloodSpearTimer`」，只保留 `syncUnregister`、`effector.detach`、`_bloodSpear = nil`；计时器在下一拍发现 `_bloodSpear == nil` 自行销毁。

> 计时器不再被 BuffClear 重置；Buff 到期后最多多跳一拍即自停。

### 2.3 大法师：水元素 3 → 2，暴风雪去掉固定基础值

**文件：`projects/demo/scripts/globals/tpl/ability/职业/大法师/水元素.lua`**

- `local summonNum = 3` → `local summonNum = 2`
- 站位 `(i - 2) * 90` → `(i - 1.5) * 90`（两只对称）
- 描述：「召唤3个水元素战斗」→「召唤2个水元素战斗」

**文件：`projects/demo/scripts/globals/tpl/ability/职业/大法师/暴风雪.lua`**

- `local dmg = 300 + hero:int() * (0.5 + lv * 0.05)` → `local dmg = hero:int() * (1.5 + lv * 0.05)`
- 描述：「伤害 = 300 + 智力 * (0.5 + 英雄等级 * 0.05)」→「伤害 = 智力 * (1.5 + 英雄等级 * 0.05)」

> L30/智力 100：单阵 500 → 300；3 只水元素 816 → 2 只 544。

### 2.4 月骑·月光：系数下调

**文件：`projects/demo/scripts/globals/tpl/ability/职业/月骑/月光.lua`**

```lua
local value = 1000 + hero:agi() * (1.0 + lv * 0.5)
```

描述：「伤害 = 1000 + 敏捷 * (1.0 + 英雄等级 * 0.5)」

> L30：5750 → 2600，6 秒 CD。

### 2.5 死骑·死亡缠绕：系数下调但保住 1600 下限

**文件：`projects/demo/scripts/globals/tpl/ability/职业/死骑/死亡缠绕.lua`**

```lua
local damage = 700 + hero:str() * (2.5 + lv * 1.4)
```

描述：「造成伤害 = 700 + 力量 * (2.5 + 英雄等级 * 1.4)」

> 报告建议的 `1.5 + 0.6×等级`（L30 = 2650/10 秒）会把死骑压到约 1285，低于 1600 下限。改取 `2.5 + 1.4×等级`（5150/10 秒），死骑约 1632，既削掉断层又留在区间内。

### 2.6 风暴之灵·球状闪电：CD 1 → 1.4，系数减半

**文件：`projects/demo/scripts/globals/tpl/ability/职业/风暴之灵/球状闪电.lua`**

- `:coolDownAdv(1, 0)` → `:coolDownAdv(1.4, 0)`
- `local value = 500 + hero:int() * (1.5 + lv * 0.1)` → `local value = 500 + hero:int() * (1.0 + lv * 0.05)`
- 描述：「伤害 = 500 + 智力 * (1.0 + 英雄等级 * 0.05)」

> 两个建议单独使用都仍 >2600（仅改系数 2826，仅改 CD 2726），同时落地后约 2529。

### 2.7 叠层统一：上限预设表 + 动态描述

**文件：`projects/demo/scripts/globals/setup/职业工具.lua`**

1. 新增预设表（两套语义：百分比属性 / 固定值）：
   ```lua
   job.killStackPresets = {
       percent = { capA = 1.5, capB = 0.02 },  -- 力/敏/智：主属性 * (1.5 + 等级*0.02)
       attack  = { capA = 2.5, capB = 0.02 },  -- 攻击：参照属性 * (2.5 + 等级*0.02)
       hp      = { capA = 20,  capB = 0.5 },   -- 生命：力量 * (20 + 等级*0.5)
       defend  = { capA = 0.8, capB = 0.01 },  -- 护甲：敏捷 * (0.8 + 等级*0.01)
   }
   ```
2. 新增 `job.killStackCap(hero, options)`，统一计算上限（含剔除本叠层自身加成），`job.killStack` 内部改调它。
3. 新增 `job.killStackTips(options, lines)`，返回 `description` 函数：技能栏悬停时追加「当前已增加: X / 上限: N」，无归属单位时只显示固定描述（参考 `英雄属性.lua` 的 `class.isObject(this, AbilityClass) and this:bindUnit()` 写法）。
4. `options` 支持 `preset` 字段；`job.killStack` 与 `killStackCap` 都从预设表取 `capA/capB`。
5. `options.effect(hero, targetUnit)` 可选回调，用于支配死灵保留「灵魂飞向施法者」特效。

**改造 10 个叠层文件**（统一结构：先定义 `local options`，再 `:description(job.killStackTips(options, {...}))`，最后 `job.killStack(tpl, options)`）：

| 文件 | preset | attr | per | capAttr |
| --- | --- | --- | ---: | --- |
| 光明游侠/圣光叠层.lua | percent | agi | 1 | agi |
| 痛苦女王/磨难叠层.lua | percent | int | 1 | int |
| 大魔导师/博学叠层.lua | percent | int | 1 | int |
| 炎魔之王/炽热叠层.lua | percent | str | 1 | str |
| 血魔法师/焚烧叠层.lua | percent | int | 1 | int |
| 死亡之翼/灭世叠层.lua | attack | attack | 2 | str |
| 虚空假面/时空叠层.lua | attack | attack | 2 | agi |
| 骷髅王/亡者叠层.lua | hp | hp | 12 | str |
| 娜迦海妖/潮汐叠层.lua | defend | defend | 1 | agi |
| 憎恶/腐肉堆积.lua | hp | hp | 15 | str |

**影魔/支配死灵.lua**：删除独立实现，改为 `job.killStack` + `preset = 'attack'`、`attr='attack'`、`per=2`、`capAttr='agi'`，并通过 `options.effect` 保留死亡特效。

> 唯一数值变化：灭世叠层上限从 `力量×(3 + 等级×0.02)`（L30 = 360）统一为 attack 预设（L30 = 300）。

### 2.8 模拟器同步（`tools/hero_dps_sim/sim.py`）

- 神灵武士 `sim_shenling`：攻速/攻击加成分别 `min(..., 100)` / `min(..., 150)`；DoT 改为「有层数就每 1/3 秒跳，5 秒无新引燃则清零」。
- 大法师：`flat_skills=[("暴风雪", 655.0, "magic")]`（300/阵 × 1.2 阵/秒 × 1.8 光环 × 1.01 精通 ≈ 655），`summons=[Summon("水元素", 544.0)]`。
- 月骑：`Active("月光", 2600 * 1.01, 6)`。
- 死骑：`Active("死亡缠绕", 5150 * 1.01, 10)`。
- 风暴之灵：`Active("球状闪电", 750 * 1.01, 1.4)`。
- 死亡之翼：`atk_siwang = p.attack + min(kills * 2.0, 300.0)`。

## 3. 预期结果（1000 击杀）

| 英雄 | 现秒伤 | 预期秒伤 | 说明 |
| --- | ---: | ---: | --- |
| 神灵武士 | 5928.8 | ~2799 | 攻速封顶 +100、攻击封顶 +150、修 DoT |
| 大法师 | 3142.5 | ~2262 | 水元素 2 只 + 暴风雪纯智力缩放 |
| 风暴之灵 | 3103.9 | ~2529 | CD 1.4 + 系数减半 |
| 月骑 | 2806.9 | ~1861 | 月光系数 1.0 + 0.5×等级 |
| 死骑 | 1805.4 | ~1632 | 死亡缠绕系数 2.5 + 1.4×等级 |
| 死亡之翼 | 2359.5 | ~2193 | 灭世上限 360 → 300 |

其余叠层英雄数值不变（狂战士之血以外均未改动输出系数）。

## 4. 风险与说明

- 神灵武士的木桩口径仍偏高（残血不还手），2799 只代表「上限被控住」，实战需进游戏复核
- 沸血之矛把计时器移出 Buff 生命周期，需重点验证：BuffClear 后层数仍刷新、Buff 自然到期后 DoT 停止、目标死亡引爆不重复
- 死亡缠绕与报告建议系数不同（为守住 1600 下限），已在 2.5 说明
- `job.killStack` 的 `options` 结构变更会影响 10 个叠层文件 + 支配死灵，必须一次性改完
- 无 Lua 解释器，语法只能人工核对；所有数值结论需进游戏验收
