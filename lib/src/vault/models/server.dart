import 'dart:convert';

import 'package:convert_the_spire_reborn/src/utils/safe_json.dart';

class ServerModel {
  final String id;
  final String name;
  final String description;
  final String icon;
  final List<ChannelModel> channels;

  ServerModel({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = '🛡️',
    required this.channels,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'channels': jsonEncode(channels.map((c) => c.toMap()).toList()),
    };
  }

  factory ServerModel.fromMap(Map<String, dynamic> map) {
    final channelJson = map['channels'] as String? ?? '[]';
    final channelList = (safeJsonDecode<List<dynamic>>(channelJson) ?? const [])
        .map((e) => ChannelModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    return ServerModel(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      icon: map['icon'] as String? ?? '🛡️',
      channels: channelList,
    );
  }
}

class ChannelModel {
  final String id;
  final String name;
  final bool isVoice;

  ChannelModel({required this.id, required this.name, this.isVoice = false});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'isVoice': isVoice ? 1 : 0};
  }

  factory ChannelModel.fromMap(Map<String, dynamic> map) {
    return ChannelModel(
      id: map['id'] as String,
      name: map['name'] as String,
      isVoice: (map['isVoice'] as int? ?? 0) == 1,
    );
  }
}

extension ServerModelCopy on ServerModel {
  ServerModel copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    List<ChannelModel>? channels,
  }) {
    return ServerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      channels: channels ?? this.channels,
    );
  }
}
