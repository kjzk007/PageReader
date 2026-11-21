package com.pagereader.app

import android.util.Log
import android.webkit.WebView
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/**
 * PageReader 的 Android 入口。
 *
 * 职责:在**文档开始之前**往 WebView 注入脚本。
 *
 * ── 为什么必须是"文档开始之前" ──
 *
 * MDN 这类站点在解析 HTML 时就会根据 `prefers-color-scheme` 决定初始主题,
 * 把结果写进 `html[data-theme]` 和随后的 CSS。等 `onPageStarted`
 * (webview_flutter 能提供的最早时机)再注入,样式已经算完了 ——
 * 覆写 matchMedia 也不会触发重算,页面保持浅色。
 *
 * 桌面端之所以能生效,是因为用了 CDP 的
 * `Page.addScriptToEvaluateOnNewDocument`,它真正在文档开始前执行。
 *
 * ── 解决办法 ──
 *
 * `WebViewCompat.addDocumentStartJavaScript`(androidx.webkit 1.9.0+)
 * 提供同样的能力:脚本在每次文档创建时、任何站点脚本之前执行。
 * 这是唯一能在 WebView 上复刻桌面端行为的公开 API。
 *
 * ── 走过的弯路(都已排除) ──
 *
 * 1. 覆盖 Activity 的 uiMode(`applyOverrideConfiguration`)
 *    必然崩溃:`getResources() or getAssets() has already been called`
 *    Flutter 引擎在 Activity 早期就访问了 resources,那个时机拿不到。
 *
 * 2. `WebSettingsCompat.setAlgorithmicDarkeningAllowed`
 *    API 返回 true 但视觉无变化 —— 这台华为设备有自家的
 *    `HwForceDarkModeConfig`,按白名单覆盖了标准 API。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 设备型号:手机配对时上报给桌面端,让「已配对的设备」能区分机型。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pagereader/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "deviceModel" -> {
                    val maker = android.os.Build.MANUFACTURER.orEmpty()
                    val model = android.os.Build.MODEL.orEmpty()
                    val name = when {
                        maker.isEmpty() -> model
                        model.startsWith(maker, ignoreCase = true) -> model
                        else -> "maker model"
                    }
                    result.success(name.trim())
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDocumentStartSupported" -> {
                    result.success(
                        WebViewFeature.isFeatureSupported(
                            WebViewFeature.DOCUMENT_START_SCRIPT,
                        ),
                    )
                }
                // 报出实际用的 WebView 包名和版本。
                //
                // 用户拿到 APK 要能自己判断「我这台行不行」——
                // 光说支持/不支持没用，得知道底下的 WebView 是哪版。
                // 不支持时也能据此建议他去更新 Android System WebView。
                "webViewPackage" -> {
                    try {
                        val info = android.webkit.WebView.getCurrentWebViewPackage()
                        result.success(
                            mapOf(
                                "package" to (info?.packageName ?: ""),
                                "version" to (info?.versionName ?: ""),
                            ),
                        )
                    } catch (e: Throwable) {
                        result.success(mapOf("package" to "", "version" to ""))
                    }
                }
                // 挂上任意脚本。
                //
                // 和旧的 setThemeMode 相比，这里不再在原生侧生成脚本内容 ——
                // 主题预设、引擎全文都由 Dart 拼好后传进来。原生只负责
                // 「在文档开始前把它执行掉」这一件事。
                "addScript" -> {
                    val script = call.argument<String>("script")
                    val id = call.argument<Number>("webViewId")?.toLong()
                    if (id == null || script == null) {
                        result.error("bad_args", "缺少 webViewId 或 script", null)
                        return@setMethodCallHandler
                    }
                    result.success(
                        applyDocumentStartScript(flutterEngine, id, script),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 往指定 WebView 注册"文档开始前执行"的脚本。
     *
     * @return 是否注册成功
     */
    private fun applyDocumentStartScript(
        engine: FlutterEngine,
        webViewId: Long,
        script: String,
    ): Boolean {
        if (!WebViewFeature.isFeatureSupported(
                WebViewFeature.DOCUMENT_START_SCRIPT,
            )
        ) {
            Log.w(TAG, "设备不支持 DOCUMENT_START_SCRIPT")
            return false
        }

        val wv: WebView? = try {
            WebViewFlutterAndroidExternalApi.getWebView(engine, webViewId)
        } catch (e: Exception) {
            Log.e(TAG, "取 WebView 失败", e)
            null
        }
        if (wv == null) {
            Log.w(TAG, "找不到 WebView, id=$webViewId")
            return false
        }

        return try {
            // 同一个 WebView 重复注册会叠加多个脚本。用 map 记录已注册的
            // 句柄,主题切换时先移除旧的。
            registered.remove(webViewId)?.let { old ->
                runCatching { old.remove() }
            }

            val handler = WebViewCompat.addDocumentStartJavaScript(
                wv,
                script,
                setOf("*"),
            )
            registered[webViewId] = handler
            Log.i(TAG, "已注册文档开始前脚本 ${script.length} 字符 (id=$webViewId)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "注册失败", e)
            false
        }
    }


    companion object {
        private const val CHANNEL = "com.pagereader/theme"
        private const val TAG = "PRTheme"

        /** webViewId → 已注册的脚本句柄,便于主题切换时移除旧的。 */
        private val registered = mutableMapOf<Long, ScriptHandler>()
    }
}
