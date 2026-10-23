# 功能规划：零百加速测试 + 设置页面

> 状态：**已实现**（见文末「实现记录」）
> 目标版本：v0.2.0
> 编写依据：当前代码库（Flutter 3.47.7 / Dart 3.13.5，单 commit `0a6d586`）

---

## 1. 背景与目标

MotoLean 目前只做一件事：**记录一段骑行**（倾角 / 速度 / 轨迹 / 海拔），产出一条行程和一份总结。这一次要补两块能力：

1. **零百加速测试**：从静止起步，测 0–100 km/h 用时，附带 0–60、60–130 等分段成绩、起步距离、坡度、GPS 质量，形成可对比的成绩记录。
2. **设置页面**：把散落在代码里的硬编码（单位、精度阈值、校准时长、地图、导出）收拢成集中配置，并给零百测试留配置位。

原则：

- **不破坏现有骑行记录流程**，零百是并行的第二个功能入口。
- **内部统一用 SI 单位**（m、m/s、m），只在展示层换算，避免"数据存了 km/h 之后无法切换单位"的坑。
- **算法可单测**：计时与判定逻辑放进纯 Dart 类，不依赖平台通道。

---

## 2. 现有架构盘点（可复用资产）

| 资产 | 位置 | 复用方式 |
| --- | --- | --- |
| 1 Hz 定位流（含 Android 前台服务通知） | [location_service.dart:101](../lib/services/location_service.dart:101) | 零百直接复用，不新建定位通道 |
| 50 Hz 加速度计 / 陀螺仪 | [sensor_service.dart:14](../lib/services/sensor_service.dart:14) | 零百起步检测可选接入 |
| SQLite + Web 内存双实现 | [ride_store.dart:28](../lib/services/ride_store.dart:28) | 新表按同样模式扩展，Web 预览继续可用 |
| 地图组件（Esri 卫星图 + 倾角着色） | [ride_map.dart](../lib/widgets/ride_map.dart) | 零百结果页直接复用 |
| 深色主题 + 卡片规范 | [theme.dart](../lib/theme.dart) | 设置页沿用 `cardDecoration()` / `AppColors` |
| ChangeNotifier + AnimatedBuilder 状态模式 | [record_screen.dart:162](../lib/screens/record_screen.dart:162) | 零百记录器与设置服务都用同一模式 |
| 返回拦截 `PopScope` | [record_screen.dart:153](../lib/screens/record_screen.dart:153) | 测试中误触返回时二次确认 |
| 分享导出（share_plus） | [summary_screen.dart:82](../lib/screens/summary_screen.dart:82) | 零百成绩分享/导出复用 |
| 格式化工具 | [format.dart](../lib/utils/format.dart) | 扩展为带单位的版本 |

**当前缺失**：本地偏好存储（无 `shared_preferences`）、单位抽象、数据库迁移（现在 `version: 1`，没有 `onUpgrade`）。

---

## 3. 功能一：零百加速测试

### 3.1 用户流程

```
首页「零百加速」入口
   ↓
准备页：检查 GPS 精度 / 静止状态 / 选择测试目标（60 / 100 / 200 km/h）
   ↓
就绪（GPS ≤ 15 m，速度 ≈ 0）→ 可选 3-2-1 倒计时
   ↓
计时页：大号实时速度 + 已用时间 + 实时 G 值 + 结束按钮
   ↓（速度达标自动结束，或手动提前结束）
结果页：0–100 用时、0–60、60–130、起步距离、平均坡度、GPS 精度、位置
   ↓
保存到「加速成绩」列表（首页区块），可删除 / 分享 / 导出 CSV
```

### 3.2 技术方案

#### 数据源

