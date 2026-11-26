#ifndef RUNNER_NATIVE_BRIDGE_H_
#define RUNNER_NATIVE_BRIDGE_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>

constexpr UINT kWmNativeAsyncComplete = WM_APP + 102;

struct NativeDispatchGuard {
  std::mutex mutex;
  bool alive = true;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  std::atomic<bool> modal_open{false};
  std::atomic<bool> force_close{false};
  std::atomic<bool> close_prompt_active{false};
};

struct NativeAsyncPayload {
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  bool ok = false;
  std::string error_code;
  std::string error_message;
  flutter::EncodableMap response;
};

void RegisterNativeBridge(
    flutter::BinaryMessenger* messenger,
    HWND hwnd,
    std::shared_ptr<NativeDispatchGuard> dispatch_guard,
    std::shared_ptr<std::atomic<bool>> document_dirty);

bool TryRequestFlutterClose(
    HWND hwnd,
    const std::shared_ptr<NativeDispatchGuard>& dispatch_guard,
    const std::shared_ptr<std::atomic<bool>>& document_dirty);

bool ShowUnsavedCloseFallbackDialog(
    HWND hwnd,
    const std::shared_ptr<NativeDispatchGuard>& dispatch_guard);

#endif  // RUNNER_NATIVE_BRIDGE_H_
