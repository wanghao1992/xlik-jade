# xlik 内置 JAPI 复刻进展：setter 家族全通 + 6 个缺失 native 已补齐

> 复刻产物：`vendor/japi-replica/`（YDWE 插件形态，链接 `ydwar3.lib`）
> 目标环境：魔兽争霸 III **1.27a**（ydwar3 版本号 `7000`；PE 版本 `52240 = 0xcc10`）
> 本文只记录**已实测验证通过**的能力与数据，未打通部分单列在最后。

---

## 一、已打通的能力（均有实测证据）

| 能力 | native | 状态 |
|---|---|---|
| 指令边界扫描 | （内部基建） | ✅ 与内置插件等价 |
| 分层字符串锚点定位 | （内部基建） | ✅ |
| **LoadToc**（载入 toc/fdf、注册控件类型） | `LoadToc (S)V` | ✅ 端到端 |
| **GetGameUI**（取根控件） | `GetGameUI ()I` | ✅ |
| 按 fdf tag 建控件 | `CreateFrameByTagName (SSISI)I` | ✅ 建出对象 |
| **FrameSetSize**（设尺寸） | `FrameSetSize (IRR)V` | ✅ 视觉闭环 |
| **FrameSetPoint**（设锚点） | `FrameSetPoint (IIIIRR)V` | ✅ 视觉闭环（见第十节） |
| **FrameSetAlpha**（设透明度） | `FrameSetAlpha (II)V` | ✅ 视觉闭环（见第十节） |
| **FrameSetText**（设文本） | `FrameSetText (IS)V` | ✅ 写入已实测（`+0x98/0x9C`）；必须先设字体，否则 `call 0` |
| **FrameSetTextFont**（设字体） | `FrameSetTextFont (ISR)V` | ✅ 已实测（`+0x8C` 得字体对象；`this`=控件本体，`ret 0xC` 需压满 3 栈参） |
| **FrameShow**（显示/隐藏） | `FrameShow (IB)V` | ✅ 已实现（RVA 0xC0CC0，this=帧本体，见第七节） |
| **FrameSetTexture**（设背景纹理） | `FrameSetTexture (ISI)V` | ⚠️ 已实现但**实测崩溃未闭环**（RVA 0xC11E0，见第十二节） |
| **FrameSetModel**（设背景模型） | `FrameSetModel (ISI)V` | ⚠️ 与 Texture 共用 0xC11E0，**同受第十二节问题影响** |
| **FrameClearAllPoints**（清空锚点） | `FrameClearAllPoints (I)V` | ✅ 已实现（RVA 0xBCCA0，this=core，见第七节） |
| **FrameFindByName**（按名查帧） | `FrameFindByName (SI)I` | ✅ 已实现（0x9EF40 全局注册表 + 0xA01D0 内层表，id>0 链遍历） |
| **DestroyFrame**（销毁帧） | `DestroyFrame (I)V` | ✅ 已实现（RVA 0xA48B0 deleting destructor，含按名注销） |
| **「挂接」**（创建后写 `+0x74/+0x78` 父链接） | （内部步骤） | ✅ 已实现（一切「通知型」setter 的前提） |

---

## 二、基建：指令边界扫描 + 字符串锚点

内置插件的核心技法「零特征码定位」= **字符串锚点 → .text 代码引用 → 解 call 目标**。

| 环节 | 内置插件 | 我们 |
|---|---|---|
| 沿指令边界扫描下一条指令 | `FUN_102c90a0`（内置 udis86） | **直接复用 ydwar3 导出的 `warcraft3::next_opcode(p, opcode, len)`**（内部就是同一份 udis86） |
| 解 `call rel32` 目标 | `p + 5 + *(int*)(p+1)` | `warcraft3::convert_function(p)` |
| 字符串查找 | `FUN_102c8f50` / `FUN_102c9450` | `jr::find_game_string()`（.rdata/.data 精确→子串） |
| 代码引用定位 | 内置循环 | `jr::find_code_ref_in_text()`（.text 逐字节找 `dword == 地址`） |

代码位置：[war3_layer.cpp](../../vendor/japi-replica/src/war3_layer.cpp) 的 `resolve_callsite` / `call_target_of` / `scan_next_call_target`。

> 关键结论：**不需要自己移植 udis86**——YDWE 已把它连同 `next_opcode` 一起导出，直接用即可。

---

## 三、LoadToc（`FUN_10248740` 三步链）

作用是**让 war3 去解析 fdf、把其中的控件类型注册进「frame 类型注册表」**。

```
① FUN_102485b0  找字符串 "UI\FrameDef\FrameDef.toc" 的 .text 引用处 ref，返回 ref - 1
                （ref 是 push imm32 的立即数，在指令第 2 字节 → ref-1 正是指令起始）
                找不到时回退 Game.dll base + 0x282BC
② FUN_10248690  从①出发沿指令边界找第一条 E8，取其目标 = FrameDef 处理函数 base_fn
③ FUN_10248740  在 base_fn 体内依次定位：
                  mov esi, imm32  (0xBE)
                  push imm32      (0x68)
                  mov edx, imm32  (0xBA)  ← 从 push 那条之后找
                  call rel32      (0xE8)  ← 从 mov edx 那条之后找
                取这三条指令的立即数，把 war3 自己那次调用「重放」一遍，
                只把首个参数换成我们传入的 toc 路径：
                  ECX = path
                  EDX = mov-edx 的立即数
                  栈  = (push 的立即数, mov-esi 的立即数)
```

**实测值（1.27a）**：

| 项 | 值 |
|---|---|
| 锚点字符串地址 | `0x6EF61C54` |
| .text 引用处 ref | `0x6E6382BC` |
| `base_fn` | `0x6E6A0B70`（RVA `0x90B70`） |
| 三个立即数 | `esi=0x6F1762CC`、`push=0x6F1C9CFC`、`edx=0x6F1C9CAC` |
| 重放的调用目标 | `0x6E676590` |

**效果验证**：`japi.Exec("LoadToc", "UI\\xlik.toc")` 之后，`UI\xlik.fdf` 里定义的条目**全部**注册成功：

```
JKFrameTypeLookup: "LK_BACKDROP"   -> entry=0x0FBC1B28 flags(bit1)=1
JKFrameTypeLookup: "LK_TEXT"       -> entry=0x0FB67C40 flags(bit1)=1
JKFrameTypeLookup: "LK_MODEL"      -> entry=0x0F8317A8 flags(bit1)=1
JKFrameTypeLookup: "LK_TEXTAREA"   -> entry=0x0FA20088 flags(bit1)=1
JKFrameTypeLookup: "LK_BACKDROP_NIL/TOOLTIP/INPUTBOX" -> 均命中
```

> ⚠️ 之前用 `LoadToc("UI\\FrameDef\\FrameDef.toc")` 是**错的路径**；框架自己的 `xlik.toc` 才是要载的那份。

---

## 四、GetGameUI

```
内置插件 FUN_10246610:  call game();  ecx=0; edx=0;  call [obj+0x24];  ret
我们:                    warcraft3::get_war3_searcher().get_gameui(0, 0)
```
实测返回非 0 的根控件指针（如 `0x28590088`）。

---

## 五、按 fdf tag 建控件 & 类型注册表机制

**注册表**（逆向 Game.dll 得到）：

| 项 | RVA | 说明 |
|---|---|---|
| frame 类型注册表对象 | `base+0xBB9CFC` | 哈希表 |
| 查表函数 | `base+0x6AEF0` | `entry = lookup(table, typeName)`，内部 `6F120694` 算哈希、`6F12070C` 比字符串 |
| frame 构造器 | `base+0x909C0` | `ctor(ECX=类型名, EDX=parent, 栈=(0,0,a5))`，`ret 0Ch` |

