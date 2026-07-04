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
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every Android module (including plugins) to compile against API 36. Some
// plugins hardcode an older compileSdk (e.g. file_picker 8.x -> 34) while others
// (flutter_plugin_android_lifecycle) require consumers to compile against 36+, which
// is newer than Flutter 3.44's default (35). Overriding it on the app module alone
// doesn't cover the plugin modules, so set it on each after they're evaluated.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            runCatching {
                android.javaClass.getMethod("setCompileSdk", Integer::class.java).invoke(android, 36)
            }.recoverCatching {
                android.javaClass.getMethod("compileSdkVersion", Integer.TYPE).invoke(android, 36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
