// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.theme,
    required this.onTheme,
    required this.connected,
    required this.onEdit,
    required this.onDisconnect,
    required this.onForgetKey,
    required this.onErase,
  });

  final ThemeMode theme;
  final ValueChanged<ThemeMode> onTheme;
  final bool connected;
  final VoidCallback? onEdit;
  final VoidCallback? onDisconnect;
  final VoidCallback? onForgetKey;
  final VoidCallback? onErase;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('编辑服务器'),
              onTap: onEdit,
            ),
          if (connected)
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('断开 SSH'),
              onTap: onDisconnect,
            ),
          if (onForgetKey != null)
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('重置主机指纹'),
              onTap: onForgetKey,
            ),
          if (onErase != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('清除本机连接数据'),
              onTap: onErase,
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<ThemeMode>(
              initialValue: theme,
              decoration: const InputDecoration(labelText: '外观'),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
              onChanged: (value) => onTheme(value!),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    ),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _links = {
    'AstrBot 官方网站': 'https://astrbot.app/',
    'AstrBot 上游源代码': 'https://github.com/AstrBotDevs/AstrBot',
    'AstrBot 最终用户许可协议':
        'https://github.com/AstrBotDevs/AstrBot/blob/master/EULA.md',
    'AstrBot 项目声明':
        'https://github.com/AstrBotDevs/AstrBot/blob/master/FIRST_NOTICE.md',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SafeArea(
      top: false,
      child: ListView(
        children: [
          const ListTile(
            title: Text('AstrBot Mobile Manager'),
            subtitle: Text('v0.1.0 · 非官方社区客户端\nAGPL-3.0-or-later'),
          ),
          for (final link in _links.entries)
            ListTile(
              title: Text(link.key),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () async {
                final opened = await launchUrl(
                  Uri.parse(link.value),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('无法打开链接。')));
                }
              },
            ),
          ListTile(
            title: const Text('第三方软件许可'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'AstrBot Mobile Manager',
            ),
          ),
        ],
      ),
    ),
  );
}
