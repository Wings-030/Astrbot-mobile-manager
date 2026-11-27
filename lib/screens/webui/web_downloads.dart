// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const webFiles = MethodChannel('app.astrbotmobile/web_files');

bool isDashboardUri(Uri origin, Uri uri) =>
    uri.scheme == 'http' &&
    uri.host == origin.host &&
    uri.port == origin.port &&
    uri.userInfo.isEmpty;

class AndroidDownloads {
  AndroidDownloads(
    this.browser,
    this.id,
    this.origin, {
    required this.isActive,
    required this.message,
  });

  static const _limit = 256 * 1024 * 1024;
  static const _chunkLimit = 128 * 1024;
  static final _views = <int, AndroidDownloads>{};

  final WebViewController browser;
  final int id;
  final Uri origin;
  final bool Function() isActive;
  final void Function(String) message;
  final _nonce = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  var _queue = Future<void>.value();
  Directory? _staging;
  RandomAccessFile? _blob;
  String? _filename;
  int _bytes = 0;
  bool _busy = false;
  bool _disposed = false;
  HttpClient? _http;
  Timer? _blobTimeout;

  Future<void> attach() async {
    _views[id] = this;
    webFiles.setMethodCallHandler((call) async {
      if (call.method != 'attachment') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final view = _views[args['id']];
      if (view != null) unawaited(view._attachment(args));
    });
    await browser.addJavaScriptChannel(
      'AstrBotFileExport',
      onMessageReceived: (event) {
        if (event.message.length > _chunkLimit * 2 || _disposed) return;
        _queue = _queue.then((_) => _blobMessage(event.message));
      },
    );
    await webFiles.invokeMethod<void>('attach', {
      'id': id,
      'port': origin.port,
    });
  }

  Future<void> installScript() async {
    try {
      await browser.runJavaScript(
        _exportScript.replaceFirst('__NONCE__', jsonEncode(_nonce)),
      );
    } on PlatformException {
      // Navigation may have already discarded this document.
    }
  }

