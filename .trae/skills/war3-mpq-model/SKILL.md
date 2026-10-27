---
name: war3-mpq-model
description: Extract Warcraft III mdx models from local MPQ archives and strip CAMS chunks. Use when a project needs a native war3 model or a UI-safe copy (提取原生模型、MPQ、剥离CAMS、头像模型). Do not use for editing models or non-war3 assets.
---

# 魔兽原生模型提取

从本机魔兽安装目录的 MPQ 归档中查找、提取 `.mdx` 模型，并按 chunk 标签剥离（常用 `CAMS`），再落到项目的资源目录并注册别名。

脚本：[scripts/extract_mdx.py](scripts/extract_mdx.py)（依赖 `mpyq`，纯 Python，不受 32/64 位限制）。

## 流程

1. **定位模型**：按关键字模糊搜，不要猜精确路径（MPQ 的 listfile 往往不全）

```bash
python scripts/extract_mdx.py find Vengeance --detail
```

2. **确认 chunk 构成**（是否带 `CAMS`、结构是否正常）

```bash
python scripts/extract_mdx.py info "units\nightelf\Vengeance\Vengeance.mdx"
```

3. **提取**（默认剥离 `CAMS`；`--strip ""` 表示原样导出）

```bash
python scripts/extract_mdx.py get "units\nightelf\Vengeance\Vengeance.mdx" --out out.mdx
```

4. **放入项目资源目录**：`vendor/assets/war3mapModel/<子目录>/<别名>.mdx`

5. **注册别名**（如 `projects/demo/assets/model_self.lua`）

```lua
assets_model("job/VengeanceJobCard", "VengeanceJobCard")
```

6. **构建并确认产物**

```bash
xlik.exe run demo -l!
```

检查 `.tmp/_local/demo/resource/war3mapModel/` 下存在对应文件，且构建脚本里出现 `assets_pset("model", "<小写别名>", "war3mapModel\\<别名>.mdl")`。

批量提取可直接给 jobs 文件（每行 `源路径|输出文件名`，`#` 为注释）：

```bash
python scripts/extract_mdx.py batch jobs.txt --out-dir ../assets/war3mapModel/job
```

魔兽目录缺省自动探测（`WAR3_DIR` 环境变量或常见安装路径），否则传 `--mpq-dir`。

## 关键约定与坑

- **扩展名**：Lua/物编里写 `.mdl`，MPQ 里实际是 `.mdx`，引擎自动回退；`assets_model` 注册出的别名也是 `.mdl`，这是正常的。
- **路径转义**：Lua 源里是 `"units\\human\\Footman\\Footman.mdl"`，传给脚本前要还原成单个 `\`。
- **归档顺序**：`war3.mpq` → `War3xLocal.mpq` → `War3x.mpq` → `War3Patch.mpq`。资料片新增模型（如 `HeroGoblinAlchemist`）只在 `War3Patch.mpq` 里，四个都要搜。
- **不要用 stormlib**：随仓库的 `stormlib.dll` 是 32 位，64 位 Python 用 ctypes 加载会报 `WinError 193`；用 `mpyq`（`python -m pip install mpyq`）。
- **MDX 结构**：文件头只有 `MDLX`(4 字节)，之后是 `标签(4)+长度(4)+数据` 的 chunk 序列，**没有全局长度字段**，所以删除 chunk 只需整段移除，不用改文件头。
- **必须复核**：剥离后对输出文件跑一次 `info`，确认 `CAMS=False` 且所有 chunk 后面没有 `<结构异常>`。

## 什么时候要剥离 CAMS

- `CAMS` 是模型内置相机。**UI 模型帧**（`DzFrameSetModel`，即 `UIModel`/`LK_MODEL`）渲染带 `CAMS` 的模型时会按模型自带相机取景，实测常表现为**画面空白**。
- 更隐蔽的问题：同一路径的模型一旦被 UI 模型帧加载过，之后单位再用它，**动作序列会错乱**（站立播 Walk、攻击不播 Attack）。所以 UI 预览不能用单位本体模型，必须用**另一个文件路径**的副本。
- `_Portrait.mdx` 全部带 `CAMS`，且序列名多为 `Portrait / Base / Stand - 2`，大多**没有 `Stand`**，不适合直接当卡片预览。
- 因此卡片/头像预览的推荐做法：提取单位模型 → 剥离 `CAMS` → 另存为 `<名字>JobCard.mdx` 之类的独立文件 → 注册别名给 UI 用。
- 体积：单位模型体积可观，全职业复制量级约 +7 MB，会直接体现在地图大小上，按需生成。

## 产物校验（可选）

```bash
python scripts/extract_mdx.py info "vendor/assets/war3mapModel/job/VengeanceJobCard.mdx"
```

对本地产物也能直接读，`归档` 会显示 `<本地文件>`。
