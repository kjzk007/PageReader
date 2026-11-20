#include "webview_host.h"

#include <dwmapi.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/event.h>

#include "WebView2EnvironmentOptions.h"
#include "../flutter/ephemeral/cpp_client_wrapper/binary_messenger_impl.h"

#include <functional>

namespace pagereader {

namespace {

// Keep in sync with lib/main.dart `_buildTheme`:
//   dark  scaffoldBackgroundColor = 0xFF0E0F12
//   light scaffoldBackgroundColor = 0xFFF7F8FA
// COLORREF is 0x00BBGGRR, so the byte order is reversed relative to the
// Flutter ARGB constant.
constexpr COLORREF kDarkBackground = RGB(0x0E, 0x0F, 0x12);
constexpr COLORREF kLightBackground = RGB(0xF7, 0xF8, 0xFA);

// DWMWA_USE_IMMERSIVE_DARK_MODE. Defined here because the SDK headers that
// ship with older Windows SDKs do not expose it.
constexpr DWORD kAttrUseImmersiveDarkMode = 20;

// Diagnostic log, written next to the app's data folder.
//
// Deliberately free of hard-coded paths: a shipped build that appends to
// "D:\PageReader\_scratch\..." would silently do nothing on a user machine.
// %APPDATA%\com.pagereader\PageReader\webview2.log is where the rest of the
// app keeps its state.
void dbg(const char* msg) {
  static std::string log_path;
  if (log_path.empty()) {
    char appdata[MAX_PATH] = {0};
    size_t len = 0;
    if (getenv_s(&len, appdata, sizeof(appdata), "APPDATA") == 0 && len > 0) {
      log_path = std::string(appdata) +
                 "\\com.pagereader\\PageReader\\webview2.log";
    } else {
      log_path = "webview2.log";
    }
  }
  try {
    FILE* f = nullptr;
    if (fopen_s(&f, log_path.c_str(), "a") == 0 && f) {
      fprintf(f, "%s\n", msg);
      fclose(f);
    }
  } catch (...) {}
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                        &out[0], n);
  return out;
}

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return std::string();
  int n = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(),
                                static_cast<int>(s.size()), nullptr, 0,
                                nullptr, nullptr);
  std::string out(n, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                        &out[0], n, nullptr, nullptr);
  return out;
}

std::string ArgString(const flutter::EncodableMap& args, const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return std::string();
  const auto* v = std::get_if<std::string>(&it->second);
  return v ? *v : std::string();
}

// The method channel lives in the .cpp so the header stays Flutter-free.
flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;

}  // namespace

WebViewHost::WebViewHost() = default;
WebViewHost::~WebViewHost() = default;