构造器一进去就查表，**查不到就返回 0**：

```
push ecx(类型名) → ecx=注册表 → call 查表
test ecx,ecx ; je → return 0
test byte [ecx+0x48],2 ; je → return 0
```

**关键结论**：注册表的键是 **fdf 条目名**（`LK_BACKDROP`、`CinematicPanel`、`Leaderboard`…），
**不是** `FRAME`/`BUTTON`/`TEXT` 这类基类型——实测这些基类型名一律 `entry=0`。
所以「必须先 `LoadToc` 载入包含该类型的 fdf，才能 `CreateFrame`」。

**实测**：`LoadToc` 之后

```
CreateFrameByTagName: type="LK_BACKDROP" name="JKApiFrame" parent=0x28590088 -> ok 0x30A4A050
CreateFrameByTagName: type="LK_TEXT"     name="JKApiText"  parent=0x00000000 -> ok 0x30B56940
```

---

## 六、框架侧的关键事实

- 框架实际调用的是 **`CreateFrameByTagName(frameType, name, parent, template, id)`**（`(SSISI)I`），
  **不是** `CreateFrame`。见 [xlik接入内置JAPI适配层方案.md](./xlik接入内置JAPI适配层方案.md)。
- fdf 来源：`exe/lib/embeds/lni/assets/UI/xlik.toc` → `xlik.fdf` / `slkc_fdf.fdf` / `xlik_overhead.fdf`
  （打包后位于地图内 `UI\xlik.toc`）。
