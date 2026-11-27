// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ssh/ssh_connector.dart';
import '../core/storage/connection_store.dart';
import '../core/tunnel/local_tunnel.dart';
import '../models/connection_problem.dart';
import '../models/connection_profile.dart';

enum ConnectionPhase { idle, connecting, connected, retrying, error }

class ConnectionController extends ChangeNotifier {
  ConnectionController(this.store, this.connector);

  final ConnectionStore store;
  final SshConnector connector;
  ConnectionProfile? profile;
  ConnectionPhase phase = ConnectionPhase.idle;
  ConnectionProblem? problem;
  HostKeyChallenge? hostKey;
  Uri? uri;

  bool _foreground = true;
  bool _requested = false;
  bool _disposed = false;
  int _generation = 0;
  int _retries = 0;
  bool _checking = false;
  Timer? _retry;
  Timer? _heartbeat;
  Completer<bool>? _trust;
  LocalTunnel? _tunnel;
  SshSession? _session;
  VoidCallback? _cancelSshAttempt;

  Future<void> start(ConnectionProfile newProfile) async {
    await disconnect();
    profile = newProfile;
    _requested = true;
    await _connect();
  }

  Future<void> retry() async {
    _retry?.cancel();
    _retries = 0;
    _requested = true;
    await _connect();
  }

  Future<void> _connect() async {
    final selected = profile;
    if (!_foreground ||
        !_requested ||
        selected == null ||
        phase == ConnectionPhase.connecting ||
        phase == ConnectionPhase.connected) {
      return;
    }
    final generation = ++_generation;
    phase = ConnectionPhase.connecting;
    problem = null;
    hostKey = null;
    _notify();

    SshSession? opened;
    LocalTunnel? created;
    try {
      final credentials = await _loadCredentials();
      if (!_current(generation)) return;
      final session = opened = await connector.connect(
        selected,
        credentials,
        (challenge) => _askTrust(generation, challenge),
        onAbortAvailable: (abort) {
          if (_current(generation)) {
            _cancelSshAttempt = abort;
          } else {
            abort();
          }
        },
      );
      if (!_current(generation)) return;
      _cancelSshAttempt = null;
      _session = session;
      unawaited(
        session.done.then<void>(
          (_) => _lost(session),
          onError: (Object _, StackTrace _) => _lost(session),
        ),
      );

      final tunnel =
          _tunnel ??
          (created = await LocalTunnel.bind(
            preferredPort: await store.preferredPort(selected),
          ));
      if (!_current(generation)) return;
      if (created != null) {
        _tunnel = tunnel;
        unawaited(
          tunnel.done.then<void>((_) {
            if (identical(_tunnel, tunnel)) _listenerLost(tunnel);
          }),
        );
      }
      await tunnel.attach(session, selected);
      if (!_current(generation)) return;
      try {
        await store.savePort(selected, tunnel.uri.port);
      } catch (_) {
        // An active tunnel still works if the next launch cannot reuse its origin.
      }
      if (!_current(generation)) return;
      _retries = 0;
      uri = tunnel.uri;
      phase = ConnectionPhase.connected;
      _heartbeat = Timer.periodic(
        const Duration(seconds: 12),
        (_) => unawaited(_check()),
      );
      _notify();
    } on ConnectionFailure catch (error) {
      if (_current(generation)) _failed(error.problem);
    } catch (_) {
      if (_current(generation)) _failed(ConnectionProblem.storage);
    } finally {
      if (opened != null && !identical(_session, opened)) opened.close();
      if (created != null && !identical(_tunnel, created)) {
        await created.close();
      }
    }
  }

  Future<SshCredentials> _loadCredentials() async {
    try {
      final credentials = await store.readCredentials();
      if (credentials != null) return credentials;
    } catch (_) {
      throw const ConnectionFailure(ConnectionProblem.storage);
    }
    throw const ConnectionFailure(ConnectionProblem.authentication);
  }

  bool _current(int generation) => !_disposed && _generation == generation;

  Future<bool> _askTrust(int generation, HostKeyChallenge challenge) async {
    if (!_current(generation)) return false;
    hostKey = challenge;
    if (challenge.expected != null) {
      _notify();
      return false;
    }
    final pending = _trust = Completer<bool>();
    _notify();
    return pending.future;
  }

  void answerHostTrust(bool accepted) {
    final pending = _trust;
    _trust = null;
    if (pending != null) {
      hostKey = null;
      pending.complete(accepted);
      _notify();
    }
  }

  Future<void> setForeground(bool foreground) async {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _retry?.cancel();
      return;
    }
    if (_requested &&
        (phase == ConnectionPhase.retrying || phase == ConnectionPhase.idle)) {
      await retry();
    } else if (phase == ConnectionPhase.connected) {
      await _check();
    }
  }

  Future<void> _check() async {
    final session = _session;
    if (!_foreground ||
        _checking ||
        session == null ||
        phase != ConnectionPhase.connected) {
      return;
    }
    _checking = true;
    try {
      await session.ping().timeout(const Duration(seconds: 5));
    } catch (_) {
      _lost(session);
    } finally {
      _checking = false;
    }
  }

  void _lost(SshSession session) {
    if (!identical(_session, session)) return;
    _failed(ConnectionProblem.lost);
  }

  void _listenerLost(LocalTunnel tunnel) {
    _tunnel = null;
    unawaited(tunnel.close());
    _failed(ConnectionProblem.localListener);
  }

  void _failed(ConnectionProblem failure) {
    _stopAttempt();
    problem = failure;
    final transient = switch (failure) {
      ConnectionProblem.unreachable ||
      ConnectionProblem.lost ||
      ConnectionProblem.dashboardUnavailable => true,
      _ => false,
    };
    if (_requested && transient && _retries < 4) {
      phase = ConnectionPhase.retrying;
      if (_foreground) {
        final delay = Duration(seconds: 2 << _retries++);
        _retry = Timer(delay, () => unawaited(_connect()));
      }
    } else {
      phase = ConnectionPhase.error;
    }
    if (failure != ConnectionProblem.hostKeyChanged) hostKey = null;
    _notify();
  }

  void _stopAttempt() {
    _generation++;
    _retry?.cancel();
    _heartbeat?.cancel();
    final pendingTrust = _trust;
    _trust = null;
    pendingTrust?.complete(false);
    final cancel = _cancelSshAttempt;
    _cancelSshAttempt = null;
    cancel?.call();
    _tunnel?.detach();
    final session = _session;
    _session = null;
    session?.close();
  }

  Future<void> disconnect() async {
    _requested = false;
    _retries = 0;
    _stopAttempt();
    final tunnel = _tunnel;
    _tunnel = null;
    // Never announce the old origin as usable after releasing its listener.
    phase = ConnectionPhase.idle;
    uri = null;
    hostKey = null;
    problem = null;
    _notify();
    await tunnel?.close();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