void WebViewHost::Attach(void* messenger_ref) {
  dbg("Attach begin BUILD=" __DATE__ " " __TIME__);
  messenger_ = messenger_ref;
  if (!messenger_ref) return;

  // Wrap the C messenger handle with the C++ adapter.
  //
  // NOTE: never reinterpret_cast the FlutterDesktopMessengerRef into a
  // flutter::BinaryMessenger*. The former is an opaque C handle; the latter
  // is a C++ class with virtual methods, so the bogus vtable crashed with
  // BEX64 on the first virtual call. BinaryMessengerImpl exists precisely to
  // bridge the two.
  dbg("Attach: wrapping messenger");
  auto* core = static_cast<FlutterDesktopMessengerRef>(messenger_ref);
  auto* impl = new flutter::BinaryMessengerImpl(core);
  messenger_impl_ = impl;
  dbg("Attach: creating channel");
  g_channel = new flutter::MethodChannel<flutter::EncodableValue>(
      impl, "com.pagereader/webview2",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result_ptr) {
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        const auto& m = call.method_name();
        {
          std::string logmsg = "HandleMethodCall: " + m;
          dbg(logmsg.c_str());
        }

        // Share the result so multiple callbacks can reference it.
        // unique_ptr cannot be copied, and the callbacks outlive this scope.
        auto result =
            std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
                std::move(result_ptr));

        // Forward window-close events to Dart so the shelf stops showing
        // the book as "currently reading".
        SetClosedSink([this](const std::string& book_id) {
          if (!g_channel) return;
          g_channel->InvokeMethod(
              "bookClosed",
              std::make_unique<flutter::EncodableValue>(book_id));
        });

        // Forward page -> Dart position reports.
        //
        // Without this the native side receives WebMessageReceived but has
        // nowhere to send it, so every report is silently dropped and no
        // progress is ever written. The Dart side listens on this channel
        // (see WebView2Engine._onNativeCall).
        SetReportSink([this](const std::string& payload) {
          if (!g_channel) return;
          g_channel->InvokeMethod(
              "report",
              std::make_unique<flutter::EncodableValue>(payload));
        });

        auto ok_fn = [result]() {
          result->Success(flutter::EncodableValue(true));
        };
        auto fail_fn = [result](const std::string& e) {
          result->Error("failed", e);
        };

        if (m == "setUserDataDir") {
          SetUserDataDir(args ? ArgString(*args, "dir") : std::string());
          ok_fn();
          return;
        }
        if (m == "setPageBridge") {
          SetPageBridge(args ? ArgString(*args, "script") : std::string());
          ok_fn();
          return;
        }
        if (m == "setDarkMode") {
          bool dark = true;
          if (args) {
            auto it = args->find(flutter::EncodableValue("dark"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) dark = *b;
            }
          }
          SetDarkMode(dark);
          ok_fn();
          return;
        }
        if (m == "setPendingExtensions") {
          std::vector<std::string> paths;
          if (args) {
            auto it = args->find(flutter::EncodableValue("paths"));
            if (it != args->end()) {
              if (const auto* list =
                      std::get_if<flutter::EncodableList>(&it->second)) {
                for (const auto& e : *list) {
                  if (const auto* s = std::get_if<std::string>(&e)) {
                    paths.push_back(*s);
                  }
                }
              }
            }
          }
          SetPendingExtensions(paths);
          ok_fn();
          return;
        }
        if (m == "openBook") {
          if (!args) {
            fail_fn("missing arguments");
            return;
          }
          OpenBook(ArgString(*args, "bookId"), ArgString(*args, "url"),
                   [result](bool ok, const std::string& p) {
                     if (ok) {
                       result->Success(flutter::EncodableValue(true));
                     } else {
                       result->Error("failed", p);
                     }
                   });
          return;
        }
        if (m == "executeScript") {
          if (!args) {
            fail_fn("missing arguments");
            return;
          }
          ExecuteScript(
              ArgString(*args, "bookId"), ArgString(*args, "script"),
              [result](bool ok, const std::string& p) {
                if (ok) {
                  result->Success(flutter::EncodableValue(p));
                } else {
                  result->Error("failed", p);
                }
              });
          return;
        }
        if (m == "closeBook") {
          if (args) CloseBook(ArgString(*args, "bookId"));
          ok_fn();
          return;
        }
        if (m == "loadExtensions") {
          std::vector<std::string> paths;
          if (args) {
            auto it = args->find(flutter::EncodableValue("paths"));
            if (it != args->end()) {
              if (const auto* list =
                      std::get_if<flutter::EncodableList>(&it->second)) {
                for (const auto& e : *list) {
                  if (const auto* s = std::get_if<std::string>(&e)) {
                    paths.push_back(*s);
                  }
                }
              }
            }
          }
          LoadExtensions(paths,
                         [result](bool ok, const std::string& p) {
                           if (ok) {
                             result->Success(flutter::EncodableValue(0));
                           } else {
                             result->Error("failed", p);
                           }
                         });
          return;
        }
        if (m == "isSupported") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
}

void WebViewHost::SetReportSink(ReportFn sink) {
  report_sink_ = std::move(sink);
}

void WebViewHost::SetClosedSink(
    std::function<void(const std::string&)> sink) {
  closed_sink_ = std::move(sink);
}

void WebViewHost::SetPageBridge(const std::string& script) {
  page_bridge_ = script;
}