| 来源 | 频率 | 用途 | 精度 |
| --- | --- | --- | --- |
| `Position.speed`（多普勒测速） | 约 1 Hz | **主计时依据** | ±0.1–0.5 m/s（比位置差分准） |
| `Position` 经纬度 | 约 1 Hz | 起步距离、轨迹、位置 | ±3–15 m |
| 加速度计 | 50 Hz | 起步瞬间检测（补 GPS 1 Hz 的盲区） | 受安装角度影响 |
| `Position.altitude` | 约 1 Hz | 坡度估算（只记录，默认不做修正） | ±5–10 m，需平滑 |

> **关键限制**：手机 GPS 普遍 1 Hz，一次 0–100 只有 5–8 个速度点。必须做**线性插值**求精确达速时刻，否则误差会到 ±0.5 s。这是本功能最大的精度瓶颈，方案里所有"误差"承诺都以此为前提。

#### 采样策略

- 复用 `LocationService.positionStream()`，但**不为该页面启动前台服务**（测试通常 < 30 秒，人在车上看屏幕，前台定位足够）。
- 若用户开启"记录全程轨迹"，额外订阅 `SensorService` 读加速度（50 Hz），用于起步检测。
- 采样点本地缓存为 `List<SpeedPoint>`，结束时一次性写库，避免测试过程中产生大量 SQLite 写入。

#### 计时算法（核心，纯 Dart 可单测）

输入：按时间排序的 `(tMs, speedMs, accuracyM, lat, lon, altitudeM)` 序列。

```
1. 预处理
   - 丢弃 accuracy > 阈值（设置项，默认 35 m）的样本
   - 速度限幅 0–120 m/s，剔除 NaN/Inf
   - 检查空洞：相邻样本间隔 > 1.5 s → 本次成绩标记"数据不足"，建议重测

2. 起步检测 t0
   - 阈值 v_start = rollout ? 1.8 m/s(≈6.5 km/h) : 0.50 m/s
   - 找第一个 speed >= v_start 的样本 i，在 i-1 与 i 之间线性插值出 t0
   - 可选增强：用加速度计找到 |a| 突增的 0.3 s 前作为 t0，与 GPS 结果比对，取较早者

3. 达速检测 t_target
   - 找第一个 speed >= v_target 的样本 j，在 j-1 与 j 之间线性插值：
     t_target = t_{j-1} + (v_target - v_{j-1}) / (v_j - v_{j-1}) * (t_j - t_{j-1})

4. 成绩 = t_target - t0（毫秒，展示保留两位小数）

5. 有效性判定（任一触发则标记"无效"，仍保存但置灰）
   - 速度序列在达速前出现 > 15% 的回落（打滑 / 松油门）
   - 起步前 3 秒平均速度 > 1 m/s（没停稳）
   - 全程 GPS 精度中位数 > 30 m
   - 样本数 < 3

6. 派生指标
   - 0–60 / 60–130：同一套插值函数，传入不同阈值
   - 起步距离：对 t0..t_target 的经纬度累加 `distanceMeters()`（已有工具）
   - 平均坡度：海拔差 / 水平距离 × 100%，海拔先做 0.25 系数平滑
   - 最大 GPS 加速度：dv/dt 的峰值（辅助判断是否打滑）
```

**1 英尺 rollout**：美式媒体口径（车移动约 30 cm 后开始计时，等效约 0.2–0.3 s）。设置为**可选开关，默认关闭**（已定：从静止起算，符合国内习惯）。开启后在结果页标注 "rollout"。同一份数据两种口径都算得出来，存库时记录 `rollout` 标记，避免成绩不可比。

**不做的事**（明确边界，避免过度承诺）：

- 不做 GPS 延迟硬件补偿（需要外部参考源）
- 不做 IMU 速度积分作为主数据源（漂移不可控），只做起步检测的辅助
- 不做坡度成绩修正（可作为后续实验开关）

### 3.3 数据模型与存储

新增两张表，`RideStore` 从 `version: 1` 升到 `version: 2`（必须有 `onUpgrade`，老用户数据不动）：