- 运行时 [init.lua](../../exe/lib/embeds/lua/engine/init.lua#L17) 本就有 `japi.LoadToc("UI\\xlik.toc")`，
  但它内部走 `japi.DZ_LoadToc` → `japi.Exec("DzLoadToc", ...)`；**我们的插件没注册 `DzLoadToc`**，
  所以那条路径一直没生效（本次是靠显式 `japi.Exec("LoadToc", ...)` 打通的）。

---

## 七、未打通的部分（含原因）

| 部分 | 现象 | 原因 |
|---|---|---|
| `FrameSetSize` | ✅ **已打通**（视觉闭环，见第十节） | 尺寸单位是**屏幕比例**，见第十节 |
| `FrameSetPoint` | ✅ **已打通**（视觉闭环，见第十节） | `relFrame` 必须是 core 指针，见第十节 |
| `FrameSetAlpha` | ✅ **已打通**（视觉闭环，见第十节） | `this` 必须是**控件本体**（不是 core），见第十节 |
| `CreateFrameByTagName` 完整实现 | 只做了"建出对象" | ⚠️ 见下方「关于 `FUN_102492e0` 的重要修正」——它很可能**不是**框架 `CreateFrameByTagName` 的真正实现 |

### ✅ 已修复：崩溃家族的统一根因（2026-10-13）

**根因**：`帧+0x74 / +0x78 / +0x7C` 是**帧内嵌的一个链表节点**（`+0x78` = next 指针、`+0x7C` = 编码后的 prev）。
早期"挂接"实现把 `+0x78` 当成"父/索引"写成 **2**，从而**写坏了这个节点**：
帧的析构函数 `RVA 0x97B80`（开头把 vtable 换成基类 `0x6F95A5C0`，随后逐个摘链）
在摘 `+0x74/+0x78/+0x7C` 这条链时执行 `mov [ecx+4],eax`（`ecx = [edi+0x78] = 2`）
→ **AV: RVA 0x97BCC 访问 0x6**。同理可解释其它表现（点/文本/退出期的各种空指针）。

**修法**（[natives.cpp](../../vendor/japi-replica/src/natives.cpp) `CreateFrameByTagName`）：
- **只写 `帧+0x74 = parent`**（通知路径 `0xBF960 → 0xB9900` 需要它）；
- **`+0x78`/`+0x7C` 保持 0**（析构 `test edx,edx / je` 会跳过摘链）；
- **不再调用 `0xBF9A0`（完整 SetParent）**——它会写 `+0x78 = idx`，同样破坏该节点。

**实测**：只建 `LK_TEXT` + 关窗口 → **无 AV、`DLL_PROCESS_DETACH` 正常出现、不再弹 `FATAL ERROR`** ✓

> 以下为历史存档（修复前的现象与分析），保留以记录定位过程。



**只发生在关闭游戏窗口时**，游戏内功能不受影响（本局能正常跑完）。

**现象**：关窗口弹 `FATAL ERROR!`（每局 Game.dll 基址不同，RVA 固定）：

```
Exception: 0xC0000005 (ACCESS_VIOLATION) at 0023:XXXXXXXX
The instruction at '0xXXXXXXXX' referenced memory at '0x00000008'.
```

**崩溃点**：`Game.dll + 0xA08A7`，落在函数 `+0xA08A0`（「把自己从双向链表摘除」）里：

```
0xA08A0: 55 8B EC         push ebp; mov ebp,esp
         56               push esi
         8B 75 08         mov esi,[ebp+8]        ; 节点指针
0xA08A7: 83 7E 08 00      cmp dword [esi+8],0    ; ← esi = NULL → 读 [8] 崩
         8B 7E 04 / 8B 4E 08 / 89 39 / 89 41 04 …   ; node->prev / node->next 摘除
```

**调用链**（VEH 转储调用栈 + 调用点反汇编确认）：

```
退出流程
 → 调用者 RVA 0x9EFB1：遍历一张「4 项全局注册表」（全局变量 RVA 0xBB9EA4 → 表指针）
       表项 12 字节：{ int=4, ptr, ptr }
 → 对某表项：call 0xA01D0（按 key 查哈希表；0xA01D0 = 字符串键哈希查找，bucket@this+0x1C、mask@this+0x24）
 → 返回 0（查不到）
 → call 0xA08A0（摘除）(arg = NULL) → 崩
```

**关键证据**：VEH 转储里「查找 key」的残留栈槽所指对象，头 4 字节是**控件 vtable（RVA 0x95AC3C）**
—— 即退出时这段代码确实在处理**我们创建的控件**，对它做一次「按名字的反查」，查不到就摘空节点。

**结论 / 缺的东西**：war3 退出时会清理一张 UI 注册表；我们创建的控件被它认领，但
**缺一条按名字的注册** —— 与第七节开头「`CreateFrameByTagName` 缺少创建后注册/挂接」是同一个坑。

**为什么暂时搁置**：继续定位需要解码那张 4 项注册表与 `0x95A6FC` 那个类，估计还要 2+ 轮游戏内验证，
收益仅为「关窗口不弹框」。等框架实际用起来后，若同类问题在**运行期**暴露，再带着真实用法回来收尾
（那时更容易知道要注册哪个名字）。

**另一处同源崩溃（`EIP = 0x00000000`）**：给 `TEXT` 控件设了文本、但**没有设字体**时，
文本对象里的渲染回调保持空指针，之后某次渲染/销毁路径会 `call 0` 崩
（表现为 `Exception: 0xC0000005 at 0023:00000000`）。
→ 要安全使用文本，必须把 `FrameSetTextFont` 也做出来（或保证模板自带 `Font`）。
> 备注：`FrameSetText` 本身的写入是对的（实测 `控件本体+0x98` 写长度、`+0x9C` 写字符串指针），
> 崩的是「设了文本却没有字体」之后的那条回调路径。

#### 创建链逆向成果与残留问题（2026-10-13）

**① 「挂接」= `child->SetParent(parent, 2, 0)`（已实现）**

`RVA 0xBF9A0`（`ToolTipCost -0x27E - 0x90` → `0xBFA30 - 0x90`）：
```
mov [child+0x74], parent      ; 父指针
mov [child+0x78], idx         ; = 2（游戏自身调用形态，RVA 0xBB906）
if (parent) parent->登记(child)   ; RVA 0xB9CA0：把 child 插进 [parent+0xD4] 子链表
```
- **通知路径只读 `+0x74`/`+0x78`**：`0xBF960` → `test [this+0x7C],1` → `0xB9900([this+0x74], [this+0x78])`。
- 实测：不挂接时 `+0x74 = 0`，任何走通知的 setter（`SetFont` / `SetTextColor`）→ `0xB9900(0,…)` 读 `[0x68]` → 崩；
  补上 `+0x74/+0x78` 后 **`FrameSetTextFont` 与 `FrameSetText` 双双通过**（`+0x8C` 得字体对象、`+0x98/0x9C` 得文本）。
- ⚠️ 父侧登记 `0xB9CA0` 会 `mov ecx,[parent+0xD4]; mov eax,[ecx+4]`，而
  `GetGameUI()` 返回的对象 **`+0xD4 = 0`** → 硬调崩（`AV: RVA 0xB9D10 访问 0x4`）。
  故当前实现：**只写 `+0x74/+0x78`**，`[parent+0xD4]==0` 时跳过父侧登记。

**② 创建链（全部离线读出，`tools/gl_disasm.py`）**

```
CreateFrameByTagName
 → ctor 0x909C0(ecx=fdf条目名, edx=owner, 栈=(a1,a2,a3))；先查 frame 类型注册表(RVA 0x6FBB9CFC, 查表 0x6AEF0)
   查不到 / (entry->0x48 & 2)==0 → 返回 0
 → 0x90750(ecx=entry, edx=owner)：eax=[entry+0x100] 为「类型创建函数」
     调用形态：push a2; edx=[entry+0x28]; ecx=owner; call eax
     → 之后 0x95A50(ecx=entry, edx=owner, 栈=(edi, 新控件, a?))
         · eax = 函数表[ 0x6F95A4A0 + [entry+0x2C]*4 ]   ← ★ 按类型索引的函数表
         · if ([entry+0x38]==0) → 0xA1380(ecx=新控件, 栈=(…))   ← ★ 疑似「实例化子对象」
         · 末尾 call 函数表项，参数含 (entry, 新控件, owner)
     → 0x91430(栈上临时对象)、虚调用 [新控件+0xDC]
```
**a2 = template**（fdf 条目名）已实测传入，但**未改变** `+0x18`。

**③ 残留崩溃（启动期，`AV#1: ip=0`）——与清理函数 `RVA 0xBD280`**

```
0xBD280(this)：先把自己从全局链表（全局 RVA 0x6FB66418/0x6FB6641C）摘除
  edi = this + 8 ; 循环 9 次（esi=0..8）:
     ecx = [edi]                 ; 槽值
     if (!ecx) next
     eax = [ecx]                 ; 期望「对象的 vtable」
     call [eax+0xC]              ; ← 崩在 esi=4
     if (!eax) next
     if ([eax+0x34]) 0xBD280(eax)     ; 递归清理子对象
  jmp [[this]+4]                ; 尾调用虚析构
调用者：RVA 0xBD6BA（由全局计数 [0x6FB66420] 驱动的一次「全局清理 pass」）
```
我们控件的现场（`tf = 0x30B89760`）：
```
tf+00: 50 B0 30 53 | 01 00 00 00 | 00 00 00 00 | 00 00 00 00
tf+10: 00 00 00 00 | 00 00 00 00 | 78 97 B8 30 | 87 68 47 CF   ← +18 = tf+18(自引用哨兵!), +1C = cookie
tf+20: 88 00 F7 26 | ...                                      ← +20 = parent
```
⇒ `esi=4` 时 `ecx = [tf+0x18] = tf+0x18`（自引用），`eax = [ecx] = tf+0x18`，
`call [eax+0xC] = [tf+0x24] = 0` → **`call 0`** ⇒ 与"关窗口崩溃"同源。

**④ 已排除**：`FrameSetPoint` 不是触发条件（不调它仍崩）；把 template 作为 ctor 的第 2 栈参传入也未改变 `+0x18`。

**⑤ 下一步（建议）**：读 `0xA1380` 与函数表 `0x6F95A4A0[…]` —— **已完成（2026-10-13）**，结果见下：

- **`0xA1380(frame, str, val)`**（`ret 8`，由 `[entry+0x38]==0` 守卫）：若 `str` 非空，则用 `0x120688(str, "…", 0x265, 0)`
  新建一个类型专属对象存进 **`frame+0x160`**，再 `0x9EE70(ecx=str, edx=frame, val)`、`[frame+0x164]=val`。
  ⇒ 它管的是 `+0x160`，**不是** `+0x18`。
- **类型函数表 `0x6F95A4A0[16]`**（全部 `.text`）：`0x92A80 / 0x92A90 / 0x92C50 / 0x92E60 / 0x92E70 / 0x92F70 / 0x92FD0 / 0x932B0 /
  0x93690 / 0x93730 / 0x937D0 / 0x93A60 / 0x93C10 / 0x93CA0 / 0x93E40 / 0x93EF0`。
  `0x95A50` 里 `idx = [entry+0x2C]; fn = Table[idx]`，末尾 `call fn(edx=新控件, 栈=(…, owner, …))` —— 类型专属初始化。
- **下一步**：确定本局 `LK_TEXT` 的 `entry+0x2C` 实际取值 → 读表中命中项的**函数体**，看它对 `帧+0x18`（及 `+8..+0x28` 那 9 个槽）
  做了什么、以及是否因为我们 fdf 缺某条指令而没执行到；也就是说：**`+0x18` 应当由谁写**。
  （工具已支持读表：`python gl_disasm.py dw 0x95A4A0 16`）
- **2026-10-13 续查**：「谁写 `帧+0x18`」用新加的 `whowrites` 模式扫过：
  - 16 个类型函数（`0x92A80–0x93EF0`）范围内 **0 处** ⇒ 与 `+0x18` 无关；
  - 创建链 `0x90000–0x96000` 有 8 处，逐个反汇编后**都不是「帧的 +0x18 自初始化」**
    （例如 `0x90C69` 是「把 12 字节表项 {obj,a,b} 拷进 `esi+0x14/+0x18/+0x1C`」的数据拷贝循环）。
  ⇒ 结论：`+0x18 = 自己` 不是这些路径写的，**更可能本来就该是「内嵌空链表哨兵」**；
    于是问题重新指向「**这个控件为什么会被 `0xBD280` 那次全局清理扫到**」（它的 `+8..+0x28` 是 9 个指针槽，
    而我们的控件在那里放的是 {0,0,0,0,self,cookie,parent,0,0}）。
    下一步：查全局清理队列（全局 RVA `0x6FB66418/0x6FB6641C`，计数 `0x6FB66420`）的**插入方**，
    弄清入队条件——正常控件何时入队、我们为何提前入队。（工具新支持：`whowrites <偏移> [lo] [hi]`）
- **2026-10-13 队列链路（已查明）**：
  ```
  入队 0xBD630(this, arg1 /*ret 4*/)
      if (arg1) { call [[this]+4](); 非 0 则返回 }          ; 虚函数可否决入队
      edx = (this ? [0x6FB66418] + this : 0x6FB6641C)      ; 按对象地址算 bucket
      摘旧节点 → [edx]=旧头; [edx+4]=…; [ecx+4]=this; [0x6FB6641C]=edx
  排空 0xBD6B0()
      while ([0x6FB66420] != 0) 0xBD280([0x6FB66420]);     ; ← 崩的就是这里
  ```
  ⇒ **`0xBD280` 不是析构，而是「对已入队对象的一次处理」**；而**入队者是 `SetSize`**
  （第十节早先记录的「setW/setH 结尾 `jmp 0xBD630`」就是它，当时误标为"通知/重排"）。
  这解释了「只建控件 → 干净；一 `SetSize` → 崩」的老观察。
  工具新增：`ref <绝对地址>`（找某个全局量的引用点，据此定位读写方）。
- **2026-10-13 队列的性质（决定性）**：`0xBD630` 的 95 个调用点形态一致 ——
  `lea ecx,[reg+0xB4]` / `add ecx,0xB4` 后 `call 0xBD630`：
  ```
  lea ecx,[edi+0xb4]; call 0xBD630    (0x94082)
  add ecx,0xb4;       call 0xBD630    (0xA3758)
  lea ecx,[esi+0xb4]; call 0xBD630    (0xA93C2 / 0xA9D26 / 0xA9D4E / 0xA9E5B)
  ```
  且 `FrameSetSize` 宽/高（`0xBD960`/`0xBD7C0`）尾部就是 `jmp 0xBD630`、**`ecx` 原样传递**（即 SetSize 的 `this`）。
  ⇒ **这是「core 专用队列」**：入队对象应为 **`帧+0xB4`**，`0xBD280` 按 **core 布局**解引用 `+8..+0x28`。
  ⇒ 而崩溃现场被处理的是**帧本体**（`0x30B89760` = ctor 返回的帧指针）
  ⇒ **我们的 `FrameSetSize` 用「帧本体」当 `this`**（`frame_this()` 走了 fallback：`[帧+0xB4]` 不可读
  ⇒ 我们这类 `LK_TEXT` 帧**没有 core**），于是**把帧误入 core 专用队列** → `0xBD280` 按 core 布局
  `call [[+0x18]+0xC]` → `call 0`。
  ⇒ 这解释了全部老观察：只建控件（不入队）→ 干净；一 `SetSize` → 入队 → 崩；
  `LK_BACKDROP_*` 那批 `self = 帧+0xB4`（有 core）而 `LK_TEXT` 没有。
  **下一步**：核实 `[帧+0xB4]`（本类帧是否真无 core）；若有 core 差别，则统一走「core 取用」并保证
  `FrameSetSize/Point/Alpha` 的 `this` 与入队对象一致。
- **2026-10-13 节点编码规则（已推演）**：该"队列"是**带哨兵的循环双向链表**，哨兵 = 全局两连 dword：
  ```
  S.next = [0x6FB6641C]        S.prev = [0x6FB66420]
  [0x6FB66418] = 0（BSS）      ⇒ 节点地址 = 对象地址（edx = 0 + this）
  prev 字段编码：v<=0 → prev = ~v ； v>0 → prev = v + (node - next->prev)   ; 见 0xBD65F–0xBD66F
  空表：S.next = S（自指）; S.prev = ~S（取反编码，正好让排空循环的 jle 判定为空）
  入队 0xBD630(obj)：arg1≠0 时先问 [obj]->vtbl[1]()；随后插到哨兵之后（表头）
  处理 0xBD280(obj)：按同一编码摘除 → 遍历 obj+8..+0x28 的 9 槽 → call [[槽]+0xC]（[[槽]+8]≠0 时递归）
                    → 末尾 jmp [[obj]+4]；并把 [S.next]/[S.prev] 清零
  ```
  ⇒ **`[S.prev]` 就是"最后入队的对象地址"**。崩溃现场 `[S.prev] = 0x30B89760`（= 帧地址）
  ⇒ 那一轮的 `SetSize` 是**以"帧本体"入队**的（而非 `帧+0xB4`）——与"两类型 `[帧+0xB4]` 均可读、
  `frame_this` 应返回 `帧+0xB4`"矛盾。
  **待验证**：用「全局量快照探针」（`start.lua`：在 未建控件 / 建控件后 / SetSize 后 三点 dump
  `base+0x6FB66418` 起 0x10 字节）直接看入队身份与时机。
- **2026-10-13 快照实测（已做，`LK_BACKDROP_NIL`）**：
  ```
  1) 初始        [0x6FB66418]=0x30  S.next=0x311595FC  S.prev=0x31155A7C
  2) 建控件后    [0x6FB66418]=0x30  S.next=0x311595FC  S.prev=0x31155A7C   ← 与 1) 相同
  3) SetSize 后  [0x6FB66418]=0x30  S.next=0x31054F3C  S.prev=0x31155A7C
  ```
  ⇒ ① **`[0x6FB66418] = 0x30`**（不是 0）⇒ **节点地址 = 对象地址 + 0x30**；
  ⇒ ② 对 `LK_BACKDROP_NIL`：**创建不入队**（1)=2)），入队发生在 `SetSize`；
  ⇒ ③ 入队对象 = `self` = **`帧+0xB4`**（`S.next` 变成 `self+0x30`，日志 `frame=0x31054E58 self=0x31054F0C`）
  —— **入队身份正确**，此前"SetSize 把帧本体入队"的怀疑不成立（至少对 `LK_BACKDROP_NIL`）。
  ⇒ 列表在启动时**已含 war3 自己的节点**（`S.next/S.prev` 指向堆对象），故 `S.prev` 不随插入表头而变。
  **继续收窄**：换 `LK_TEXT`（崩溃现场用的就是它）复做同三点快照，看 `self` 是否仍为 `帧+0xB4`。
