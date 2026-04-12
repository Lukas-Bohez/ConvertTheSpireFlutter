class Contact {
  final String id;
  final String username;
  final String publicKey;
  final String avatarSeed;
  final String displayName;
  final String importedFrom;

  Contact({
    required this.id,
    required this.username,
    required this.publicKey,
    required this.avatarSeed,
    required this.displayName,
    required this.importedFrom,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'public_key': publicKey,
      'avatar_seed': avatarSeed,
      'display_name': displayName,
      'imported_from': importedFrom,
    };
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      publicKey: json['public_key'] as String? ?? '',
      avatarSeed: json['avatar_seed'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      importedFrom: json['imported_from'] as String? ?? 'unknown',
    );
  }
}