```sql
CREATE TABLE acceleration_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at INTEGER NOT NULL,          -- 毫秒时间戳
  target_speed_kmh REAL NOT NULL,       -- 主目标，通常是 100
  result_ms INTEGER NOT NULL,           -- 成绩
  rollout INTEGER NOT NULL DEFAULT 0,   -- 是否含 1 英尺 rollout
  result_60_ms INTEGER,                 -- 0-60 成绩（可空）
  result_130_ms INTEGER,                -- 60-130 成绩（可空）
  distance_m REAL,                      -- 起步到达速的距离
  max_speed_kmh REAL,
  grade_percent REAL,                   -- 平均坡度
  gps_accuracy_m REAL,                  -- 精度中位数
  start_lat REAL, start_lon REAL,
  valid INTEGER NOT NULL DEFAULT 1,     -- 有效性
  is_demo INTEGER NOT NULL DEFAULT 0,
  note TEXT
);

CREATE TABLE acceleration_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER NOT NULL,
  t_ms INTEGER NOT NULL,
  speed_kmh REAL NOT NULL,
  accuracy_m REAL,
  lat REAL, lon REAL,
  FOREIGN KEY (run_id) REFERENCES acceleration_runs (id) ON DELETE CASCADE
);
CREATE INDEX idx_accel_samples_run ON acceleration_samples (run_id, t_ms);
```

Dart 模型：`lib/models/acceleration_run.dart`、`lib/models/acceleration_sample.dart`，沿用 `RideSession` 的 `toMap / fromMap / copyWith` 写法（[ride_session.dart:76](../lib/models/ride_session.dart:76)），保持风格一致。

**Web 预览**：内存实现同样支持，用 `_useMemory` 分支（同 [ride_store.dart:78](../lib/services/ride_store.dart:78)），演示成绩可一键载入，和现有演示行程逻辑一致。

### 3.4 页面与状态机

新增 `lib/screens/acceleration_screen.dart`，状态机与 `RideRecorder` 平行：

```
idle → waitingGps → ready → countdown(可选) → running → finished(结果) → saved
                        ↑                        ↓
                      failed ←—————————————— 数据不足
```

| 状态 | 界面要点 |
| --- | --- |
| `waitingGps` | 显示 GPS 精度环形指示（≤15 m 变绿），未达标时不可开始，给出"到空旷处"提示 |
| `ready` | 大号"踩下油门"提示 + 目标速度选择（60/100/200）+ rollout 开关 |
| `countdown` | 3-2-1 大字，可关闭（设置项） |
| `running` | 速度大数字（沿用 82px 字号，[record_screen.dart:644](../lib/screens/record_screen.dart:644)）、毫秒计时、实时 G 值、进度条到目标速度、结束按钮 |
| `finished` | 结果大字（如 `4.82 s`）、分段成绩、坡度、GPS 精度、地图缩略图、"分享" / "再测一次" / "保存" |

结果页可参照 `SummaryScreen` 的结构（[summary_screen.dart:209](../lib/screens/summary_screen.dart:209)）：顶部大数 + 统计卡网格 + 地图 + 底部按钮。

### 3.5 首页集成（已定：独立成绩页面）

在现有 Hero 卡片下方（[home_screen.dart:175](../lib/screens/home_screen.dart:175) 的 `_HeroCard` 之后）插入一张**零百入口卡**：

- 主按钮「零百加速」→ 进入准备/计时页
- 卡片右侧显示历史最佳 0–100 成绩（无记录时显示 `—`）
- 卡片下方一个「成绩记录」入口 → 进入独立的**加速成绩页面**
- 卡片风格复用 `cardDecoration()`，图标 `Icons.speed_rounded`

新增 `lib/screens/acceleration_history_screen.dart`（独立成绩页）：

