// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dartssh2/dartssh2.dart';

import '../../models/connection_problem.dart';
import '../../models/connection_profile.dart';
import '../storage/connection_store.dart';

typedef AskHostTrust = Future<bool> Function(HostKeyChallenge challenge);

abstract interface class SshSession {
  Future<void> get done;
  Future<void> ping();
  Future<SSHSocket> openChannel(String host, int port, {int sourcePort = 0});
  void close();
}

class SshConnector {
  const SshConnector(this.store);

  final ConnectionStore store;
  static const timeout = Duration(seconds: 12);

  Future<SshSession> connect(
    ConnectionProfile profile,
    SshCredentials credentials,
    AskHostTrust askHostTrust, {
    void Function(void Function())? onAbortAvailable,
  }) async {
    final identities = profile.authentication == Authentication.privateKey
        ? await _decodeKey(credentials)
        : null;
    final endpoint = profile.sshEndpoint;
    final String? savedPin;
    try {
      savedPin = await store.readPin(endpoint);
    } catch (_) {
      throw const ConnectionFailure(ConnectionProblem.storage);
    }

    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        profile.host,
        profile.sshPort,
        timeout: timeout,
      );
    } on Exception {
      throw const ConnectionFailure(ConnectionProblem.unreachable);
    }

    onAbortAvailable?.call(socket.destroy);
    ConnectionFailure? keyFailure;
    final SSHClient client;
    try {
      client = SSHClient(
        socket,
        username: profile.username,
        identities: identities,
        onPasswordRequest: identities == null ? () => credentials.secret : null,
        keepAliveInterval: null,
        handshakeTimeout: const Duration(minutes: 2),
        authTimeout: timeout,
        onVerifyHostKey: (algorithm, value) async {
          final received = HostFingerprint(algorithm, utf8.decode(value));
          if (savedPin == received.pin) return true;
          if (savedPin != null) {
            keyFailure = const ConnectionFailure(
              ConnectionProblem.hostKeyChanged,
            );
            unawaited(
              askHostTrust(
                HostKeyChallenge(endpoint, received, expected: savedPin),
              ),
            );
            return false;
          }
          if (!await askHostTrust(HostKeyChallenge(endpoint, received))
              .timeout(const Duration(seconds: 90), onTimeout: () => false)) {
            keyFailure = const ConnectionFailure(
              ConnectionProblem.hostKeyRejected,
            );
            return false;
          }
          try {
            await store.writePin(endpoint, received.pin);
            return true;
          } catch (_) {
            keyFailure = const ConnectionFailure(ConnectionProblem.storage);
            return false;
          }
        },
      );
    } catch (_) {
      socket.destroy();
      throw const ConnectionFailure(ConnectionProblem.handshake);
    }

    // dartssh2 may report the same failure on the authentication and transport futures.
    unawaited(
      client.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    try {
      await client.authenticated;
      return _DartSshSession(client, socket);
    } on SSHAuthFailError {
      client.close();
      socket.destroy();
      throw keyFailure ??
          const ConnectionFailure(ConnectionProblem.authentication);
    } catch (_) {
      client.close();
      socket.destroy();
      throw keyFailure ?? const ConnectionFailure(ConnectionProblem.handshake);
    }
  }
}

Future<List<SSHKeyPair>> _decodeKey(SshCredentials credentials) async {
  try {
    return await Isolate.run(
      () =>
          SSHKeyPair.fromPem(credentials.secret.trim(), credentials.passphrase),
    );
  } catch (_) {
    throw const ConnectionFailure(ConnectionProblem.invalidPrivateKey);
  }
}

class _DartSshSession implements SshSession {
  _DartSshSession(this.client, this.socket);

  final SSHClient client;
  final SSHSocket socket;

  @override
  Future<void> get done => client.done;

  @override
  Future<void> ping() => client.ping();

  @override
  Future<SSHSocket> openChannel(String host, int port, {int sourcePort = 0}) =>
      client.forwardLocal(
        host,
        port,
        localHost: '127.0.0.1',
        localPort: sourcePort,
      );

  @override
  void close() {
    client.close();
    socket.destroy();
  }
}