void WebViewHost::ApplyThemeToWindow(HWND hwnd) {
  if (!hwnd) return;

  BOOL use_dark = dark_mode_ ? TRUE : FALSE;
  ::DwmSetWindowAttribute(hwnd, kAttrUseImmersiveDarkMode, &use_dark,
                          sizeof(use_dark));

  // Repaint so the new brush takes effect immediately (theme switches while
  // a book is already open).
  ::InvalidateRect(hwnd, nullptr, TRUE);
}

void WebViewHost::SetDarkMode(bool dark) {
  if (dark_mode_ == dark && background_brush_ != nullptr) return;
  dark_mode_ = dark;

  // Rebuild the shared background brush. It is used by ReadingWindowProc when
  // erasing the window background, so swapping it here plus InvalidateRect is
  // enough to repaint every open reading window.
  if (background_brush_ != nullptr) {
    ::DeleteObject(background_brush_);
  }
  background_brush_ =
      ::CreateSolidBrush(dark ? kDarkBackground : kLightBackground);

  dbg(dark ? "SetDarkMode: dark" : "SetDarkMode: light");

  for (auto& entry : sessions_) {
    ApplyThemeToWindow(entry.second->hwnd);
  }
}

void WebViewHost::MarkSessionClosing(const std::string& book_id) {
  auto it = sessions_.find(book_id);
  if (it != sessions_.end()) it->second->closing = true;
}

void WebViewHost::SetPendingExtensions(
    const std::vector<std::string>& paths) {
  pending_extensions_ = paths;
  pending_extensions_loaded_ = false;
  char buf[128];
  sprintf_s(buf, "SetPendingExtensions: %zu", paths.size());
  dbg(buf);
}

// Captures the final scroll position before the window dies.
//
// Returns true if a capture was started; the caller must NOT destroy the
// window in that case -- the script callback does it. False means the caller
// can destroy immediately.
//
// The script runs asynchronously, so this cannot block: instead the
// "destroy window" step is attached to the completion callback, with a short
// timer as a fallback in case the page is hung and never answers.
bool WebViewHost::CaptureFinalPosition(HWND hwnd,
                                       const std::string& book_id) {
  auto it = sessions_.find(book_id);
  if (it == sessions_.end() || !it->second->webview) return false;

  auto webview = it->second->webview;
  if (!webview) return false;

  // Same shape as readPositionScript on the Dart side: returns a JSON string.
  static const wchar_t* kScript =
      L"(function(){try{"
      L"var se=document.scrollingElement||document.documentElement;"
      L"var max=Math.max(1,se.scrollHeight-se.clientHeight);"
      L"var y=window.scrollY||se.scrollTop||0;"
      L"var a=(window.__pr&&window.__pr.collect)?window.__pr.collect():null;"
      L"return JSON.stringify({ok:true,url:location.href,"
      L"title:document.title,ratio:Math.min(1,Math.max(0,y/max)),"
      L"anchor:a?a.anchor:null});"
      L"}catch(e){return JSON.stringify({ok:false});}})();";

  // Keep the window alive for a moment; destroy in the callback or timeout.
  ::SetTimer(hwnd, kCloseTimerId, 1200, nullptr);

  webview->ExecuteScript(
      kScript,
      Microsoft::WRL::Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
          [this, hwnd, book_id](HRESULT hr, LPCWSTR json) -> HRESULT {
            dbg("CaptureFinalPosition: callback");
            // Only accept the report if this window still owns the session.
            //
            // Race: the user closes book A and immediately reopens it. The
            // old window's capture callback can arrive AFTER the new window
            // has already opened and recorded its own position -- writing it
            // would drag the saved position back to where the old window was.
            // ForgetSession removed the stale entry, so a mismatch here means
            // "this window is no longer the current one for this book".
            auto it = sessions_.find(book_id);
            const bool still_owner =
                it != sessions_.end() && it->second->hwnd == hwnd;
            if (!still_owner) {
              dbg("CaptureFinalPosition: stale window, report dropped");
            } else if (SUCCEEDED(hr) && json && report_sink_) {
              std::string payload = WideToUtf8(json);
              report_sink_("{\"bookId\":\"" + book_id +
                           "\",\"data\":" + payload + "}");
            }
            ::KillTimer(hwnd, kCloseTimerId);
            ::DestroyWindow(hwnd);
            return S_OK;
          })
          .Get());
  return true;
}

