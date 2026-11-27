// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:astrbot_mobile_manager/core/storage/connection_store.dart';
import 'package:astrbot_mobile_manager/models/connection_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_store.dart';

void main() {
  const profile = ConnectionProfile(host: 'example.org', username: 'alice');

  test(
    'Profile preferences contain no secret and both slots are erased',
    () async {
      final store = testStore();
      await store.save(profile, const SshCredentials('test-only-password'));
      final raw = await store.preferences.getString(ConnectionStore.profileKey);
      expect(raw, contains('example.org'));
      expect(raw, isNot(contains('test-only-password')));
      expect((await store.readCredentials())?.secret, 'test-only-password');

      const keyProfile = ConnectionProfile(
        host: 'example.org',
        username: 'alice',
        authentication: Authentication.privateKey,
      );
      await store.save(
        keyProfile,
        const SshCredentials('test-key', passphrase: 'test-passphrase'),
      );
      expect(
        (await store.readProfile())?.authentication,
        Authentication.privateKey,
      );
      expect((await store.readCredentials())?.passphrase, 'test-passphrase');
      expect(
        (await store.secureStorage.readAll()).values.single,
        contains('test-key'),
      );
      await store.deleteProfile();
      expect(await store.readProfile(), isNull);
      expect(await store.readCredentials(), isNull);
      expect(await store.secureStorage.readAll(), isEmpty);
    },
  );

  test('Browser port is specific to the complete dashboard identity', () async {
    final store = testStore();
    await store.savePort(profile, 32000);
    expect(await store.preferredPort(profile), 32000);
    expect(
      await store.preferredPort(
        const ConnectionProfile(host: 'example.org', username: 'bob'),
      ),
      isNull,
    );
    await store.forgetPort();
    expect(await store.preferredPort(profile), isNull);
  });
}
