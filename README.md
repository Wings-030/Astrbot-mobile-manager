# AstrBot Mobile Manager

[简体中文](README_zh.md) · v0.1.0 · AGPL-3.0-or-later

AstrBot Mobile Manager is an independent, unofficial Android and iOS client for managing an existing AstrBot deployment. It opens the WebUI served by your AstrBot instance and keeps the original dashboard login, including any configured two-factor authentication.

The phone connects over the SSH service you already have. Keep the WebUI port private. The app requires no domain, HTTPS reverse proxy, VPN, or additional server process.

## Server requirements

- The phone must be able to reach the server's SSH port. The SSH account must be allowed to open local TCP forwards to the WebUI destination. For OpenSSH, check `AllowTcpForwarding` and any `PermitOpen` restrictions that apply to the account.
- The SSH server must be able to reach AstrBot's HTTP WebUI. The default destination is `127.0.0.1:6185` **as seen from the SSH server**. For Docker, a host mapping such as `127.0.0.1:6185:6185` keeps the published port on the host loopback. The process inside the container needs to listen on an interface reachable from the mapped port.
- Configure a strong dashboard password through AstrBot's normal setup, even when its HTTP listener is private. Use the dashboard's own authentication and TOTP settings.

## Connect

1. Enter the SSH host, port and username. Choose password authentication or import an OpenSSH or supported PEM private key and enter its passphrase when prompted.
2. Enter the WebUI destination host and port. Tap **保存并连接** (Save and connect).
3. Compare the shown SHA256 host-key fingerprint with the fingerprint from a trusted server console or administrator. On the SSH server, `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256` shows the Ed25519 fingerprint. Use the corresponding public-key file for the algorithm displayed by the app.
4. Sign in to AstrBot in the WebUI. The toolbar refreshes the page and opens the settings for editing, disconnecting and choosing a theme. The app supports one saved connection.
5. If a host key changes, verify the replacement independently. In **设置** (Settings), choose **重置主机指纹** (Reset host fingerprint), reconnect, and confirm the verified fingerprint.

## Tunnel and session

```text
WebView → 127.0.0.1:<device port> → SSH local forwarding → WebUI HTTP endpoint
```

An OS-assigned device port is used on the first connection. The listener is IPv4 loopback only. Each accepted connection gets a separate SSH direct-tcpip channel. The tunnel carries HTTP, WebSocket, SSE and file transfer bytes. It does not rewrite HTTP, issue a dashboard token or bundle AstrBot's WebUI source.

The app keeps the local origin and the WebView during automatic reconnect. It also attempts to rebind the saved port after a manual disconnect or restart. A different port, a changed destination, or clearing site data can require a fresh dashboard login. Once foregrounded, the app checks the SSH session and reconnects as needed. OS suspension can interrupt an ongoing upload or stream.

The dashboard destination uses HTTP over SSH. The phone-to-SSH-server leg is encrypted. If the configured destination is another host, the connection from the SSH server to that destination follows that network's HTTP security. The native app currently uses Simplified Chinese. WebUI language and appearance are controlled in AstrBot.

## Install a test build

In your GitHub repository, open **Actions**, select **Android test APK** or **iOS unsigned IPA**, then select **Run workflow** on a branch containing the workflow. Download the artifact from the completed run.

- **Android 7.0+ (API 24)** — Extract and install `app-debug.apk`. The APK is signed with a debug key. Updating over an existing installation requires the same signing key. GitHub runners may create a different key between runs.
- **iOS 15+** — Extract `astrbot-mobile-unsigned.ipa` and sign it with SideStore, Sideloadly, or your own Xcode signing setup before installing. Personal Apple IDs can be used with compatible sideloading tools. App re-signing with a different bundle identifier or signing team can affect access to existing Keychain data.

## Build and test

Use Flutter **3.50.1** (Dart 3.14), JDK 21, Android SDK platforms 35 and 36, Build Tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1 for Android. Use macOS and Xcode for iOS. GitHub Actions pins Flutter and uses the same locked Dart dependencies.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

On macOS, Swift Package Manager resolves the iOS plugin dependencies as part of the Flutter build.

```sh
flutter precache --ios
flutter build ios --release --no-codesign
python3 tool/package_ipa.py build/ios/iphoneos/Runner.app build/astrbot-mobile-unsigned.ipa
```

See [Contributing](CONTRIBUTING.md) for the SSH fixture, device test and manual acceptance checks.

## Scope and upstream

The MVP opens an HTTP WebUI served from a single AstrBot instance. Embedded top-level navigation stays on the tunnel origin. Android WebUI exports support a single download at a time up to 256 MiB. Some plugin pages can require browser capabilities beyond the embedded WebView.

The upstream projects and relevant documents are [AstrBot](https://github.com/AstrBotDevs/AstrBot), [AstrBot Desktop](https://github.com/AstrBotDevs/AstrBot-desktop), the [official site](https://astrbot.app/), the upstream [EULA](https://github.com/AstrBotDevs/AstrBot/blob/master/EULA.md) and [project notice](https://github.com/AstrBotDevs/AstrBot/blob/master/FIRST_NOTICE.md). This client is independent of AstrBotDevs. The upstream implementation was reviewed at [AstrBot f37e158](https://github.com/AstrBotDevs/AstrBot/tree/f37e158dc1a5b5f2d90515a937e1c1aabde6b4ce) and [AstrBot Desktop 32b0e69](https://github.com/AstrBotDevs/AstrBot-desktop/tree/32b0e693ca865276f8162bab9fdf7ecb08d11fa9).

This project is free and open-source under [AGPL-3.0-or-later](LICENSE). Publish the complete corresponding source alongside any binary distribution. See [Privacy](PRIVACY.md) and [Third-party notices](THIRD_PARTY_NOTICES.md).