void WebViewHost::LoadPendingExtensionsIfReady() {
  if (pending_extensions_loaded_) return;
  if (pending_extensions_.empty()) return;
  if (!profile_) return;

  pending_extensions_loaded_ = true;
  // Fire and forget: the page keeps loading while extensions attach.
  LoadExtensions(pending_extensions_, [](bool ok, const std::string& e) {
    dbg(ok ? "LoadPendingExtensions: done" : "LoadPendingExtensions: failed");
  });
}

// Drops the session after its window is destroyed.
//
// Leaving it behind meant reopening the same book hit a stale entry and
// called Navigate on a destroyed controller: no window appeared, yet the
// shelf still showed the book as open.
void WebViewHost::ForgetSession(const std::string& book_id) {
  auto it = sessions_.find(book_id);
  if (it == sessions_.end()) return;
  if (it->second->webview) {
    it->second->webview->remove_WebMessageReceived(it->second->message_token);
  }
  sessions_.erase(it);
}

// static
LRESULT CALLBACK WebViewHost::ReadingWindowProc(HWND hwnd, UINT msg,
                                                WPARAM wparam, LPARAM lparam) {
  if (msg == WM_CLOSE) {
    dbg("ReadingWindowProc: WM_CLOSE");
    // The user clicked the window's X.
    //
    // Capture the position BEFORE letting the window die.
    //
    // Previously this only told Dart "the book closed", and Dart then called
    // executeScript asynchronously to read the position -- but by then the
    // window was already destroyed and the session cleared, so it always
    //
    // failed and the last screen of progress was lost.
    // Now: intercept WM_CLOSE, capture first, then close.
    auto* host = reinterpret_cast<WebViewHost*>(
        ::GetPropW(hwnd, L"PageReaderHost"));
    auto* book_id = reinterpret_cast<std::string*>(
        ::GetPropW(hwnd, L"PageReaderBookId"));

    // Guard against re-entrant WM_CLOSE for THIS window.
    //
    // The flag must be per-window, not per-host: a host-wide flag stayed
    // true after the first book closed, so every later window became
    // impossible to close.
    bool* closing_flag = reinterpret_cast<bool*>(
        ::GetPropW(hwnd, L"PageReaderClosing"));
    if (!closing_flag) {
      closing_flag = new bool(false);
      ::SetPropW(hwnd, L"PageReaderClosing",
                 reinterpret_cast<HANDLE>(closing_flag));
    }

    if (host && book_id && !*closing_flag) {
      *closing_flag = true;

      // Mark the session closing so a concurrent OpenBook for the same book
      // does not try to reuse a webview that is being torn down.
      if (host) host->MarkSessionClosing(*book_id);

      const std::string id_copy = *book_id;

      // Report the close first so the shelf can drop "reading" state.
      if (host->closed_sink_) host->closed_sink_(id_copy);

      // Then grab the final position. The window stays alive until the
      // script callback returns (see CloseAfterCapture).
      if (!host->CaptureFinalPosition(hwnd, id_copy)) {
        dbg("WM_CLOSE: capture impossible, destroying now");
        // No session/script support: destroy immediately.
        ::DestroyWindow(hwnd);
      } else {
        dbg("WM_CLOSE: capture started, window kept alive");
      }
      return 0;
    }
    return 0;
  }
  if (msg == WM_ERASEBKGND) {
    // Paint with the app theme instead of the system default.
    //
    // The class is registered with hbrBackground = nullptr, so without this
    // the window shows whatever was underneath (typically white) around the
    // WebView until the page paints.
    auto* host = reinterpret_cast<WebViewHost*>(
        ::GetPropW(hwnd, L"PageReaderHost"));
    if (host != nullptr && host->background_brush_ != nullptr) {
      RECT rc;
      ::GetClientRect(hwnd, &rc);
      ::FillRect(reinterpret_cast<HDC>(wparam), &rc, host->background_brush_);
      return 1;
    }
    return 0;
  }
  if (msg == WM_TIMER && wparam == kCloseTimerId) {
    // Timeout fallback: the page never answered (crashed or hung), so the
    // capture callback will never fire. Close anyway.
    dbg("ReadingWindowProc: close timeout");
    ::KillTimer(hwnd, kCloseTimerId);
    ::DestroyWindow(hwnd);
    return 0;
  }
  if (msg == WM_DESTROY) {
    // IMPORTANT: drop the session from the map here.
    //
    // Leaving it behind meant that opening the same book again hit a stale
    // entry and called Navigate on an already-destroyed controller: the
    // window silently never appeared, while the shelf kept showing the book
    // as open.
    dbg("ReadingWindowProc: WM_DESTROY");
    auto* host = reinterpret_cast<WebViewHost*>(
        ::GetPropW(hwnd, L"PageReaderHost"));
    auto* book_id = reinterpret_cast<std::string*>(
        ::GetPropW(hwnd, L"PageReaderBookId"));
    if (host && book_id) {
      host->ForgetSession(*book_id);
    }
    if (book_id) {
      ::RemovePropW(hwnd, L"PageReaderBookId");
      delete book_id;
    }
    // Free the per-window close guard so the property does not leak.
    auto* closing_flag = reinterpret_cast<bool*>(
        ::GetPropW(hwnd, L"PageReaderClosing"));
    if (closing_flag) {
      ::RemovePropW(hwnd, L"PageReaderClosing");
      delete closing_flag;
    }
    ::RemovePropW(hwnd, L"PageReaderHost");
    return 0;
  }
  return ::DefWindowProc(hwnd, msg, wparam, lparam);
}