- **2026-10-13 快照实测（`LK_TEXT`，决定性）**：
  ```
  1) 初始        [0x6FB66418]=0x30  S.next=0x30E695FC  S.prev=0x30E65A7C
  2) 建控件后    [0x6FB66418]=0x30  S.next=0x30E69844  S.prev=0x30E65A7C     ← ★ 变了
  3) SetSize 后  [0x6FB66418]=0x30  S.next=0x30E69844  S.prev=0x30E65A7C     ← 不再变
  日志：created ok 0x30E69760；[帧+0xB4]=0x606EB164；SetSize self=0x30E69814 = 帧+0xB4
  ```
  ⇒ `S.next = 0x30E69844 = (帧+0xB4) + 0x30` ⇒ **`LK_TEXT` 在「创建」这一步就把 `帧+0xB4` 入了队**
  （`LK_BACKDROP_NIL` 创建时**不入队**）——**类型相关**，差别在**创建路径**，不在 setter。
  ⇒ `SetSize` 只是把同一节点再插到表头（已在表头 ⇒ 快照 3) 不变）。
  ⇒ 结论方向：**修法应落在 `CreateFrameByTagName`（创建路径）**；下一步做最小复现：
  只建 `LK_TEXT`、不调任何 setter，然后关窗口，看是否仍崩。


插件里已备好只读取证工具：`JKDumpSetters` / `JKDumpFrame` / `JKDumpMem` / `JKDumpCode` /
`JKDumpCallers` / `JKTrialSetPoint` / `JKTrialSetAlpha` / `JKProbeExitCrash`（VEH，转储崩溃现场）。

### 两个关键修复（让 SetSize 从"崩溃"变"成功"）

