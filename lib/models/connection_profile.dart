// SPDX-License-Identifier: AGPL-3.0-or-later
enum Authentication { password, privateKey }

class ConnectionProfile {
  const ConnectionProfile({
    required this.host,
    required this.username,
    this.sshPort = 22,
    this.authentication = Authentication.password,
    this.dashboardHost = '127.0.0.1',
    this.dashboardPort = 6185,
  });

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) =>
      ConnectionProfile(
        host: json['host'] as String,
        username: json['username'] as String,
        sshPort: json['sshPort'] as int,
        authentication: Authentication.values.byName(
          json['authentication'] as String,
        ),
        dashboardHost: json['dashboardHost'] as String,
        dashboardPort: json['dashboardPort'] as int,
      );

  final String host;
  final String username;
  final int sshPort;
  final Authentication authentication;
  final String dashboardHost;
  final int dashboardPort;

  String get sshEndpoint =>
      Uri(scheme: 'ssh', host: host.toLowerCase(), port: sshPort).toString();

  // The browser identity also changes when the SSH account or the target changes.
  String get dashboardIdentity => [
    sshEndpoint,
    username,
    dashboardHost.toLowerCase(),
    dashboardPort,
  ].join('\n');

  Map<String, Object> toJson() => {
    'host': host,
    'username': username,
    'sshPort': sshPort,
    'authentication': authentication.name,
    'dashboardHost': dashboardHost,
    'dashboardPort': dashboardPort,
  };
}

class SshCredentials {
  const SshCredentials(this.secret, {this.passphrase});

  /// SSH password or PEM/OpenSSH private key, depending on the profile.
  final String secret;
  final String? passphrase;
}
