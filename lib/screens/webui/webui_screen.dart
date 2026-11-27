// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'web_downloads.dart';

class WebUiScreen extends StatefulWidget {
  const WebUiScreen({
    super.key,
    required this.origin,
    required this.online,
    required this.refresh,
  });

  final Uri origin;
  final bool online;
  final ValueNotifier<int> refresh;

  static Future<void> clearWebsiteData() async {
    final browser = WebViewController();
    await WebViewCookieManager().clearCookies();
    await browser.clearLocalStorage();
    await browser.clearCache();
  }

  @override
  State<WebUiScreen> createState() => _WebUiScreenState();
}

class _WebUiScreenState extends State<WebUiScreen> {
  late final WebViewController _browser;
  AndroidDownloads? _downloads;
  Uri? _lastPage;
  bool _ready = false;
  bool _failed = false;
  bool _loading = true;
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _browser = WebViewController(
      onPermissionRequest: (request) => unawaited(request.deny()),
    );
    widget.refresh.addListener(_refresh);
    unawaited(_setup());
  }

  Future<void> _setup() async {
    try {
      await _browser.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _browser.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isDashboardUri(widget.origin, uri)) {
              return widget.online
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            // Subframes are left to the dashboard's own policy. External main
            // frames never share this browser instance with dashboard credentials.
            return !request.isMainFrame
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _failed = false;
              });
            }
          },
          onUrlChange: (url) {
            final page = Uri.tryParse(url.url ?? '');
            if (page != null && isDashboardUri(widget.origin, page)) {
              _lastPage = page;
            }
            unawaited(_updateHistory());
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loading = false);
            unawaited(_updateHistory());
            final page = Uri.tryParse(url);
            if (page != null && isDashboardUri(widget.origin, page)) {
              unawaited(_downloads?.installScript());
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) _showPageFailure();
          },
        ),
      );
      if (!mounted) return;
      final platform = _browser.platform;
      if (platform is AndroidWebViewController) {
        await platform.setAllowFileAccess(false);
        await platform.setGeolocationEnabled(false);
        await platform.setOnShowFileSelector((params) async {
          if (!widget.online) return [];
          try {
            return await webFiles.invokeListMethod<String>('pickFiles', {
                  'accept': params.acceptTypes,
                  'multiple': params.mode == FileSelectorMode.openMultiple,
                }) ??
                [];
          } on PlatformException {
            _message('无法打开系统文件选择器。');
            return [];
          }
        });
        if (!mounted) return;
        final downloads = _downloads = AndroidDownloads(
          _browser,
          platform.webViewIdentifier,
          widget.origin,
          isActive: () => mounted && widget.online,
          message: _message,
        );
        await downloads.attach();
      } else if (platform is WebKitWebViewController) {
        await platform.setAllowsBackForwardNavigationGestures(true);
        await webFiles.invokeMethod<void>('attach', {
          'id': platform.webViewIdentifier,
          'port': widget.origin.port,
        });
      }
      if (!mounted) return;
      _ready = true;
      if (widget.online) await _browser.loadRequest(widget.origin);
    } catch (_) {
      _showPageFailure();
    }
  }

  void _showPageFailure() {
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _updateHistory() async {
    if (!mounted) return;
    try {
      final canGoBack = await _browser.canGoBack();
      if (mounted && _canGoBack != canGoBack) {
        setState(() => _canGoBack = canGoBack);
      }
    } on PlatformException {
      // The native view may have been released by the OS.
    }
  }

  @override
  void didUpdateWidget(WebUiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.online && !oldWidget.online && (_failed || _lastPage == null)) {
      _refresh();
    }
  }

  void _refresh() {
    if (!widget.online || !mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    if (!_ready) {
      unawaited(_setup());
      return;
    }
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final page = await _browser.currentUrl();
      final url = Uri.tryParse(page ?? '');
      if (!mounted || !widget.online) return;
      if (url != null &&
          isDashboardUri(widget.origin, url) &&
          _lastPage != null) {
        await _browser.reload();
      } else {
        await _browser.loadRequest(_lastPage ?? widget.origin);
      }
    } catch (_) {
      _showPageFailure();
    }
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_refresh);
    _downloads?.dispose();
    final platform = _browser.platform;
    if (platform is WebKitWebViewController) {
      unawaited(
        webFiles
            .invokeMethod<void>('detach', {'id': platform.webViewIdentifier})
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_canGoBack || !widget.online,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _canGoBack && widget.online) unawaited(_browser.goBack());
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _browser),
        if (_loading && widget.online)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
        if (_failed && widget.online)
          Material(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('WebUI 页面加载失败'),
                  TextButton(onPressed: _refresh, child: const Text('重新加载')),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
