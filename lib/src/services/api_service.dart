import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;

  const ApiService({required this.baseUrl});

  Future<Map<String, dynamic>> getJson(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