- 顶部统计条：总测试次数、最佳 0–100、最佳 0–60、最佳 60–130
- 成绩列表：按时间倒序，每条显示 `0–100 4.82s · 10月23日 · 坡度 +2.1% · GPS ±8m`
- 无效成绩置灰并标「数据不足」
- 每项滑动删除（`Dismissible`）+ 二次确认；也可以点进结果页查看曲线与地图
- 空状态引导「去测一次」，复用首页空态设计语言（[home_screen.dart:720](../lib/screens/home_screen.dart:720)）

首页与成绩页之间的刷新：成绩页返回时刷新入口卡的最佳成绩，沿用 `_openSummary` 的做法（[home_screen.dart:72](../lib/screens/home_screen.dart:72)）。

---

## 4. 功能二：设置页面

### 4.1 设置项清单

| 分组 | 设置项 | 类型 | 默认值 | 影响范围 |
| --- | --- | --- | --- | --- |
| **单位** | 速度单位 | km/h / mph | km/h | 首页、记录页、总结页、零百 |
| | 距离单位 | km / mi | km | 同上 |
| | 倾角显示 | 度（暂只支持度） | ° | 记录页、总结页 |
| **记录** | 校准时长 | 2 / 3 / 5 秒 | 3 秒 | `RideRecorder` 校准计时 |
| | GPS 精度阈值 | 10–50 m 滑块 | 35 m | 采样过滤、精度徽标配色 |
| | 默认开启屏幕常亮 | 开关 | 关 | 记录页初始状态 |
| | 结束前二次确认 | 开关 | 开 | 记录页 / 零百页返回 |
| **零百测试** | 默认目标速度 | 60 / 100 / 200 | 100 | 零百准备页 |
| | 1 英尺 rollout | 开关 | 关 | 计时算法 |
| | 起步倒计时 | 0 / 3 秒 | 3 秒 | 零百流程 |
| | 记录全程轨迹 | 开关 | 开 | 是否订阅 IMU + 存轨迹 |
| **地图** | 显示实时轨迹 | 开关 | 开 | 记录页地图 |
| | 底图 | 卫星 / 简约暗色 | 卫星 | `RideMap` 瓦片源 |
| **数据** | 导出全部行程 | 操作 | — | 生成 GPX（合并）+ CSV |
| | 清空全部骑行记录 | 危险操作 | — | 二次确认 + 输入确认词 |
| | 清空加速成绩 | 危险操作 | — | 同上 |
| | 演示数据 | 操作 | — | 载入 / 清除演示 |
| **关于** | 版本号 / 开源许可 / 隐私说明 / 测量说明 | 只读 | — | — |

**刻意不做的设置**（避免过度设计）：

- 主题切换（当前深色主题是产品辨识度的一部分，且浅色主题需要重做整套配色，工作量 ≈ 设置页本身）
- 语言切换（当前只支持中文，`MaterialApp` 已硬编码 `zh_CN`）
- 采样率自定义（受硬件限制，改了也无效）

### 4.2 技术方案

- 依赖：`shared_preferences`（键值存储，跨 Android/iOS/Web 一致）。**不加数据库表**，因为设置不需要查询、不需要事务。
- 新增 `lib/services/settings_service.dart`：

```dart
class SettingsService extends ChangeNotifier {
  Future<void> load();                 // 启动时读
  // 字段：speedUnit, distanceUnit, calibrationSeconds, gpsAccuracyLimit,
  //       defaultScreenAwake, confirmBeforeStop, accelTargetSpeed,
  //       accelRollout, accelCountdown, accelRecordTrack, showLiveTrack, mapStyle
  Future<void> setSpeedUnit(SpeedUnit value);  // set 后 notify + 异步落盘
}
```

- `main.dart` 在 `RideStore.init()` 之前/之后初始化 `SettingsService`（[main.dart:20](../lib/main.dart:20)），失败时回退默认值而不是崩掉。
- `app.dart` 用 `AnimatedBuilder(animation: settings)` 包住 `MaterialApp`，让主题/单位变更立即生效（[app.dart:15](../lib/app.dart:15)）。
- 单位换算统一放 `lib/utils/units.dart`：