void WebViewHost::SetUserDataDir(const std::string& dir) {
  user_data_dir_ = dir;
}

void WebViewHost::EnsureEnvironment(
    std::function<void(bool, const std::string&)> done) {
  if (env_ready_) {
    done(true, "");
    return;
  }
  auto wdir = Utf8ToWide(user_data_dir_);

  struct Context {
    WebViewHost* host;
    std::function<void(bool, const std::string&)> done;
  };
  auto* ctx = new Context{this, std::move(done)};

  // MUST create the environment with extensions enabled.
  //
  // Per the WebView2 docs on AreBrowserExtensionsEnabled:
  //   "AreBrowserExtensionsEnabled is default to be false, in this case,
  //    new extensions can't be installed, and already installed extension
  //    won't be available to use in user profile."
  //
  // Without this flag, AddBrowserExtension returns
  // HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED) (0x80070032) and no extension
  // ever loads -- which is exactly the "plugins don't work" symptom.
  Microsoft::WRL::ComPtr<ICoreWebView2EnvironmentOptions> options;
  {
    Microsoft::WRL::ComPtr<CoreWebView2EnvironmentOptions> concrete;
    if (SUCCEEDED(Microsoft::WRL::MakeAndInitialize<
                  CoreWebView2EnvironmentOptions>(&concrete))) {
      concrete->put_AreBrowserExtensionsEnabled(TRUE);
      options = concrete;
      dbg("EnsureEnvironment: extensions enabled in options");
    } else {
      dbg("EnsureEnvironment: cannot create options object");
    }
  }

  HRESULT hr = ::CreateCoreWebView2EnvironmentWithOptions(
      nullptr, wdir.empty() ? nullptr : wdir.c_str(), options.Get(),
      Microsoft::WRL::Callback<
          ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [ctx](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
            auto* host = ctx->host;
            auto cb = std::move(ctx->done);
            delete ctx;
            if (FAILED(result) || !env) {
              cb(false, "WebView2 environment failed");
              return S_OK;
            }
            host->env_ = env;
            host->env_ready_ = true;
            cb(true, "");
            return S_OK;
          })
          .Get());

  if (FAILED(hr)) {
    auto cb = std::move(ctx->done);
    delete ctx;
    cb(false, "cannot create WebView2 environment");
  }
}

