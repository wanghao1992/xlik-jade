#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
英雄同属性打木桩秒伤模拟器
================================
口径来源（均已按项目代码核对）：
- 普攻伤害 = 攻击力 + rand(0, 攻击波动)，默认攻击波动 0
- 攻速：attackSpace = attackSpaceBase / (1 + attackSpeed/100)
  统一把 attackSpaceBase 归一为 1.0，攻击速度面板 100 => 每秒 2 次
- 暴击期望 = 1 + 暴击几率 * 暴击伤害%
- 物理伤害吃护甲，木桩护甲 0；三维精通：每 100 敏/智 +1% 物理/法术伤害
- 技能伤害走 job.damage，全部吃暴击；召唤物不继承英雄暴击与三维精通
- 击杀叠层按累计击杀折算；默认按设计封顶（capAttr 已剔除自身叠层加成）
- 主动技能假设卡 CD 自动释放、蓝量充足；被动按期望触发

用法：
  python sim.py                          # 1000 击杀、同属性、60 秒
  python sim.py --kills 0                # 不看击杀叠层，纯技能组
  python sim.py --kills 1000 --stack-mode intended   # 按设计意图封顶
  python sim.py --csv out.csv
"""

import argparse
import csv
import math
from dataclasses import dataclass, field

# ---------------------------------------------------------------- 全局模拟参数


@dataclass
class Profile:
    level: int = 30
    attack: float = 300.0          # 最终攻击力（三围换算已包含在内）
    aps: float = 2.0               # 最终每秒攻击次数
    crit: float = 0.25             # 暴击几率
    crit_dmg: float = 1.50         # 暴击伤害（150% => 2.5 倍）
    hp: float = 8000.0             # 生命上限
    seconds: float = 60.0          # 模拟时长
    kills: int = 1000              # 累计击杀（叠层用）
    stack_mode: str = "intended"   # intended=按设计封顶(当前代码)；bug=旧行为(叠层不封顶)对照用
    str: float = 100.0
    agi: float = 100.0
    int: float = 100.0

    @property
    def crit_mult(self) -> float:
        return 1.0 + self.crit * self.crit_dmg

    @property
    def phys_mastery(self) -> float:
        return 1.0 + self.agi / 10000.0

    @property
    def magic_mastery(self) -> float:
        return 1.0 + self.int / 10000.0


@dataclass
class Proc:
    label: str
    chance: float          # 每次普攻触发概率
    damage: float          # 单次伤害（已含该伤害类型的精通/专属乘区）
    kind: str = "magic"    # phys / magic
    icd: float = 0.0       # 内置冷却，0 表示无


@dataclass
class OnHit:
    label: str
    damage: float          # 每次普攻必附带的伤害
    kind: str = "magic"


@dataclass
class Active:
    label: str
    damage: float          # 单次释放伤害
    cd: float
    kind: str = "magic"


@dataclass
class Dot:
    label: str
    dps: float             # 原始每秒伤害（已含精通）
    kind: str = "magic"


@dataclass
class Summon:
    label: str
    dps: float             # 召唤物自身秒伤（不含英雄暴击/精通）


@dataclass
class Hero:
    name: str
    attack: float = 300.0
    as_mult: float = 1.0           # 攻速对每秒攻击次数的乘数
    phys_amp: float = 1.0          # 目标物理易伤/减甲等额外乘区
    magic_amp: float = 1.0         # 目标法术易伤/光环等额外乘区
    all_amp: float = 1.0           # 全伤害易伤
    phys_mastery: float = None     # None => 用全局 1.01
    procs: list = field(default_factory=list)
    onhits: list = field(default_factory=list)
    actives: list = field(default_factory=list)
    dots: list = field(default_factory=list)
    summons: list = field(default_factory=list)
    flat_skills: list = field(default_factory=list)  # (label, dps, kind) 已经是秒伤
    notes: list = field(default_factory=list)

    def proc_dps(self, aps: float) -> float:
        total = 0.0
        for p in self.procs:
            rate = p.chance * aps
            if p.icd > 0:
                rate = min(rate, 1.0 / p.icd)
            total += rate * p.damage
        return total

    def onhit_dps(self, aps: float) -> float:
        return sum(o.damage for o in self.onhits) * aps

    def active_dps(self) -> float:
        return sum(a.damage / a.cd for a in self.actives)

    def dot_dps(self) -> float:
        return sum(d.dps for d in self.dots)

    def summon_dps(self) -> float:
        return sum(s.dps for s in self.summons)


def sum_kind(items, aps, kind):
    return 0.0


def run_hero(h: Hero, p: Profile):
    """返回 dict：各来源原始DPS(未暴击)、最终DPS、总伤"""
    aps = p.aps * h.as_mult
    crit = p.crit_mult
    phys_mastery = h.phys_mastery if h.phys_mastery is not None else p.phys_mastery

    # 普攻
    basic_raw = h.attack * aps * phys_mastery * h.phys_amp * h.all_amp
    # 必中附加
    onhit_raw = 0.0
    for o in h.onhits:
        amp = h.phys_amp if o.kind == "phys" else h.magic_amp
        onhit_raw += o.damage * aps * amp * h.all_amp
    # 概率触发
    proc_raw = 0.0
    for pr in h.procs:
        amp = h.phys_amp if pr.kind == "phys" else h.magic_amp
        rate = pr.chance * aps
        if pr.icd > 0:
            rate = min(rate, 1.0 / pr.icd)
        proc_raw += rate * pr.damage * amp * h.all_amp
    # 主动（已按 /CD 折算，下面乘暴击）
    active_raw = 0.0
    for a in h.actives:
        amp = h.phys_amp if a.kind == "phys" else h.magic_amp
        active_raw += (a.damage / a.cd) * amp * h.all_amp
    # 持续伤害
    dot_raw = 0.0
    for d in h.dots:
        amp = h.phys_amp if d.kind == "phys" else h.magic_amp
        dot_raw += d.dps * amp * h.all_amp
    # 固定技能秒伤
    flat_raw = 0.0
    for _, dps, kind in h.flat_skills:
        amp = h.phys_amp if kind == "phys" else h.magic_amp
        flat_raw += dps * amp * h.all_amp
    # 召唤物（无暴击、无英雄精通）
    summon_raw = h.summon_dps() * h.all_amp

    hero_raw = basic_raw + onhit_raw + proc_raw + active_raw + dot_raw + flat_raw
    dps = hero_raw * crit + summon_raw
    total = dps * p.seconds

    return {
        "dps": dps,
        "total": total,
        "basic": basic_raw * crit,
        "onhit": onhit_raw * crit,
        "proc": proc_raw * crit,
        "active": active_raw * crit,
        "dot": dot_raw * crit,
        "flat": flat_raw * crit,
        "summon": summon_raw,
        "aps": aps,
    }


# ---------------------------------------------------------------- 神灵武士（时间步）


def sim_shenling(p: Profile):
    """沸血之矛(自损/叠层DoT) + 狂战士之血(按损失生命加攻速/攻击) + 活血术(治疗/加攻)"""
    dt = 0.05
    t = 0.0
    hp_max = p.hp
    hp = hp_max
    stacks = 0.0
    last_attack = 0.0
    blood_until = -1.0
    blood_atk = 0.0
    next_blood = 0.0
    total_basic = 0.0
    total_dot = 0.0
    crit = p.crit_mult
    phys = p.phys_mastery

    while t < p.seconds - 1e-9:
        if t + 1e-9 >= next_blood:
            blood_until = t + 15.0
            lost = math.floor(max(0.0, 1.0 - hp / hp_max) * 100)
            # 狂战士之血: 攻击加成封顶 +150
            cur_atk = p.attack + min(7.0 * lost, 150.0)
            blood_atk = math.floor(cur_atk * 0.33)
            next_blood += 20.0

        lost = math.floor(max(0.0, 1.0 - hp / hp_max) * 100)
        # 狂战士之血: 攻速加成封顶 +100(3.0 APS)
        as_stat = 100.0 + min(3.0 * lost, 100.0)
        aps = 1.0 + as_stat / 100.0
        atk = p.attack + min(7.0 * lost, 150.0) + (blood_atk if t < blood_until else 0.0)
        attacks = aps * dt

        total_basic += attacks * atk * crit * phys

        if hp > hp_max * 0.15:
            hp -= attacks * hp_max * 0.02
            stacks = min(10.0, stacks + attacks)
            last_attack = t

        # 沸血之矛 DoT 与攻击脱钩: 每 1/3 秒按层数跳一次; 5 秒内没有新引燃则清空层数
        if stacks > 0 and t - last_attack > 5.0:
            stacks = 0.0
        if stacks > 0:
            total_dot += (67.0 * stacks) * dt * crit * phys

        if t < blood_until:
            hp += hp * 0.01 * dt
        hp = min(hp, hp_max)
        t += dt

    dps = (total_basic + total_dot) / p.seconds
    return {
        "dps": dps,
        "total": total_basic + total_dot,
        "basic": total_basic / p.seconds,
        "onhit": 0.0,
        "proc": 0.0,
        "active": 0.0,
        "dot": total_dot / p.seconds,
        "flat": 0.0,
        "summon": 0.0,
        "aps": p.aps,
    }


# ---------------------------------------------------------------- 英雄数据


def build_heroes(p: Profile):
    kills = p.kills
    # 主属性叠层：当前代码 capAttr 读取的是被加成后的属性 -> 每杀必成，1000杀=+1000
    if p.stack_mode == "bug":
        p_stack = 100.0 + kills
    else:
        p_stack = 100.0 + min(kills, 210.0)

    hs = []

    # ---------------- 邪剑圣
    jian_mul = 7.0 + p.level * 0.04          # 总倍率(L30 = 8.2)
    hs.append(Hero(
        "邪剑圣",
        procs=[Proc("致命一击", 0.20, (jian_mul - 1.0) * p.attack, "phys")],
        notes=[f"致命一击 20% 概率、总倍率 {jian_mul:.1f}（追加 {jian_mul - 1:.1f} 倍）"],
    ))

    # ---------------- 剑圣
    hs.append(Hero(
        "剑圣",
        procs=[Proc("剑舞术", 0.15, 1550 * 1.01)],
        actives=[Active("剑刃风暴", 3850 * 1.01, 10), Active("疾步风", 4200 * 1.01, 12)],
    ))

    # ---------------- 大娜迦
    hs.append(Hero(
        "大娜迦",
        onhits=[OnHit("分裂箭主目标", 120 * 1.01)],
        actives=[Active("石化", 1780 * 0.9 * 1.01, 11)],
    ))

    # ---------------- 大鱼人
    hs.append(Hero(
        "大鱼人",
        phys_amp=1.255,
        procs=[Proc("鱼人碎击", 0.15, 1740 * 1.01, "phys", icd=2.5)],
        actives=[Active("鱼人重击", 1840 * 1.01, 5, "phys")],
        notes=["伤害加深：-51 护甲 5/10 秒，物理易伤 1.255"],
    ))

    # ---------------- 恶魔猎手
    hs.append(Hero(
        "恶魔猎手",
        attack=413.33,
        phys_mastery=1.0667,
        all_amp=1.28,
        flat_skills=[("变身溅射", 101.0, "magic")],
        notes=["变身 20/30 秒，攻击 470/300 折算 413；恐怖心潮全伤害 1.28"],
    ))

    # ---------------- 火女
    hs.append(Hero(
        "火女",
        as_mult=1.625,
        actives=[Active("光击阵", 1750 * 1.253, 10), Active("龙破斩", 1750 * 1.253, 7)],
        notes=["炽魂可叠层，平均 2.5 层 -> 攻速 +125、法术 +25%；攻速乘数 1.625"],
    ))

    # ---------------- 圣骑士（主目标额外 2 跳）
    hs.append(Hero(
        "圣骑士",
        procs=[Proc("圣锤", 0.15, 470 * 3 * 1.01)],
        notes=["圣锤 15% 概率，主目标额外承受 2 跳"],
    ))

    # ---------------- 影魔
    atk_yingmo = p.attack + min(kills * 2.0, 310.0)
    hs.append(Hero(
        "影魔",
        attack=atk_yingmo,
        phys_amp=1.0907,
        procs=[Proc("毁灭阴影", 0.15, 950 * 1.01, "phys")],
        notes=[f"支配死灵 +{min(kills*2,310):.0f} 攻击；魔王降临 -9.07 护甲 -> 物理 1.0907"],
    ))

    # ---------------- 大法师
    hs.append(Hero(
        "大法师",
        flat_skills=[("暴风雪", 655.0, "magic")],
        summons=[Summon("水元素", 544.0)],
        notes=["水元素 2 只，继承攻击，20/25 秒；暴风雪纯智力缩放(300/阵)并含辉煌光环 1.8"],
    ))

    # ---------------- 神灵武士（特殊）
    shenling = Hero("神灵武士", notes=["时间步模拟：沸血之矛自损+DoT、狂战士之血按损失生命加攻速/攻击、活血术"])
    hs.append(shenling)

    # ---------------- 幻影刺客
    hs.append(Hero(
        "幻影刺客",
        procs=[Proc("恩赐解脱", 0.15, p.attack * 4.02 * 1.01, "phys")],
        notes=["15% 概率、L30 暴击倍率 400%×敏捷系数 1.005"],
    ))

    # ---------------- 地狱火
    hs.append(Hero(
        "地狱火",
        procs=[Proc("邪爆拳", 0.15, 470 * 1.01)],
        dots=[Dot("永久献祭", 170 * 1.01)],
    ))

    # ---------------- 复仇之魂
    hs.append(Hero(
        "复仇之魂",
        attack=p.attack * 1.88,
        phys_amp=1.06,
        actives=[Active("魔法箭", 1510 * 1.01, 10), Active("恐怖波动", 1000 * 1.01, 11)],
        notes=["复仇光环 +88% 攻击；恐怖波动 -11 护甲 6/11 秒 -> 物理 1.06"],
    ))

    # ---------------- 卓尔游侠
    agi_do = 277.5
    do_mul = 0.5 + p.level * 0.04            # L30 = 1.7
    hs.append(Hero(
        "卓尔游侠",
        attack=p.attack + math.floor(agi_do / 5) - 20,
        phys_mastery=1.0 + agi_do / 10000.0,
        onhits=[OnHit("冰冻冷箭", (100 + agi_do * do_mul) * 1.01)],
        notes=[f"敏捷光环自身 +177.5 敏捷，冰冻冷箭每击 {100 + agi_do * do_mul:.0f}（系数 {do_mul:.2f}）"],
    ))

    # ---------------- 山丘之王
    hs.append(Hero(
        "山丘之王",
        attack=p.attack + math.floor(260 * 20 / 30),
        procs=[Proc("雷霆一击", 0.15, 440 * 1.01)],
        actives=[Active("风暴之锤", 1480 * 1.01, 10)],
        notes=["天神下凡 +260 攻击，20/30 秒折算"],
    ))

    # ---------------- 飞机
    hs.append(Hero(
        "飞机",
        procs=[
            Proc("弹幕攻击-物理", 0.15, 300 * 1.01, "phys"),
            Proc("弹幕攻击-法术", 0.15, 220 * 1.01),
            Proc("高射火炮", 0.15, 5 * 440 * 1.01),
        ],
        actives=[Active("召唤导弹", 1500 * 1.01, 10)],
    ))

    # ---------------- 大牛
    hs.append(Hero(
        "大牛",
        as_mult=1.4,
        procs=[Proc("震荡波X", 0.15, 1050 * 1.01)],
        actives=[Active("战争践踏", 1630 * 1.01, 12)],
        notes=["耐久光环 +80 攻速 -> 2.8 APS"],
    ))

    # ---------------- 月骑
    hs.append(Hero(
        "月骑",
        phys_amp=1.297,
        magic_amp=1.297,
        actives=[Active("月光", 2600 * 1.01, 6)],
        notes=["鼓舞光环自身 +30 物/法伤害点 -> 全伤害 1.297"],
    ))

    # ---------------- 火枪
    hs.append(Hero(
        "火枪",
        procs=[Proc("爆炎冲击", 1.0 / (3 + 1 / 0.13), 2200 * 1.01)],
        actives=[Active("榴霰弹", 6 * 340 * 1.01, 12, "phys")],
    ))

    # ---------------- 兽王
    hs.append(Hero(
        "兽王",
        procs=[Proc("惊吓", 0.15, 265 * 1.01)],
        summons=[Summon("战鹰", 182.0), Summon("豪猪", 182.0)],
        notes=["战鹰/豪猪继承英雄 40% 攻击与攻速 -> 各 182 秒伤"],
    ))

    # ---------------- 巫妖
    hs.append(Hero(
        "巫妖",
        procs=[Proc("霜冻闪电", 0.15, 375 * 1.01)],
        actives=[Active("霜冻新星", 1900 * 1.01, 10)],
    ))

    # ---------------- 狼骑
    hs.append(Hero(
        "狼骑",
        all_amp=1.09,
        procs=[Proc("挥舞利刃", 0.15, 2100 * 1.01, "phys")],
        actives=[Active("诱捕", 2600 * 1.01, 10)],
        summons=[Summon("战狼", 40.0)],
        notes=["诱捕易伤 +30%，3/10 秒 -> 全伤害 1.09"],
    ))

    # ---------------- 恐惧魔王
    hs.append(Hero(
        "恐惧魔王",
        procs=[Proc("魔王利爪", 0.15, 1840 * 1.01, "phys"), Proc("腐臭蜂群", 0.15, 600 * 1.01)],
    ))

    # ---------------- 死骑
    hs.append(Hero(
        "死骑",
        onhits=[OnHit("霜之哀伤", 30 * 1.01)],
        actives=[Active("死亡缠绕", 5150 * 1.01, 10)],
    ))

    # ---------------- 狮鹫
    hs.append(Hero(
        "狮鹫",
        procs=[Proc("风暴战锤", 0.25, (300 + 200 * 0.95) * 1.02)],
        actives=[Active("雷击", (1000 + 200 * 13.5) * 1.02, 10)],
        notes=["雷电光环自身 +100 智力 -> 雷击/战锤按智力 200 计算"],
    ))

    # ---------------- 巫医
    hs.append(Hero(
        "巫医",
        actives=[Active("弹弹乐", 550 * 1.01, 10)],
        summons=[Summon("死亡守卫", 347.85)],
    ))

    # ---------------- 食尸鬼之王
    hs.append(Hero(
        "食尸鬼之王",
        as_mult=1.5,
        onhits=[OnHit("盛宴", 64.64, "phys")],
        flat_skills=[("狂暴伤害", 123.2, "magic")],
        notes=["狂暴 +200 攻速 5/10 秒 -> 平均 3 APS"],
    ))

    # ---------------- 大G
    hs.append(Hero(
        "大G",
        attack=307.2,
        as_mult=1.3,
        procs=[Proc("沸腾之斧", 0.15, 695 * 1.01, "phys")],
        notes=["斗志爆发 +100 攻速 6/10 秒、力量 +60"],
    ))

    # ---------------- 绞肉车
    hs.append(Hero(
        "绞肉车",
        dots=[Dot("散播瘟疫", 580 * 1.01)],
        notes=["尸体派对需击杀，木桩场景为 0"],
    ))

    # ---------------- 炼金术士
    # 化学狂暴只 +150 攻速(aps 2.0 -> 3.5)，15 秒持续 / 22 秒冷却
    lianjin_uptime = 15.0 / 22.0
    as_lianjin = (2.0 + 1.5 * lianjin_uptime) / 2.0
    hs.append(Hero(
        "炼金术士",
        as_mult=as_lianjin,
        procs=[Proc("贪婪", 0.15, 700 * 1.01, "phys")],
        actives=[Active("腐蚀酸雾", 185.8, 10)],
        notes=[f"化学狂暴仅 +150 攻速，平均 {2.0 * as_lianjin:.2f} APS"],
    ))

    # ---------------- 巫师
    hs.append(Hero(
        "巫师",
        procs=[
            Proc("艾瑞达重击", 0.12, 340 * 1.01),
            Proc("死亡群指", 0.15, 440 * 1.01, icd=1.0),
        ],
        flat_skills=[("混乱之雨改(单体命中率6.7%)", 116.7, "magic")],
    ))

    # ---------------- 混沌骑士
    hs.append(Hero(
        "混沌骑士",
        procs=[Proc("致命一击", 0.15, 69 * 1.01, "phys")],
        actives=[Active("混乱之箭", 2950 * 1.01, 10)],
        summons=[Summon("幻象", 42.4)],
    ))

    # ---------------- 斧王（攻击也可触发反击螺旋 + 越战越勇加攻击）
    atk_fw = p.attack + min(kills, 30) * 5
    hs.append(Hero(
        "斧王",
        attack=atk_fw,
        procs=[Proc("反击螺旋(攻击触发)", 0.08, 570 * 1.01)],
        notes=["攻击触发 8%：400+力量*1.7=570；越战越勇满层 +150 攻击"],
    ))

    # ---------------- 风暴之灵
    hs.append(Hero(
        "风暴之灵",
        actives=[Active("球状闪电", 750 * 1.01, 1.4), Active("牵引", 2450 * 1.01, 10)],
        flat_skills=[("超负荷", 440 * 1.01, "magic")],
        notes=["球状闪电 CD 1.4 秒；超负荷约 1 次/秒；未计蓝量约束"],
    ))

    # ---------------- 龙骑士
    hs.append(Hero(
        "龙骑士",
        attack=613.33,
        actives=[Active("Duang", 2450 * 1.01, 6)],
        notes=["变龙 20/30 秒：攻击 770/300，溅射排除主目标"],
    ))

    # ---------------- 虚空假面
    atk_xukong = p.attack + min(kills * 2.0, 310.0) + 25 * 6 / 11
    hs.append(Hero(
        "虚空假面",
        attack=atk_xukong,
        procs=[Proc("时间锁定", 0.20, 540 * 1.01)],
        actives=[Active("时间结界", 1300 * 1.01, 11)],
        notes=[f"时空叠层 +{min(kills*2,310):.0f} 攻击；时间结界 +25 攻击 6/11 秒"],
    ))

    # ---------------- 血魔法师（主属性叠层）
    mm = 1.0 + p_stack / 10000.0
    atk_stack = p.attack + math.floor(p_stack / 5) - 20
    hs.append(Hero(
        "血魔法师",
        attack=atk_stack,
        actives=[
            Active("火焰风暴", (1850 + 5.3 * p_stack) * mm, 14),
            Active("烈焰冲击", (800 + 4.1 * p_stack) * mm, 9),
        ],
        notes=[f"焚烧叠层已封顶：智力 +{p_stack - 100:.0f}"],
    ))

    # ---------------- 死亡之翼
    atk_siwang = p.attack + min(kills * 2.0, 300.0)
    hs.append(Hero(
        "死亡之翼",
        attack=atk_siwang,
        procs=[Proc("龙焰溅射", 0.25, 560 * 1.01)],
        actives=[Active("奥术脉冲", 990 * 1.01, 10)],
        notes=[f"灭世叠层 +{min(kills*2,300):.0f} 攻击"],
    ))

    # ---------------- 骷髅王
    hs.append(Hero(
        "骷髅王",
        procs=[Proc("冥火爆击", 0.20, 640 * 1.01)],
        actives=[Active("魂之挽歌", 1450 * 1.01, 12)],
        notes=["亡者叠层只加生命上限，对木桩秒伤无影响"],
    ))

    # ---------------- 娜迦海妖
    hs.append(Hero(
        "娜迦海妖",
        procs=[Proc("致命漩涡", 0.20, 590 * 1.01)],
        actives=[Active("碎浪", 1300 * 1.01, 10)],
        notes=["潮汐叠层只加护甲，对木桩秒伤无影响"],
    ))

    # ---------------- 光明游侠（主属性叠层）
    hs.append(Hero(
        "光明游侠",
        attack=atk_stack,
        phys_mastery=1.0 + p_stack / 10000.0,
        procs=[Proc("逐光", 0.25, (400 + 2.9 * p_stack) * 1.01)],
        actives=[Active("光明箭雨", (900 + 4.8 * p_stack) * 1.01, 11)],
        notes=[f"圣光叠层已封顶：敏捷 +{p_stack - 100:.0f}"],
    ))

    # ---------------- 大魔导师（主属性叠层）
    hs.append(Hero(
        "大魔导师",
        attack=atk_stack,
        procs=[Proc("奥术共鸣", 0.20, (350 + 2.4 * p_stack) * mm)],
        actives=[Active("奥术冲击", (1100 + 4.6 * p_stack) * mm, 11)],
        notes=[f"博学叠层已封顶：智力 +{p_stack - 100:.0f}"],
    ))

    # ---------------- 炎魔之王（主属性叠层 + 生命转输出）
    hp_yanmo = p.hp + 3.0 * (p_stack - 100.0)
    hs.append(Hero(
        "炎魔之王",
        attack=atk_stack,
        procs=[Proc("焚身", 0.20, (0.04 * hp_yanmo + 1.5 * p_stack) * 1.01)],
        actives=[Active("熔岩爆发", (0.10 * hp_yanmo + 3.5 * p_stack) * 1.01, 11)],
        notes=[f"炽热叠层已封顶：力量 +{p_stack - 100:.0f}，生命 {hp_yanmo:.0f}"],
    ))

    # ---------------- 痛苦女王（主属性叠层）
    hs.append(Hero(
        "痛苦女王",
        attack=atk_stack,
        procs=[Proc("痛苦之刺", 0.25, (300 + 2.4 * p_stack) * mm)],
        actives=[Active("尖啸", (1000 + 4.3 * p_stack) * mm, 10)],
        notes=[f"磨难叠层已封顶：智力 +{p_stack - 100:.0f}"],
    ))

    # ---------------- 憎恶（生命叠层 + 生命转输出）
    hp_zengwu = p.hp + min(kills * 15.0, 3500.0)
    hs.append(Hero(
        "憎恶",
        dots=[Dot("腐烂", (0.04 * hp_zengwu + 1.5 * 100.0) * 8 / 14 * 1.01)],
        notes=[f"腐肉堆积 +{min(kills*15,3500):.0f} 生命 -> 腐烂每跳随生命上限提高"],
    ))

    # ================================================================
    # 以下为本轮新增的 8 个 SSR 职业（2026-11-11 迁移）
    # ================================================================

    # ---------------- 欺诈者（智力）
    # 裂地: CD25, 持续10秒每0.5秒 智力*1.2 魔法(共20跳)
    # 死亡一指: 每0.2秒 智力*1.8 魔法(5次/秒)
    # 幽魂: 环绕碰撞爆炸 智力*5, 单体木桩轨道不命中目标
    liedi_per_cast = 20 * p.int * 1.2 * p.magic_mastery
    siwang_dps = p.int * 1.8 * 5 * p.magic_mastery
    hs.append(Hero(
        "欺诈者",
        actives=[Active("裂地", liedi_per_cast, 25)],
        flat_skills=[("死亡一指", siwang_dps, "magic")],
        notes=["裂地 20跳*智力*1.2 / 25秒；死亡一指 智力*1 / 0.2秒；幽魂环绕木桩不命中"],
    ))

    # ---------------- 阿卡玛（敏捷）
    # 致命一击: 5%概率全伤害*1.75 -> 期望乘区 1.0375
    # 附魔攻击: CD45持续15秒, 普攻附加 攻击*2 物理
    # 双刃剑: HP>50%普攻对400码 敏捷*2.5 物理
    akama_enchant_dps = p.aps * p.attack * 2 * (15.0 / 45.0) * p.phys_mastery
    hs.append(Hero(
        "阿卡玛",
        all_amp=1.0 + 0.05 * 0.75,
        procs=[Proc("双刃剑", 1.0, p.agi * 2.5 * p.phys_mastery, "phys")],
        flat_skills=[("附魔攻击", akama_enchant_dps, "phys")],
        notes=["致命一击 5%*1.75 全伤害；附魔攻击 15/45秒普攻+攻击*2；双刃剑 普攻+敏捷*2.5"],
    ))

    # ---------------- 精灵信使（智力）
    # 金钟罩: CD18持续10秒, 护盾期间+40%伤害 -> 期望 1.222
    # 强化一击: 每3秒充能, 普攻 智力*4 魔法
    # 水元素: CD40持续30秒, 2只 智力*0.5攻击
    jinzhong_amp = 1.0 + 0.4 * (10.0 / 18.0)
    hs.append(Hero(
        "精灵信使",
        all_amp=jinzhong_amp,
        actives=[Active("强化一击", p.int * 10 * p.magic_mastery, 3)],
        summons=[Summon("水元素", 4 * p.int * 1 * p.aps * (30.0 / 40.0))],
        notes=["金钟罩 10/18秒+40%伤害；强化一击 智力*10/3秒；水元素 4只*智力*1攻, 30/40秒"],
    ))

    # ---------------- 深渊魔王（力量）
    # 英雄之力: CD3, 力量*15 物理
    # 护甲增幅: 纯防御(+20%护甲)
    # 阎刃: 普攻直线 力量*20 魔法, CD5秒
    hs.append(Hero(
        "深渊魔王",
        actives=[Active("英雄之力", p.str * 15 * p.phys_mastery, 3, "phys")],
        procs=[Proc("阎刃", 1.0, p.str * 20 * p.magic_mastery, "magic", icd=5.0)],
        notes=["英雄之力 力量*15/3秒；阎刃 普攻触发 力量*20, CD5；护甲增幅 +20%纯防御"],
    ))

    # ---------------- 火之熊猫战士（敏捷）
    # 强化: CD120持续15秒, 期间普攻400码 攻击*2, 每次普攻减CD1秒 -> 循环约90秒
    # 冲击: 20%概率 攻击*2.5 魔法
    # 燃烧: 每秒 生命上限*5% 魔法
    qianghua_uptime = 15.0 / 90.0
    qianghua_dps = p.aps * p.attack * 2 * qianghua_uptime * p.phys_mastery
    hs.append(Hero(
        "火之熊猫战士",
        procs=[Proc("冲击", 0.20, p.attack * 2.5 * p.magic_mastery, "magic")],
        flat_skills=[
            ("强化", qianghua_dps, "phys"),
            ("燃烧", p.hp * 0.05 * p.magic_mastery, "magic"),
        ],
        notes=["强化 15/90秒循环, 普攻+攻击*2；冲击 20%攻击*2.5；燃烧 HP*5%/秒"],
    ))

    # ---------------- 地之熊猫战士（智力）
    # 通灵: CD40持续20秒, 召唤 (2+等级/5) 只影狼, 智力*1.25攻击
    # 夺魂: 每4秒充能, 普攻3道 智力*10 魔法
    # 魔霭诅咒: 普攻叠层, 每层每秒 智力*0.1 魔法, 持续2秒 -> 稳态4层
    wolf_count = 2 + p.level // 5
    wolf_dps = wolf_count * p.int * 1.25 * p.aps * (20.0 / 40.0)
    curse_stacks = min(10, int(p.aps * 2))
    curse_dps = curse_stacks * p.int * 0.1 * p.magic_mastery
    hs.append(Hero(
        "地之熊猫战士",
        actives=[Active("夺魂", 3 * p.int * 10 * p.magic_mastery, 4)],
        flat_skills=[("魔霭诅咒", curse_dps, "magic")],
        summons=[Summon("影狼", wolf_dps)],
        notes=[f"通灵 {wolf_count}只影狼*智力*1.25攻, 20/40秒；夺魂 3*智力*10/4秒；魔霭诅咒 稳态{curse_stacks}层*智力*0.1/秒"],
    ))

    # ---------------- 火浣（敏捷）
    # 抗拒火环: CD7, 敏捷*8 物理 + 10层灼烧
    # 灼烧: 普攻+1层, 每层每秒 敏捷*0.25 魔法, 上限50层(攻击刷新持续, 快速叠满)
    # 潮汐之刃: CD3, 普攻扇形 攻击*2 物理
    burn_stacks_avg = 44.0  # 2APS+抗拒火环每7秒+10层, 约15秒到50层的均值
    burn_dps = burn_stacks_avg * p.agi * 0.25 * p.magic_mastery
    hs.append(Hero(
        "火浣",
        actives=[Active("抗拒火环", p.agi * 8 * p.phys_mastery, 7, "phys")],
        procs=[Proc("潮汐之刃", 1.0, p.attack * 2 * p.phys_mastery, "phys", icd=3.0)],
        flat_skills=[("灼烧", burn_dps, "magic")],
        notes=[f"抗拒火环 敏捷*8/7秒；灼烧 稳态约{burn_stacks_avg:.0f}层*敏捷*0.25/秒；潮汐之刃 攻击*2/3秒"],
    ))

    return hs, shenling


# ---------------------------------------------------------------- 输出


def fmt_pct(part, total):
    return f"{part / total * 100:5.1f}%" if total > 0 else "  0.0%"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kills", type=int, default=1000)
    ap.add_argument("--stack-mode", choices=["bug", "intended"], default="intended")
    ap.add_argument("--attack", type=float, default=300)
    ap.add_argument("--aps", type=float, default=2.0)
    ap.add_argument("--crit", type=float, default=0.25)
    ap.add_argument("--crit-dmg", type=float, default=1.5)
    ap.add_argument("--hp", type=float, default=8000)
    ap.add_argument("--seconds", type=float, default=60)
    ap.add_argument("--level", type=int, default=30)
    ap.add_argument("--csv", default="")
    args = ap.parse_args()

    p = Profile(
        level=args.level, attack=args.attack, aps=args.aps,
        crit=args.crit, crit_dmg=args.crit_dmg, hp=args.hp,
        seconds=args.seconds, kills=args.kills, stack_mode=args.stack_mode,
    )

    heroes, shenling = build_heroes(p)
    rows = []
    for h in heroes:
        if h is shenling:
            r = sim_shenling(p)
        else:
            r = run_hero(h, p)
        r["name"] = h.name
        r["notes"] = "；".join(h.notes)
        rows.append(r)

    rows.sort(key=lambda x: x["dps"], reverse=True)

    print(f"\n模拟口径: L={p.level} 攻击={p.attack:.0f} 攻速={p.aps:.2f}/s "
          f"暴击={p.crit*100:.0f}% 暴伤={p.crit_dmg*100:.0f}% HP={p.hp:.0f} "
          f"时长={p.seconds:.0f}s 击杀={p.kills} 叠层={p.stack_mode}")
    print("=" * 112)
    print(f"{'#':>2} {'英雄':<8} {'总伤':>10} {'秒伤':>9} {'普攻%':>7} {'触发%':>7} "
          f"{'主动%':>7} {'持续%':>7} {'召唤%':>7} {'APS':>5}")
    print("-" * 112)
    for i, r in enumerate(rows, 1):
        t = r["total"]
        d = r["dps"]
        print(f"{i:>2} {r['name']:<8} {t:>10.0f} {d:>9.1f} "
              f"{fmt_pct(r['basic'], d):>7} {fmt_pct(r['proc'] + r['onhit'], d):>7} "
              f"{fmt_pct(r['active'], d):>7} {fmt_pct(r['dot'] + r['flat'], d):>7} "
              f"{fmt_pct(r['summon'], d):>7} {r['aps']:>5.2f}")
    print("=" * 112)

    top = rows[0]["dps"]
    bottom = rows[-1]["dps"]
    print(f"最高/最低秒伤比: {top / bottom:.2f}x  （{rows[0]['name']} vs {rows[-1]['name']}）")
    print(f"中位秒伤: {sorted(r['dps'] for r in rows)[len(rows)//2]:.1f}")

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(["排名", "英雄", "总伤", "秒伤", "普攻伤害", "触发伤害",
                        "主动伤害", "持续/固定", "召唤伤害", "APS", "备注"])
            for i, r in enumerate(rows, 1):
                w.writerow([i, r["name"], round(r["total"]), round(r["dps"], 1),
                            round(r["basic"]), round(r["proc"] + r["onhit"]),
                            round(r["active"]), round(r["dot"] + r["flat"]),
                            round(r["summon"]), round(r["aps"], 3), r["notes"]])
        print(f"\n已写入 CSV: {args.csv}")


if __name__ == "__main__":
    main()
