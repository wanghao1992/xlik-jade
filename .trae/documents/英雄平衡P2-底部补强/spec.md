# 英雄平衡 P2（抬底部）实施规格

- 状态：待评审
- 范围：只做 P2「把 1600 以下的底部英雄抬到约 1300~1450」，不做 P1（收顶部）
- 不在本轮：骷髅王、娜迦海妖（坦克/生命向，木桩天然吃亏，按报告结论不改）；大G（同类，视设计）；神灵武士、大法师、风暴之灵、月骑等顶部英雄

## 1. 验收口径

- 面板：L30，攻击 300，2.0 APS，暴击 25% / 暴伤 150%，HP 8000，单体木桩，60 秒，1000 击杀
- 纯普攻基准：833.2 / 秒
- 本轮目标：下列 8 名英雄抬到约 1300~1450；血魔法师跨过 1600
- 验收步骤：
  1. 在 `d:\Lua\xlik-jade\tools\hero_dps_sim` 运行
     - `python sim.py --kills 1000 --csv results_1000_fixed.csv`
     - `python sim.py --kills 0 --csv results_0_fixed.csv`
  2. 更新 `d:\Lua\xlik-jade\.trae\documents\英雄同属性秒伤模拟报告.md` 的「一、结论摘要」「三、结果总表」「五、调整建议 P2 状态」
  3. 环境无 Lua 解释器，只能人工核对语法；结论中提示进游戏验收

## 2. 逐项改动

### 2.1 斧王 833.2 → 约 1376

**A. `projects/demo/scripts/globals/tpl/ability/职业/斧王/反击螺旋.lua`**

- 把现有触发逻辑抽成 `local function tryCast(hero, odds)`：
  - 内置冷却判断、`math.rand(1, 100) > odds`、`_fxLx_lock`、伤害与 `job.aoeDamage` 全部保留原样
  - `odds` 由调用方传入
- 受击通道（原 `onUnitEvent(eventKind.unitHurt)`）保持：
  - 仍要求 `evtData.damageSrc == injury.damageSrc.attack`
  - `odds = 15`；有「狂战士的怒吼」翻倍；再 `+ BuffCount(hero, { key = "越战越勇" })`
- 新增攻击通道：
  ```lua
  job.onAttack(TPL_ABILITY.JOB['反击螺旋'], function(hero)
      --- 攻击时也有 8% 概率触发(受击通道的一半)
      local odds = 8
      if (BuffHas(hero, "狂战士的怒吼")) then
          odds = odds * 2
      end
      odds = odds + BuffCount(hero, { key = "越战越勇" })
      tryCast(hero, odds)
  end)
  ```
- 描述追加：「攻击时也有 8% 概率触发」

**B. `projects/demo/scripts/globals/tpl/ability/职业/斧王/越战越勇.lua`**

- 每层 Buff 增加 `+5 攻击力`：
  ```lua
  purpose = function(o) o:attack("+=5") end,
  rollback = function(o)
      if (false == class.isDestroy(o)) then
          o:attack("-=5")
      end
  end,
  ```
- 描述改为：「每层使「反击螺旋」触发概率 +1%、攻击力 +5」
- 30 层封顶 → 最多 +150 攻击

**C. `tools/hero_dps_sim/sim.py`**

```python
atk_fw = p.attack + min(kills, 30) * 5
hs.append(Hero(
    "斧王",
    attack=atk_fw,
    procs=[Proc("反击螺旋(攻击触发)", 0.08, 570 * 1.01)],
    notes=["攻击触发 8%：400+力量*1.7=570；越战越勇满层 +150 攻击"],
))
```

### 2.2 幻影刺客 858.0 → 约 1336

**文件：`projects/demo/scripts/globals/tpl/ability/职业/幻影刺客/恩赐解脱.lua`**

- 触发概率 `10 → 15`
- 暴击加成：
  ```lua
  local bonus = (250 + lv * 5) * agiMul   -- L30 = 400% × agiMul
  ```
- 描述改为：「攻击有 15% 概率发生暴击」「暴击倍率 = 250 + 英雄等级 * 5」

**sim.py**

```python
hs.append(Hero(
    "幻影刺客",
    procs=[Proc("恩赐解脱", 0.15, p.attack * 4.02 * 1.01, "phys")],
    notes=["15% 概率、L30 暴击倍率 400%×敏捷系数 1.005"],
))
```

### 2.3 兽王 967.7 → 约 1308

**文件：**
- `projects/demo/scripts/globals/tpl/ability/职业/兽王/豪猪.lua`
- `projects/demo/scripts/globals/tpl/ability/职业/兽王/战鹰.lua`

在 `job.summon(...)` 成功返回 `mob` 后追加：

