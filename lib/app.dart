// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'core/ssh/ssh_connector.dart';
import 'core/storage/connection_store.dart';
import 'models/connection_profile.dart';
import 'screens/connection/connection_screen.dart';
import 'screens/connection/connection_status.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/webui/webui_screen.dart';
import 'services/connection_controller.dart';

class AstrBotMobileApp extends StatefulWidget {
  const AstrBotMobileApp({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<AstrBotMobileApp> createState() => _AstrBotMobileAppState();
}

class _AstrBotMobileAppState extends State<AstrBotMobileApp> {
  ThemeMode _theme = ThemeMode.system;

  void _setTheme(ThemeMode theme) {
    setState(() => _theme = theme);
    unawaited(
      widget.store.preferences
          .setString('ui.theme', theme.name)
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreTheme());
  }

  Future<void> _restoreTheme() async {
    try {
      final saved = await widget.store.preferences.getString('ui.theme');
      if (saved != null && mounted) {
        setState(() => _theme = ThemeMode.values.byName(saved));
      }
    } catch (_) {
      // Use the system theme if the preference is unavailable.
    }
  }

  ThemeData _themeData(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff356769),
      brightness: brightness,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AstrBot Mobile Manager',
    theme: _themeData(Brightness.light),
    darkTheme: _themeData(Brightness.dark),
    themeMode: _theme,
    home: _ManagerHome(store: widget.store, theme: _theme, onTheme: _setTheme),
  );
}

class _ManagerHome extends StatefulWidget {
  const _ManagerHome({
    required this.store,
    required this.theme,
    required this.onTheme,
  });

  final ConnectionStore store;
  final ThemeMode theme;
  final ValueChanged<ThemeMode> onTheme;

  @override
  State<_ManagerHome> createState() => _ManagerHomeState();
}

class _ManagerHomeState extends State<_ManagerHome> {
  late final ConnectionController _connection;
  late final AppLifecycleListener _lifecycle;
  final _refresh = ValueNotifier(0);
  ConnectionProfile? _profile;
  bool _starting = true;
  bool _startupError = false;
  bool _editing = false;
  bool _settingsOpen = false;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _connection = ConnectionController(
      widget.store,
      SshConnector(widget.store),
    );
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_connection.setForeground(true)),
      onHide: () => unawaited(_connection.setForeground(false)),
    );
    unawaited(_restoreConnection());
  }

  Future<void> _restoreConnection() async {
    try {
      final saved = await widget.store.readProfile();
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _starting = false;
        _startupError = false;
      });
      if (saved != null) await _connection.start(saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _startupError = true;
          _starting = false;
        });
      }
    }
  }

  Future<void> _save(
    ConnectionProfile profile,
    SshCredentials credentials,
  ) async {
    final previous = _profile;
    if (previous != null &&
        previous.dashboardIdentity != profile.dashboardIdentity) {
      await _connection.disconnect();
      await WebUiScreen.clearWebsiteData();
      await widget.store.forgetPort();
    }
    await widget.store.save(profile, credentials);
    if (!mounted) return;
    setState(() => _profile = profile);
    unawaited(_connection.start(profile));
  }

  Future<void> _edit() async {
    if (_editing || _profile == null) return;
    _editing = true;
    try {
      SshCredentials? credentials;
      try {
        credentials = await widget.store.readCredentials();
      } catch (_) {
        // A failed read can be recovered with replacement credentials.
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (pageContext) => Scaffold(
            appBar: AppBar(title: const Text('编辑服务器')),
            body: ConnectionScreen(
              profile: _profile,
              credentials: credentials,
              onSave: (profile, credentials) async {
                await _save(profile, credentials);
                if (pageContext.mounted) Navigator.of(pageContext).pop();
              },
            ),
          ),
        ),
      );
    } finally {
      _editing = false;
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _clearConnection({required bool erase}) async {
    final profile = _profile;
    if (_changing || profile == null) return;
    _changing = true;
    try {
      final confirmed = erase
          ? await _confirm('清除本机连接数据？', '将删除 SSH 配置、凭据、已保存的主机指纹和 WebUI 登录数据。')
          : await _confirm('重置已保存的主机指纹？', '请先向服务器管理员核对新指纹。下次连接时将再次要求确认。');
      if (!confirmed || !mounted) return;
      await _connection.disconnect();
      await WebUiScreen.clearWebsiteData();
      await widget.store.forgetPort();
      if (erase) {
        await widget.store.deleteProfile();
        await widget.store.secureStorage.deleteAll();
        if (mounted) setState(() => _profile = null);
      } else {
        await widget.store.removePin(profile.sshEndpoint);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('清除失败。请重试。')));
      }
    } finally {
      _changing = false;
    }
  }

  Future<void> _settings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    try {
      final hasProfile = _profile != null;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (settingsContext) => SettingsScreen(
            theme: widget.theme,
            onTheme: widget.onTheme,
            connected: _connection.phase != ConnectionPhase.idle,
            onEdit: !hasProfile
                ? null
                : () {
                    Navigator.of(settingsContext).pop();
                    unawaited(_edit());
                  },
            onDisconnect: () {
              Navigator.of(settingsContext).pop();
              unawaited(_connection.disconnect());
            },
            onForgetKey: !hasProfile
                ? null
                : () {
                    Navigator.of(settingsContext).pop();
                    unawaited(_clearConnection(erase: false));
                  },
            onErase: !hasProfile
                ? null
                : () {
                    Navigator.of(settingsContext).pop();
                    unawaited(_clearConnection(erase: true));
                  },
          ),
        ),
      );
    } finally {
      _settingsOpen = false;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _connection.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _connection,
    builder: (context, _) {
      final connected = _connection.phase == ConnectionPhase.connected;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: connected ? 48 : null,
          title: const Text('AstrBot Mobile Manager'),
          actions: [
            if (connected)
              IconButton(
                tooltip: '刷新 WebUI',
                onPressed: () => _refresh.value++,
                icon: const Icon(Icons.refresh),
              ),
            IconButton(
              tooltip: connected ? 'SSH 已连接 · 设置' : '设置',
              onPressed: _settings,
              icon: Icon(connected ? Icons.link : Icons.settings_outlined),
            ),
          ],
        ),
        body: _body(connected),
      );
    },
  );

  Widget _body(bool connected) {
    if (_starting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_startupError) {
      return Center(
        child: FilledButton(
          onPressed: _restoreConnection,
          child: const Text('重新读取本机配置'),
        ),
      );
    }
    if (_profile == null) return ConnectionScreen(onSave: _save);
    final origin = _connection.uri;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (origin != null)
          SafeArea(
            top: false,
            child: ExcludeSemantics(
              excluding: !connected,
              child: IgnorePointer(
                ignoring: !connected,
                child: WebUiScreen(
                  key: ValueKey(origin),
                  origin: origin,
                  online: connected,
                  refresh: _refresh,
                ),
              ),
            ),
          ),
        if (!connected)
          ConnectionStatus(controller: _connection, onEdit: _edit),
      ],
    );
  }
}
