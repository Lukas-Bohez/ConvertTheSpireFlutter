// <windows.h> and <unknwn.h> come before the C++/WinRT headers: only then can
// C++/WinRT hand out classic COM interfaces such as IInitializeWithWindow.
#include <windows.h>
#include <unknwn.h>
#include <appmodel.h>
#include <shobjidl_core.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Services.Store.h>

#include "store_purchases.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace store_purchases {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Foundation::IAsyncOperation;
using winrt::Windows::Services::Store::StoreAppLicense;
using winrt::Windows::Services::Store::StoreContext;
using winrt::Windows::Services::Store::StoreProduct;
using winrt::Windows::Services::Store::StoreProductQueryResult;
using winrt::Windows::Services::Store::StorePurchaseResult;
using winrt::Windows::Services::Store::StorePurchaseStatus;
using winrt::Windows::Services::Store::StoreRateAndReviewResult;
using winrt::Windows::Services::Store::StoreRateAndReviewStatus;

using Result = std::shared_ptr<flutter::MethodResult<EncodableValue>>;

constexpr wchar_t kDispatcherClass[] = L"ConvertTheSpireStoreDispatcher";
// Carries a std::function<void()>* to run on the platform thread.
constexpr UINT kRunTask = WM_APP + 0x53;

// The app's top-level window, which the Store's dialogs belong to.
HWND g_window = nullptr;
// A message-only window: the Store answers on other threads, and Flutter
// takes replies only on the platform thread, so they come back through it.
HWND g_dispatcher = nullptr;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;

