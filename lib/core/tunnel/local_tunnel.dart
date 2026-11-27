// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../../models/connection_problem.dart';
import '../../models/connection_profile.dart';
import '../ssh/ssh_connector.dart';

class LocalTunnel {
  LocalTunnel._(this._listener) {
    _listener.listen(
      _accept,
      onError: (Object _, StackTrace _) {
        if (!_done.isCompleted) _done.complete();
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  static const timeout = Duration(seconds: 8);
  static const _maxConnections = 64;
  final ServerSocket _listener;
  final _done = Completer<void>();
  final _connections = <_ForwardedConnection>{};
  SshSession? _session;
  ConnectionProfile? _profile;
  int _generation = 0;

  Uri get uri =>
      Uri(scheme: 'http', host: '127.0.0.1', port: _listener.port, path: '/');
  Future<void> get done => _done.future;

  static Future<LocalTunnel> bind({int? preferredPort}) async {
    if (preferredPort != null &&
        preferredPort >= 1024 &&
        preferredPort <= 65535) {
      try {
        return LocalTunnel._(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, preferredPort),
        );
      } on SocketException {
        // Another process may already own the previous origin.
      }
    }
    try {
      return LocalTunnel._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      );
    } on SocketException {
      throw const ConnectionFailure(ConnectionProblem.localListener);
    }
  }

  Future<void> attach(SshSession session, ConnectionProfile profile) async {
    detach();
    final generation = _generation;
    // An SSH open failure distinguishes an sshd policy rejection from HTTP failure.
    try {
      final channel = await _openChannel(session, profile);
      unawaited(
        channel.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      channel.destroy();
    } on SSHChannelOpenError catch (error) {
      // RFC 4254 SSH_OPEN_ADMINISTRATIVELY_PROHIBITED.
      throw ConnectionFailure(
        error.code == 1
            ? ConnectionProblem.forwardingDenied
            : ConnectionProblem.dashboardUnavailable,
      );
    } catch (_) {
      throw const ConnectionFailure(ConnectionProblem.dashboardUnavailable);
    }

    if (generation != _generation) return;
    _session = session;
    _profile = profile;
    await checkDashboard();
  }

  Future<void> checkDashboard() async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw const ConnectionFailure(ConnectionProblem.dashboardUnavailable);
      }
      // The response body is deliberately discarded. Probe only reachability.
      unawaited(
        response.listen(null, onError: (Object _, StackTrace _) {}).cancel(),
      );
    } catch (_) {
      throw const ConnectionFailure(ConnectionProblem.dashboardUnavailable);
    } finally {
      client.close(force: true);
    }
  }

  void detach() {
    _generation++;
    _session = null;
    _profile = null;
    for (final connection in _connections.toList()) {
      connection.close();
    }
  }

  Future<void> close() async {
    detach();
    await _listener.close();
  }

  void _accept(Socket socket) {
    final session = _session;
    final profile = _profile;
    if (session == null ||
        profile == null ||
        _connections.length >= _maxConnections) {
      socket.destroy();
      return;
    }
    final connection = _ForwardedConnection(socket);
    _connections.add(connection);
    unawaited(
      connection
          .forward(
            () => _openChannel(session, profile, sourcePort: socket.remotePort),
          )
          .whenComplete(() => _connections.remove(connection)),
    );
  }

  static Future<SSHSocket> _openChannel(
    SshSession session,
    ConnectionProfile profile, {
    int sourcePort = 0,
  }) {
    final open = session.openChannel(
      profile.dashboardHost,
      profile.dashboardPort,
      sourcePort: sourcePort,
    );
    return open.timeout(
      timeout,
      onTimeout: () {
        unawaited(
          open.then<void>((lateChannel) {
            unawaited(
              lateChannel.done.then<void>(
                (_) {},
                onError: (Object _, StackTrace _) {},
              ),
            );
            lateChannel.destroy();
          }, onError: (Object _, StackTrace _) {}),
        );
        throw TimeoutException('SSH forwarding channel');
      },
    );
  }
}

class _ForwardedConnection {
  _ForwardedConnection(this.local);

  final Socket local;
  SSHSocket? _remote;
  bool _closed = false;

  Future<void> forward(Future<SSHSocket> Function() open) async {
    try {
      unawaited(
        local.done.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) => close(),
        ),
      );
      final remote = _remote = await open();
      unawaited(
        remote.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      unawaited(
        remote.sink.done.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      if (_closed) {
        remote.destroy();
        return;
      }
      local.setOption(SocketOption.tcpNoDelay, true);
      // Keep independent streams so multiple requests, upgrades and streaming
      // responses can use the tunnel without any HTTP parsing or buffering here.
      await Future.wait([
        _upstream(remote),
        _downstream(remote),
      ], eagerError: true);
    } catch (_) {
      // A failed channel only terminates its own local connection.
    } finally {
      close();
    }
  }

  Future<void> _upstream(SSHSocket remote) async {
    // Let stream backpressure follow the SSH channel window. Flushing each
    // channel directly would contend for the same transport socket.
    await remote.sink.addStream(local);
    unawaited(
      remote.sink.close().then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  Future<void> _downstream(SSHSocket remote) async {
    await local.addStream(remote.stream);
    await local.flush();
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    local.destroy();
    _remote?.destroy();
  }
}
