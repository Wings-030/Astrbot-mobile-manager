// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:astrbot_mobile_manager/core/storage/connection_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

ConnectionStore testStore() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  FlutterSecureStorage.setMockInitialValues({});
  return ConnectionStore(
    SharedPreferencesAsync(),
    const FlutterSecureStorage(),
  );
}
