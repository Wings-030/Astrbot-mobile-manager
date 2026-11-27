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

- **Android 7.0+ (API 24)** — For local testing on an ARM64 phone, install `astrbot-mobile-manager-0.1.0-arm64.apk` (about 19 MiB). The **Android test APK** workflow currently produces the larger universal `app-debug.apk`. Both use debug signing keys. To update an existing installation, use the same signing key and a compatible version code.
- **iOS 15+** — The **iOS unsigned IPA** workflow is configured to produce `astrbot-mobile-unsigned.ipa` for signing with a tool such as SideStore or Sideloadly. You can also configure signing in Xcode and build the project for your device. Changing the signing team or bundle identifier can affect access to existing Keychain data.

To run a build on GitHub, first make sure the workflow file exists on the repository's default branch. Open **Actions**, select the workflow, choose a branch under **Run workflow**, and download the artifact after the run completes.

## Build and test

Use Flutter **3.50.1** (Dart 3.14), JDK 21, Android SDK platforms 35 and 36, Build Tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1 for Android. Use macOS and Xcode for iOS. GitHub Actions pins Flutter and uses the same locked Dart dependencies.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

The Android APKs are written to `build/app/outputs/flutter-apk/`. Use `app-arm64-v8a-release.apk` for an ARM64 phone. On macOS, Swift Package Manager resolves the iOS plugin dependencies as part of the Flutter build.

```sh
flutter precache --ios
flutter build ios --release --no-codesign
python3 tool/package_ipa.py build/ios/iphoneos/Runner.app build/astrbot-mobile-unsigned.ipa
```

### Verification

On Windows, `flutter analyze` and all 10 host tests passed with the SSH fixture enabled. Two Android emulator tests passed for secure storage and WebView session retention with a fixture page. The ARM64 Release APK passed signature verification. Sign-in, TOTP and file import/export against a real AstrBot instance are pending device verification. The iOS workflow and IPA packaging script are configured. macOS compilation and installation on an iPhone are pending.

`flutter test` skips the SSH fixture by default. To include it, install Paramiko 5.1.0 and set `ASTRBOT_SSH_TEST=1` before running the tests. On a connected mobile device or emulator, run `flutter test integration_test/webui_test.dart -d <device-id>`.

## Scope and upstream

The MVP opens an HTTP WebUI served from a single AstrBot instance. Embedded top-level navigation stays on the tunnel origin. Android WebUI exports support a single download at a time up to 256 MiB. Some plugin pages can require browser capabilities beyond the embedded WebView.

The upstream projects and relevant documents are [AstrBot](https://github.com/AstrBotDevs/AstrBot), [AstrBot Desktop](https://github.com/AstrBotDevs/AstrBot-desktop), the [official site](https://astrbot.app/), the upstream [EULA](https://github.com/AstrBotDevs/AstrBot/blob/master/EULA.md) and [project notice](https://github.com/AstrBotDevs/AstrBot/blob/master/FIRST_NOTICE.md). This client is independent of AstrBotDevs. The upstream implementation was reviewed at [AstrBot f37e158](https://github.com/AstrBotDevs/AstrBot/tree/f37e158dc1a5b5f2d90515a937e1c1aabde6b4ce) and [AstrBot Desktop 32b0e69](https://github.com/AstrBotDevs/AstrBot-desktop/tree/32b0e693ca865276f8162bab9fdf7ecb08d11fa9).

## License

This project is free and open-source under [AGPL-3.0-or-later](LICENSE). When distributing binaries, include the complete corresponding source, build instructions, [license](LICENSE), and [third-party notices](THIRD_PARTY_NOTICES.md). See the [privacy notice](PRIVACY.md).