```dart
enum SpeedUnit { kmh, mph }
enum DistanceUnit { km, mi }

String formatSpeedValue(double mps, SpeedUnit unit);   // 数值
String speedUnitLabel(SpeedUnit unit);                 // "km/h" / "mph"
String formatDistanceValue(double meters, DistanceUnit unit);
```

- 改造现有硬编码：`formatSpeed()`（[format.dart:19](../lib/utils/format.dart:19)）、`formatDistance()`（[format.dart:12](../lib/utils/format.dart:12)）、以及 `record_screen.dart` / `summary_screen.dart` 里直接写死的 `'km/h'` 字符串。这一步是**改动面最大**的部分，会影响现有测试的断言。

### 4.3 页面结构

`lib/screens/settings_screen.dart`，标准分组列表：

```
设置
├── 单位            → 速度 / 距离
├── 记录            → 校准时长、GPS 阈值、屏幕常亮、二次确认
├── 零百加速        → 目标速度、rollout、倒计时、记录轨迹
├── 地图            → 实时轨迹、底图
├── 数据            → 导出全部、清空记录、演示数据
└── 关于            → 版本、许可、隐私、测量说明
```

- 每行用统一的 `lib/widgets/settings_tile.dart`：`_SettingsTile(icon, title, subtitle, trailing)`。
- 开关用 `Switch.adaptive`，单选用底部弹窗（`showModalBottomSheet`，与现有 `_MeasurementInfoSheet` 风格一致，[home_screen.dart:121](../lib/screens/home_screen.dart:121)）。
- 危险操作用 `AlertDialog` + 红色按钮（与"删除行程"一致，[summary_screen.dart:110](../lib/screens/summary_screen.dart:110)）。
- 入口：首页 `_Header` 右侧加一个齿轮按钮（现在只有一个 info 按钮，[home_screen.dart:360](../lib/screens/home_screen.dart:360)）。

---

## 5. 工程结构变更清单

### 新增

```
lib/models/acceleration_run.dart
lib/models/acceleration_sample.dart
lib/services/settings_service.dart
lib/services/acceleration_recorder.dart      # 状态机 + 采集
lib/utils/units.dart
lib/screens/settings_screen.dart
lib/screens/acceleration_screen.dart          # 准备 / 计时
lib/screens/acceleration_history_screen.dart  # 独立成绩页
lib/screens/acceleration_result_screen.dart   # 结果 / 分享
lib/widgets/settings_tile.dart
test/acceleration_timer_test.dart             # 算法单测（重点）
test/settings_service_test.dart
test/acceleration_store_test.dart
```

### 修改

```
pubspec.yaml                     # + shared_preferences
lib/main.dart                    # 初始化 SettingsService
lib/app.dart                     # 注入 settings，主题/语言响应
lib/screens/home_screen.dart     # 零百入口卡 + 设置按钮 + 成绩列表
lib/services/ride_store.dart     # v2 迁移、零百表 CRUD、清空接口
lib/utils/format.dart            # 单位化
lib/screens/record_screen.dart   # 单位化 + 校准时长/常亮读取设置
lib/screens/summary_screen.dart  # 单位化
lib/services/ride_recorder.dart  # 校准时长参数化
README.md                        # 新功能说明
```

### 数据库迁移

```dart
version: 2,
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 2) {
    await db.execute('''CREATE TABLE acceleration_runs (...)''');
    await db.execute('''CREATE TABLE acceleration_samples (...)''');
    await db.execute('''CREATE INDEX ...''');
  }
},
```

> 注意：`onCreate` 里要把 v2 的全部表也建好（新装用户走 `onCreate`，老用户走 `onUpgrade`）。建议把建表 SQL 抽成常量，两条路径共用，避免两处不一致——这是最容易埋 bug 的地方。

---

## 6. 分阶段实施计划

