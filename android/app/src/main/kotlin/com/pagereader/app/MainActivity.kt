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
                "setThemeMode" -> {
                    val enabled = call.argument<Boolean>("dark") ?: false
                    val id = call.argument<Number>("webViewId")?.toLong()
                    if (id == null) {
                        result.error("no_id", "缺少 webViewId", null)
                        return@setMethodCallHandler
                    }
                    result.success(applyDocumentStart(flutterEngine, id, enabled))
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
    private fun applyDocumentStart(
        engine: FlutterEngine,
        webViewId: Long,
        dark: Boolean,
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

            val script = buildScript(dark)
            val handler = WebViewCompat.addDocumentStartJavaScript(
                wv,
                script,
                setOf("*"),
            )
            registered[webViewId] = handler
            Log.i(TAG, "已注册文档开始前脚本 dark=$dark (id=$webViewId)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "注册失败", e)
            false
        }
    }

    /**
     * 文档开始前执行的脚本。
     *
     * 只覆写 matchMedia —— 站点会自己根据结果挑主题,
     * 我们不该改它的 DOM(那会导致两边互相覆盖、深浅闪烁)。
     */
    private fun buildScript(dark: Boolean): String {
        val value = if (dark) "true" else "false"
        return """
(function () {
  if (window.__prDocStartPatched) return;
  window.__prDocStartPatched = true;
  try {
    var orig = window.matchMedia.bind(window);
    window.matchMedia = function (query) {
      var mql = orig(query);
      if (!query || query.indexOf('prefers-color-scheme') < 0) return mql;
      var askDark = query.indexOf('dark') >= 0;
      var askLight = query.indexOf('light') >= 0;
      if (!askDark && !askLight) return mql;
      try {
        Object.defineProperty(mql, 'matches', {
          get: function () { return askDark ? $value : ${if (dark) "false" else "true"}; }
        });
      } catch (e) {}
      return mql;
    };
  } catch (e) {}
})();
        """.trimIndent()
    }

    companion object {
        private const val CHANNEL = "com.pagereader/theme"
        private const val TAG = "PRTheme"

        /** webViewId → 已注册的脚本句柄,便于主题切换时移除旧的。 */
        private val registered = mutableMapOf<Long, ScriptHandler>()
    }
}
