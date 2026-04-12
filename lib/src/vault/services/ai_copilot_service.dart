import 'dart:convert';

import 'package:dio/dio.dart';

class AiChatChunk {
  final String content;
  final bool done;

  const AiChatChunk({required this.content, required this.done});
}

class AiCopilotService {
  AiCopilotService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? 'http://localhost:11434',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 120),
            ),
          );

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  void setBaseUrl(String value) {
    _dio.options.baseUrl = value.trim();
  }

  Future<bool> checkVersion() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/tags');
      final models = response.data?['models'];
      return response.statusCode == 200 && models is List;
    } on DioException {
      return false;
    }
  }

  Future<List<String>> fetchModels() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/tags');
    final raw = response.data?['models'];
    if (raw is! List) return const <String>[];
    return raw
        .whereType<Map>()
        .map((entry) => (entry['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<bool> modelExists(String modelName) async {
    try {
      final models = await fetchModels();
      return models.contains(modelName);
    } catch (_) {
      return false;
    }
  }

  Stream<Map<String, dynamic>> pullModelStream(String modelName) async* {
    final response = await _dio.post<ResponseBody>(
      '/api/pull',
      data: {'model': modelName, 'stream': true},
      options: Options(responseType: ResponseType.stream),
    );

    final stream = utf8.decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (line.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(line);
        if (parsed is Map<String, dynamic>) {
          yield parsed;
        }
      } catch (_) {
        // ignore malformed JSON chunks
      }
    }
  }

  Future<Stream<AiChatChunk>> chatChunkStream({
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    final response = await _dio.post<ResponseBody>(
      '/api/chat',
      data: {'model': model, 'messages': messages, 'stream': true},
      options: Options(responseType: ResponseType.stream),
    );

    return utf8.decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final map = jsonDecode(line);
          if (map is Map<String, dynamic>) {
            final done = map['done'] == true;
            final message = map['message'] as Map<String, dynamic>?;
            final content = (message?['content'] as String?) ?? '';
            return AiChatChunk(content: content, done: done);
          }
          return const AiChatChunk(content: '', done: false);
        });
  }

  Future<Stream<String>> chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    final response = await _dio.post<ResponseBody>(
      '/api/chat',
      data: {'model': model, 'messages': messages, 'stream': true},
      options: Options(responseType: ResponseType.stream),
    );

    return utf8.decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final map = jsonDecode(line);
          if (map is Map<String, dynamic>) {
            final message = map['message'] as Map<String, dynamic>?;
            return (message?['content'] as String?) ?? '';
          }
          return '';
        })
        .where((content) => content.isNotEmpty);
  }

  Future<bool> verifyTorrentIntent({
    required String model,
    required String userMessage,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final response = await _dio
        .post<Map<String, dynamic>>(
          '/api/chat',
          data: {
            'model': model,
            'stream': false,
            'messages': [
              {
                'role': 'system',
                'content':
                    'Is this message a torrent app command? Reply only YES or NO.',
              },
              {'role': 'user', 'content': userMessage},
            ],
          },
        )
        .timeout(timeout);

    final content = ((response.data?['message'] as Map?)?['content'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    return content.startsWith('YES');
  }
}
