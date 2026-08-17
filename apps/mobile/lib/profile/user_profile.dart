class UserProfile {
  const UserProfile({this.name = '', this.language = 'English'});

  final String name;
  final String language;

  bool get hasName => name.trim().isNotEmpty;
  String get displayName => hasName ? name.trim() : 'Your Profile';
  String get feedbackName => hasName ? name.trim() : '';

  UserProfile copyWith({String? name, String? language}) {
    return UserProfile(
      name: name ?? this.name,
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'language': language};
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: (json['name'] as String?) ?? '',
      language: (json['language'] as String?) ?? 'English',
    );
  }
}
