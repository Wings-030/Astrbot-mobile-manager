// SPDX-License-Identifier: AGPL-3.0-or-later
enum ConnectionProblem {
  unreachable,
  authentication,
  invalidPrivateKey,
  hostKeyRejected,
  hostKeyChanged,
  handshake,
  forwardingDenied,
  dashboardUnavailable,
  lost,
  storage,
  localListener,
}

class ConnectionFailure implements Exception {
  const ConnectionFailure(this.problem);
  final ConnectionProblem problem;
}

class HostFingerprint {
  const HostFingerprint(this.algorithm, this.fingerprint);

  final String algorithm;
  final String fingerprint;

  String get pin => '$algorithm $fingerprint';
}

class HostKeyChallenge {
  const HostKeyChallenge(this.endpoint, this.received, {this.expected});
  final String endpoint;
  final HostFingerprint received;
  final String? expected;
}
