import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';

class SearchResult {
  final String torrentId;
  final String name;
  final int? size;
  final int? seeders;
  final int? leechers;
  final int? ageYears;
  final String magnetLink;
  final String responderId;
  final String source;

  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) {
      try {
        return utf8.decode(value);
      } catch (e) {
        debugPrint('SearchResult _asString decode error: $e');
        return value.toString();
      }
    }
    try {
      return value.toString();
    } catch (e) {
      debugPrint('SearchResult _asString toString error: $e');
      return '';
    }
  }

  SearchResult({
    required this.torrentId,
    required this.name,
    required this.magnetLink,
    required this.responderId,
    required this.source,
    this.size,
    this.seeders,
    this.leechers,
    this.ageYears,
  });

  factory SearchResult.fromMap(Map<String, dynamic> map) => SearchResult(
        torrentId: _asString(map['torrentId']),
        name: _asString(map['name']),
        magnetLink: _asString(map['magnetLink']),
        responderId: _asString(map['responderId']),
        source: _asString(map['source']).isEmpty
            ? _asString(map['responderId'])
            : _asString(map['source']),
        size: map['size'] is int
            ? map['size'] as int
            : int.tryParse(_asString(map['size'])),
        seeders: map['seeders'] is int
            ? map['seeders'] as int
            : int.tryParse(_asString(map['seeders'])),
        leechers: map['leechers'] is int
            ? map['leechers'] as int
            : int.tryParse(_asString(map['leechers'])),
        ageYears: map['ageYears'] is int
            ? map['ageYears'] as int
            : int.tryParse(_asString(map['ageYears'])),
      );

  Map<String, dynamic> toMap() {
    return {
      'torrentId': torrentId,
      'name': name,
      'size': size,
      'seeders': seeders,
      'leechers': leechers,
      'ageYears': ageYears,
      'magnetLink': magnetLink,
      'responderId': responderId,
      'source': source,
    };
  }
}

class SearchService {
  SearchService._();

  static final SearchService instance = SearchService._();

  final _resultsController = StreamController<List<SearchResult>>.broadcast();

  Stream<List<SearchResult>> get resultsStream => _resultsController.stream;

  final List<SearchResult> _results = [];
  Future<void> broadcastSearch(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return;

    _results.clear();
    final all = await TorrentService.instance.allTorrents();
    for (final torrent in all) {
      if (!torrent.name.toLowerCase().contains(normalizedQuery)) {
        continue;
      }
      _results.add(
        SearchResult(
          torrentId: torrent.id,
          name: torrent.name,
          magnetLink: torrent.magnetLink ?? '',
          responderId: 'local',
          source: 'local',
          size: torrent.totalSize,
          seeders: torrent.seeders,
          leechers: torrent.leechers,
        ),
      );
    }
    _resultsController.add(List.unmodifiable(_results));
  }

  void dispose() {
    _resultsController.close();
  }
}
