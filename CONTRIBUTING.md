# Contributing

Keep changes small and keep the SSH, storage and tunnel code independent of the embedded browser. Verify behavior through the app's normal connection flow. File and network tests should use local fixtures or an AstrBot instance you are authorized to manage.

## Checks

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

The same tests can use a real, ephemeral SSH server and HTTP fixture on the local development machine. Install Paramiko in your Python environment, then enable the fixture.

```sh
python -m pip install paramiko==5.1.0
ASTRBOT_SSH_TEST=1 flutter test
```

In PowerShell, set `$env:ASTRBOT_SSH_TEST = '1'` before running `flutter test`. Set `ASTRBOT_TEST_PYTHON` to a Python executable path if needed. Test credentials are synthetic and files with usable credentials must stay out of the repository.

When an Android or iOS device or simulator is connected, run the native WebView integration test.

```sh
flutter test integration_test/webui_test.dart -d <device-id>
```

For acceptance against an actual AstrBot instance, confirm that dashboard authentication and TOTP behave as they do in the browser. Open model, plugin, persona and log pages. Import a supported file, export a persona (Blob download), download a backup (HTTP attachment), and verify the saved files. Check both Android and iOS. Confirm that an SSH disconnect, Wi-Fi to cellular switch, and a return from background preserve the dashboard route and login where possible. Test a renamed or replaced host key, repeat with a refused forward, then close the connection and verify that the local listener is gone. Test Keychain/Keystore persistence after a process relaunch and verify deletion from the settings screen.

## Reporting problems

Include the app, AstrBot, OS and WebView versions, the steps to reproduce and the visible error. Remove credentials, tokens, private keys, server addresses and sensitive screenshots. Use a small pull request with test evidence and an English title such as `fix: handle an unavailable dashboard`.
