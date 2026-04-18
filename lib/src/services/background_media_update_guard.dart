class BackgroundMediaUpdateGuard {
  int _token = 0;

  int nextToken() {
    _token += 1;
    return _token;
  }

  bool isCurrent(int token) => token == _token;

  int get currentToken => _token;
}
