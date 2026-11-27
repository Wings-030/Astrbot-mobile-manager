// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:material_ui/material_ui.dart';

import '../../models/connection_problem.dart';
import '../../services/connection_controller.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    super.key,
    required this.controller,
    required this.onEdit,
  });

  final ConnectionController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final phase = controller.phase;
    final hostKey = controller.hostKey;
    final firstTrust = hostKey != null && hostKey.expected == null;
    final waiting =
        phase == ConnectionPhase.connecting ||
        phase == ConnectionPhase.retrying;
    final colors = Theme.of(context).colorScheme;
    final title = firstTrust
        ? '验证 SSH 主机指纹'
        : switch (phase) {
            ConnectionPhase.connecting => '正在连接',
            ConnectionPhase.retrying => '正在尝试重新连接',
            ConnectionPhase.idle => 'SSH 已断开',
            _ => _problemText(controller.problem),
          };

    return Material(
      child: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (waiting && !firstTrust) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  if (waiting && !firstTrust && controller.problem != null)
                    Text(_problemText(controller.problem)),
                  if (hostKey != null) ...[
                    Text(
                      hostKey.endpoint,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      hostKey.received.pin,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    if (firstTrust)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text('请从服务器控制台或管理员处核对 SHA256 指纹，再决定是否信任。'),
                      )
                    else ...[
                      const SizedBox(height: 12),
                      const Text('已保存的指纹'),
                      SelectableText(
                        hostKey.expected!,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 12),
                      const Text('连接已阻止。确认服务器确实更换了主机密钥后，可在设置中重置指纹。'),
                    ],
                  ],
                  const SizedBox(height: 24),
                  if (firstTrust) ...[
                    FilledButton(
                      onPressed: () => controller.answerHostTrust(true),
                      child: const Text('已核对，信任并连接'),
                    ),
                    TextButton(
                      onPressed: () => controller.answerHostTrust(false),
                      child: const Text('拒绝连接'),
                    ),
                  ] else ...[
                    if (phase != ConnectionPhase.connecting &&
                        hostKey?.expected == null)
                      FilledButton(
                        onPressed: controller.retry,
                        child: const Text('重新连接'),
                      ),
                    if (waiting)
                      OutlinedButton(
                        onPressed: controller.disconnect,
                        child: const Text('停止连接'),
                      ),
                    TextButton(onPressed: onEdit, child: const Text('编辑服务器')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _problemText(ConnectionProblem? problem) => switch (problem) {
  ConnectionProblem.unreachable => '无法访问 SSH 服务器。请检查网络、地址和端口。',
  ConnectionProblem.authentication => 'SSH 认证失败。请检查用户名和凭据。',
  ConnectionProblem.invalidPrivateKey => '无法读取 SSH 私钥。请检查格式和口令。',
  ConnectionProblem.hostKeyRejected => 'SSH 主机指纹未获确认。',
  ConnectionProblem.hostKeyChanged => 'SSH 主机指纹已变化',
  ConnectionProblem.handshake => 'SSH 握手失败。请检查 SSH 服务和密钥算法。',
  ConnectionProblem.forwardingDenied => 'SSH 服务器拒绝了端口转发。',
  ConnectionProblem.dashboardUnavailable => 'AstrBot WebUI 无法访问。请检查服务、地址和端口。',
  ConnectionProblem.lost => 'SSH 连接已中断。',
  ConnectionProblem.storage => '无法读取连接配置或安全存储。',
  ConnectionProblem.localListener => '无法监听设备上的回环端口。',
  null => '无法连接。请重试。',
};
