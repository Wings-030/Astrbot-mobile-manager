// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/connection_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AstrBotMobileApp(
      store: ConnectionStore(
        SharedPreferencesAsync(),
        const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
          ),
        ),
      ),
    ),
  );
}