void WebViewHost::OpenBook(const std::string& book_id,
                           const std::string& url, ResultFn done) {
  dbg("OpenBook: enter");
  if (book_id.empty() || url.empty()) {
    dbg("OpenBook: empty args");
    done(false, "bookId and url are required");
    return;
  }

  auto it = sessions_.find(book_id);
  // Only reuse a session that is alive AND not tearing down.
  //
  // Reusing one that is closing caused a nasty race the user hit: close the
  // book, and while the shelf still showed "reading", click it again. The
  // second open found this stale entry, called Navigate on a webview that was
  // being destroyed, and the result was -- no new window, no progress
  // written, and a book that could never be opened again.
  if (it != sessions_.end() && it->second->webview && !it->second->closing) {
    dbg("OpenBook: reusing existing session");
    std::wstring wurl = Utf8ToWide(url);
    it->second->webview->Navigate(wurl.c_str());
    done(true, "");
    return;
  }
  if (it != sessions_.end()) {
    // Stale entry: drop it so a fresh window gets created below.
    dbg("OpenBook: dropping stale session");
    ForgetSession(book_id);
  }

  dbg("OpenBook: ensuring environment");
  EnsureEnvironment([this, book_id, url, done](bool ok,
                                               const std::string& err) {
    if (!ok) {
      dbg("OpenBook: environment failed");
      done(false, err);
      return;
    }
    dbg("OpenBook: creating session");
    CreateSession(book_id, url, done);
  });
}

