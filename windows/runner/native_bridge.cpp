#include "native_bridge.h"

#include <commctrl.h>
#include <commdlg.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <robuffer.h>
#include <shellapi.h>
#include <winspool.h>
#include <windows.foundation.collections.h>
#include <windows.foundation.h>
#include <windows.globalization.h>
#include <windows.graphics.imaging.h>
#include <windows.media.ocr.h>
#include <windows.storage.streams.h>
#include <winstring.h>
#include <wrl/client.h>
#include <wrl/wrappers/corewrappers.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <map>
#include <mutex>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HString;
using Microsoft::WRL::Wrappers::HStringReference;

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) return L"";
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), len);
  return out;
}

std::string WideToUtf8(const wchar_t* wide, UINT32 len) {
  if (wide == nullptr || len == 0) return "";
  int bytes = WideCharToMultiByte(CP_UTF8, 0, wide, static_cast<int>(len),
                                  nullptr, 0, nullptr, nullptr);
  if (bytes <= 0) return "";
  std::string out(static_cast<size_t>(bytes), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, static_cast<int>(len), out.data(),
                      bytes, nullptr, nullptr);
  return out;
}

std::string HStringToUtf8(HSTRING hstr) {
  if (hstr == nullptr) return "";
  UINT32 len = 0;
  const wchar_t* raw = WindowsGetStringRawBuffer(hstr, &len);
  return WideToUtf8(raw, len);
}

// ===========================================================================
// 1. Windows.Media.Ocr 4-way orientation detection (0 / 90 / 180 / 270)
// ===========================================================================

template <typename Op, typename Res>
HRESULT AwaitAsyncOp(Op* op, Res* out_result) {
  if (op == nullptr || out_result == nullptr) return E_POINTER;
  ComPtr<ABI::Windows::Foundation::IAsyncInfo> info;
  HRESULT hr = op->QueryInterface(IID_PPV_ARGS(&info));
  if (FAILED(hr)) return hr;
  ABI::Windows::Foundation::AsyncStatus status =
      ABI::Windows::Foundation::AsyncStatus::Started;
  for (int i = 0; i < 6000; ++i) {
    hr = info->get_Status(&status);
    if (FAILED(hr)) return hr;
    if (status != ABI::Windows::Foundation::AsyncStatus::Started) break;
    Sleep(5);
  }
  if (status != ABI::Windows::Foundation::AsyncStatus::Completed) {
    HRESULT err = E_FAIL;
    info->get_ErrorCode(&err);
    return FAILED(err) ? err : E_FAIL;
  }
  return op->GetResults(out_result);
}

HRESULT TryCreateOcrEngineForTag(
    ABI::Windows::Media::Ocr::IOcrEngineStatics* ocr_statics,
    ABI::Windows::Globalization::ILanguageFactory* lang_factory,
    const wchar_t* tag,
    ABI::Windows::Media::Ocr::IOcrEngine** out_engine) {
  HStringReference htag(tag);
  ComPtr<ABI::Windows::Globalization::ILanguage> lang;
  HRESULT hr = lang_factory->CreateLanguage(htag.Get(), &lang);
  if (FAILED(hr) || !lang) return FAILED(hr) ? hr : E_FAIL;

  boolean supported = FALSE;
  hr = ocr_statics->IsLanguageSupported(lang.Get(), &supported);
  if (FAILED(hr) || !supported) return E_FAIL;

  return ocr_statics->TryCreateFromLanguage(lang.Get(), out_engine);
}

// Rotate tight BGRA8 buffer clockwise by delta (0, 90, 180, 270).
void RotateBgra(const std::vector<uint8_t>& src, int w, int h, int delta,
                std::vector<uint8_t>* dst, int* out_w, int* out_h) {
  if (delta == 0) {
    *dst = src;
    *out_w = w;
    *out_h = h;
    return;
  }
  if (delta == 180) {
    *out_w = w;
    *out_h = h;
    dst->resize(static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        size_t s = (static_cast<size_t>(y) * w + x) * 4;
        size_t d = (static_cast<size_t>(h - 1 - y) * w + (w - 1 - x)) * 4;
        std::memcpy(dst->data() + d, src.data() + s, 4);
      }
    }
    return;
  }
  if (delta == 90) {
    *out_w = h;
    *out_h = w;
    dst->resize(static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        size_t s = (static_cast<size_t>(y) * w + x) * 4;
        int nx = h - 1 - y;
        int ny = x;
        size_t d = (static_cast<size_t>(ny) * (*out_w) + nx) * 4;
        std::memcpy(dst->data() + d, src.data() + s, 4);
      }
    }
    return;
  }
  // delta == 270
  *out_w = h;
  *out_h = w;
  dst->resize(static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      size_t s = (static_cast<size_t>(y) * w + x) * 4;
      int nx = y;
      int ny = w - 1 - x;
      size_t d = (static_cast<size_t>(ny) * (*out_w) + nx) * 4;
      std::memcpy(dst->data() + d, src.data() + s, 4);
    }
  }
}

int ScoreRecognizedText(const std::string& utf8) {
  int score = 0;
  for (size_t i = 0; i < utf8.size();) {
    unsigned char c = static_cast<unsigned char>(utf8[i]);
    if (c < 0x80) {
      if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
          (c >= 'a' && c <= 'z')) {
        score += 1;
      }
      i += 1;
    } else if ((c & 0xE0) == 0xC0) {
      i += 2;
      score += 1;
    } else if ((c & 0xF0) == 0xE0) {
      // CJK unified ideographs live mostly in 3-byte UTF-8 range.
      i += 3;
      score += 2;
    } else {
      i += 4;
      score += 1;
    }
  }
  return score;
}

