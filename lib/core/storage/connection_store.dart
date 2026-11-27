// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/connection_profile.dart';

class ConnectionStore {
  ConnectionStore(this.preferences, this.secureStorage);

  static const profileKey = 'connection.profile';
  static const _credentialsPrefix = 'connection.credentials.';
  static const _pinPrefix = 'connection.hostKey.';
  final SharedPreferencesAsync preferences;
  final FlutterSecureStorage secureStorage;

  Future<ConnectionProfile?> readProfile() async {
    final raw = await preferences.getString(profileKey);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return ConnectionProfile.fromJson(data['profile'] as Map<String, dynamic>);
  }

  Future<SshCredentials?> readCredentials() async {
    final raw = await preferences.getString(profileKey);
    if (raw == null) return null;
    final ref =
        (jsonDecode(raw) as Map<String, dynamic>)['credentialsRef'] as String;
    final secret = await secureStorage.read(key: '$_credentialsPrefix$ref');
    if (secret == null) return null;
    final data = jsonDecode(secret) as Map<String, dynamic>;
    return SshCredentials(
      data['secret'] as String,
      passphrase: data['passphrase'] as String?,
    );
  }

  Future<void> save(
    ConnectionProfile profile,
    SshCredentials credentials,
  ) async {
    final raw = await preferences.getString(profileKey);
    final oldRef = raw == null
        ? 'b'
        : (jsonDecode(raw) as Map<String, dynamic>)['credentialsRef'] as String;
    final newRef = oldRef == 'a' ? 'b' : 'a';

    // Write the inactive slot first so a failed metadata write keeps the old login usable.
    await secureStorage.write(
      key: '$_credentialsPrefix$newRef',
      value: jsonEncode({
        'secret': credentials.secret,
        'passphrase': credentials.passphrase,
      }),
    );
    try {
      await preferences.setString(
        profileKey,
        jsonEncode({'profile': profile.toJson(), 'credentialsRef': newRef}),
      );
    } catch (_) {
      await secureStorage.delete(key: '$_credentialsPrefix$newRef');
      rethrow;
    }
    // The new profile is committed. A later save will overwrite a stale slot.
    try {
      await secureStorage.delete(key: '$_credentialsPrefix$oldRef');
    } on Exception {
      // Erasing saved data also deletes both slots.
    }
  }

  Future<void> deleteProfile() async {
    await preferences.remove(profileKey);
    await secureStorage.delete(key: '${_credentialsPrefix}a');
    await secureStorage.delete(key: '${_credentialsPrefix}b');
  }

  Future<String?> readPin(String endpoint) =>
      secureStorage.read(key: '$_pinPrefix$endpoint');

  Future<void> writePin(String endpoint, String pin) =>
      secureStorage.write(key: '$_pinPrefix$endpoint', value: pin);

  Future<void> removePin(String endpoint) =>
      secureStorage.delete(key: '$_pinPrefix$endpoint');

  Future<int?> preferredPort(ConnectionProfile profile) async {
    final raw = await preferences.getString('webui.origin');
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return data['identity'] == profile.dashboardIdentity
        ? data['port'] as int
        : null;
  }

  Future<void> savePort(ConnectionProfile profile, int port) =>
      preferences.setString(
        'webui.origin',
        jsonEncode({'identity': profile.dashboardIdentity, 'port': port}),
      );

  Future<void> forgetPort() => preferences.remove('webui.origin');
}
