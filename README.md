# 西小电物语

西安电子科技大学学生的校园助手 App：查培养方案、看课表、跟西小电聊天。

> 非官方工具，数据都来自学校自己的系统。仅供个人学习使用，请勿用于其他用途。

## 功能

### 培养方案

- 复用统一身份认证的登录态，直接进一站式服务大厅的「个人方案查询」应用，把整棵培养方案树抓下来
- 展示成 Markdown 风格的清单：模块按层级缩进，每门课前面一个**能打勾的方框**
- 顶部固定一条进度：`已修 x / y 学分` + 进度条。分母取方案标题上标的那个数字（比如「智能科学与技术 157」里的 157），因为方案里有些模块是并列好几个选项的（思政那类），照课程一门门累加会偏大
- **英语分级**：初 / 中 / 高三档可切。只有基础课模块跟着分档走，选修课的三个班是同一套，不参与筛选
- 模块可逐个折叠，也能一键全部收起 / 展开。默认只展开顶层

### 课表

- 主页是**当天的时间轴**：左边开始时间，中间圆点连线，右边课程卡片（课程名、时间段、节次、教室·老师）
- 点课程卡片或右上「周课表」进**周网格**，可以左右切周，进来自动定位到今天那一列

### 西小电

- 内置人设提示词，配置页里可以改，也能一键恢复默认
- 支持 DeepSeek / 智谱 GLM / 通义千问 / OpenAI，另外有个「自定义」可以填任意 OpenAI 兼容地址
- 流式输出，回复边收边显示；带多轮上下文；回复可以长按选中复制
- 每次对话会带上你**当前的课表**（含今天日期和当前周次），所以问「明天有什么课」「周三下午几点下课」它能直接答
- 配置页有个「测试连通」，会真的发一条请求过去看看通不通

#### 桌宠

页面上方站着一个 Live2D 形象，说话时会跟着换表情、做动作。

- 模型用的是 Cubism 官方示例模型 **Haru**（表情 F01–F08，动作组 `Idle` / `TapBody`），放在 `assets/live2d/haru/`
- 驱动方式是「回复里内嵌标记」：system 里额外拼一段协议（`live2dInstruction`），让模型在回复开头写 `[act:happy]` 或 `[act:sad,tap]`。前端边收流边解析，把标记抹掉后交给桌宠
- 情绪只映射这七个：平静 / 开心 / 难过 / 生气 / 惊讶 / 害羞 / 困惑
- 那段协议是单独拼在**人设提示词之外**的，所以自己改人设不会把桌宠弄哑

### 其他

- **主题**：跟随系统 / 浅色 / 深色
- **清除本地缓存**：清掉抓下来的培养方案和课表，打过的勾会保留
- **彩蛋**：连点五次设置页的「版本」，自己试试看

## 环境

```
Flutter 3.47.x (stable)
Dart 3.13.x
只针对 Android（minSdk 按 Flutter 默认，已在 Android 13 真机上验证）
```

主要依赖：

| 包 | 用途 |
| --- | --- |
| `flutter_inappwebview` | 内嵌浏览器做登录、以及注入脚本抓教务数据 |
| `flutter_secure_storage` | 存登录 Cookie、各账号的数据缓存 |
| `http` | 西小电发请求、读流式响应 |
| `flutter_live2d` | 助手页的桌宠，走 Cubism Native SDK + OpenGL ES 渲染 |

## 构建

```bash
flutter pub get

# 开发调试（能看到日志和热重载）
flutter run -d <设备号>

# 打 release 包，按 CPU 架构拆开，体积小很多
flutter build apk --release --split-per-abi
# 产物在 build/app/outputs/flutter-apk/，真机装 app-arm64-v8a-release.apk
```

换应用图标：把新图放项目根目录命名为 `icon.jpg`，然后

```bash
dart run flutter_launcher_icons
```

## 目录结构