bool DetectOcrOrientationSync(const std::vector<uint8_t>& bgra_bytes,
                              int width,
                              int height,
                              flutter::EncodableMap* out_map,
                              std::string* out_err_code,
                              std::string* out_err_msg) {
  if (width <= 0 || height <= 0 ||
      bgra_bytes.size() <
          static_cast<size_t>(width) * static_cast<size_t>(height) * 4) {
    *out_err_code = "INVALID_IMAGE";
    *out_err_msg = "位图尺寸或缓冲无效";
    return false;
  }

  struct ScopedRoInit {
    bool did_init = false;
    HRESULT hr = S_OK;
    ScopedRoInit() {
      hr = RoInitialize(RO_INIT_MULTITHREADED);
      if (hr == RPC_E_CHANGED_MODE) {
        hr = S_OK;
        did_init = false;
      } else {
        did_init = SUCCEEDED(hr);
      }
    }
    ~ScopedRoInit() {
      if (did_init) {
        RoUninitialize();
      }
    }
  };

  ScopedRoInit ro_guard;
  if (FAILED(ro_guard.hr)) {
    *out_err_code = "WINRT_INIT_FAILED";
    *out_err_msg = "无法初始化 Windows OCR 运行时";
    return false;
  }

  int best_delta = 0;
  int best_score = -1;
  int second_score = -1;
  int score_zero = 0;

  {
    ComPtr<ABI::Windows::Media::Ocr::IOcrEngineStatics> ocr_statics;
    HRESULT hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Media_Ocr_OcrEngine).Get(),
        IID_PPV_ARGS(&ocr_statics));
    ComPtr<ABI::Windows::Globalization::ILanguageFactory> lang_factory;
    if (SUCCEEDED(hr)) {
      RoGetActivationFactory(
          HStringReference(RuntimeClass_Windows_Globalization_Language).Get(),
          IID_PPV_ARGS(&lang_factory));
    }

    ComPtr<ABI::Windows::Media::Ocr::IOcrEngine> engine;
    if (ocr_statics && lang_factory) {
      if (FAILED(TryCreateOcrEngineForTag(ocr_statics.Get(), lang_factory.Get(),
                                          L"zh-Hans", &engine)) ||
          !engine) {
        TryCreateOcrEngineForTag(ocr_statics.Get(), lang_factory.Get(), L"zh-CN",
                                 &engine);
      }
    }
    if (!engine && ocr_statics) {
      ocr_statics->TryCreateFromUserProfileLanguages(&engine);
    }
    if (!engine) {
      *out_err_code = "NO_OCR_LANGUAGE";
      *out_err_msg = "未找到可用的 Windows OCR 语言包";
      return false;
    }

    ComPtr<ABI::Windows::Graphics::Imaging::ISoftwareBitmapStatics> sb_statics;
    hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Graphics_Imaging_SoftwareBitmap)
            .Get(),
        IID_PPV_ARGS(&sb_statics));
    ComPtr<ABI::Windows::Storage::Streams::IBufferFactory> buf_factory;
    if (SUCCEEDED(hr)) {
      hr = RoGetActivationFactory(
          HStringReference(RuntimeClass_Windows_Storage_Streams_Buffer).Get(),
          IID_PPV_ARGS(&buf_factory));
    }
    if (FAILED(hr) || !sb_statics || !buf_factory) {
      *out_err_code = "OCR_FACTORY_FAILED";
      *out_err_msg = "无法创建 OCR 位图工厂";
      return false;
    }

    const int deltas[4] = {0, 90, 180, 270};
    for (int idx = 0; idx < 4; ++idx) {
      int delta = deltas[idx];
      std::vector<uint8_t> rotated;
      int rw = 0;
      int rh = 0;
      RotateBgra(bgra_bytes, width, height, delta, &rotated, &rw, &rh);

      ComPtr<ABI::Windows::Storage::Streams::IBuffer> buf;
      hr = buf_factory->Create(static_cast<UINT32>(rotated.size()), &buf);
      if (SUCCEEDED(hr) && buf) {
        hr = buf->put_Length(static_cast<UINT32>(rotated.size()));
      }
      ComPtr<Windows::Storage::Streams::IBufferByteAccess> byte_access;
      if (SUCCEEDED(hr) && buf) hr = buf.As(&byte_access);
      byte* raw_buf = nullptr;
      if (SUCCEEDED(hr) && byte_access) hr = byte_access->Buffer(&raw_buf);
      if (FAILED(hr) || raw_buf == nullptr) continue;
      std::memcpy(raw_buf, rotated.data(), rotated.size());

      ComPtr<ABI::Windows::Graphics::Imaging::ISoftwareBitmap> sb;
      hr = sb_statics->CreateCopyFromBuffer(
          buf.Get(),
          ABI::Windows::Graphics::Imaging::BitmapPixelFormat_Bgra8,
          static_cast<INT32>(rw), static_cast<INT32>(rh), &sb);
      if (FAILED(hr) || !sb) continue;

      ComPtr<ABI::Windows::Foundation::IAsyncOperation<
          ABI::Windows::Media::Ocr::OcrResult*>>
          rec_op;
      hr = engine->RecognizeAsync(sb.Get(), &rec_op);
      ComPtr<ABI::Windows::Media::Ocr::IOcrResult> ocr_res;
      if (SUCCEEDED(hr) && rec_op) {
        hr = AwaitAsyncOp(rec_op.Get(), ocr_res.GetAddressOf());
      }
      if (FAILED(hr) || !ocr_res) continue;

      HString text_hs;
      ocr_res->get_Text(text_hs.GetAddressOf());
      int sc = ScoreRecognizedText(HStringToUtf8(text_hs.Get()));
      if (delta == 0) score_zero = sc;
      if (sc > best_score) {
        second_score = best_score;
        best_score = sc;
        best_delta = delta;
      } else if (sc > second_score) {
        second_score = sc;
      }
    }
  }

  if (best_score < 6) {
    (*out_map)[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
    return true;
  }
  double confidence = 0.0;
  if (best_score > 0) {
    int runner_up = std::max(0, second_score);
    confidence = static_cast<double>(best_score - runner_up) * 100.0 /
                 static_cast<double>(best_score);
  }
  (*out_map)[flutter::EncodableValue("ok")] = flutter::EncodableValue(true);
  (*out_map)[flutter::EncodableValue("delta")] =
      flutter::EncodableValue(best_delta);
  (*out_map)[flutter::EncodableValue("confidence")] =
      flutter::EncodableValue(confidence);
  (*out_map)[flutter::EncodableValue("bestScore")] =
      flutter::EncodableValue(best_score);
  (*out_map)[flutter::EncodableValue("zeroScore")] =
      flutter::EncodableValue(score_zero);
  return true;
}

