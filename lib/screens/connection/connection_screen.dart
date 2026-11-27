// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/connection_profile.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    this.profile,
    this.credentials,
    required this.onSave,
  });

  final ConnectionProfile? profile;
  final SshCredentials? credentials;
  final Future<void> Function(ConnectionProfile, SshCredentials) onSave;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const _maxKeyBytes = 128 * 1024;
  final _form = GlobalKey<FormState>();
  late final _host = TextEditingController(text: widget.profile?.host ?? '');
  late final _port = TextEditingController(
    text: '${widget.profile?.sshPort ?? 22}',
  );
  late final _username = TextEditingController(
    text: widget.profile?.username ?? '',
  );
  late final _targetHost = TextEditingController(
    text: widget.profile?.dashboardHost ?? '127.0.0.1',
  );
  late final _targetPort = TextEditingController(
    text: '${widget.profile?.dashboardPort ?? 6185}',
  );
  late Authentication _method =
      widget.profile?.authentication ?? Authentication.password;
  late final _password = TextEditingController(
    text: _method == Authentication.password
        ? widget.credentials?.secret ?? ''
        : '',
  );
  late final _passphrase = TextEditingController(
    text: widget.credentials?.passphrase ?? '',
  );
  late String? _privateKey = _method == Authentication.privateKey
      ? widget.credentials?.secret
      : null;

  String? _keyName;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final field in [
      _host,
      _port,
      _username,
      _targetHost,
      _targetPort,
      _password,
      _passphrase,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '请填写此项' : null;

  String? _validHost(String? value) {
    final host = value?.trim() ?? '';
    if (InternetAddress.tryParse(host) != null) return null;
    final label = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');
    final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    if (name.length <= 253 && name.split('.').every(label.hasMatch)) {
      return null;
    }
    return '请输入 IPv4、IPv6 或主机名';
  }

  String? _validPort(String? value) {
    final input = value?.trim() ?? '';
    final port = int.tryParse(input);
    return !RegExp(r'^[0-9]+$').hasMatch(input) ||
            port == null ||
            port < 1 ||
            port > 65535
        ? '请输入 1–65535 之间的端口'
        : null;
  }

  Future<void> _importKey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await openFile();
      if (file == null) return;
      if (await file.length() > _maxKeyBytes) throw const FormatException();
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxKeyBytes) throw const FormatException();
      final key = utf8.decode(bytes).trim();
      if (!RegExp(r'^-----BEGIN (OPENSSH|RSA|EC) PRIVATE KEY-----')
          .hasMatch(key)) {
        throw const FormatException();
      }
      if (!mounted) return;
      setState(() {
        _privateKey = key;
        _keyName = file.name;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法导入私钥。请选择 OpenSSH 或 PEM 私钥文件。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final isKey = _method == Authentication.privateKey;
    if (isKey && _privateKey == null) {
      setState(() => _error = '请先导入 SSH 私钥。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        ConnectionProfile(
          host: _host.text.trim(),
          sshPort: int.parse(_port.text.trim()),
          username: _username.text.trim(),
          authentication: _method,
          dashboardHost: _targetHost.text.trim(),
          dashboardPort: int.parse(_targetPort.text.trim()),
        ),
        SshCredentials(
          isKey ? _privateKey! : _password.text,
          passphrase: isKey && _passphrase.text.isNotEmpty
              ? _passphrase.text
              : null,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败。请检查设备存储后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '连接服务器',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '通过 SSH 打开服务器上的 AstrBot WebUI。',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                _field(
                  'SSH 主机',
                  _host,
                  validator: _validHost,
                  type: TextInputType.url,
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _field('SSH 用户名', _username, validator: _required),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'SSH 端口',
                        _port,
                        validator: _validPort,
                        type: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<Authentication>(
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: '认证方式'),
                  items: const [
                    DropdownMenuItem(
                      value: Authentication.password,
                      child: Text('SSH 密码'),
                    ),
                    DropdownMenuItem(
                      value: Authentication.privateKey,
                      child: Text('SSH 私钥'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (method) => setState(() => _method = method!),
                ),
                const SizedBox(height: 16),
                if (_method == Authentication.password)
                  _field(
                    'SSH 密码',
                    _password,
                    secret: true,
                    validator: (text) =>
                        text == null || text.isEmpty ? '请输入 SSH 密码' : null,
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importKey,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(
                      _keyName ?? (_privateKey == null ? '导入私钥' : '替换已保存的私钥'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field('私钥口令（可选）', _passphrase, secret: true),
                ],
                const Divider(height: 40),
                Text(
                  'AstrBot WebUI',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '填入 SSH 服务器能够访问的 HTTP 地址。',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _field(
                        'WebUI 主机',
                        _targetHost,
                        validator: _validHost,
                        type: TextInputType.url,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'WebUI 端口',
                        _targetPort,
                        validator: _validPort,
                        type: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('保存并连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool secret = false,
    TextInputType? type,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      obscureText: secret,
      keyboardType: type,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: secret ? null : const [],
      enabled: !_busy,
      decoration: InputDecoration(labelText: label),
      validator: validator,
    ),
  );
}