void WebViewHost::CreateSession(const std::string& book_id,
                                const std::string& url, ResultFn done) {
  HINSTANCE inst = ::GetModuleHandle(nullptr);
  static const wchar_t* kClass = L"PageReaderWebViewWindow";
  static bool registered = false;
  if (!registered) {
    WNDCLASSEX wc = {};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.lpfnWndProc = &WebViewHost::ReadingWindowProc;
    wc.hInstance = inst;
    wc.lpszClassName = kClass;
    wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
    // No background brush: ReadingWindowProc paints it in WM_ERASEBKGND so
    // the colour can follow the app theme instead of the system one.
    // COLOR_WINDOW here was what made reading windows flash white.
    wc.hbrBackground = nullptr;
    ::RegisterClassEx(&wc);
    registered = true;
  }

  HWND hwnd = ::CreateWindowEx(0, kClass, L"PageReader", WS_OVERLAPPEDWINDOW,
                               next_host_x_, next_host_y_, 1100, 900, nullptr,
                               nullptr, inst, nullptr);
  if (!hwnd) {
    dbg("CreateSession: window creation failed");
    done(false, "cannot create window");
    return;
  }
  dbg("CreateSession: window created");
  // Attach book_id so the window proc can report which book closed.
  ::SetPropW(hwnd, L"PageReaderBookId",
             reinterpret_cast<HANDLE>(new std::string(book_id)));
  ::SetPropW(hwnd, L"PageReaderHost", reinterpret_cast<HANDLE>(this));

  // Paint the window with the app theme before it becomes visible, otherwise
  // the first frame flashes a light frame on a dark app theme.
  if (background_brush_ == nullptr) {
    background_brush_ =
        ::CreateSolidBrush(dark_mode_ ? kDarkBackground : kLightBackground);
  }
  ApplyThemeToWindow(hwnd);

  next_host_x_ += 40;
  next_host_y_ += 40;
  ::ShowWindow(hwnd, SW_SHOWMAXIMIZED);
  ::UpdateWindow(hwnd);

  auto session = std::make_unique<Session>();
  session->book_id = book_id;
  session->hwnd = hwnd;
  Session* session_raw = session.get();
  sessions_[book_id] = std::move(session);

  auto url_wide = Utf8ToWide(url);

  env_->CreateCoreWebView2Controller(
      hwnd,
      Microsoft::WRL::Callback<
          ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
          [this, session_raw, url_wide, done](
              HRESULT hr, ICoreWebView2Controller* controller) -> HRESULT {
            if (FAILED(hr) || !controller) {
              char buf[128];
              sprintf_s(buf, "CreateSession: controller FAILED hr=0x%08lx", hr);
              dbg(buf);
              done(false, "cannot create WebView2 controller");
              return S_OK;
            }
            dbg("CreateSession: controller ok");
            session_raw->controller = controller;
            HRESULT ghr = controller->get_CoreWebView2(&session_raw->webview);
            {
              char buf[160];
              sprintf_s(buf, "CreateSession: get_CoreWebView2 hr=0x%08lx ptr=%p",
                        ghr, static_cast<void*>(session_raw->webview.Get()));
              dbg(buf);
            }
            if (!session_raw->webview) {
              dbg("CreateSession: webview is null, abort");
              done(false, "WebView2 webview is null");
              return S_OK;
            }

            // Profile is needed for AddBrowserExtension; it lives on
            // ICoreWebView2_13.
            Microsoft::WRL::ComPtr<ICoreWebView2_13> wv13;
            if (SUCCEEDED(session_raw->webview->QueryInterface(
                    IID_PPV_ARGS(&wv13))) &&
                wv13) {
              Microsoft::WRL::ComPtr<ICoreWebView2Profile> profile;
              HRESULT phr = wv13->get_Profile(&profile);
              {
                char buf[128];
                sprintf_s(buf, "CreateSession: get_Profile hr=0x%08lx", phr);
                dbg(buf);
              }
              if (SUCCEEDED(phr)) {
                this->profile_ = profile;
                dbg("CreateSession: profile stored");
                // Extensions must attach before the first page finishes
                // loading, otherwise the page the user starts reading has
                // no extensions in it.
                this->LoadPendingExtensionsIfReady();
              }
            }

            RECT bounds;
            ::GetClientRect(session_raw->hwnd, &bounds);
            {
              char buf[160];
              sprintf_s(buf, "CreateSession: bounds %ldx%ld",
                        bounds.right - bounds.left,
                        bounds.bottom - bounds.top);
              dbg(buf);
            }
            HRESULT bhr = controller->put_Bounds(bounds);
            {
              char buf[128];
              sprintf_s(buf, "CreateSession: put_Bounds hr=0x%08lx", bhr);
              dbg(buf);
            }

            auto webview = session_raw->webview;

            // Bridge the page's report channel.
            //
            // The anchor script (core/domain/anchor_script.dart) expects a
            // global function `window.__prReport`. Under CDP that came from
            // Runtime.addBinding; WebView2 has no such API, so we install a
            // shim that forwards through chrome.webview.postMessage and pick
            // it up in WebMessageReceived below.
            //
            // MUST await AddScriptToExecuteOnDocumentCreated before
            // Navigate: it is async, and navigating first means the very
            // first document loads without the script -- which is exactly
            // the document the user starts reading on, so the initial
            // position would never be recorded.
            auto bridge = std::make_shared<std::wstring>(
                Utf8ToWide(page_bridge_));
            auto host = this;
            auto nav_url = url_wide;
            {
              char buf[160];
              sprintf_s(buf, "CreateSession: bridge len=%zu",
                        page_bridge_.size());
              dbg(buf);
            }
            HRESULT ashr =
            webview->AddScriptToExecuteOnDocumentCreated(
                bridge->c_str(),
                Microsoft::WRL::Callback<
                    ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
                    [host, session_raw, nav_url](
                        HRESULT script_hr, LPCWSTR) -> HRESULT {
                      char buf[128];
                      sprintf_s(buf, "CreateSession: script installed hr=0x%08lx",
                                script_hr);
                      dbg(buf);
                      // Register the message sink before navigating so the
                      // first report is not dropped.
                      session_raw->webview->add_WebMessageReceived(
                          Microsoft::WRL::Callback<
                              ICoreWebView2WebMessageReceivedEventHandler>(
                              [host, session_raw](
                                  ICoreWebView2*,
                                  ICoreWebView2WebMessageReceivedEventArgs*
                                      args) -> HRESULT {
                                LPWSTR raw = nullptr;
                                args->get_WebMessageAsJson(&raw);
                                if (raw) {
                                  std::string payload = WideToUtf8(raw);
                                  ::CoTaskMemFree(raw);
                                  if (host->report_sink_) {
                                    host->report_sink_(
                                        "{\"bookId\":\"" +
                                        session_raw->book_id +
                                        "\",\"data\":" + payload + "}");
                                  }
                                }
                                return S_OK;
                              })
                              .Get(),
                          &session_raw->message_token);

                      // Script installation failure should not block
                      // reading, so navigate regardless.
                      session_raw->webview->Navigate(nav_url.c_str());
                      return S_OK;
                    })
                    .Get());
            {
              char buf[128];
              sprintf_s(buf, "CreateSession: AddScript hr=0x%08lx", ashr);
              dbg(buf);
            }

            done(true, "");
            return S_OK;
          })
          .Get());
}