// ===========================================================================
// 2. Native Win32 GDI Printing (one-page-at-a-time streaming, zero PDFium dup)
// ===========================================================================

struct PrintPageFile {
  std::wstring raw_path;  // Header (8B: int32 w, int32 h) + BGRA pixels
  double width_pt = 595.28;
  double height_pt = 841.89;
};

struct PrintJobState {
  std::wstring job_name;
  std::vector<PrintPageFile> pages;
};

std::mutex g_print_mutex;
std::map<std::string, PrintJobState> g_print_jobs;
int g_next_job_seq = 1;

struct ScopedModalFlag {
  std::shared_ptr<NativeDispatchGuard> guard;
  explicit ScopedModalFlag(std::shared_ptr<NativeDispatchGuard> g)
      : guard(std::move(g)) {
    if (guard) guard->modal_open.store(true);
  }
  ~ScopedModalFlag() {
    if (guard) guard->modal_open.store(false);
  }
};

struct PrintSession {
  std::wstring job_name;
  std::vector<PrintPageFile> pages;
  HDC hdc = nullptr;
  HGLOBAL h_devmode = nullptr;
  HGLOBAL h_devnames = nullptr;
  std::wstring printer_name;
  WORD copies = 1;
  bool collate = false;
};

void FreePrintSessionHandles(PrintSession* session) {
  if (!session) return;
  if (session->h_devmode) {
    GlobalFree(session->h_devmode);
    session->h_devmode = nullptr;
  }
  if (session->h_devnames) {
    GlobalFree(session->h_devnames);
    session->h_devnames = nullptr;
  }
  if (session->hdc) {
    DeleteDC(session->hdc);
    session->hdc = nullptr;
  }
}

void CleanupPrintJobFiles(const PrintJobState& job) {
  for (const auto& p : job.pages) {
    if (!p.raw_path.empty()) {
      DeleteFileW(p.raw_path.c_str());
    }
  }
}

void CleanupPrintSessionFiles(const PrintSession& session) {
  for (const auto& p : session.pages) {
    if (!p.raw_path.empty()) {
      DeleteFileW(p.raw_path.c_str());
    }
  }
}

void ApplyPrinterOrientation(HDC hdc,
                             DEVMODEW* devmode,
                             HANDLE printer_handle,
                             const std::wstring& printer_name,
                             short target_orient) {
  if (!devmode) return;
  devmode->dmFields |= DM_ORIENTATION;
  devmode->dmOrientation = target_orient;
  if (printer_handle && !printer_name.empty()) {
    DocumentPropertiesW(nullptr, printer_handle,
                        const_cast<wchar_t*>(printer_name.c_str()), devmode,
                        devmode, DM_IN_BUFFER | DM_OUT_BUFFER);
  }
  ResetDCW(hdc, devmode);
}