```lua
--- 继承英雄 40% 攻击力与攻击速度
mob:attack("+=" .. math.floor((hero:attack() or 0) * 0.4))
local spd = math.floor((hero:attackSpeed() or 0) * 0.4)
if (spd > 0) then
    mob:attackSpeed("+=" .. spd)
end
```

描述追加：「继承英雄 40% 攻击力与攻击速度」

**sim.py**

```python
summons=[Summon("战鹰", 182.0), Summon("豪猪", 182.0)]
# 攻击 10 + 300*40% = 130；攻速 +40 → 1.4 APS → 182
```

### 2.4 圣骑士 1029.1 → 约 1420

**文件：`projects/demo/scripts/globals/tpl/ability/职业/圣骑士/圣锤.lua`**

- `hop` 中首次落点（`depth == 1`）对主目标额外结算 2 跳：
  ```lua
  job.aoeDamage(hero, cur:x(), cur:y(), 225, dmg, job.magic, hero)
  if (depth == 1) then
      --- 单体目标额外承受 2 跳
      job.damage(hero, cur, dmg, job.magic)
      job.damage(hero, cur, dmg, job.magic)
  end
  ```
- 描述追加：「主目标额外承受 2 跳伤害」

**sim.py**

```python
procs=[Proc("圣锤", 0.15, 470 * 3 * 1.01)]
```

### 2.5 混沌骑士 1109.9 → 约 1314

**文件：`projects/demo/scripts/globals/tpl/ability/职业/混沌骑士/混乱之箭.lua`**

```lua
local value = 1000 + hero:str() * (12 + lv * 0.25)   -- L30 = 2950
```

描述改为：「伤害 = 1000 + 力量 * (12 + 英雄等级 * 0.25)」

**sim.py**

```python
actives=[Active("混乱之箭", 2950 * 1.01, 10)]
```

### 2.6 大娜迦 1118.8 → 约 1369

**文件：`projects/demo/scripts/globals/tpl/ability/职业/大娜迦/分裂箭.lua`**

- 主目标附加伤害 `base * 0.1 → base * 0.4`
- 描述改为：「命中附加伤害 = 攻击力 * 40%」

> 报告里写的「秘术异蛇」在本项目不存在，大娜迦实际技能为 石化 / 分裂箭 / 法术护盾，本轮改分裂箭。

**sim.py**

```python
onhits=[OnHit("分裂箭主目标", 120 * 1.01)]
```

### 2.7 憎恶 1134.8 → 约 1318

**文件：`projects/demo/scripts/globals/tpl/ability/职业/憎恶/腐烂.lua`**

```lua
local dmg = hero:hp() * 0.04 + job.primary(hero) * 1.5
```

描述改为：「每跳伤害 = 自身生命上限 * 4% + 主属性 * 1.5」

**sim.py**（同时把主属性从 `p.attack` 修正为 100）

```python
dots=[Dot("腐烂", (0.04 * hp_zengwu + 1.5 * 100.0) * 8 / 14 * 1.01)]
```

### 2.8 血魔法师 1588.0 → 约 1630

**文件：**
- `projects/demo/scripts/globals/tpl/ability/职业/血魔法师/火焰风暴.lua`
  - `burst = 1100 + primary * (2.2 + lv * 0.05)` → `(2.6 + lv * 0.05)`
- `projects/demo/scripts/globals/tpl/ability/职业/血魔法师/烈焰冲击.lua`
  - `damage = 800 + primary * (2 + lv * 0.05)` → `(2.6 + lv * 0.05)`

**sim.py**

```python
Active("火焰风暴", (1850 + 5.3 * p_stack) * mm, 14),
Active("烈焰冲击", (800 + 4.1 * p_stack) * mm, 9),
```

> 火焰风暴合并式：`(1100 + 4.1p) + 3*(250 + 0.4p) = 1850 + 5.3p`。

### 2.9 不改动

- 骷髅王、娜迦海妖：按报告结论保留（亡者/潮汐叠层不加输出）
- 大G：同类坦克向，视设计，不在本轮

## 3. 预期结果（1000 击杀）

| 英雄 | 现秒伤 | 预期秒伤 |
| --- | ---: | ---: |
| 斧王 | 833.2 | ~1376 |
| 幻影刺客 | 858.0 | ~1336 |
| 兽王 | 967.7 | ~1308 |
| 圣骑士 | 1029.1 | ~1420 |
| 混沌骑士 | 1109.9 | ~1314 |
| 大娜迦 | 1118.8 | ~1369 |
| 憎恶 | 1134.8 | ~1318 |
| 血魔法师 | 1588.0 | ~1630 |

## 4. 风险与说明

- 本轮数值均为「同属性木桩」口径；斧王、兽王、圣骑士在真实多目标/受击场景收益更高，需进游戏复核
- 斧王的越战越勇满层依赖持续击杀；0 击杀时仍约 960
- 无 Lua 解释器，语法只能人工核对