LRESULT CALLBACK DispatcherProc(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  if (message == kRunTask) {
    std::unique_ptr<std::function<void()>> task(
        reinterpret_cast<std::function<void()>*>(lparam));
    (*task)();
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void RunOnPlatformThread(HWND dispatcher, std::function<void()> task) {
  auto* heap = new std::function<void()>(std::move(task));
  if (dispatcher == nullptr ||
      !PostMessageW(dispatcher, kRunTask, 0, reinterpret_cast<LPARAM>(heap))) {
    // The window is gone: the app is closing and nobody waits for this.
    delete heap;
  }
}

void Reply(HWND dispatcher, Result result, EncodableValue value) {
  RunOnPlatformThread(dispatcher, [result, value]() { result->Success(value); });
}

void ReplyError(HWND dispatcher, Result result, std::string message) {
  RunOnPlatformThread(dispatcher, [result, message]() {
    result->Error("store_error", message);
  });
}

std::string HResultText(int32_t code) {
  char text[16];
  std::snprintf(text, sizeof(text), "0x%08X", static_cast<uint32_t>(code));
  return text;
}

std::string Describe(winrt::hresult_error const& error) {
  std::string message = winrt::to_string(error.message());
  const std::string code = HResultText(error.code());
  return message.empty() ? code : message + " (" + code + ")";
}

bool IsPackaged() {
  UINT32 length = 0;
  return GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

std::string PackageFamilyName() {
  UINT32 length = 0;
  if (GetCurrentPackageFamilyName(&length, nullptr) !=
          ERROR_INSUFFICIENT_BUFFER ||
      length == 0) {
    return "";
  }
  std::wstring name(length, L'\0');
  if (GetCurrentPackageFamilyName(&length, name.data()) != ERROR_SUCCESS) {
    return "";
  }
  name.resize(length > 0 ? length - 1 : 0);  // |length| counts the NUL.
  return winrt::to_string(name);
}

// A desktop app has to tell the Store which window its dialogs belong to.
void AttachToWindow(StoreContext const& context) {
  if (g_window == nullptr) return;
  auto initialize = context.as<::IInitializeWithWindow>();
  winrt::check_hresult(initialize->Initialize(g_window));
}

const char* PurchaseStatusName(StorePurchaseStatus status) {
  switch (status) {
    case StorePurchaseStatus::Succeeded:
      return "succeeded";
    case StorePurchaseStatus::AlreadyPurchased:
      return "alreadyPurchased";
    case StorePurchaseStatus::NotPurchased:
      return "notPurchased";
    case StorePurchaseStatus::NetworkError:
      return "networkError";
    case StorePurchaseStatus::ServerError:
      return "serverError";
  }
  return "failed";
}

const char* ReviewStatusName(StoreRateAndReviewStatus status) {
  switch (status) {
    case StoreRateAndReviewStatus::Succeeded:
      return "succeeded";
    case StoreRateAndReviewStatus::CanceledByUser:
      return "canceled";
    case StoreRateAndReviewStatus::NetworkError:
      return "networkError";
    case StoreRateAndReviewStatus::Error:
      return "failed";
  }
  return "failed";
}

// The app's durable add-ons: [{storeId, token, title, price, owned}], token
// being the product ID given to the add-on in Partner Center. Asked on a
// thread of its own: the answers are waited for there.
void GetAddOns(Result result) {
  HWND dispatcher = g_dispatcher;
  std::thread([result, dispatcher]() {
    bool apartment = false;
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      apartment = true;
    } catch (winrt::hresult_error const&) {
      // Already set up on this thread; carry on.
    }
    try {
      StoreContext context = StoreContext::GetDefault();
      std::vector<winrt::hstring> kinds{winrt::hstring(L"Durable")};
      StoreProductQueryResult query =
          context
              .GetAssociatedStoreProductsAsync(
                  winrt::single_threaded_vector<winrt::hstring>(
                      std::move(kinds)))
              .get();
      const auto products = query.Products();
      if (products.Size() == 0 && query.ExtendedError() < 0) {
        throw winrt::hresult_error(query.ExtendedError());
      }

      // What the user owns: the license is kept on the PC, so this also
      // answers offline.
      std::vector<std::wstring> owned_tokens;
      try {
        StoreAppLicense license = context.GetAppLicenseAsync().get();
        for (auto const& entry : license.AddOnLicenses()) {
          if (entry.Value().IsActive()) {
            owned_tokens.emplace_back(entry.Value().InAppOfferToken());
          }
        }
      } catch (winrt::hresult_error const&) {
        // IsInUserCollection below still says.
      }

      EncodableList list;
      for (auto const& entry : products) {
        StoreProduct product = entry.Value();
        const std::wstring token(product.InAppOfferToken());
        bool owned = product.IsInUserCollection();
        for (const auto& owned_token : owned_tokens) {
          if (!token.empty() && owned_token == token) owned = true;
        }
        list.push_back(EncodableValue(EncodableMap{
            {EncodableValue("storeId"),
             EncodableValue(winrt::to_string(product.StoreId()))},
            {EncodableValue("token"), EncodableValue(winrt::to_string(token))},
            {EncodableValue("title"),
             EncodableValue(winrt::to_string(product.Title()))},
            {EncodableValue("price"),
             EncodableValue(
                 winrt::to_string(product.Price().FormattedPrice()))},
            {EncodableValue("owned"), EncodableValue(owned)},
        }));
      }
      Reply(dispatcher, result, EncodableValue(list));
    } catch (winrt::hresult_error const& error) {
      ReplyError(dispatcher, result, Describe(error));
    } catch (...) {
      ReplyError(dispatcher, result, "The Store could not be asked.");
    }
    if (apartment) winrt::uninit_apartment();
  }).detach();
}

// Shows the Store's purchase dialog for the add-on |store_id|. Started here
// on the platform thread, which owns the window; the answer comes later.
void Purchase(const std::string& store_id, Result result) {
  HWND dispatcher = g_dispatcher;
  try {
    StoreContext context = StoreContext::GetDefault();
    AttachToWindow(context);
    auto operation = context.RequestPurchaseAsync(winrt::to_hstring(store_id));
    operation.Completed(
        [result, dispatcher, context](
            IAsyncOperation<StorePurchaseResult> const& done,
            AsyncStatus status) {
          try {
            if (status != AsyncStatus::Completed) {
              done.GetResults();  // Throws why it did not complete.
              ReplyError(dispatcher, result, "The purchase did not complete.");
              return;
            }
            StorePurchaseResult purchase = done.GetResults();
            EncodableMap answer{
                {EncodableValue("status"),
                 EncodableValue(PurchaseStatusName(purchase.Status()))},
            };
            if (purchase.ExtendedError() < 0) {
              answer[EncodableValue("error")] =
                  EncodableValue(HResultText(purchase.ExtendedError()));
            }
            Reply(dispatcher, result, EncodableValue(answer));
          } catch (winrt::hresult_error const& error) {
            ReplyError(dispatcher, result, Describe(error));
          } catch (...) {
            ReplyError(dispatcher, result, "The purchase failed.");
          }
        });
  } catch (winrt::hresult_error const& error) {
    result->Error("store_error", Describe(error));
  }
}

// The Store's own "rate and review" dialog (Windows 10 1809 and later).
void RateAndReview(Result result) {
  HWND dispatcher = g_dispatcher;
  try {
    StoreContext context = StoreContext::GetDefault();
    AttachToWindow(context);
    auto operation = context.RequestRateAndReviewAppAsync();
    operation.Completed(
        [result, dispatcher, context](
            IAsyncOperation<StoreRateAndReviewResult> const& done,
            AsyncStatus status) {
          try {
            if (status != AsyncStatus::Completed) {
              done.GetResults();
              ReplyError(dispatcher, result, "The rating did not complete.");
              return;
            }
            Reply(dispatcher, result,
                  EncodableValue(ReviewStatusName(done.GetResults().Status())));
          } catch (winrt::hresult_error const& error) {
            ReplyError(dispatcher, result, Describe(error));
          } catch (...) {
            ReplyError(dispatcher, result, "The rating dialog failed.");
          }
        });
  } catch (winrt::hresult_error const& error) {
    result->Error("store_error", Describe(error));
  }
}

void HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> unique_result) {
  const std::string& method = call.method_name();
  if (method == "isAvailable") {
    unique_result->Success(EncodableValue(IsPackaged()));
    return;
  }
  if (method == "packageFamilyName") {
    const std::string name = PackageFamilyName();
    unique_result->Success(name.empty() ? EncodableValue()
                                        : EncodableValue(name));
    return;
  }
  if (method != "getAddOns" && method != "purchase" &&
      method != "rateAndReview") {
    unique_result->NotImplemented();
    return;
  }
  if (!IsPackaged()) {
    unique_result->Error("not_packaged",
                         "Only the Microsoft Store version has the Store.");
    return;
  }
  Result result(std::move(unique_result));
  if (method == "getAddOns") {
    GetAddOns(result);
  } else if (method == "purchase") {
    std::string store_id;
    if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
      const auto found = args->find(EncodableValue("storeId"));
      if (found != args->end()) {
        if (const auto* id = std::get_if<std::string>(&found->second)) {
          store_id = *id;
        }
      }
    }
    if (store_id.empty()) {
      result->Error("bad_args", "storeId is missing.");
      return;
    }
    Purchase(store_id, result);
  } else {
    RateAndReview(result);
  }
}

}  // namespace

void Register(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = DispatcherProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kDispatcherClass;
  RegisterClassW(&window_class);  // Fails harmlessly if already registered.
  g_dispatcher = CreateWindowExW(0, kDispatcherClass, L"", 0, 0, 0, 0, 0,
                                 HWND_MESSAGE, nullptr, instance, nullptr);

  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "convert_the_spire/store",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleCall(call, std::move(result));
      });
}

void Unregister() {
  g_channel = nullptr;
  if (g_dispatcher != nullptr) {
    DestroyWindow(g_dispatcher);
    g_dispatcher = nullptr;
  }
  g_window = nullptr;
}

}  // namespace store_purchases