1. **`this` 必须是「控件 + 0xB4」，不是控件本身**
   依据是游戏自身的调用（创建 `CinematicPanel` 后）：
   ```
   6F34B3AA: call 6F0909C0        ; 构造器
   6F34B3BA: lea  ecx,[eax+0xB4]  ; ← this = 控件 + 0xB4
   6F34B3D4: call 6F0BD8A0        ; setPoint
   ```
   与插件 `FrameSetSize_a/Point_real` 里的 `LEA ESI,[frame+0xb4]` + `CMOVZ` 一致：
   若 `[frame+0xB4]` 是"可读指针"（正常控件）→ `this = frame+0xB4`；否则（simple 控件）→ `this = frame`。
   **之前传 `frame`**，`movss [ecx+0x58]` 就写到了 `frame+0x58`（错误位置）→ 写坏控件 → 崩。
2. **`R` 参数是指向实数的指针**（不是裸位模式）——见上一节。

**修复后实测**（`japi_replica.log`）：
```
resolve "ToolTipCost" -0x100 -> 0x6E6CD960  序言: 55 8B EC F3 0F 10
FrameSetSize: 准备调用 frame=0x3153A238 self=0x3153A2EC w=200.000 h=100.000
FrameSetSize: 完成
```
`self = frame + 0xB4` 成立、`w/h` 正确、无异常、游戏不崩。

### 关于 `FUN_102492e0` 的重要修正（下一步的关键）

对 `FUN_102492e0` 依赖的 8 个全局件做「交叉引用 → 反编译写入方」后，有两点结论：

**① 所有函数指针都是「可复刻」的** —— 它们全部由初始化函数 `FUN_1024e670` 用**同一套锚点+偏移**从 Game.dll 解析出来，没有外部注入：

| 全局 | 锚点字符串 / 来源 |
|---|---|
| `DAT_106e4ddc` | `(%s//%d) Error, unrecognized frametype %s!` |
| `DAT_106e4e04` | `(%s//%d) Error, frame %s cannot inherit from %s: conflicting types` |
| `DAT_106e4c38` | `FUN_10249200()` 结果 `+0x67` 处的 `convert_function` |
| `DAT_106e4de0` | 同上另一处（`FUN_10249200()` 结果 `+0x71`） |
| `DAT_106e4e00` | ` model preloaded` |
| `DAT_106e5e14` | `ResourceBarFrame` |

**② 但 `DAT_106e6158` 是插件自己的固定类型表** —— `FUN_1024e670` 末尾有：

```c
local_218[0..0x1f] = { 0x1064ce00, 0x1064cb80, ... , 0x1064cdac };   // 32 个固定字符串
for (i = 0; i < 0x20; i++) { *FUN_10254460(&DAT_106e6158, name[i]) = i; }   // map[name] = 0..31
```

循环前还插入了约 10 个 war3 现成控件名：`WORLDFRAME` / `PORTRAIT` / `MINIMAP` /
`TimeOfDayIndicator` / `TimeOfDayIndicatorTooltip` / `ResourceBarFrame` / `SimpleConsole` /
`SimpleTexture` / `SimpleString` / `SIMPLESTATUSBAR` / `SIMPLEFRAME`，
以及 32 个固定名中的一个已确认是 `SIMPLESTATUSBAR`。

**推论**：`FUN_102492e0` 处理的是**基类型控件**，并依赖插件自建的类型表。
即：`CreateFrameByTagName(frameType, name, parent, template, id)` 的正确语义是
**`frameType` = fdf 基类型**（`FRAME`/`BUTTON`/…，用于查 `DAT_106e6158` 拿索引），
**`template` = fdf 条目名**（如 `LK_BACKDROP`，交给创建函数实例化）——**两者不能混用**。

#### 已定位的 native 注册表（决定性证据）

注册表本体在 `FUN_102520f0` 内，格式为 `FUN_102ca4e0(函数地址, "名字", "签名")`。摘录：

| native | C 函数 | 签名 |
|---|---|---|
| `LoadToc` | `0x10248740` | `(S)V` |
| `CreateFrame` | `0x102483b0` | `(SII)I` |
| **`CreateFrameByTagName`** | **`0x10249740`** | `(SSISI)I` |
| `DestroyFrame` | `0x102491a0` | |
| `FrameSetSize` | `0x10247ed0` | `(IRR)V` |
| `FrameSetPoint` | `0x10248210` | `(IIIIRR)V` |
| `FrameSetAlpha` | `0x10248eb0` | `(II)V` |
| `FrameShow` | `0x10249050` | `(IB)V` |
| `FrameSetTexture` | `0x10248bd0` | `(ISI)V` |
| `FrameSetText` | `0x1024a4b0` | `(IS)V` |
| `FrameClearAllPoints` | `0x1024de00` | |
| `FrameFindByName` | `0x1024b2f0` | `(SI)I` |

即：此前假设的 `CreateFrameByTagName = FUN_10249740` **是正确**的。

> **2026-10-13：表中 6 个缺失 native（`DestroyFrame` / `FrameShow` / `FrameSetTexture` / `FrameSetModel` /
> `FrameClearAllPoints` / `FrameFindByName`）已全部实现并注册**（见 [natives.cpp](../../vendor/japi-replica/src/natives.cpp) 与 [dllmain.cpp](../../vendor/japi-replica/src/dllmain.cpp)）。

#### 反向重建出的「锚点 → 内部函数」候选表（补齐其余 setter 的施工图）

插件那套「锚点 + 偏移」表无法直接读（没有插件二进制），但可以用 `JKScanAnchorOps` 扫
`ToolTipCost` / `RealmListContainer` 两个锚点引用点附近的 `E8`，把同族的内部函数全部列出来 ——
**已知的三项完全对上**（`-0x256→0xBD960` SetSizeW、`-0x276→0xBD7C0` SetSizeH、`-0x49→0xBD8A0` SetPoint），
说明这张清单与插件的表同源。再用 `JKDumpCode` 看函数体 + `JKDumpCallers` 看游戏自身调用点的实参，得到：

| 候选 RVA | 函数体要点 | 调用点实参 | 判断 |
|---|---|---|---|
| `0xBFA30` | `arg1` 指向的 4 字节依次写 `this+0x68/6B/6A/69`，再 `call [vtbl+0x24]` 通知 | `lea eax,[esi+0x4C]; push eax`（4 字节指针） | **FrameSetTextColor**（⚠️ 实测调用抛异常 → notify 依赖「挂接」，**暂未启用**） |
| `0xC1020` | 清 `[this+0x9C]` 首字节；`arg1` 非空则调「拷贝字符串」 | 句柄→`char*` 后压栈 | **FrameSetText ✅ 已实现**（`ToolTipCost -0x23D`；实测 `this`=控件本体、`+0x98` 写长度、`+0x9C` 写指针） |
| `0x51310` | `this+8 = arg1`，带**引用计数**替换并释放旧对象 | — | 资源 setter → **FrameSetTexture** 系 |
| `0xC1170` | 取 `arg1` 首 dword → 建对象存 `this+0x8C`，类型(1/2)存 `+0x90` | 有 3 参调用点 `(esi, 0, 1)` | 背景色 setter（**已排除**）→ **Texture/Model 实为 `0xC11E0`** |
| `0xC0C20` | 按 `arg1` 的 bit0/1/2 改 `this+0xC0`，变了就尾调通知 | `[esi+0x5C]` | mode 选择器（**已排除**）→ **Show 实为 `0xC0CC0`** |
| `0xA93E0` | `arg1` 或进 `[this+0x1F0]` 的 64 位标志，并置 4 个 dirty | `[esi+0x1EC]` | 标志类 |
| `0xA9FE0`（=`0xA9FC0`+0x20） | 两个 float 存 `this+0x208/0x20C` 并置脏 | 压 `[esi+0x1E0]`,`[esi+0x1E4]`（x,y） | 坐标 setter |
| `0xC0B40` | 一个 float 存 `this+0x90`，并释放 `+0xA0/+0x8C` 的旧对象 | `(arg1, float([esi+0x34]))` | 尺寸 / 缩放 |
| `0xAA130` | 字符串写进 `[this+0x1E8]` 的内部缓冲（容量在 `+0x1E4`） | 调用点前有 sprintf 风格序列（格式串 RVA `0x6E2FB0`） | 名字 / 文本缓冲 |
| `0xB9E10` | `this+0xCC = arg1`（先做一次处理） | — | 指针 setter |
| `0xBFB10` | `mov dword [esi],0x606ECE00`（设 vtable） | — | **是构造函数**，非 setter |
| `0x324AD0` / `0x2A2F0` | 走全局表查找 / 复杂流程 | — | 通用辅助，非 setter |

