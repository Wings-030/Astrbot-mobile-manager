// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:astrbot_mobile_manager/core/ssh/ssh_connector.dart';
import 'package:astrbot_mobile_manager/core/tunnel/local_tunnel.dart';
import 'package:astrbot_mobile_manager/models/connection_problem.dart';
import 'package:astrbot_mobile_manager/models/connection_profile.dart';
import 'package:astrbot_mobile_manager/services/connection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_store.dart';

const password = SshCredentials('test-only-password');
final _payload = List<int>.generate(1024 * 1024, (index) => index % 256);

void main() {
  test(
    'A busy preferred port falls back to a different loopback port',
    () async {
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);
      final tunnel = await LocalTunnel.bind(preferredPort: occupied.port);
      addTearDown(tunnel.close);
      expect(tunnel.uri.host, '127.0.0.1');
      expect(tunnel.uri.port, isNot(occupied.port));
    },
  );

  group(
    'Real SSH transport',
    () {
      late HttpServer dashboard;
      late _Fixture fixture;

      setUpAll(() async {
        dashboard = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        dashboard.listen(_serve);
        fixture = await _Fixture.start(dashboard.port);
      });

      tearDownAll(() async {
        await fixture.stop();
        await dashboard.close(force: true);
      });

      ConnectionProfile profile({
        Authentication method = Authentication.password,
        int? port,
      }) => ConnectionProfile(
        host: '127.0.0.1',
        sshPort: fixture.port,
        username: 'fixture',
        dashboardPort: port ?? dashboard.port,
        authentication: method,
      );

      test('Password, confirmed SHA256 fingerprint, failed auth and host key change', () async {
        final store = testStore();
        final ssh = SshConnector(store);
        final selected = profile();
        await expectLater(
          ssh.connect(selected, password, (_) async => false),
          throwsA(failure(ConnectionProblem.hostKeyRejected)),
        );
        expect(await store.readPin(selected.sshEndpoint), isNull);

        final session = await ssh.connect(selected, password, (
          challenge,
        ) async {
          expect(challenge.expected, isNull);
          expect(challenge.received.fingerprint, startsWith('SHA256:'));
          return true;
        });
        session.close();
        await expectLater(
          ssh.connect(selected, const SshCredentials('incorrect'), (_) async {
            fail('A pinned key must not prompt again');
          }),
          throwsA(failure(ConnectionProblem.authentication)),
        );

        await fixture.send('rotate');
        await expectLater(
          ssh.connect(selected, password, (challenge) async {
            expect(challenge.expected, isNotNull);
            expect(challenge.received.pin, isNot(challenge.expected));
            return true;
          }),
          throwsA(failure(ConnectionProblem.hostKeyChanged)),
        );
      });

      test('Encrypted OpenSSH Ed25519 key and wrong passphrase', () async {
        final ssh = SshConnector(testStore());
        final selected = profile(method: Authentication.privateKey);
        await expectLater(
          ssh.connect(
            selected,
            SshCredentials(fixture.privateKey, passphrase: 'incorrect'),
            (_) async => true,
          ),
          throwsA(failure(ConnectionProblem.invalidPrivateKey)),
        );
        final session = await ssh.connect(
          selected,
          SshCredentials(
            fixture.privateKey,
            passphrase: 'test-only-passphrase',
          ),
          (_) async => true,
        );
        addTearDown(session.close);
        await session.ping();
      });

      test('Concurrent HTTP, protected endpoint, upload, download, SSE and WebSocket', () async {
        final selected = profile();
        final session = await SshConnector(testStore())
            .connect(selected, password, (_) async => true);
        addTearDown(session.close);
        final tunnel = await LocalTunnel.bind();
        addTearDown(tunnel.close);
        await tunnel.attach(session, selected);
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        addTearDown(() => client.close(force: true));

        final results = await Future.wait(
          List.generate(16, (index) async {
            final response = await (await client.getUrl(
              tunnel.uri.resolve('/echo/$index'),
            )).close();
            return utf8.decoder.bind(response).join();
          }),
        );
        expect(results, List.generate(16, (index) => '/echo/$index'));

        final protected = await (await client.getUrl(
          tunnel.uri.resolve('/protected'),
        )).close();
        expect(protected.statusCode, HttpStatus.unauthorized);
        await protected.drain<void>();

        final upload = await client.postUrl(tunnel.uri.resolve('/upload'));
        upload.add(_payload);
        final download = await upload.close();
        expect(
          download.headers.value('content-disposition'),
          contains('attachment'),
        );
        final received = await download.expand((bytes) => bytes).toList();
        expect(received, orderedEquals(_payload));

        final socket = await WebSocket.connect(
          tunnel.uri.replace(scheme: 'ws', path: '/ws').toString(),
        );
        addTearDown(socket.close);
        socket.add('hello');
        expect(await socket.first, 'hello');
        await socket.close();

        final response = await (await client.getUrl(
          tunnel.uri.resolve('/events'),
        )).close();
        expect(response.headers.contentType?.mimeType, 'text/event-stream');
        final lines = StreamIterator(
          const LineSplitter().bind(utf8.decoder.bind(response)),
        );
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 2)),
          true,
        );
        expect(lines.current, 'data: ready');
        // The server leaves the response open, so readiness requires streaming.
        await lines.cancel();
        final uri = tunnel.uri;
        await tunnel.close();
        await expectLater(
          Socket.connect(uri.host, uri.port),
          throwsA(isA<SocketException>()),
        );
      });

      test(
        'SSH forwarding policy rejection and dashboard HTTP error are distinct',
        () async {
          final selected = profile();
          final session = await SshConnector(testStore())
              .connect(selected, password, (_) async => true);
          addTearDown(session.close);
          final tunnel = await LocalTunnel.bind();
          addTearDown(tunnel.close);
          await expectLater(
            tunnel.attach(session, profile(port: dashboard.port == 1 ? 2 : 1)),
            throwsA(failure(ConnectionProblem.forwardingDenied)),
          );
          await tunnel.attach(session, selected);
          await dashboard.close(force: true);
          await expectLater(
            tunnel.checkDashboard(),
            throwsA(failure(ConnectionProblem.dashboardUnavailable)),
          );
          dashboard = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            selected.dashboardPort,
          );
          dashboard.listen(_serve);
        },
      );

      test(
        'A dropped SSH connection recovers on foreground with the same origin',
        () async {
          final selected = profile();
          final store = testStore();
          await store.save(selected, password);
          final controller = ConnectionController(store, SshConnector(store));
          addTearDown(controller.dispose);
          controller.addListener(() {
            if (controller.hostKey?.expected == null &&
                controller.hostKey != null) {
              controller.answerHostTrust(true);
            }
          });

          await controller.start(selected);
          expect(controller.phase, ConnectionPhase.connected);
          final origin = controller.uri!;
          await controller.setForeground(false);
          final interrupted = _waitFor(controller, ConnectionPhase.retrying);
          await fixture.send('drop');
          await interrupted;
          expect(controller.uri, origin);
          await controller.setForeground(true);
          expect(controller.phase, ConnectionPhase.connected);
          expect(controller.uri, origin);
          await controller.disconnect();
          expect(controller.phase, ConnectionPhase.idle);
          expect(controller.uri, isNull);
          await expectLater(
            Socket.connect(origin.host, origin.port),
            throwsA(isA<SocketException>()),
          );
        },
      );
    },
    skip: Platform.environment['ASTRBOT_SSH_TEST'] != '1'
        ? 'Enable ASTRBOT_SSH_TEST=1 with Paramiko installed'
        : false,
  );
}

