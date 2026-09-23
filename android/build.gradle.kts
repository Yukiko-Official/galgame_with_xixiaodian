allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// flutter_live2d 在它的 build.gradle.kts 里把 CMake 版本钉死成 3.10.2，但 Google
// 已经不在 SDK 里单独提供这个版本了（仓库里只剩 3.10.2.4988404，目录名对不上），
// 它的 CMakeLists 又只要求 >= 3.10，所以这里统一改成 SDK 里现成的 3.22.1。
// 用反射是为了不依赖 AGP 的 DSL 类型；必须注册在下面的 evaluationDependsOn 之前，
// 否则子项目已经评估完，AGP 早把配置读走了。
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            val nativeBuild = androidExtension.javaClass
                .getMethod("getExternalNativeBuild")
                .invoke(androidExtension)
            val cmake = nativeBuild.javaClass.getMethod("getCmake").invoke(nativeBuild)
            cmake.javaClass
                .getMethod("setVersion", String::class.java)
                .invoke(cmake, "3.22.1")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