bool SpoolPrintSession(PrintSession* session, std::string* out_err_msg) {
  if (!session || !session->hdc || session->pages.empty()) {
    *out_err_msg = "没有可打印的页面或设备上下文无效";
    return false;
  }

  HDC hdc = session->hdc;
  DEVMODEW* devmode =
      session->h_devmode
          ? static_cast<DEVMODEW*>(GlobalLock(session->h_devmode))
          : nullptr;

  HANDLE h_printer = nullptr;
  if (!session->printer_name.empty()) {
    OpenPrinterW(const_cast<wchar_t*>(session->printer_name.c_str()),
                 &h_printer, nullptr);
  }

  short current_orient = devmode ? devmode->dmOrientation : 0;
  if (devmode) {
    short page0_orient =
        session->pages[0].width_pt > session->pages[0].height_pt
            ? DMORIENT_LANDSCAPE
            : DMORIENT_PORTRAIT;
    if (page0_orient != current_orient ||
        (devmode->dmFields & DM_ORIENTATION) == 0) {
      ApplyPrinterOrientation(hdc, devmode, h_printer, session->printer_name,
                              page0_orient);
      current_orient = page0_orient;
    }
  }

  DOCINFOW doc_info{};
  doc_info.cbSize = sizeof(doc_info);
  doc_info.lpszDocName =
      session->job_name.empty() ? L"PDF 打印" : session->job_name.c_str();

  if (StartDocW(hdc, &doc_info) <= 0) {
    if (h_printer) ClosePrinter(h_printer);
    if (devmode) GlobalUnlock(session->h_devmode);
    FreePrintSessionHandles(session);
    *out_err_msg = "StartDocW 启动打印作业失败";
    return false;
  }

  std::vector<size_t> emit_order;
  const int copies = std::max<int>(1, session->copies);
  if (session->collate) {
    for (int c = 0; c < copies; ++c) {
      for (size_t i = 0; i < session->pages.size(); ++i) {
        emit_order.push_back(i);
      }
    }
  } else {
    for (size_t i = 0; i < session->pages.size(); ++i) {
      for (int c = 0; c < copies; ++c) {
        emit_order.push_back(i);
      }
    }
  }

  bool ok = true;
  for (size_t idx = 0; idx < emit_order.size(); ++idx) {
    const auto& page = session->pages[emit_order[idx]];
    if (devmode) {
      short target_orient = page.width_pt > page.height_pt
                                ? DMORIENT_LANDSCAPE
                                : DMORIENT_PORTRAIT;
      if (target_orient != current_orient) {
        ApplyPrinterOrientation(hdc, devmode, h_printer, session->printer_name,
                                target_orient);
        current_orient = target_orient;
      }
    }

    if (StartPage(hdc) <= 0) {
      ok = false;
      *out_err_msg = "StartPage 失败";
      break;
    }

    std::ifstream ifs(page.raw_path, std::ios::binary);
    int32_t img_w = 0;
    int32_t img_h = 0;
    ifs.read(reinterpret_cast<char*>(&img_w), sizeof(img_w));
    ifs.read(reinterpret_cast<char*>(&img_h), sizeof(img_h));
    if (!ifs || img_w <= 0 || img_h <= 0) {
      EndPage(hdc);
      ok = false;
      *out_err_msg = "读取打印页面位图失败";
      break;
    }
    const size_t pixel_bytes =
        static_cast<size_t>(img_w) * static_cast<size_t>(img_h) * 4;
    std::vector<uint8_t> pixels(pixel_bytes);
    ifs.read(reinterpret_cast<char*>(pixels.data()),
             static_cast<std::streamsize>(pixel_bytes));
    if (!ifs) {
      EndPage(hdc);
      ok = false;
      *out_err_msg = "打印页面位图数据不完整";
      break;
    }

    // 转 bottom-up 24bpp BGR (DWORD 对齐)，兼容各类 PCL/PS/老旧 GDI 打印驱动
    const size_t bgr_stride =
        (static_cast<size_t>(img_w) * 3 + 3) & ~static_cast<size_t>(3);
    std::vector<uint8_t> bgr24(bgr_stride * static_cast<size_t>(img_h), 0);
    for (int y = 0; y < img_h; ++y) {
      const size_t src_row = static_cast<size_t>(y) * img_w * 4;
      const size_t dst_row =
          static_cast<size_t>(img_h - 1 - y) * bgr_stride;
      for (int x = 0; x < img_w; ++x) {
        const size_t si = src_row + static_cast<size_t>(x) * 4;
        const size_t di = dst_row + static_cast<size_t>(x) * 3;
        const uint8_t a = pixels[si + 3];
        if (a == 255) {
          bgr24[di] = pixels[si];
          bgr24[di + 1] = pixels[si + 1];
          bgr24[di + 2] = pixels[si + 2];
        } else {
          // 合成到白纸底色
          const uint32_t inv_a = 255 - a;
          bgr24[di] = static_cast<uint8_t>(
              (static_cast<uint32_t>(pixels[si]) * a + 255 * inv_a) / 255);
          bgr24[di + 1] = static_cast<uint8_t>(
              (static_cast<uint32_t>(pixels[si + 1]) * a + 255 * inv_a) / 255);
          bgr24[di + 2] = static_cast<uint8_t>(
              (static_cast<uint32_t>(pixels[si + 2]) * a + 255 * inv_a) / 255);
        }
      }
    }

    const int page_w = std::max(1, GetDeviceCaps(hdc, HORZRES));
    const int page_h = std::max(1, GetDeviceCaps(hdc, VERTRES));
    const int dpi_x = std::max(1, GetDeviceCaps(hdc, LOGPIXELSX));
    const int dpi_y = std::max(1, GetDeviceCaps(hdc, LOGPIXELSY));
    const double phys_w_in = static_cast<double>(page_w) / dpi_x;
    const double phys_h_in = static_cast<double>(page_h) / dpi_y;
    const double inch_scale =
        std::min(phys_w_in / img_w, phys_h_in / img_h);
    const int dst_w =
        std::max(1, static_cast<int>(std::lround(img_w * inch_scale * dpi_x)));
    const int dst_h =
        std::max(1, static_cast<int>(std::lround(img_h * inch_scale * dpi_y)));
    const int dst_x = (page_w - dst_w) / 2;
    const int dst_y = (page_h - dst_h) / 2;

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = img_w;
    bmi.bmiHeader.biHeight = img_h;  // Bottom-up 24bpp BGR
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 24;
    bmi.bmiHeader.biCompression = BI_RGB;

    SetStretchBltMode(hdc, HALFTONE);
    SetBrushOrgEx(hdc, 0, 0, nullptr);
    int drawn = StretchDIBits(hdc, dst_x, dst_y, dst_w, dst_h, 0, 0, img_w,
                              img_h, bgr24.data(), &bmi, DIB_RGB_COLORS,
                              SRCCOPY);
    if (drawn <= 0 || drawn == GDI_ERROR) {
      EndPage(hdc);
      ok = false;
      *out_err_msg = "StretchDIBits 向打印机输出页面失败";
      break;
    }

    if (EndPage(hdc) <= 0) {
      ok = false;
      *out_err_msg = "EndPage 失败";
      break;
    }
  }

  if (ok) {
    EndDoc(hdc);
  } else {
    AbortDoc(hdc);
  }

  if (h_printer) ClosePrinter(h_printer);
  if (devmode) GlobalUnlock(session->h_devmode);
  FreePrintSessionHandles(session);
  return ok;
}