Matcher failure(ConnectionProblem reason) => isA<ConnectionFailure>().having(
  (error) => error.problem,
  'problem',
  reason,
);

Future<void> _waitFor(ConnectionController controller, ConnectionPhase phase) {
  final result = Completer<void>();
  void listener() {
    if (controller.phase == phase && !result.isCompleted) result.complete();
  }

  controller.addListener(listener);
  listener();
  return result.future
      .timeout(const Duration(seconds: 8))
      .whenComplete(() => controller.removeListener(listener));
}

Future<void> _serve(HttpRequest request) async {
  final response = request.response;
  final path = request.uri.path;
  if (path == '/events') {
    response.headers.contentType = ContentType('text', 'event-stream');
    response.bufferOutput = false;
    response.write('data: ready\n\n');
    await response.flush();
    return;
  }
  if (path == '/ws') {
    final socket = await WebSocketTransformer.upgrade(request);
    await for (final message in socket) {
      socket.add(message);
    }
    return;
  }
  if (path == '/upload') {
    response.headers.set(
      'content-disposition',
      'attachment; filename=fixture.bin',
    );
    await response.addStream(request);
  } else if (path == '/protected') {
    response.statusCode = HttpStatus.unauthorized;
  } else {
    response.write(path);
  }
  await response.close();
}

class _Fixture {
  _Fixture(this.process, this.lines, this.port, this.privateKey, this.errors);

  final Process process;
  final StreamIterator<String> lines;
  final int port;
  final String privateKey;
  final Future<String> errors;

  static Future<_Fixture> start(int targetPort) async {
    final process = await Process.start(
      Platform.environment['ASTRBOT_TEST_PYTHON'] ?? 'python',
      ['-X', 'utf8', '-u', 'tool/ssh_fixture.py', '$targetPort'],
    );
    final errors = const Utf8Decoder(allowMalformed: true)
        .bind(process.stderr)
        .join();
    final lines = StreamIterator(
      const LineSplitter().bind(utf8.decoder.bind(process.stdout)),
    );
    if (!await lines.moveNext().timeout(const Duration(seconds: 20))) {
      throw StateError('Could not start SSH fixture: ${await errors}');
    }
    final ready = jsonDecode(lines.current) as Map<String, dynamic>;
    return _Fixture(
      process,
      lines,
      ready['port'] as int,
      ready['key'] as String,
      errors,
    );
  }

  Future<void> send(String command) async {
    process.stdin.writeln(command);
    if (!await lines.moveNext().timeout(const Duration(seconds: 8)) ||
        lines.current != 'ok') {
      throw StateError('SSH fixture did not acknowledge $command');
    }
  }

  Future<void> stop() async {
    await process.stdin.close();
    await lines.cancel();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    expect(code, 0, reason: await errors);
  }
}
