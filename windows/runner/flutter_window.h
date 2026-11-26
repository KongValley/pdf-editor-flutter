#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <atomic>
#include <memory>

#include "native_bridge.h"
#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::shared_ptr<NativeDispatchGuard> dispatch_guard_ =
      std::make_shared<NativeDispatchGuard>();
  std::shared_ptr<std::atomic<bool>> dirty_flag_ =
      std::make_shared<std::atomic<bool>>(false);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
