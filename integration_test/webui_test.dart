// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:astrbot_mobile_manager/screens/webui/webui_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Platform secure storage can write, read and erase test credentials',
    (tester) async {
      const storage = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );
      const key = 'integration.temporary';
      addTearDown(() => storage.delete(key: key));
      await storage.write(key: key, value: 'fixture-only');
      expect(await storage.read(key: key), 'fixture-only');
      await storage.delete(key: key);
      expect(await storage.read(key: key), isNull);
    },
  );

  testWidgets(
    'Native WebView keeps its origin and session through a reconnect',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final origin = Uri.parse('http://127.0.0.1:${server.port}/');
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
        <!doctype html>
        <form><input type="file"></form>
        <script>
          localStorage.setItem('fixture', 'present');
          document.title = 'AstrBot fixture';
        </script>
        ''');
        await request.response.close();
      });

      final refresh = ValueNotifier(0);
      addTearDown(refresh.dispose);
      Widget view(bool online) => MaterialApp(
        home: Scaffold(
          body: WebUiScreen(origin: origin, online: online, refresh: refresh),
        ),
      );
      await tester.pumpWidget(view(true));
      final browser = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (await browser.getTitle() != 'AstrBot fixture') {
        if (DateTime.now().isAfter(deadline)) {
          fail('The native WebView did not load the fixture');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      }
      await browser.runJavaScript("history.pushState({}, '', '/settings');");
      await tester.pumpWidget(view(false));
      await tester.pumpWidget(view(true));
      final reconnected = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      expect(reconnected, same(browser));
      final currentUrl = await browser.currentUrl();
      expect(Uri.parse(currentUrl!).path, '/settings');
      expect(
        (await browser.runJavaScriptReturningResult(
          "localStorage.getItem('fixture')",
        )).toString(),
        contains('present'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
