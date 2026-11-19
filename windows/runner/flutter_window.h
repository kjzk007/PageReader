#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "webview_host.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Flutter engine, kept for lazily registering the WebView2 channel.
  flutter::FlutterEngine* engine_ = nullptr;

  // Whether the WebView2 method channel has been registered.
  bool webview_registered_ = false;

  // Embedded WebView2 host for reading windows.
  //
  // Reading windows are created and managed by it, outside Flutter's
  // composition layer, so they are unaffected by platform-view GPU issues
  // and do not contend with the user's own browser profile.
  std::unique_ptr<pagereader::WebViewHost> webview_host_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