void DispatchAsyncResult(HWND hwnd,
                         const std::shared_ptr<NativeDispatchGuard>& guard,
                         std::unique_ptr<NativeAsyncPayload> payload) {
  if (!guard) return;
  std::lock_guard<std::mutex> lock(guard->mutex);
  if (guard->alive && IsWindow(hwnd)) {
    NativeAsyncPayload* raw = payload.release();
    if (!PostMessage(hwnd, kWmNativeAsyncComplete, 0,
                     reinterpret_cast<LPARAM>(raw))) {
      delete raw;
    }
  }
}

std::wstring SanitizeFileName(const std::wstring& input) {
  std::wstring out;
  out.reserve(input.size());
  for (wchar_t ch : input) {
    if (ch < 32 || ch == L'<' || ch == L'>' || ch == L':' || ch == L'"' ||
        ch == L'/' || ch == L'\\' || ch == L'|' || ch == L'?' || ch == L'*') {
      continue;
    }
    out.push_back(ch);
    if (out.size() >= 200) break;
  }
  return out;
}

}  // namespace

bool ShowUnsavedCloseFallbackDialog(
    HWND hwnd,
    const std::shared_ptr<NativeDispatchGuard>& dispatch_guard) {
  ScopedModalFlag modal(dispatch_guard);
  using TaskDialogIndirectFn =
      HRESULT(WINAPI*)(const TASKDIALOGCONFIG*, int*, int*, BOOL*);
  HMODULE comctl = LoadLibraryW(L"comctl32.dll");
  if (comctl) {
    auto task_dialog_indirect = reinterpret_cast<TaskDialogIndirectFn>(
        GetProcAddress(comctl, "TaskDialogIndirect"));
    if (task_dialog_indirect) {
      const TASKDIALOG_BUTTON buttons[] = {
          {IDYES, L"不保存并关闭"},
          {IDNO, L"取消"},
      };
      TASKDIALOGCONFIG tdc{};
      tdc.cbSize = sizeof(tdc);
      tdc.hwndParent = hwnd;
      tdc.dwFlags =
          TDF_POSITION_RELATIVE_TO_WINDOW | TDF_ALLOW_DIALOG_CANCELLATION;
      tdc.pszWindowTitle = L"PDF 编辑器 — 未保存的更改";
      tdc.pszMainIcon = TD_WARNING_ICON;
      tdc.pszMainInstruction = L"当前文档有未保存的更改";
      tdc.pszContent = L"直接关闭窗口将丢失尚未保存的批注或页面修改。";
      tdc.cButtons = static_cast<UINT>(std::size(buttons));
      tdc.pButtons = buttons;
      tdc.nDefaultButton = IDNO;
      int pressed = IDNO;
      HRESULT hr = task_dialog_indirect(&tdc, &pressed, nullptr, nullptr);
      FreeLibrary(comctl);
      if (SUCCEEDED(hr)) {
        return pressed == IDYES;
      }
    } else {
      FreeLibrary(comctl);
    }
  }
  int ans = MessageBoxW(
      hwnd,
      L"当前文档有未保存的更改，直接关闭将丢失这些更改。\n确定要不保存并关闭吗？",
      L"未保存的更改", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2);
  return ans == IDYES;
}

bool TryRequestFlutterClose(
    HWND hwnd,
    const std::shared_ptr<NativeDispatchGuard>& dispatch_guard,
    const std::shared_ptr<std::atomic<bool>>& document_dirty) {
  if (!dispatch_guard) return false;
  if (dispatch_guard->close_prompt_active.exchange(true)) {
    return true;
  }

  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  {
    std::lock_guard<std::mutex> lock(dispatch_guard->mutex);
    if (dispatch_guard->alive) {
      channel = dispatch_guard->channel;
    }
  }
  if (!channel) {
    dispatch_guard->close_prompt_active.store(false);
    return false;
  }

  auto result_handler =
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [hwnd, dispatch_guard,
           document_dirty](const flutter::EncodableValue* value) {
            dispatch_guard->close_prompt_active.store(false);
            bool allow_close = false;
            if (value) {
              if (const auto* b = std::get_if<bool>(value)) {
                allow_close = *b;
              }
            }
            if (allow_close) {
              document_dirty->store(false);
              dispatch_guard->force_close.store(true);
              PostMessage(hwnd, WM_CLOSE, 0, 0);
            }
          },
          [hwnd, dispatch_guard, document_dirty](
              const std::string& /*code*/, const std::string& /*msg*/,
              const flutter::EncodableValue* /*details*/) {
            dispatch_guard->close_prompt_active.store(false);
            if (!document_dirty->load()) {
              dispatch_guard->force_close.store(true);
              PostMessage(hwnd, WM_CLOSE, 0, 0);
            }
          },
          [hwnd, dispatch_guard, document_dirty]() {
            if (!document_dirty->load()) {
              dispatch_guard->close_prompt_active.store(false);
              dispatch_guard->force_close.store(true);
              PostMessage(hwnd, WM_CLOSE, 0, 0);
            } else {
              bool discard =
                  ShowUnsavedCloseFallbackDialog(hwnd, dispatch_guard);
              dispatch_guard->close_prompt_active.store(false);
              if (discard) {
                document_dirty->store(false);
                dispatch_guard->force_close.store(true);
                PostMessage(hwnd, WM_CLOSE, 0, 0);
              }
            }
          });
  channel->InvokeMethod("requestClose", nullptr, std::move(result_handler));
  return true;
}

