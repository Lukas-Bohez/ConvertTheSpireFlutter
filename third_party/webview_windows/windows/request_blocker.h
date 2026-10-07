#pragma once

#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

// The in-app browser's ad blocker, matched here so that no request waits on
// Dart. The same rules and the same matching as FilterSet.blocks in the
// app's lib/src/browser/adblock/filter_list.dart: a change there comes here
// too.

// A request rule scoped to a path on its host, to some pages, or both.
struct UrlRule {
  // What follows the host in the URL: `*` any run of characters, `^` a
  // separator or the end, a final `|` the end. Empty for the whole host.
  std::string pattern;
  // Applies on pages of these sites only (all when empty)...
  std::vector<std::string> on_pages;
  // ...and not on pages of these.
  std::vector<std::string> not_on_pages;

  bool Matches(std::string_view rest, std::string_view page_host) const;
};

struct RequestBlockRules {
  // Which rules these are, so each webview needs them sent only once.
  std::string id;
  std::unordered_set<std::string> blocked_hosts;
  std::unordered_set<std::string> allowed_hosts;
  std::unordered_map<std::string, std::vector<UrlRule>> rules;
  std::unordered_map<std::string, std::vector<UrlRule>> exceptions;
  // Sites on whose pages nothing is blocked.
  std::unordered_set<std::string> allowed_pages;
  std::vector<std::string> exempt_pages;

  // Whether [url], requested by the page at [page_url], is blocked.
  bool Blocks(std::string_view url, std::string_view page_url) const;

  // The rules every webview shares; null until some are sent.
  static std::shared_ptr<const RequestBlockRules>& Shared();
};

// The lowercase host of an http(s) or ws(s) [url] and what follows it (a
// port skipped); false for any other URL.
bool SplitUrl(std::string_view url, std::string* host, std::string* rest);

// Whether [host] is [domain] or under it; `example.*` is example under any
// top-level domain.
bool IsOnDomain(std::string_view host, std::string_view domain);

// Whether the filter [pattern] matches [text] from its start.
bool PatternMatches(std::string_view pattern, std::string_view text);

// [host] and each parent domain, the top-level domain left out.
std::vector<std::string> HostAndParents(const std::string& host);