> `this` 规律：`0xBFA30` / `0xC1020` / `0xC1170` / `0xC0B40` 操作的字段都落在 `+0x8C..0xB4`，
> 与 `FrameSetAlpha`（写 `this+0xAC`）同族 → 这几个的 `this` 是**控件本体**（不是 core）。
> 另外 `0xBFB10` 这个 ctor 把 `+0xAC/+0xB0/+0xB4` 清 0 并设 vtable `0x606ECE00`，可作该类对象的识别特征。

#### 6 个缺失 native 的最终定位（2026-10-13，离线反汇编确认）

用 `gl_disasm.py` 在两个锚点引用点（`ToolTipCost` ref=0x384BBB、`RealmListContainer` ref=0x2BE62A）附近
批量扫 `E8` 家族 + 逐函数反汇编，得出**决定性结论**（已全部写入 [natives.cpp](../../vendor/japi-replica/src/natives.cpp)）：

| native | 内部函数 RVA | 调用形态 | this 形态 |
|---|---|---|---|
| `FrameShow` | `0xC0CC0` | `show(ecx, 栈=show)`；改 `+0xC0` bit 0x8000，变了尾调 `0xC1500` 重排；ret 4 | **帧本体**（flags@+0xC0；调用点 `lea ecx,[edi+8]` 取证） |
| `FrameSetTexture` / `FrameSetModel` | `0xC11E0` | `setTex(ecx, 栈=(path, flag))`；释放 `+0x8C` 旧对象→建资源对象存 `+0x8C`、类型存 `+0x90`→`0xBF960` 通知；ret 8 | **core（帧+B4）**（与 SetTextFont 共用 `+0x8C` 对象槽） |
| `FrameClearAllPoints` | `0xBCCA0` | `clear(ecx)`；循环 `[core+4]` 次摘除/释放 `[core+8..]` 锚点槽 | **core**（`[core+4]`=计数、`[core+8]`=槽数组） |
| `FrameFindByName` | `0x9EF40` + `0xA01D0` | `0x120694(name)`→hash；`0x9EF40(ecx=name, edx=hash)`→全局注册表节点 `+0x18`（内层表）；`0xA01D0(ecx=inner, 栈=name)`→帧节点；id>0 手写 bucket 链步进 | 返回**帧节点**（vtable `0x95AC3C`=帧 vtable） |
| `DestroyFrame` | `0xA48B0`（+`0xA0F00` 内部析构） | `destroy(ecx, 栈=deleting)`；`[+0x168]` 引用计数、`+0xA0F00` 内调 `0x9EF60` 按名注销注册表、`deleting&1` 释放内存 | **帧本体**（`[+0x168]/[+0x170]` 引用计数字段） |

> 注意：`0xC0CC0` / `0xC11E0` / `0xBCCA0` / `0xA48B0` 均**无可直接复用的「ref-偏移 E8」调用点**
> （或 E8 位置与现有插件偏移表未逐一匹配），故全部用 **`g.base + RVA` 常量直寻址**（1.27a 专属），
> 每次调用前在日志打印序言字节供校验。`0xC11E0` 末尾 `call 0xBF960` → 调用前必须 `clear_dirty_bit`。
> `FrameFindByName` 的 id>0 链遍历按 `0xA01D0` 内部模式手写（`next = *(*(bucket+idx*12) + node + 4)`，
> `node>0` 有效，逐个校验「同 hash + 同名」）。

#### `DAT_106e6158` 的 32 个基类型名（实测读出）

```
BASE, FRAME, CONTROL, BUTTON, SPRITE, MESSAGE, TEXT, BACKDROP,
TEXTBUTTON, CHECKBOX, EDITBOX, SLIDER, SCROLL, SCROLLBAR, RADIOGROUP,
LISTBOXITEM, LISTBOX, STATUSBAR, HIGHLIGHT, MODEL, DIALOG, MENU, POPUPMENU,
CHATDISPLAY, TEXTAREA, LISTBUTTON, SIMPLETOP, SIMPLEFRAME, SIMPLEGRID,
SIMPLEBUTTON, SIMPLECHECKBOX, SIMPLESTATUSBAR
```

> ⚠️ 注意：这些基类型名在 war3 自己的 frame 注册表（`base+0xBB9CFC`）里查不到
> （实测 `FRAME`/`BUTTON`/`TEXT` 全部 `entry=0`）——它们**只存在于插件自建的这张表**里。

#### 当前实现与插件的差异

我们的 `CreateFrameByTagName` 走 **Game.dll 的 fdf-tag 构造器**（认 fdf 条目名），
所以实现上取 `template` 作为构造类型；插件则走 `FUN_102492e0`（认基类型 + 插件表 + 模板）。
两者建出的对象**等价**，但插件路径包含额外的「创建后注册/挂接」——这正是 `FrameSetPoint` 仍然异常的原因。

**setter 的逆向结论（已验证正确，暂未启用）**：

共用锚点解析器 `FUN_10246540()` = `.text` 中引用字符串 **`"ToolTipCost"`** 的位置；
各 setter 由此位置减固定偏移得到一条 `E8`，取其目标即 war3 内部方法；
调用形态统一为 **`resolved(ECX=控件+0xB4, EDX=0, 栈=参数…)`**（见「两个关键修复」）。

| setter | 锚点 | 偏移(1.27a) | 目标函数 | 实际动作 |
|---|---|---|---|---|
| SetSize 宽 | `ToolTipCost` | `-0x100` | `base+0xBD960` | `movss [ecx+0x58], xmm0` |
| SetSize 高 | `ToolTipCost` | `-0x114` | `base+0xBD7C0` | `movss [ecx+0x5C], xmm0` |
| SetPoint | `ToolTipCost` | `-0x31` | `base+0xBD8A0` | — |
| SetAlpha | `RealmListContainer` | `-0x16` | （待验证） | — |

> 崩溃链：`setW/setH` 结尾 `jmp 0x6F0BD630`（改尺寸后的通知/重排）→ 遍历控件树 → 因控件未注册读到野指针。

### 另一个已修的坑：`R` 参数传的是**指针**

本环境下 japi 的 `R` 参数不是裸位模式，而是**指向实数的指针**（依据：插件 `FrameSetSize` 反汇编
`MOV EAX,[EBP+0xc]; MOV EAX,[EAX]`）。之前当成位模式，导致 `w=0.000`。已在
`natives.cpp` 的 `read_real()` 里按"能安全读则当指针、否则当位模式"处理。

---

## 八、当前实验开关（`projects/demo/scripts/process/start.lua`）

- **已启用（连通性/能力自检）**：`JKTest`、`GetMouseX`、`JKWar3Version`、`GetKeyState`、`UnlockFps`、
  `UnlockBlpSize`、`JKFrameCtorAddr`、`JKGetGameUI`、`LoadToc`、`GetGameUI`
