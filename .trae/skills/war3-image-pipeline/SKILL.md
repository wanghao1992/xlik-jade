---
name: war3-image-pipeline
description: 生成魔兽3卡片或图标美术并压缩为 128x128 调色板 BLP1，用于新增图鉴/技能/物品图标或缩小 TGA 资源体积。当用户要求生成卡片图、绘制图标、压缩图片、换用 BLP 时使用；不用于模型、地形或界面排版。
---

# 魔兽3 图片资源生成与压缩

一条流水线：**生成原图 → 定成 128×128 → 压成调色板 BLP → 声明资源 → 构建验证**。
产出必须尺寸不变、单张约 23KB，避免把 65KB 的 32 位 TGA 塞进地图。

## 一、路径约定

| 用途 | 位置 |
| --- | --- |
| 原始生成图（不入包） | `.tmp/<任务>_art/raw/<prefix>_01.jpg` |
| 中间 TGA（不入包） | `.tmp/<任务>_art/tga/` |
| 最终资源 | `vendor/assets/war3mapImage/<分类>/<名字>.blp` |
| 资源声明 | `projects/demo/assets/image_<分类>.lua` |

- 源图、中间文件一律放 `.tmp`，不要放进 `vendor/assets`。
- 名字清单写成 UTF-8 文本、一行一个，序号与 `raw/<prefix>_NN` 一一对应。
- 旧 TGA 备份放 `.tmp/_<分类>_tga_backup`，便于回退。

## 二、生成原图

用 `GenerateImage`（先 `ToolSearch` 取 schema，再 `DeferExecuteTool`）。要点：

- `image_size` 用 `square`；`path` 给**不带扩展名**的绝对路径，如
  `d:\Lua\xlik-jade\.tmp\codex_art\raw\card_01`。
- 一次一张、按清单顺序编号；风格句保持完全一致，只替换主体，保证整册统一。
- 提示词模板：

```
Warcraft III hand-painted trading card art: <主体与关键特征>, dark fantasy,
painterly brush strokes, dramatic rim light, rich gold and steel palette,
bust composition filling the frame, high detail, no text, no watermark, no frame
```

羁绊图把主体换成"组合意象/徽记"，用：

```
Warcraft III hand-painted bond emblem art: <主题意象>, two or more iconic elements
intertwined, dark fantasy, painterly, glowing accents, centered composition,
no text, no watermark, no frame
```

生成后先看整体预览（下一步的 `--sheet`），有明显崩坏的重生成，再进入压缩。

## 三、定尺寸（裁水印 + 方形 + 128）

```powershell
python .trae\skills\war3-image-pipeline\scripts\make_tga.py `
  --src .tmp\codex_art\raw --dst .tmp\codex_art\tga --prefix card `
  --names .tmp\codex_art\names.txt --sheet .tmp\codex_art\sheet.png
```

- 默认裁掉底部 15%（去生成工具水印），居中裁正方形，LANCZOS 缩到 128，存 32 位 TGA。
- 非 128 的旧图也可以指定 `--size`，但本项目图标统一 128。
- 打开 `sheet.png` 抽查，确认无错位、无裁剪主体。

## 四、压缩为 BLP（尺寸不变）

```powershell
python .trae\skills\war3-image-pipeline\scripts\tga2blp.py `
  --src .tmp\codex_art\tga --dst vendor\assets\war3mapImage\图鉴\卡片
```

- 256 色调色板 + Floyd-Steinberg 抖动 + 5 级 mip；单张 128×128 = **23004 B**（32 位 TGA 为 65580 B）。
- 脚本自带回读自检：全部 PSNR ≥ 30dB 才算通过；偏低就人工看图或调 `--colors`。
- 格式细节见 `references/blp1-format.md`。
- 不推荐的两条路：24 位 TGA 只省 25%；JPEG 压缩 BLP 体积更小但头结构需额外验证，默认不用。

## 五、声明与引用

1. `projects/demo/assets/image_<分类>.lua` 增加 `assets_image("<分类>/<名字>.blp")`，**blp 必须带后缀**。
2. 代码里动态拼图标路径的地方同步改后缀，例如 `setup/图鉴.lua` 的
   `('图鉴/卡片/' .. c.name .. '.blp')`。
3. 同一目录不许 `.tga` 与 `.blp` 同名共存：构建会两份都打进去，且加载优先取 tga。

## 六、构建验证

```powershell
& 'D:\Lua\xlik-jade\vendor\japi-replica\third_party\YDWE\Build\lua\luabuild\lua.exe' `
  -e "assert(loadfile([[projects\demo\assets\image_codex.lua]])) print('syntax ok')"

.\xlik.exe run demo -l!
```

- 日志里若出现 `【资源检测】image:xxx 可能未曾使用`，说明该图没被正确引用（检查声明与代码后缀）。
- 若同名旧 TGA 曾被构建过，先清 `.tmp\_local\demo\resource\war3mapImage\<分类>` 下的旧文件再打包，否则地图会同时含新旧两份。
- 对比 `大小 xx MB` 确认收益。

## 七、边界

- 用户只说"压缩、不改变尺寸"时，不要重绘、不要缩放、不要改名。
- 一次任务里新增的图片数量较多时，先跑 1~2 张验证格式与观感，再批量。
- 不要给资源重复声明别名，也不要把脚本、源图写进 `vendor/assets`。
