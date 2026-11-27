// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:astrbot_mobile_manager/app.dart';
import 'package:astrbot_mobile_manager/models/connection_profile.dart';
import 'package:astrbot_mobile_manager/screens/connection/connection_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_store.dart';

void main() {
  testWidgets('First launch displays the connection form and settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(450, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AstrBotMobileApp(store: testStore()));
    await tester.pumpAndSettle();
    expect(find.text('连接服务器'), findsOneWidget);
    expect(find.text('127.0.0.1'), findsOneWidget);
    expect(find.text('6185'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsOneWidget);
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.textContaining('非官方社区客户端'), findsOneWidget);
    expect(find.text('AstrBot 项目声明'), findsOneWidget);
  });

  testWidgets('Connection form validates fields and submits one profile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(450, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ConnectionProfile? savedProfile;
    SshCredentials? savedCredentials;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionScreen(
            onSave: (profile, credentials) async {
              savedProfile = profile;
              savedCredentials = credentials;
            },
          ),
        ),
      ),
    );
    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(field('SSH 主机'), 'https://example.org');
    await tester.enterText(field('SSH 端口'), '65536');
    final submit = find.text('保存并连接');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(savedProfile, isNull);
    expect(find.text('请输入 IPv4、IPv6 或主机名'), findsOneWidget);
    await tester.enterText(field('SSH 主机'), 'example.org');
    await tester.enterText(field('SSH 端口'), '22');
    await tester.enterText(field('SSH 用户名'), 'alice');
    await tester.enterText(field('SSH 密码'), 'test-only-password');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(savedProfile?.dashboardHost, '127.0.0.1');
    expect(savedProfile?.dashboardPort, 6185);
    expect(savedProfile?.username, 'alice');
    expect(savedCredentials?.secret, 'test-only-password');
  });
}