void RegisterNativeBridge(
    flutter::BinaryMessenger* messenger,
    HWND hwnd,
    std::shared_ptr<NativeDispatchGuard> dispatch_guard,
    std::shared_ptr<std::atomic<bool>> document_dirty) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pdf_editor_flutter/native",
      &flutter::StandardMethodCodec::GetInstance());
  {
    std::lock_guard<std::mutex> lock(dispatch_guard->mutex);
    dispatch_guard->alive = true;
    dispatch_guard->channel = channel.get();
  }

  channel->SetMethodCallHandler(
      [hwnd, dispatch_guard, document_dirty](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        const std::string& method = call.method_name();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

        if (method == "setTitle") {
          std::string title = "PDF 编辑器";
          if (args) {
            auto it = args->find(flutter::EncodableValue("title"));
            if (it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                title = *s;
              }
            }
          }
          SetWindowTextW(hwnd, Utf8ToWide(title).c_str());
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "setDirty") {
          bool dirty = false;
          if (args) {
            auto it = args->find(flutter::EncodableValue("dirty"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) {
                dirty = *b;
              }
            }
          }
          document_dirty->store(dirty);
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "toggleFullscreen") {
          static bool s_fullscreen = false;
          static WINDOWPLACEMENT s_prev_placement{sizeof(WINDOWPLACEMENT)};
          LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
          if (!s_fullscreen) {
            MONITORINFO mi{sizeof(mi)};
            if (GetWindowPlacement(hwnd, &s_prev_placement) &&
                GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY),
                               &mi)) {
              SetWindowLongPtr(hwnd, GWL_STYLE,
                               style & ~WS_OVERLAPPEDWINDOW);
              SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                           mi.rcMonitor.right - mi.rcMonitor.left,
                           mi.rcMonitor.bottom - mi.rcMonitor.top,
                           SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
              s_fullscreen = true;
            }
          } else {
            SetWindowLongPtr(hwnd, GWL_STYLE, style | WS_OVERLAPPEDWINDOW);
            SetWindowPlacement(hwnd, &s_prev_placement);
            SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                             SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
            s_fullscreen = false;
          }
          result->Success(flutter::EncodableValue(s_fullscreen));
          return;
        }

        if (method == "forceClose") {
          document_dirty->store(false);
          dispatch_guard->force_close.store(true);
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "openFolder") {
          std::string path;
          bool select_file = false;
          if (args) {
            auto it_p = args->find(flutter::EncodableValue("path"));
            if (it_p != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_p->second)) {
                path = *s;
              }
            }
            auto it_s = args->find(flutter::EncodableValue("select"));
            if (it_s != args->end()) {
              if (const auto* b = std::get_if<bool>(&it_s->second)) {
                select_file = *b;
              }
            }
          }
          if (path.empty()) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          std::wstring wpath = Utf8ToWide(path);
          std::replace(wpath.begin(), wpath.end(), L'/', L'\\');
          HINSTANCE hinst = nullptr;
          if (select_file) {
            std::wstring param = L"/select,\"" + wpath + L"\"";
            hinst = ShellExecuteW(hwnd, L"open", L"explorer.exe", param.c_str(),
                                  nullptr, SW_SHOWNORMAL);
          } else {
            hinst = ShellExecuteW(hwnd, L"open", L"explorer.exe",
                                  (L"\"" + wpath + L"\"").c_str(), nullptr,
                                  SW_SHOWNORMAL);
          }
          result->Success(flutter::EncodableValue(
              reinterpret_cast<INT_PTR>(hinst) > 32));
          return;
        }

        if (method == "ocrDetectOrientation") {
          if (!args) {
            result->Error("INVALID_ARGS", "参数无效");
            return;
          }
          auto it_bytes = args->find(flutter::EncodableValue("bytes"));
          auto it_w = args->find(flutter::EncodableValue("width"));
          auto it_h = args->find(flutter::EncodableValue("height"));
          if (it_bytes == args->end() || it_w == args->end() ||
              it_h == args->end()) {
            result->Error("INVALID_ARGS", "缺少图片参数");
            return;
          }
          const auto* bytes_ptr =
              std::get_if<std::vector<uint8_t>>(&it_bytes->second);
          const auto* w_ptr = std::get_if<int32_t>(&it_w->second);
          const auto* h_ptr = std::get_if<int32_t>(&it_h->second);
          if (!bytes_ptr || !w_ptr || !h_ptr) {
            result->Error("INVALID_ARGS", "图片参数类型错误");
            return;
          }
          std::vector<uint8_t> copied = *bytes_ptr;
          int w = *w_ptr;
          int h = *h_ptr;
          auto* raw_res = result.release();
          std::thread([hwnd, dispatch_guard, copied = std::move(copied), w, h,
                       raw_res]() mutable {
            auto payload = std::make_unique<NativeAsyncPayload>();
            payload->result.reset(raw_res);
            payload->ok = DetectOcrOrientationSync(
                copied, w, h, &payload->response, &payload->error_code,
                &payload->error_message);
            DispatchAsyncResult(hwnd, dispatch_guard, std::move(payload));
          }).detach();
          return;
        }

        if (method == "printPrepare") {
          std::string job_name = "PDF 打印";
          if (args) {
            auto it = args->find(flutter::EncodableValue("jobName"));
            if (it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                job_name = *s;
              }
            }
          }
          std::lock_guard<std::mutex> lock(g_print_mutex);
          std::string job_id = "print-" + std::to_string(g_next_job_seq++);
          PrintJobState st;
          st.job_name = Utf8ToWide(job_name);
          g_print_jobs.emplace(job_id, std::move(st));
          result->Success(flutter::EncodableValue(job_id));
          return;
        }

        if (method == "printAddPage") {
          if (!args) {
            result->Error("INVALID_ARGS", "参数无效");
            return;
          }
          auto it_job = args->find(flutter::EncodableValue("jobId"));
          auto it_path = args->find(flutter::EncodableValue("rawPath"));
          auto it_w = args->find(flutter::EncodableValue("widthPt"));
          auto it_h = args->find(flutter::EncodableValue("heightPt"));
          const auto* job_id = it_job != args->end()
                                   ? std::get_if<std::string>(&it_job->second)
                                   : nullptr;
          const auto* raw_path = it_path != args->end()
                                     ? std::get_if<std::string>(&it_path->second)
                                     : nullptr;
          const auto* w_pt = it_w != args->end()
                                 ? std::get_if<double>(&it_w->second)
                                 : nullptr;
          const auto* h_pt = it_h != args->end()
                                 ? std::get_if<double>(&it_h->second)
                                 : nullptr;
          if (!job_id || !raw_path) {
            result->Error("INVALID_ARGS", "打印页面参数无效");
            return;
          }
          std::lock_guard<std::mutex> lock(g_print_mutex);
          auto it = g_print_jobs.find(*job_id);
          if (it == g_print_jobs.end()) {
            result->Error("JOB_MISSING", "打印任务已过期");
            return;
          }
          PrintPageFile pf;
          pf.raw_path = Utf8ToWide(*raw_path);
          if (w_pt) pf.width_pt = *w_pt;
          if (h_pt) pf.height_pt = *h_pt;
          it->second.pages.push_back(std::move(pf));
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "printAbort") {
          if (args) {
            auto it_id = args->find(flutter::EncodableValue("jobId"));
            if (it_id != args->end()) {
              if (const auto* job_id = std::get_if<std::string>(&it_id->second)) {
                std::lock_guard<std::mutex> lock(g_print_mutex);
                auto it = g_print_jobs.find(*job_id);
                if (it != g_print_jobs.end()) {
                  CleanupPrintJobFiles(it->second);
                  g_print_jobs.erase(it);
                }
              }
            }
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "printCommit") {
          if (!args) {
            result->Error("INVALID_ARGS", "参数无效");
            return;
          }
          auto it_id = args->find(flutter::EncodableValue("jobId"));
          if (it_id == args->end()) {
            result->Error("INVALID_ARGS", "缺少 jobId");
            return;
          }
          const auto* job_id = std::get_if<std::string>(&it_id->second);
          if (!job_id) {
            result->Error("INVALID_ARGS", "jobId 类型无效");
            return;
          }
          PrintJobState job;
          {
            std::lock_guard<std::mutex> lock(g_print_mutex);
            auto it = g_print_jobs.find(*job_id);
            if (it == g_print_jobs.end()) {
              result->Error("JOB_MISSING", "打印任务已过期");
              return;
            }
            job = std::move(it->second);
            g_print_jobs.erase(it);
          }

          if (job.pages.empty()) {
            CleanupPrintJobFiles(job);
            flutter::EncodableMap resp;
            resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
            resp[flutter::EncodableValue("canceled")] =
                flutter::EncodableValue(false);
            resp[flutter::EncodableValue("error")] =
                flutter::EncodableValue("没有可打印的页面");
            result->Success(flutter::EncodableValue(resp));
            return;
          }

          PRINTDLGW pd{};
          pd.lStructSize = sizeof(pd);
          pd.hwndOwner = hwnd;
          pd.Flags = PD_RETURNDC | PD_USEDEVMODECOPIESANDCOLLATE |
                     PD_NOSELECTION | PD_NOPAGENUMS;
          pd.nCopies = 1;
          pd.nMinPage = 1;
          pd.nMaxPage =
              static_cast<WORD>(std::min<size_t>(job.pages.size(), 0xFFFF));

          BOOL dlg_ok = FALSE;
          {
            ScopedModalFlag modal(dispatch_guard);
            dlg_ok = PrintDlgW(&pd);
          }
          if (!dlg_ok) {
            DWORD err = CommDlgExtendedError();
            CleanupPrintJobFiles(job);
            flutter::EncodableMap resp;
            resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
            resp[flutter::EncodableValue("canceled")] =
                flutter::EncodableValue(err == 0);
            if (err != 0) {
              resp[flutter::EncodableValue("error")] =
                  flutter::EncodableValue("无法打开系统打印对话框");
            }
            result->Success(flutter::EncodableValue(resp));
            return;
          }

          if (!pd.hDC) {
            if (pd.hDevMode) GlobalFree(pd.hDevMode);
            if (pd.hDevNames) GlobalFree(pd.hDevNames);
            CleanupPrintJobFiles(job);
            flutter::EncodableMap resp;
            resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
            resp[flutter::EncodableValue("canceled")] =
                flutter::EncodableValue(false);
            resp[flutter::EncodableValue("error")] =
                flutter::EncodableValue("无法获取打印机设备上下文");
            result->Success(flutter::EncodableValue(resp));
            return;
          }

          auto session = std::make_shared<PrintSession>();
          session->job_name = std::move(job.job_name);
          session->pages = std::move(job.pages);
          session->hdc = pd.hDC;
          session->h_devmode = pd.hDevMode;
          session->h_devnames = pd.hDevNames;
          session->copies = pd.nCopies;
          session->collate = (pd.Flags & PD_COLLATE) != 0;

          if (pd.hDevNames) {
            const auto* dn =
                static_cast<const DEVNAMES*>(GlobalLock(pd.hDevNames));
            if (dn) {
              const wchar_t* base = reinterpret_cast<const wchar_t*>(dn);
              session->printer_name = base + dn->wDeviceOffset;
              GlobalUnlock(pd.hDevNames);
            }
          }

          auto* raw_res = result.release();
          std::thread([hwnd, dispatch_guard, session, raw_res]() mutable {
            std::string err_msg;
            bool ok = SpoolPrintSession(session.get(), &err_msg);
            CleanupPrintSessionFiles(*session);

            auto payload = std::make_unique<NativeAsyncPayload>();
            payload->result.reset(raw_res);
            payload->ok = true;
            payload->response[flutter::EncodableValue("ok")] =
                flutter::EncodableValue(ok);
            payload->response[flutter::EncodableValue("canceled")] =
                flutter::EncodableValue(false);
            if (!err_msg.empty()) {
              payload->response[flutter::EncodableValue("error")] =
                  flutter::EncodableValue(err_msg);
            }
            DispatchAsyncResult(hwnd, dispatch_guard, std::move(payload));
          }).detach();
          return;
        }

        if (method == "pickSaveFile") {
          std::wstring title = L"保存文件";
          std::wstring def_name;
          std::wstring filter_label;
          std::wstring ext;
          if (args) {
            auto it_t = args->find(flutter::EncodableValue("dialogTitle"));
            if (it_t != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_t->second)) {
                title = Utf8ToWide(*s);
              }
            }
            auto it_n = args->find(flutter::EncodableValue("fileName"));
            if (it_n != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_n->second)) {
                def_name = SanitizeFileName(Utf8ToWide(*s));
              }
            }
            auto it_fl = args->find(flutter::EncodableValue("filterLabel"));
            if (it_fl != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_fl->second)) {
                filter_label = Utf8ToWide(*s);
              }
            }
            auto it_ex = args->find(flutter::EncodableValue("ext"));
            if (it_ex != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it_ex->second)) {
                ext = Utf8ToWide(*s);
                while (!ext.empty() && ext[0] == L'.') {
                  ext.erase(ext.begin());
                }
              }
            }
          }

          wchar_t path_buf[4096] = {0};
          if (!def_name.empty() && def_name.size() < 4090) {
            wcsncpy_s(path_buf, def_name.c_str(), _TRUNCATE);
          }

          std::wstring filter_str;
          if (!ext.empty()) {
            if (filter_label.empty()) {
              filter_label = ext + L" 文件 (*." + ext + L")";
            }
            filter_str.append(filter_label);
            filter_str.push_back(L'\0');
            filter_str.append(L"*.");
            filter_str.append(ext);
            filter_str.push_back(L'\0');
          }
          filter_str.append(L"所有文件 (*.*)");
          filter_str.push_back(L'\0');
          filter_str.append(L"*.*");
          filter_str.push_back(L'\0');
          filter_str.push_back(L'\0');

          OPENFILENAMEW ofn = {};
          ofn.lStructSize = sizeof(ofn);
          ofn.hwndOwner = hwnd;
          ofn.lpstrFilter = filter_str.c_str();
          ofn.lpstrFile = path_buf;
          ofn.nMaxFile = static_cast<DWORD>(std::size(path_buf));
          ofn.lpstrTitle = title.c_str();
          ofn.lpstrDefExt = ext.empty() ? nullptr : ext.c_str();
          ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

          BOOL dlg_res = FALSE;
          {
            ScopedModalFlag modal(dispatch_guard);
            dlg_res = GetSaveFileNameW(&ofn);
            if (!dlg_res && CommDlgExtendedError() == FNERR_INVALIDFILENAME) {
              path_buf[0] = L'\0';
              dlg_res = GetSaveFileNameW(&ofn);
            }
          }
          if (dlg_res == TRUE) {
            std::string chosen = WideToUtf8(
                path_buf, static_cast<UINT32>(wcslen(path_buf)));
            result->Success(flutter::EncodableValue(chosen));
          } else {
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
              result->Error("SAVE_DLG_ERROR", "打开保存对话框失败");
            } else {
              result->Success(flutter::EncodableValue());
            }
          }
          return;
        }

        result->NotImplemented();
      });

  static std::vector<std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>>
      s_channels;
  s_channels.push_back(std::move(channel));
}
