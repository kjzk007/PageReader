plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pagereader.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pagereader.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // androidx.webkit 提供 WebSettingsCompat.setAlgorithmicDarkeningAllowed,
    // 这是让 WebView 按主题强制深色渲染的官方 API。
    //
    // 为什么要它:
    // 站点自己的 CSS `@media (prefers-color-scheme: dark)` 由 WebView 引擎
    // 按 Activity 的 uiMode 求值,注入 JS 改不了(实测 MDN 就是 matchMedia
    // 返回 true、背景仍白)。而改 Activity 的 uiMode 在 Flutter 的启动流程下
    // 会崩 —— Flutter 引擎在 Activity 早期就调用了 getResources,
    // 之后 applyOverrideConfiguration 必抛 IllegalStateException。
    //
    // 所以只能在原生 WebView 实例上开 algorithmic darkening:
    // 它会自动把浅色页面转成深色,包括内容容器的背景色。
    implementation("androidx.webkit:webkit:1.12.1")
}

flutter {
    source = "../.."
}
