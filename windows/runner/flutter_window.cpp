#include "flutter_window.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Register the embedded WebView2 host.
  //
  // Deferred: GetRegistrarForPlugin must not run before the engine has
  // finished starting up. Doing it in OnCreate or in the first-frame
  // callback both crashed (BEX64 / access violation). The channel is
  // created on demand from the window procedure instead -- see
  // MessageHandler handling of WM_APP+1.
  engine_ = flutter_controller_->engine();

  // WebViewHost must be created here rather than as a value member:
  // its ComPtr members require COM to be initialised and the WebView2
  // runtime to be resolvable, neither of which holds during
  // FlutterWindow's own construction.
  webview_host_ = std::make_unique<pagereader::WebViewHost>();

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    this->Show();
    // Ask ourselves to register after the message loop is running.
    ::PostMessage(GetHandle(), WM_APP + 1, 0, 0);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Release WebView2 COM objects before the engine goes away.
  //
  // ComPtr destructors release interfaces; running them after
  // CoUninitialize (which happens in main after the message loop ends)
  // is an access violation.
  if (webview_host_) {
    webview_host_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Register the WebView2 channel on demand.
  //
  // Doing this earlier (in OnCreate or the first-frame callback) crashed:
  // GetRegistrarForPlugin touches engine state that is not ready until the
  // message loop is pumping. Posting ourselves a message defers it safely.
  if (message == WM_APP + 1) {
    if (!webview_registered_ && engine_) {
      webview_registered_ = true;
      FlutterDesktopPluginRegistrarRef core_registrar =
          engine_->GetRegistrarForPlugin("PageReaderWebView");
      // Pass the raw C messenger handle; WebViewHost wraps it with
      // BinaryMessengerImpl internally.
      FlutterDesktopMessengerRef messenger =
          FlutterDesktopPluginRegistrarGetMessenger(core_registrar);
      FlutterDesktopMessengerAddRef(messenger);
      if (webview_host_) {
        webview_host_->Attach(messenger);
      }
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
