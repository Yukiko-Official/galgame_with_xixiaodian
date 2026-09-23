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