void WebViewHost::ExecuteScript(const std::string& book_id,
                                const std::string& script, ResultFn done) {
  auto it = sessions_.find(book_id);
  if (it == sessions_.end() || !it->second->webview) {
    done(false, "no window for this book");
    return;
  }
  auto wscript = Utf8ToWide(script);
  it->second->webview->ExecuteScript(
      wscript.c_str(),
      Microsoft::WRL::Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
          [done](HRESULT hr, LPCWSTR json) -> HRESULT {
            if (FAILED(hr)) {
              done(false, "script execution failed");
            } else {
              done(true, json ? WideToUtf8(json) : std::string());
            }
            return S_OK;
          })
          .Get());
}

void WebViewHost::CloseBook(const std::string& book_id) {
  auto it = sessions_.find(book_id);
  if (it == sessions_.end()) return;
  if (it->second->webview) {
    it->second->webview->remove_WebMessageReceived(it->second->message_token);
  }
  if (it->second->controller) it->second->controller->Close();
  if (it->second->hwnd) ::DestroyWindow(it->second->hwnd);
  sessions_.erase(it);
}

void WebViewHost::LoadExtensions(const std::vector<std::string>& paths,
                                 ResultFn done) {
  {
    char buf[128];
    sprintf_s(buf, "LoadExtensions: profile=%d paths=%zu",
              profile_ ? 1 : 0, paths.size());
    dbg(buf);
  }
  if (!profile_) {
    done(false, "WebView2 profile not ready");
    return;
  }
  if (paths.empty()) {
    done(true, "");
    return;
  }

  Microsoft::WRL::ComPtr<ICoreWebView2Profile7> profile7;
  HRESULT qhr = profile_->QueryInterface(IID_PPV_ARGS(&profile7));
  {
    char buf[160];
    sprintf_s(buf, "LoadExtensions: QI Profile7 hr=0x%08lx ptr=%p",
              qhr, static_cast<void*>(profile7.Get()));
    dbg(buf);
  }
  if (FAILED(qhr) || !profile7) {
    dbg("LoadExtensions: Profile7 unavailable");
    done(false, "WebView2 runtime too old for extensions");
    return;
  }

  auto remaining = std::make_shared<int>(static_cast<int>(paths.size()));
  auto failed = std::make_shared<int>(0);

  for (const auto& p : paths) {
    auto wpath = Utf8ToWide(p);
    HRESULT ahr = profile7->AddBrowserExtension(
        wpath.c_str(),
        Microsoft::WRL::Callback<
            ICoreWebView2ProfileAddBrowserExtensionCompletedHandler>(
            [remaining, failed, done](HRESULT hr,
                                      ICoreWebView2BrowserExtension*) {
              char buf[128];
              sprintf_s(buf, "AddBrowserExtension: hr=0x%08lx", hr);
              dbg(buf);
              if (FAILED(hr)) (*failed)++;
              if (--(*remaining) == 0) done(true, "");
              return S_OK;
            })
            .Get());
    {
      char buf[160];
      sprintf_s(buf, "LoadExtensions: AddBrowserExtension returned hr=0x%08lx",
                ahr);
      dbg(buf);
    }
  }
}

}  // namespace pagereader