| 阶段 | 内容 | 交付物 | 估时 |
| --- | --- | --- | --- |
| **P0 地基** | `SettingsService` + `units.dart`（含 km/h 与 mph）+ 数据库 v2 迁移 + 空设置页 | 设置项能存能读，单位切换在总结页生效 | 3 天 |
| **P1 设置页打磨** | 全部分组 UI、危险操作确认、导出全部、演示数据管理 | 完整设置页 | 2 天 |
| **P2 零百算法** | `acceleration_recorder.dart` 的计时/判定纯逻辑 + 单测（先不接 UI） | 用构造速度序列验证误差 < 50 ms | 2 天 |
| **P3 零百 UI** | 准备页、计时页、状态机、GPS 就绪判定、倒计时 | 可在真机跑通一次测试 | 3 天 |
| **P4 结果与历史** | 结果页、分享、CSV 导出、独立成绩页、删除 | 闭环 | 2.5 天 |
| **P5 联调收尾** | 真机验证、`flutter analyze`、全量测试、README、隐私说明更新 | 可发布 | 2 天 |

合计约 **14.5 天**（单人，不含真机路测）。若砍掉设置页的"数据管理"分组，可压到 12 天。

**建议顺序**：P0 → P2 → P3 → P4 → P1 → P5。即**先把零百算法与流程跑通，再回头做设置页打磨**——因为零百是用户的真实诉求，设置页是配套；且设置页的大部分项要等零百的配置需求明确后才知道该放什么。

---

## 7. 测试策略

| 层级 | 内容 |
| --- | --- |
| 算法单测（最重要） | 构造已知速度曲线：匀速、线性加速、带噪声、有回落（打滑）、有空洞（隧道），断言 `result_ms` 与真值误差 < 50 ms；rollout 开关两种口径一致性 |
| 存储测试 | 沿用 `ride_store_memory_test.dart` 的风格，验证零百 CRUD、级联删除、v1→v2 迁移（可用 `sqflite_common_ffi` 跑真实 SQLite，或仅测内存实现） |
| Widget 测试 | 设置页各组渲染、单位切换后数值变化、危险操作弹窗、零百页面各状态渲染 |
| 真机验证 | 封闭场地实测，与视频帧/OBD 对比；记录不同机型 GPS 精度差异 |

现有测试基线（[test/](../test/)）：算法、存储、导出、界面共 8 个文件，改动 `format.dart` 后需同步更新断言。

---

## 8. 风险与边界

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| GPS 1 Hz + 插值误差 | 0–100 成绩误差约 ±0.1–0.3 s，不同机型不一致 | UI 标注"手机 GPS 估算，非专业设备"；结果页显示 GPS 精度与样本数；无效成绩置灰 |
| GPS 输出延迟 | 达速时刻系统性偏晚 | 不做硬件补偿；同一设备横向对比仍有效；文案说明"成绩只适用于同机对比" |
| 起步瞬间 GPS 未更新 | t0 偏差可达 1 s | 加速度计辅助起步检测（可选开启） |
| 坡度影响 | 上坡慢、下坡快 | 记录坡度；成绩卡显示"坡度 +2.1%"；不提供修正 |
| 安全 | 公共道路测零百极其危险 | 准备页强制安全提示；首页入口卡注明"仅在封闭场地"；不做排行榜/社交 |
| 数据库迁移 | 老用户升级后丢数据 | 抽公共建表 SQL + 迁移单测；升级前先 `flutter build` 验证 |
| 单位改造面广 | 现有测试断言大面积失败 | 先加 `units.dart` 并提供默认 km/h 行为，再逐屏替换，测试跟着改 |

**明确的非目标**：不做排行榜/云端对比、不做 OBD 接入、不做视频叠加、不做赛道圈速。

---

## 9. 已确认的决策

