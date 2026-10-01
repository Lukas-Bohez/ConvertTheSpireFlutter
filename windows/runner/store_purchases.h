#ifndef RUNNER_STORE_PURCHASES_H_
#define RUNNER_STORE_PURCHASES_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// The Microsoft Store, for the Store version of the app (the MSIX package):
// Dart's "convert_the_spire/store" channel. It lists the app's add-ons with
// their price and whether this user owns them, buys one, and opens the
// Store's rating dialog. Outside a Store package it answers that the Store
// is not available.
namespace store_purchases {

// |window| is the app's top-level window: the Store's dialogs belong to it.
void Register(flutter::BinaryMessenger* messenger, HWND window);

// Stops answering; called when the window goes away.
void Unregister();

}  // namespace store_purchases

#endif  // RUNNER_STORE_PURCHASES_H_