- **已停用（复刻期取证脚手架，需要时逐段取消注释）**：建控件 / `FrameSetSize` / `FrameSetPoint` /
  `FrameSetAlpha` / `JKFrameTypeLookup` 查表 / `JKFrameCreateRaw` / `JKProbeExitCrash`(VEH)
  —— 停用原因见第七节「已知问题：关窗口时崩溃」

插件共注册 **28 个 native**（`japi_replica.log` 可见）。

---

## 九、构建 / 部署 / 日志

```powershell
# 构建（32 位）
cd vendor/japi-replica
& $cmake --build build --config Release

# 部署到运行时目录（关键：CMake 的插件输出目录不是运行时目录）
Copy-Item build/Release/japi_replica.dll vendor/WE.v4/plugin/warcraft3/japi_replica.dll -Force
```

- 插件日志：`vendor/WE.v4/plugin/warcraft3/japi_replica.log`
- Lua 打印落盘：`vendor/WE.v4/plugin/warcraft3/xlik_lua.log`

### 🔧 离线逆向工具（**首选**，别再靠游戏内日志猜）

`vendor/japi-replica/tools/gl_disasm.py` —— 用 **Python 3.11 + Capstone** 直接反汇编本机
`D:\War3\war3 1.27\Warcraft III Frozen Throne\Game.dll`，把"抄十六进制手推 x86"换成"读汇编"：

```powershell
cd vendor/japi-replica/tools
python gl_disasm.py info                          # PE 节区 / ImageBase(0x6F000000)
python gl_disasm.py func 0xC0B40 0x120            # 反汇编某个 RVA（call/jmp 自动标注目标 RVA）
python gl_disasm.py calls 0xC0B40 3               # 列出所有调用点 + 各自前 0x30 字节反汇编
python gl_disasm.py anchor ToolTipCost -0x400 0x100   # 锚点引用点附近的 E8 → 候选函数 + 前 0x40 反汇编
python gl_disasm.py dw 0x95A4A0 16                  # 按 dword 读表（函数指针表等），镜像内的值自动换算 RVA + 标注节
python gl_disasm.py whowrites 0x18 0x90000 0x96000  # 找「谁写 [reg+0x18]」（定位某结构偏移的写入方；可限定区间）
python gl_disasm.py ref 0x6FB6641C                  # 找某全局量在 .text 里的引用点（定位它的读写方）
```

**正确的工作方式（已改为这个）**：
① 离线 `gl_disasm.py` 读清签名/语义 → ② 照着写 native → ③ **一次**游戏内验证。
不再出现"传错参数硬试"的来回。

首个战果：`0xC0B40` 读出是 `SetFont(this, char* file, float height, int flag)` 且 **`ret 0xC`**，
而初版只压了 2 个栈参（`flag` 会读到栈上垃圾）→ 已修。另外 `0xC1170` 读出是「按句柄设置资源对象
（存 `this+0x8C`、类型存 `this+0x90`）」→ 是 `FrameSetTexture` / `FrameSetModel` 的候选。

---

## 十、setter 三件套打通（SetSize / SetPoint / SetAlpha）

### 调用形态（已由机器码证实）

游戏自身在建完控件后设锚点的调用序列（RVA `0x34B3D4`，与我们完全一致）：

```
8D 88 B4 00 00 00   lea  ecx,[eax+0xB4]      ; this = 控件 + 0xB4
6A 07 56 6A 07      push 7; push esi; push 7  ; relPoint=7, relFrame=esi, point=7
E8 ...              call setPoint
```

setPoint（RVA `0xBD8A0`）的真实签名（反汇编解出）：

```
ecx        = this（控件 + 0xB4）
edx        = 未使用（函数内不读）
[ebp+0x08] = point      （0~8，见下「点序」）
[ebp+0x0C] = relFrame   ← 必须是 core 指针（控件 + 0xB4），不是原控件指针
[ebp+0x10] = relPoint
[ebp+0x14] = x          （float，屏幕比例）
[ebp+0x18] = y          （float，屏幕比例）
[ebp+0x1C] = 1
```

函数头关键指令：

```
8B 5D 08        mov  ebx,[ebp+8]        ; point
8B 74 9F 08     mov  esi,[edi+ebx*4+8]  ; 以 point 索引 this+8 起的 9 个「锚点槽」
...
8B 4D 0C        mov  ecx,[ebp+0xC]      ; relFrame → 作为内层调用的 this
8B 55 10        mov  edx,[ebp+0x10]     ; relPoint
```

### 三条关键事实（都是踩坑换来的）

1. **尺寸与偏移都是「屏幕比例」，不是像素。**
   框架侧证据：[library/class/ui/_ui.lua](../../library/class/ui/_ui.lua) 的注释
   `设置宽高尺寸[0-0.8,0-0.6]`；UI 套件里用的是 `width = 0.12` 这种量级
   （见 `vendor/assets/war3mapUI/ability_select/main.lua` 的 `relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, 0, 0.2)`）。
   ⚠️ 我们曾误传 `FrameSetSize(f, 200, 100)` → 相当于 200 倍屏幕 → 控件被拉满全屏。

2. **点序 = 暴雪 `UI_ALIGN_*`（0~8）**，实测 `7 = BOTTOM`、`4 = CENTER` 均正确：

   ```
   0 左上   1 上   2 右上
   3 左     4 中   5 右
   6 左下   7 下   8 右下
   ```

3. **只有「有尺寸 + 有锚点」的控件才会被绘制。**
   只 `FrameSetSize`、不设锚点的控件不会被绘制——这解释了「单独 SetSize 看不出任何变化」。

### ⚠️ `this` 不是「一刀切」的 core —— SetAlpha 要的是控件本体

| setter | `this` | 依据 |
|---|---|---|
| `FrameSetSize` / `FrameSetPoint` | **控件 + 0xB4**（core） | 游戏自身调用序列 `lea ecx,[eax+0xB4]` |
| `FrameSetAlpha` | **控件本体** | `frame[+0xAC]=255`（默认不透明 alpha）而 `core[+0xAC]=24`；`this=控件本体` 试验返回 ok、`this=core` 抛异常 |

`FrameSetAlpha`（RVA `0x9CA50`）的真实签名（反汇编 + 实测）：

```
ecx        = this（控件本体）
edx        = 未使用
[ebp+0x08] = alpha     （按 bl 低字节使用，0~255；框架侧 _ui.lua 注释也写 [0-255]）
[ebp+0x0C] = 递归标志  （游戏自身传 0）
```

函数头关键指令：

```
8B 5D 08            mov  ebx,[ebp+8]          ; alpha
8B 7D 0C            mov  edi,[ebp+0xC]        ; 递归标志
38 9E AC 00 00 00   cmp  byte [esi+0xAC], bl   ; 与当前 alpha 比较（相同且不递归则早退）
88 9E AC 00 00 00   mov  [esi+0xAC], bl       ; 写 alpha
FF 90 A4 00 00 00   call [eax+0xA4]           ; 通知
```

⚠️ 两个坑：① 之前只压 1 个栈参 → `[ebp+0xC]` 读到栈上垃圾 → 崩；
② 补上第 2 个栈参后 `this` 还必须是**控件本体**才能通过（core 会在 `call [eax+0xA4]` 处异常）。

### 实测证据（`japi_replica.log` + 肉眼）

```
FrameSetSize: 准备调用 frame=0x312BA238 self=0x312BA2EC w=0.120 h=0.060
FrameSetSize: 完成
FrameSetPoint: 完成
FrameSetAlpha: frame=0x312BA420 alpha=100 fn=0x6E6ACA50      ← 无「调用异常」
```

