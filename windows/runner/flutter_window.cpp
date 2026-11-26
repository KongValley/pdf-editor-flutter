#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "native_bridge.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  if (dispatch_guard_) {
    std::lock_guard<std::mutex> lock(dispatch_guard_->mutex);
    dispatch_guard_->alive = true;
    dispatch_guard_->force_close.store(false);
    dispatch_guard_->close_prompt_active.store(false);
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterNativeBridge(flutter_controller_->engine()->messenger(), GetHandle(),
                       dispatch_guard_, dirty_flag_);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (dispatch_guard_) {
    std::lock_guard<std::mutex> lock(dispatch_guard_->mutex);
    dispatch_guard_->alive = false;
    dispatch_guard_->channel = nullptr;
  }

  MSG msg;
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    while (PeekMessageW(&msg, hwnd, kWmNativeAsyncComplete,
                        kWmNativeAsyncComplete, PM_REMOVE)) {
      std::unique_ptr<NativeAsyncPayload> payload(
          reinterpret_cast<NativeAsyncPayload*>(msg.lParam));
      if (payload && payload->result && flutter_controller_) {
        payload->result->Error("WINDOW_CLOSED", "窗口已关闭");
      }
    }
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
  if (message == WM_CLOSE && dispatch_guard_ &&
      dispatch_guard_->modal_open.load()) {
    return 0;
  }
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      auto* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
      UINT dpi = FlutterDesktopGetDpiForMonitor(
          MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));
      double scale = dpi / 96.0;
      mmi->ptMinTrackSize.x = static_cast<LONG>(1024 * scale);
      mmi->ptMinTrackSize.y = static_cast<LONG>(640 * scale);
      return 0;
    }
    case WM_CLOSE: {
      if (dispatch_guard_ && dispatch_guard_->modal_open.load()) {
        return 0;
      }
      if (dispatch_guard_ && dispatch_guard_->force_close.load()) {
        break;
      }
      if (dispatch_guard_ && flutter_controller_ &&
          TryRequestFlutterClose(hwnd, dispatch_guard_, dirty_flag_)) {
        return 0;
      }
      if (dirty_flag_->load()) {
        if (!ShowUnsavedCloseFallbackDialog(hwnd, dispatch_guard_)) {
          return 0;
        }
        dirty_flag_->store(false);
      }
      break;
    }
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case kWmNativeAsyncComplete: {
      std::unique_ptr<NativeAsyncPayload> payload(
          reinterpret_cast<NativeAsyncPayload*>(lparam));
      bool can_reply = false;
      if (dispatch_guard_) {
        std::lock_guard<std::mutex> lock(dispatch_guard_->mutex);
        can_reply = dispatch_guard_->alive && flutter_controller_ != nullptr;
      }
      if (can_reply && payload && payload->result) {
        if (payload->ok) {
          payload->result->Success(flutter::EncodableValue(payload->response));
        } else {
          payload->result->Error(payload->error_code, payload->error_message);
        }
      }
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
