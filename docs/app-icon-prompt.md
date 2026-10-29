# 摩倾 MotoLean · App 图标提示词

> 原提示词：「一款记录摩托车压弯时的时速、倾角、GPS轨迹的APP」
> 问题：这是**产品功能清单**，不是**视觉描述**。模型会试图同时画出三样东西，结果是又小又碎的图标。

---

## 一、润色思路（为什么这么改）

| 原提示词的问题 | 改法 |
| --- | --- |
| 三个功能并列，没有主次 | 只留**一个视觉焦点**：压弯的倾角。速度和轨迹退为辅助符号 |
| 「记录」「APP」是抽象概念，模型无法画 | 换成可绘制实体：车身与地面的夹角、一条弧线、车轮 |
| 没规定视角/构图/配色/风格 | 逐项锁死，减少随机性 |
| 没有小尺寸约束 | 明确「60×60 仍可辨认」+ 元素≤2 + 粗线条 |
| 图标不能有文字 | 负面词里封杀 text / letters / numbers |

**核心设计巧思**：让同一条弧线同时充当三件事——**地面 / 弯道轨迹（GPS）/ 倾角刻度弧**。
一个形状承载三层语义，这是好图标和 AI 拼贴图的分界。

---

## 二、方案 A：倾角为主角（推荐）

最贴合「MotoLean（摩**倾**）」的命名，辨识度最高。

**中文版（通义 / 即梦 / 豆包）**

> iOS 应用图标，圆角方形。深空黑到石墨灰的径向渐变背景。
> 画面中央一辆极简摩托车侧视图，正以 35° 倾角压弯，纯白剪影；车轮外圈描荧光橙边。
> 车身下方一条电光青色弧线从画面左下扫向右上，同时表示路面、弯道轨迹和倾角刻度弧，
> 与车身夹角形成强烈的「倾斜感」。
> 扁平矢量风格，粗描边，高对比，居中构图，四周留白充足，画面中没有任何文字或数字。
> 现代摩托赛事仪表盘美学，边缘锐利，轻微内发光。1:1 正方形。

**英文版（Midjourney / DALL·E / Flux / SDXL）**

```
iOS app icon, rounded square, deep charcoal black radial gradient background.
A single minimalist motorcycle in pure white silhouette leaning hard into a corner
at a 35 degree lean angle, side view. Wheel rims accented in neon orange.
A glowing electric cyan arc sweeps beneath the bike from lower-left to upper-right,
reading at once as the road edge, the cornering line and the lean-angle arc.
Flat vector illustration, bold thick strokes, high contrast, centered composition,
generous negative space, no text no letters no numbers.
Legible at 60x60 px, modern motorsport telemetry aesthetic, crisp geometric edges,
subtle inner glow. --ar 1:1 --style raw
```

**负面提示词（SDXL / Flux 必填）**

```
text, letters, numbers, words, watermark, signature, logo, rider, human figure, face,
helmet detail, spokes, chain, exhaust pipes, engine detail, multiple motorcycles,
cluttered background, thin hairlines, low contrast, muddy colors, drop shadow outside
the icon, blurry, jpeg artifacts, photo, 3d render noise
```

---

## 三、方案 B：俯视弯道（科技感 / 地图感）

强调 GPS 轨迹，视觉更「数据」。

```
iOS app icon, top-down view. A sweeping S-curve ribbon of neon cyan across a dark navy
background, reading as a GPS track. A tiny motorbike silhouette leans into the apex,
with a visible lean-angle gap between the bike and the road centerline.
Two short neon orange speed streaks trail the bike. Flat vector, geometric, high contrast,
centered, no text, no numbers, legible at small sizes. --ar 1:1
```

---

## 四、方案 C：仪表盘 / 角度表（硬核仪表风）

把「倾角」抽象成指针 + 刻度，避开具象摩托的绘制难度。

```
iOS app icon, abstract instrument gauge. A bold neon orange needle tilted 40 degrees
inside a white arc scale with tick marks, on near-black background. The needle's tip
extends into a simplified leaning motorcycle silhouette. One electric cyan trail curve
cuts across the dial. Flat minimal vector, high contrast, no numbers, no text,
centered, legible at 60x60. --ar 1:1
```

---

## 五、风格变体（替换方案 A 的末段即可）

| 风格 | 替换语句 |
| --- | --- |
| 扁平矢量（推荐） | `flat vector illustration, bold thick strokes, crisp geometric edges` |
| 新拟物 3D | `glossy 3D render, soft studio lighting, clay material, subtle bevel, octane render` |
| 霓虹赛博 | `neon glow, dark cyberpunk, volumetric light streaks, high saturation` |
| 极简单色 | `monochrome, single accent color, ultra minimal, negative space logo` |

## 六、配色（可直接替换）

| 用途 | 色值 | 说明 |
| --- | --- | --- |
| 背景 | `#0B0F14 → #161C24` | 深空黑径向渐变，图标不透光更稳 |
| 主色 | `#FF5A1F` | 荧光橙 = 速度与激情 |
| 辅色 | `#00E5FF` | 电光青 = GPS / 数据 / 科技 |
| 中性 | `#FFFFFF` | 车身剪影 |

想沿用当前品牌色（`assets/app_icon.png` 的青蓝渐变 + `#0E9CB4`），把背景换成
`teal-to-deep-blue gradient (#17C3DB → #0B6E8F)`，辅色保留白色，仅用橙色点缀车轮。

---

## 七、出图后验收清单

- [ ] 导出 **1024×1024** PNG（无 alpha 通道，iOS 要求）
- [ ] 缩到 **60×60** 看：能一眼认出「倾斜的摩托 + 一条弧线」吗？细节糊掉就删细节
- [ ] 缩到 **29×29** 看：还有形状感吗？只剩色块说明元素太多
- [ ] 主元素留白 ≥ 画面 12%（iOS 圆角会切掉四角）
- [ ] **Android 自适应图标**：前景元素全部落在中间 **66% 安全区**内（配置在 `pubspec.yaml` 的
      `flutter_launcher_icons.adaptive_icon_foreground`，背景色 `#0E9CB4`）
- [ ] 生成一版**单色版**（纯白 / 纯黑），用于通知栏与系统小图标
- [ ] 检查无任何文字、数字、水印

## 八、迭代技巧

1. 倾角太小（像停车）→ 把 `35 degree` 改成 `45–50 degree`，并加 `front wheel turned into the corner`
2. 摩托画成自行车 → 加 `wide rear tire, low-slung sportbike, fairing, aggressive stance`
3. 太写实、脏 → 加 `flat vector, no gradients, two colors only, poster-like`
4. 元素太满 → 加 `extremely minimal, 2 elements maximum, lots of negative space`
5. 想要 A/B 对比 → 同一段 prompt 固定 seed 跑 4 张，只改配色
