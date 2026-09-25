#ifndef RUNNER_OPEN_REQUESTS_H_
#define RUNNER_OPEN_REQUESTS_H_

#include <windows.h>

#include <string>
#include <vector>

// Files and links the app is asked to open: a media file or a .torrent from
// "Open with" or a double-click, or a magnet link from a browser. Windows
// starts a new copy of the app for each one; that copy hands the request to
// the copy already running and quits.
namespace open_requests {

// When another copy of the app is running, sends it |arguments| (possibly
// none, which just brings its window forward) and returns true: this copy
// should then exit. Returns false when this is the only copy, or when the
// other copy did not answer in time.
bool ForwardToRunningInstance(const std::vector<std::string>& arguments);

// Marks |window| as the window ForwardToRunningInstance sends requests to.
void MarkMainWindow(HWND window);

// Reads the arguments out of a WM_COPYDATA sent by ForwardToRunningInstance.
// Returns false for any other WM_COPYDATA.
bool DecodeForwarded(const COPYDATASTRUCT* data,
                     std::vector<std::string>* arguments);

// Registers this app for the current user as a program that opens the media
// files the player plays, .torrent files and magnet links, so Windows offers
// it under "Open with", in "How do you want to open this?" and in Default
// apps. It never replaces the app a user already chose. Runs on every start,
// so the entries follow the exe when its folder moves.
void RegisterAssociations();

}  // namespace open_requests

#endif  // RUNNER_OPEN_REQUESTS_H_