肉眼（模板 `LK_BACKDROP_NIL`、尺寸 `0.12×0.06`）：
`FrameSetPoint(7, GameUI, 7)` → 屏幕**底部中央**出现小方块；
`FrameSetPoint(4, GameUI, 4)` → 出现在**屏幕正中央**；
对中央那个 `FrameSetAlpha(…, 100)` → 它明显比底部那个**淡**（底部保持默认 255）。
（`LK_BACKDROP_NIL` 的 `BackdropEdgeFile` 是 `PathTextures\4x4Unflyable.tga`（近乎纯白），
所以外观是「白色边框 + 中间半透明黑底」——正好同时证明 fdf 的边框层与背景层都被正确绘制。）

### ⚠️ 踩坑：不要用「故意传错参」的方式试探

`relFrame` 传原控件指针（而非 core）会**先写坏控件内部的 9 个锚点槽、然后才抛异常**；
被 SEH 拦下不代表没破坏，游戏会在之后某次清理时崩溃：

```
Exception: 0xC0000005 (ACCESS_VIOLATION) at 0x52D9D2D8
  referenced memory at 0x0000040C   （槽里的对象首 dword 被写成 0x400 → call [0x40C]）
```

该处是 RVA `0xBD280`（9 个锚点槽的清理/析构）里的 `call [eax+0xC]`。
**结论：参数试验只做「确定正确」的调用，不要再做破坏性试探。**

### 本次新增的诊断 native（均为复刻期的取证工具）

| native | 签名 | 用途 |
|---|---|---|
| `JKDumpSetters` | `()I` | 转储 4 个 setter 的函数头 + `.text` 里「游戏自身调用点」前的参数装配 |
| `JKDumpFrame` | `(I)I` | 转储控件本体 / core（控件 + 0xB4）内存，查锚点槽与 alpha 字段 |
| `JKTrialSetPoint` | `(IIII)I` | 试验性调 setPoint（指定 point / relFrame / relFrame 形态），返回是否抛异常 |
| `JKTrialSetAlpha` | `(III)I` | 试验性调 SetAlpha（指定 this 形态：core / 控件本体 / `[控件+0x1E8]`+0xB4） |
| `JKDumpCode` | `(II)I` | 按 RVA 转储任意 `.text` 机器码（崩溃弹窗绝对地址 − Game.dll 基址 = RVA） |

---

## 十一、下一步

1. **【进行中】框架侧接入**：按 [xlik接入内置JAPI适配层方案.md](./xlik接入内置JAPI适配层方案.md) 增加 `library/japi/wh.lua`
   与归一化 shim（注意框架的 toc 归一化名用 `japi.FrameLoadToc` 避开已占用的 `japi.LoadToc`）。
   setter 三件套已全通，接线后 `class/ui` 即可在内置 JAPI 上跑起来。
2. **【已搁置】关窗口崩溃**：见第七节「已知问题：关窗口时崩溃」。只影响退出，不影响游戏内；
   等框架实际用起来、在运行期暴露同类线索时再回来收尾（那时更容易知道要注册哪个名字）。
3. **【2026-10-13 实现、2026-10-14 实测崩溃后暂停】其余 setter / 能力**：`FrameShow` / `FrameSetTexture` / `FrameSetModel` /
   `FrameClearAllPoints` / `FrameFindByName` / `DestroyFrame` **6 个 native 已全部实现并注册**
   （实现见 [natives.cpp](../../vendor/japi-replica/src/natives.cpp)，注册见 [dllmain.cpp](../../vendor/japi-replica/src/dllmain.cpp)）。
   6 个 native 直接调用均无异常；**但 `FrameSetTexture` 创建真实纹理对象后渲染遍历崩溃，排障未收敛已暂停**
   （详见第十二节），实验性改动已全部回退。不调用 `FrameSetTexture`/`FrameSetModel` 时项目稳定可用。
4. **`CreateFrameByTagName` 完整实现**（可选）：见第七节「关于 `FUN_102492e0` 的重要修正」——
   当前走 Game.dll 的 fdf 构造器已能满足框架用法。

---

## 十二、FrameSetTexture 实测崩溃：未闭环，已暂停并回退（2026-10-14）

**结论**：直调 `0xC11E0` 创建纹理对象后，渲染遍历崩溃；多轮取证无法在现有调用形态下收敛，
**已暂停**并回退全部实验改动。框架 UI 不调用 `FrameSetTexture`/`FrameSetModel` 时项目稳定可用。

### 崩溃链（离线反汇编 + VEH 现场双重确认）

```
渲染遍历 0xA2780: mov eax,[ecx+0x140]; test eax,eax; je 跳过 → call 0x190160
  → 0x190160 → 0x18F030（节点遍历）: mov esi,[edi+0x1C]       → AV 0x18F040 读 0x4D
  → 0x190160 → 0x18E700（run 遍历）: mov eax,[ecx+0x10]
                                     mov esi,[eax+edx*4]      → AV 0x18E707 读 0x1D
```

`SetTexture` 创建并存入 `[core+0x8C]`（= `frame+0x140`）的纹理对象（vtable RVA 0x964BA0，
分配 size = 路径长 + 0x25，路径字符串存 +0x24）：

| 偏移 | 值 | 语义 |
|---|---|---|
| `+0x10` | `1`（垃圾） | `0x18E700` 当 run 数组基址 |
| `+0x14` | `0` | — |
| `+0x18` | `0x40`（垃圾） | — |
| `+0x1C` | `0x40`（垃圾） | `0x18F030` 当节点指针 |
| `+0x20` | 路径串指针 | — |

创建路径（`0xC11E0` 开头无条件释放 `+0x8C` 旧对象 → `0x197450` 建对象 → `0x197880` 只读
`[ecx+0x10]&1` 标志）**不初始化 run 容器**。

### 实验与结论

1. `+0x14/+0x1C` 补零 → 崩点从 `0x18F040` 前进到 `0x18E707`（证明方向对；但 `+0x10` 不能清零——
   `0x18E700` 无条件解引用，清零会在更早处崩）。
2. SetTexture 第 3 参 `flag=1`（0xC1298 的 `and eax,1` 分支）→ 对象结构不变（`+0x10` 仍 1），
   该 flag 分支**不构建 run 容器**。
3. **JKRef 对照**（LK_BACKDROP_NIL 完整模板、引擎自建帧）：`frame+0x140` = **0** →
   `0xA2780` 的 `je` 直接跳过 → 引擎的 BACKDROP 帧平时**不挂纹理对象**。故对照帧无法提供
   "引擎正确构建的纹理对象"金标准。

### 判断与后续方向

`0xC11E0` 的直调路径可能本身缺"run 容器构建"环节（DZ 官方实现或另走完整函数，或该对象
需先经帧渲染注册）。继续定位需研究 `0x18E700`/`0x18F030` 的 run 语义与 `0xC11E0` 全部 33 个
调用点的参数形态。**暂不推进**。

### 已回退的实验改动

- `vendor/japi-replica/src/natives.cpp`：删除 SetTexture 成功后对对象的 `+0x14/+0x1C` 补零块；
  VEH 寄存器转储恢复"仅 ip==0"触发。
- `projects/demo/scripts/process/start.lua`：删除 JKProbeAv / JKTexAuto / JKRef / JKDumpMem 取证脚手架（git 还原到 `1b8777e`）。
- 模板树 `exe/lib/embeds/new/scripts/globals/setup/command.lua` 死代码、`xlik.fdf` 还原 HEAD。
- 保留：6 个 native 的注册与实现、`library/japi/_japi.lua` 的 `_nativeOrder` 注释说明。