| 决策 | 结论 |
| --- | --- |
| 零百口径 | **默认从静止起算**，1 英尺 rollout 作为可选开关（默认关） |
| 成绩入口 | **独立「加速成绩」页面**，从首页入口卡进入 |
| 单位 | **km/h 与 mph 都支持**（内部仍存 SI，仅展示层换算） |
| 设置页范围 | 含"清空全部数据"，但必须二次确认（默认纳入方案，可砍） |
| 主题 | 不做浅色主题（工作量 2–3 天，且会稀释现有深色辨识度） |

其余细节在开发前定即可，不影响开始 P0。

---

## 10. 附：一次典型 0–100 的数据形态（便于理解算法）

假设 5.2 秒完成，GPS 1 Hz：

| t (s) | v (km/h) | 说明 |
| --- | --- | --- |
| 0.0 | 0.8 | 起步后第一个有效帧 |
| 1.0 | 28.4 | |
| 2.0 | 51.2 | |
| 3.0 | 68.9 | |
| 4.0 | 82.5 | |
| 5.0 | 95.1 | |
| 6.0 | 104.3 | 首次超过 100 |

线性插值：`t = 5.0 + (100 − 95.1) / (104.3 − 95.1) × 1.0 ≈ 5.53 s`，再减去起步插值点，得成绩约 **5.42 s**。

这正是"为什么必须插值"：直接用采样点会得到 5.0 或 6.0 s，误差 0.4–0.6 s，比插值后的误差大一个数量级。

---

## 11. 实现记录

实现已按方案落地，与规划的偏差如下（均为实现中发现并修正的）：

| 项目 | 规划 | 实现 | 原因 |
| --- | --- | --- | --- |
| rollout 起步阈值 | 0.3 m/s | **1.8 m/s** | 规划把方向写反了。1 英尺 rollout 语义是「车已移动约 30 cm 后才开始计时」，比静止口径**更晚**；用 `v = sqrt(2·a·0.3048)`，a 取 5–6 m/s² 得约 1.8 m/s（≈6.5 km/h）。0.3 m/s 会让成绩偏慢，物理上错误 |
| 无效成绩 | 入库并置灰 | **不入库** | `result_ms` 是 NOT NULL，而未达目标时没有成绩；强行存 0 会污染「最佳成绩」统计。改为 UI 直接显示失败原因 |
| 成绩入口 | 首页区块 | 独立页面 | 按你的选择实现 |
| 单位 | 待定 | km/h + mph + km/mi + 海拔 ft | 按你的选择实现 |

实际新增文件：

```
lib/models/acceleration_run.dart
lib/models/acceleration_sample.dart
lib/services/acceleration_timer.dart      纯算法，12 个单测
lib/services/acceleration_recorder.dart   状态机与采集
lib/services/settings_service.dart        偏好设置
lib/utils/units.dart                      单位换算
lib/screens/acceleration_screen.dart
lib/screens/acceleration_result_screen.dart
lib/screens/acceleration_history_screen.dart
lib/screens/settings_screen.dart
lib/widgets/settings_tile.dart
```

验证结果：

- `flutter analyze`：**0 issue**
- `flutter test`：**73 个测试全部通过**（原 44 个 + 零百算法 12 + 零百存储 6 + 设置与单位 11）
- `flutter build apk --release`：成功，universal 52.7 MB，arm64 约 18.5 MB

构建侧的两处环境适配（非业务代码）：

1. `android/app/build.gradle.kts`：`compileSdk` 36 → 37，`permission_handler_android` 强制要求。
2. `android/gradle.properties`：`kotlin.incremental=false`、`org.gradle.parallel=false`，规避 Windows 上 Kotlin 增量缓存被占用导致的 `Could not close incremental caches`。

待办（需要真机）：

- 封闭场地实测，与视频/OBD 对比成绩误差
- 验证长时间后台记录不受 `parallel=false` 影响（只影响构建，不影响运行）
- 上架前换包名 `com.jsonwoo.motolean` 与正式签名