  Future<void> _blobMessage(String raw) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['nonce'] != _nonce || _disposed) return;
      if (data['kind'] == 'error') {
        if (_blob != null) await _clean();
        message('文件过大或无法读取。');
        return;
      }
      if (!isActive()) {
        if (_blob != null) await _clean();
        await _ack(false);
        return;
      }
      switch (data['kind']) {
        case 'start':
          final size = data['size'] as int;
          if (_busy || size < 0 || size > _limit) {
            message('请完成当前下载，或选择较小的文件。');
            await _ack(false);
            return;
          }
          _busy = true;
          _filename = _safeName(data['name'] as String);
          _blob = await (await _newFile()).open(mode: FileMode.write);
          _bytes = 0;
          _restartBlobTimeout();
          await _ack(true);
        case 'chunk':
          final file = _blob;
          if (file == null) {
            await _ack(false);
            return;
          }
          final bytes = base64Decode(data['data'] as String);
          _bytes += bytes.length;
          if (bytes.length > _chunkLimit || _bytes > _limit) {
            throw const FormatException();
          }
          await file.writeFrom(bytes);
          _restartBlobTimeout();
          await _ack(true);
        case 'end':
          final file = _blob;
          if (file == null) return;
          _blobTimeout?.cancel();
          _blob = null;
          final path = _staging!.path;
          final name = _filename!;
          await file.close();
          await _ack(true);
          await _save(File('$path/download'), name);
          await _clean();
      }
    } catch (_) {
      if (_blob != null || _http == null) await _clean();
      message('下载未能保存。');
      await _ack(false);
    }
  }

  void _restartBlobTimeout() {
    _blobTimeout?.cancel();
    _blobTimeout = Timer(const Duration(seconds: 20), () {
      _queue = _queue.then((_) => _blob == null ? null : _clean());
    });
  }

  Future<void> _ack(bool success) async {
    if (_disposed) return;
    try {
      await browser.runJavaScript('window.__astrBotFileAck?.($success)');
    } on PlatformException {
      // The WebView may have navigated away during the export.
    }
  }

  Future<void> _attachment(Map<String, dynamic> args) async {
    final url = Uri.tryParse(args['url'] as String? ?? '');
    if (_disposed ||
        !isActive() ||
        url == null ||
        !isDashboardUri(origin, url)) {
      return;
    }
    if (_busy) {
      message('请完成当前下载。');
      return;
    }
    _busy = true;
    final http = _http = HttpClient()..findProxy = (_) => 'DIRECT';
    const timeout = Duration(seconds: 20);
    try {
      final request = await http.getUrl(url).timeout(timeout);
      request.followRedirects = false;
      final cookie = args['cookie'] as String?;
      final userAgent = args['userAgent'] as String?;
      if (cookie != null && cookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      if (userAgent != null) {
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200 || response.contentLength > _limit) {
        throw const FormatException();
      }
      final file = await _newFile();
      final output = await file.open(mode: FileMode.write);
      try {
        var size = 0;
        await for (final chunk in response.timeout(timeout)) {
          size += chunk.length;
          if (size > _limit || _disposed) throw const FormatException();
          await output.writeFrom(chunk);
        }
      } finally {
        await output.close();
      }
      await _save(file, _safeName(args['filename'] as String? ?? 'download'));
    } catch (_) {
      message('下载失败。请检查连接或文件大小。');
    } finally {
      http.close(force: true);
      _http = null;
      await _clean();
    }
  }

  Future<File> _newFile() async {
    final folder = _staging = await Directory.systemTemp.createTemp(
      'astrbot-export-',
    );
    return File('${folder.path}/download');
  }

  Future<void> _save(File file, String name) async {
    if (_disposed || !isActive()) return;
    final saved = await webFiles.invokeMethod<bool>('saveFile', {
      'path': file.path,
      'name': name,
    });
    if (saved == true) message('文件已保存。');
  }

  Future<void> _clean() async {
    _blobTimeout?.cancel();
    final file = _blob;
    final folder = _staging;
    _blob = null;
    _staging = null;
    try {
      await file?.close();
      await folder?.delete(recursive: true);
    } on FileSystemException {
      // The OS can reclaim the app's private temporary cache.
    } finally {
      _busy = false;
    }
  }

  static String _safeName(String input) {
    final name = input.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    return name.isEmpty || name == '.' || name == '..'
        ? 'download'
        : String.fromCharCodes(name.runes.take(180));
  }

  void dispose() {
    _disposed = true;
    _views.remove(id);
    final http = _http;
    http?.close(force: true);
    if (http == null) _queue = _queue.then((_) => _clean());
  }
}

// Android WebView cannot hand a blob: URL to its normal download listener.
const _exportScript = r'''
(() => {
  if (window.__astrBotFileExportInstalled) return;
  window.__astrBotFileExportInstalled = true;
  const nonce = __NONCE__;
  let active = false;

  function post(kind, fields = {}) {
    AstrBotFileExport.postMessage(JSON.stringify({ nonce, kind, ...fields }));
  }

  function send(kind, fields) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        delete window.__astrBotFileAck;
        resolve(false);
      }, 15000);
      window.__astrBotFileAck = (ok) => {
        clearTimeout(timer);
        delete window.__astrBotFileAck;
        resolve(ok);
      };
      post(kind, fields);
    });
  }

  async function exportBlob(url, name) {
    if (active) return;
    active = true;
    try {
      // Start fetch before the dashboard can revoke its object URL.
      const blob = await (await fetch(url)).blob();
      if (!(await send('start', { name, size: blob.size }))) return;
      for (let start = 0; start < blob.size; start += 65536) {
        const bytes = new Uint8Array(await blob.slice(start, start + 65536).arrayBuffer());
        if (!(await send('chunk', { data: btoa(String.fromCharCode(...bytes)) }))) return;
      }
      await send('end');
    } catch {
      post('error');
    } finally {
      active = false;
    }
  }

  function intercept(anchor) {
    if (!(anchor instanceof HTMLAnchorElement) || !anchor.hasAttribute('download')) return false;
    if (!anchor.href.startsWith('blob:' + location.origin + '/')) return false;
    void exportBlob(anchor.href, anchor.download || 'download');
    return true;
  }

  const click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (!intercept(this)) click.call(this);
  };
  addEventListener('click', (event) => {
    if (intercept(event.target.closest?.('a[download]'))) event.preventDefault();
  }, true);
})();
''';
