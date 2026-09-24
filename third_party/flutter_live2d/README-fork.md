# flutter_live2d（fork）

从 pub.dev 的 `flutter_live2d` 1.0.2 复制过来，改了两处：**着色器改成按需编译**、
**模型资产不再跨启动复用旧副本**。

## 为什么 fork

原版在 `CubismShader_OpenGLES2::GenerateShaders()` 里会把**所有混合模式组合**的着色器一次性
编译完：

- `ColorBlendMode` 16 种 × `AlphaBlendMode` 5 种 × 6 个 mask 变体 ≈ **480 个着色器程序**
- 实测在 Android 13 真机上要 **4.7 秒**，而实际渲染只会用到其中 2～4 个

也就是每次进助手页，用户都要白等 4 秒多。

## 改了什么

### 1. 着色器按需编译

只动了 `android/src/main/cpp/CubismFramework/Rendering/OpenGL/CubismShader_OpenGLES2.{hpp,cpp}`：

- 加 `ShaderSpec` 结构和 `_shaderSpecs` 表。`GenerateShaders()` 里**只登记**每个索引需要的
  着色器文件和参数（顶点/片元路径、混合模式、mask 类型），不再立刻编译
- 加 `GetShaderSet(index)`：取用时如果还没编译，就在那一刻编译，并补上各个变量地址
  （`SetShaderSet` 只是 `glGetAttribLocation`/`glGetUniformLocation`，没有副作用，可以随时重调）
- `SetupShaderProgramForDrawable` 和 `SetupShaderProgramForOffscreen` 里取 shader 的两处改用
  `GetShaderSet()`
- 基础那 8 个（Normal 系列 / Copy / SetupMask）仍然立即编译——它们几乎必然用到

原因和实测数据记在项目根目录 README 的「桌宠加载慢的原因」一节。

### 2. 模型资产每次都重新解压

改了 `lib/src/asset_cache.dart`：删掉 `.ready` 标记那套「目录已存在就跳过复制」的逻辑，
每次冷启动都重新解压一遍（进程内仍然只复制一次）。

原因是缓存 key 只用了 asset 目录名的 base64，跟文件内容无关。所以**原地改了模型文件、
目录名却没变**（改 model3.json、换纹理都是常事）之后，App 会一直拿磁盘上的旧副本，
表现出来就是「改了模型却没生效」。复制那几 MB 比排查这类问题便宜。

## 注意

- **着色器文件不在这个 fork 里**。Cubism 是运行时从 APK assets 的 `FrameworkShaders/` 下面读它们，
  所以那 36 个 `.vert` / `.frag` 放在宿主项目的
  `android/app/src/main/assets/FrameworkShaders/`。
- 升级 pub.dev 上的原版时记得把这两处改动合并过去：着色器看 `GenerateShaders` 附近的 diff，
  资产缓存看 `asset_cache.dart`。
