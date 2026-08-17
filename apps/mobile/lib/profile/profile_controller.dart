import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'user_profile.dart';

final profileController = ProfileController();

class ProfileController extends ValueNotifier<UserProfile> {
  ProfileController() : super(const UserProfile());

  static const _fileName = 'vanam_profile.json';

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final file = await _profileFile();
      if (!await file.exists()) return;

      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        value = UserProfile.fromJson(json);
      }
    } catch (_) {
      value = const UserProfile();
    }
  }

  Future<void> save(UserProfile profile) async {
    value = profile;
    final file = await _profileFile();
    await file.writeAsString(jsonEncode(profile.toJson()));
  }

  Future<File> _profileFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
