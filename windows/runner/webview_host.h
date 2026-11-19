#ifndef RUNNER_WEBVIEW_HOST_H_
#define RUNNER_WEBVIEW_HOST_H_

// NOTE: no Flutter headers here.
//
// Including flutter/method_channel.h in a header that is pulled in by
// flutter_window.h crashed at startup with BEX64 (ntdll access violation),
// apparently from static initialisation ordering between the Flutter C++
// wrapper and WebView2's MIDL interfaces. Keeping this header Flutter-free
// and taking the messenger as an opaque pointer avoids the problem.
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <wrl.h>

#include "WebView2.h"

namespace pagereader {

// Opaque types from the Flutter embedder.
struct FlutterMessenger;

class WebViewHost {
 public:
  struct Session {
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller;
    Microsoft::WRL::ComPtr<ICoreWebView2> webview;
    std::string book_id;
    HWND hwnd = nullptr;
    EventRegistrationToken message_token{};

    // Set once the window starts closing (WM_CLOSE received and the final
    // position capture has begun).
    //
    // The session stays in the map until WM_DESTROY so the capture can still
    // read the page, but it is no longer usable for navigation: the webview
    // is being torn down. Reusing it made the second open silently do
    // nothing -- no window, no progress, and the shelf stuck on "reading".
    bool closing = false;
  };

  // Per-method result callback, so this header does not need Flutter types.
  using ResultFn = std::function<void(bool ok, const std::string& payload)>;
  using ReportFn = std::function<void(const std::string& payload)>;

  WebViewHost();
  ~WebViewHost();

  // Binds the host to the Flutter messenger (created with
  // FlutterDesktopPluginRegistrarGetMessenger). Called once at startup.
  void Attach(void* messenger_ref);

  // Called from Dart via the method channel.
  void OpenBook(const std::string& book_id, const std::string& url,
                ResultFn done);
  void ExecuteScript(const std::string& book_id, const std::string& script,
                     ResultFn done);
  void CloseBook(const std::string& book_id);

  // Drops the session after its window is destroyed.
  void ForgetSession(const std::string& book_id);
  void LoadExtensions(const std::vector<std::string>& paths, ResultFn done);

  // Stores the extension paths without loading them yet.
  //
  // Called from Dart before openBook. The actual AddBrowserExtension must
  // wait until the WebView2 profile exists (it only exists once the first
  // controller is created), so we remember the list and load it right when
  // the profile becomes available -- before the first page finishes
  // loading, so extensions apply to the page the user starts reading.
  void SetPendingExtensions(const std::vector<std::string>& paths);

  // Loads whatever SetPendingExtensions stored, if the profile is ready.
  void LoadPendingExtensionsIfReady();

  // Marks a session as closing so OpenBook will not reuse it.
  void MarkSessionClosing(const std::string& book_id);

  // Captures the final scroll position before the window dies.
  //
  // Returns true if a capture was started (the caller must NOT destroy the
  // window; the script callback does it). False means the caller can
  // destroy immediately.
  bool CaptureFinalPosition(HWND hwnd, const std::string& book_id);

  // How long to wait for the final capture before force-closing (ms).
  static constexpr UINT_PTR kCloseTimerId = 0x9B01;
  void SetUserDataDir(const std::string& dir);

  // Page -> Dart reports.
  void SetReportSink(ReportFn sink);

  // Fired when a reading window is closed by the user (clicking X).
  // Dart uses it to drop the book from "currently reading".
  void SetClosedSink(std::function<void(const std::string& book_id)> sink);

  // Script injected before any page script runs (anchor collection and the
  // __prReport bridge). Must be set before the first OpenBook.
  void SetPageBridge(const std::string& script);

 private:
  // Window procedure for reading windows: reports close events to Dart.
  static LRESULT CALLBACK ReadingWindowProc(HWND hwnd, UINT msg,
                                            WPARAM wparam, LPARAM lparam);

  void EnsureEnvironment(std::function<void(bool, const std::string&)> done);
  void CreateSession(const std::string& book_id, const std::string& url,
                     ResultFn done);

  void* messenger_ = nullptr;
  // Real type is flutter::BinaryMessengerImpl. Kept as void* so this header
  // stays free of Flutter headers (including them here crashed at startup).
  void* messenger_impl_ = nullptr;
  std::function<void(const std::string&)> closed_sink_;
  std::string page_bridge_;

  // Extension directories to load as soon as the profile exists.
  std::vector<std::string> pending_extensions_;
  bool pending_extensions_loaded_ = false;
  ReportFn report_sink_;

  Microsoft::WRL::ComPtr<ICoreWebView2Environment> env_;
  Microsoft::WRL::ComPtr<ICoreWebView2Profile> profile_;
  bool env_ready_ = false;
  std::string user_data_dir_;

  std::map<std::string, std::unique_ptr<Session>> sessions_;
  int next_host_x_ = 80;
  int next_host_y_ = 80;
};

}  // namespace pagereader

#endif  // RUNNER_WEBVIEW_HOST_H_
