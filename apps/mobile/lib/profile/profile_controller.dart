import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'user_profile.dart';

final profileController = ProfileController();

class ProfileController extends ValueNotifier<UserProfile> {
  ProfileController() : super(const UserProfile());

  bool _loaded = false;
  String _accountId = 'signed-out';

  Future<void> load({String? userId}) async {
    final accountId = userId ?? 'signed-out';
    if (_accountId != accountId) {
      _loaded = false;
      value = const UserProfile();
      _accountId = accountId;
    }
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

  void clearSession() {
    _loaded = false;
    _accountId = 'signed-out';
    value = const UserProfile();
  }

  Future<File> _profileFile() async {
    final directory = await getApplicationSupportDirectory();
    final scopedName = 'vanam_profile_$_accountId.json';
    return File('${directory.path}${Platform.pathSeparator}$scopedName');
  }
}
