#include "request_blocker.h"

#include <algorithm>

namespace {

char Lower(char c) { return (c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c; }

// Anything but a letter, a digit or one of `_-.%`.
bool IsSeparator(char c) {
  return !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' ||
           c == '%');
}

bool OnAnyOf(const std::string& host,
             const std::unordered_set<std::string>& sites) {
  for (const auto& h : HostAndParents(host)) {
    if (sites.count(h)) return true;
  }
  return false;
}

}  // namespace

bool SplitUrl(std::string_view url, std::string* host, std::string* rest) {
  const auto scheme_end = url.find("://");
  if (scheme_end == std::string_view::npos || scheme_end == 0) return false;
  std::string scheme(url.substr(0, scheme_end));
  std::transform(scheme.begin(), scheme.end(), scheme.begin(), Lower);
  if (scheme != "http" && scheme != "https" && scheme != "ws" &&
      scheme != "wss") {
    return false;
  }
  size_t start = scheme_end + 3;
  size_t end = start;
  while (end < url.size()) {
    const char c = url[end];
    if (c == '/' || c == '?' || c == '#' || c == ':') break;
    if (c == '@') start = end + 1;  // user@host
    end++;
  }
  if (end == start) return false;
  host->assign(url.substr(start, end - start));
  std::transform(host->begin(), host->end(), host->begin(), Lower);
  if (end < url.size() && url[end] == ':') {
    end++;
    while (end < url.size() && url[end] >= '0' && url[end] <= '9') end++;
  }
  rest->assign(url.substr(end));
  return true;
}

bool IsOnDomain(std::string_view host, std::string_view domain) {
  if (host.empty()) return false;
  if (domain.size() >= 2 && domain.substr(domain.size() - 2) == ".*") {
    const auto base = domain.substr(0, domain.size() - 1);  // "example."
    if (host.substr(0, base.size()) == base) return true;
    std::string dotted = ".";
    dotted.append(base);
    return host.find(dotted) != std::string_view::npos;
  }
  if (host == domain) return true;
  return host.size() > domain.size() &&
         host.substr(host.size() - domain.size()) == domain &&
         host[host.size() - domain.size() - 1] == '.';
}

bool PatternMatches(std::string_view pattern, std::string_view text) {
  std::string_view p = pattern;
  const bool end_anchor = !p.empty() && p.back() == '|';
  if (end_anchor) p.remove_suffix(1);
  size_t pi = 0, ti = 0, mark = 0;
  bool starred = false;
  size_t star = 0;
  while (true) {
    if (pi == p.size()) {
      if (!end_anchor || ti == text.size()) return true;
    } else {
      const char c = p[pi];
      if (c == '*') {
        star = pi++;
        starred = true;
        mark = ti;
        continue;
      }
      if (ti < text.size() &&
          (c == Lower(text[ti]) || (c == '^' && IsSeparator(text[ti])))) {
        pi++;
        ti++;
        continue;
      }
      if (ti == text.size() && c == '^') {
        // `^` also matches the end.
        pi++;
        continue;
      }
    }
    if (!starred || mark >= text.size()) return false;
    pi = star + 1;
    ti = ++mark;
  }
}

std::vector<std::string> HostAndParents(const std::string& host) {
  std::vector<std::string> out{host};
  auto i = host.find('.');
  while (i != std::string::npos) {
    std::string parent = host.substr(i + 1);
    if (parent.find('.') == std::string::npos) break;
    out.push_back(std::move(parent));
    i = host.find('.', i + 1);
  }
  return out;
}

bool UrlRule::Matches(std::string_view rest, std::string_view page_host) const {
  if (!on_pages.empty() &&
      std::none_of(on_pages.begin(), on_pages.end(), [&](const auto& d) {
        return IsOnDomain(page_host, d);
      })) {
    return false;
  }
  if (std::any_of(not_on_pages.begin(), not_on_pages.end(),
                  [&](const auto& d) { return IsOnDomain(page_host, d); })) {
    return false;
  }
  return pattern.empty() || PatternMatches(pattern, rest);
}

bool RequestBlockRules::Blocks(std::string_view url,
                               std::string_view page_url) const {
  std::string host, rest;
  if (!SplitUrl(url, &host, &rest)) return false;
  std::string page_host, page_rest;
  if (!SplitUrl(page_url, &page_host, &page_rest)) page_host.clear();
  if (!page_host.empty()) {
    for (const auto& d : exempt_pages) {
      if (IsOnDomain(page_host, d)) return false;
    }
    if (OnAnyOf(page_host, allowed_pages)) return false;
  }
  const auto candidates = HostAndParents(host);
  for (const auto& h : candidates) {
    if (allowed_hosts.count(h)) return false;
    const auto it = exceptions.find(h);
    if (it != exceptions.end()) {
      for (const auto& rule : it->second) {
        if (rule.Matches(rest, page_host)) return false;
      }
    }
  }
  for (const auto& h : candidates) {
    if (blocked_hosts.count(h)) return true;
    const auto it = rules.find(h);
    if (it != rules.end()) {
      for (const auto& rule : it->second) {
        if (rule.Matches(rest, page_host)) return true;
      }
    }
  }
  return false;
}

std::shared_ptr<const RequestBlockRules>& RequestBlockRules::Shared() {
  static std::shared_ptr<const RequestBlockRules> shared;
  return shared;
}