```
lib/
├── main.dart                      入口、底部导航、设置页
├── pages/
│   ├── login_page.dart            内嵌浏览器登录
│   ├── plan_page.dart             培养方案（清单 + 勾选 + 折叠）
│   ├── timetable_page.dart        课表主页（当天时间轴）
│   ├── timetable_grid_page.dart   周课表网格
│   ├── assistant_page.dart        西小电聊天（含桌宠舞台）
│   └── assistant_config_page.dart 西小电配置
├── widgets/
│   └── live2d_stage.dart          桌宠：把模型接到桌宠状态上
└── services/
    ├── auth_service.dart          登录态、Cookie、学号
    ├── plan_service.dart          培养方案抓取 + 解析 + 缓存
    ├── plan_scripts.dart          培养方案用的注入脚本
    ├── timetable_service.dart     课表抓取 + 解析 + 缓存
    ├── timetable_scripts.dart     课表用的注入脚本
    ├── assistant_service.dart     模型配置 + 流式聊天 + 桌宠指令解析
    ├── live2d_actor.dart          桌宠状态、情绪映射、[act:] 标记解析
    └── settings_service.dart      主题、彩蛋
```

（数据都按账号隔离：缓存 key 后面拼学号，换账号不会串数据。）

## 备注

`android/gradle.properties` 里有一行 `android.r8.proguardAndroidTxt.disallowed=false`，
是为了绕过 AGP 9 禁用了旧 proguard 文件写法的限制（`flutter_inappwebview` 目前还在用旧写法）。
等插件适配之后可以删掉。

`android/build.gradle.kts` 里有一段用反射把子项目的 CMake 版本统一改成 3.22.1。原因是
`flutter_live2d` 钉死了 3.10.2，而 Google 已经不在 SDK 里单独提供这个版本了（仓库里只剩
`3.10.2.4988404`，目录名对不上，AGP 搜不到）。它的 CMakeLists 只要求 `>= 3.10`，所以直接用
SDK 里现成的 3.22.1。

`android/gradle.properties` 里的 `kotlin.incremental=false` 是为了绕开跨盘符的坑：pub 缓存在
C 盘、工程在 D 盘时，Kotlin 增量编译计算源文件相对路径会抛 `IllegalArgumentException`，缓存
写不进去，整个 Kotlin 编译就失败了。把 pub 缓存挪到和工程同一个盘（设 `PUB_CACHE`）也能解决，
那样这行就可以删掉。

`android/app/src/main/AndroidManifest.xml` 里关掉了 Impeller
（`io.flutter.embedding.android.EnableImpeller = false`），这个不能删——删了桌宠就看不见了。
`flutter_live2d` 走的是 hybrid composition 的 `TextureView`，在 Impeller 下 GL 明明一直在画
（日志里每一帧都在走），但结果合成不到屏幕上，界面上干干净净什么都没有。退回旧的 OpenGL
后端就正常了。等插件适配 Impeller 之后这条可以去掉。

桌宠用的 Haru 是 Live2D 官方示例模型（来自 `Live2D/CubismWebSamples`），
按官方的免费素材许可只能非商业使用；换模型时留意各自的授权。

`android/app/src/main/assets/FrameworkShaders/` 里是从 `flutter_live2d` 抽出来的 Cubism 着色器
源码（36 个 `.vert` / `.frag`）。插件自己没把它们打进 assets，运行时去 `FrameworkShaders/` 下面
找却一个都找不到，着色器编译失败，模型就画不出来——而且插件把 Cubism 的日志回调留成了空函数，
报错全被吞掉，现象就成了「加载成功但屏幕上什么都没有」。升级插件时留意这个目录要不要跟着更新。

## 桌宠加载慢的原因（已解决）

最早进助手页要等 6 秒多模型才出来。分段计时定位到瓶颈（Android 13 真机，ariu 模型）：

| 阶段 | 耗时 |
| --- | --- |
| platform view 就绪 | 约 0.9s |
| `LoadAssets`（解析 moc3） | 14ms |
| `CreateRenderer`（**编译着色器**） | **约 4.7s** |
| `SetupTextures`（解码纹理+传 GPU） | 422ms |

问题出在 `CreateRenderer`：Cubism 初始化时会把**所有混合模式组合**的着色器一次性全编译——
`ColorBlendMode` 16 种 × `AlphaBlendMode` 5 种 × 6 个 mask 变体 ≈ **480 个着色器程序**，
而实际渲染只用到其中 2～4 个。

解决办法是把插件 fork 进 `third_party/flutter_live2d`，改成「用到哪个才编译哪个」，
细节见那里的 `README-fork.md`。改完实测：

```
[桌宠] 模型加载成功，总耗时 437ms      # 之前是 6425ms
```

注意**纹理不是瓶颈**：把 ariu 的纹理从 4096 缩到 2048 只省下那 422ms 里的一小部分，
真正的收益在包体积（38.7MB → 27.6MB）。
