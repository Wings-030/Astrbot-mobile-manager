# Third-party notices

AstrBot Mobile Manager is licensed under [AGPL-3.0-or-later](LICENSE). The app opens a separate AstrBot deployment's WebUI over SSH. AstrBot, AstrBot Desktop and their source code, branding and web assets remain with their respective owners. See the [AstrBot license](https://github.com/AstrBotDevs/AstrBot/blob/master/LICENSE) and [AstrBot Desktop license](https://github.com/AstrBotDevs/AstrBot-desktop/blob/main/LICENSE).

## Flutter project template

Android and iOS project scaffolding originates from the Flutter 3.50.1 application template. Copyright 2014 The Flutter Authors. The Flutter SDK and template are provided under the [BSD 3-Clause license](https://github.com/flutter/flutter/blob/ae9b586f34a8443573f82ef57c3bf914a908cbf7/LICENSE).

The local test build's launcher artwork comes from AstrBotDevs' [AstrBot Desktop application icon](https://github.com/AstrBotDevs/AstrBot-desktop/blob/32b0e693ca865276f8162bab9fdf7ecb08d11fa9/src-tauri/icons/icon.png). The platform resources use resized versions of the upstream artwork. See the [upstream license](https://github.com/AstrBotDevs/AstrBot-desktop/blob/32b0e693ca865276f8162bab9fdf7ecb08d11fa9/LICENSE). AstrBot Mobile Manager identifies itself as an independent community client.

## App dependencies

The exact versions and hashes of the Dart packages are recorded in [pubspec.lock](pubspec.lock). Each package retains its original license and attribution, which Flutter also includes in its generated in-app license notices.

| Direct runtime dependency | License | Primary source |
| --- | --- | --- |
| Flutter, Material UI | BSD-3-Clause | [Flutter](https://github.com/flutter/flutter/blob/ae9b586f34a8443573f82ef57c3bf914a908cbf7/LICENSE), [material_ui](https://pub.dev/packages/material_ui/versions/1.11.1/license) |
| dartssh2 | MIT | [dartssh2](https://pub.dev/packages/dartssh2/versions/4.2.0/license) |
| flutter_secure_storage | BSD-3-Clause | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0/license) |
| file_selector | BSD-3-Clause | [file_selector](https://pub.dev/packages/file_selector/versions/1.1.0/license) |
| shared_preferences | BSD-3-Clause | [shared_preferences](https://pub.dev/packages/shared_preferences/versions/2.5.6/license) |
| url_launcher | BSD-3-Clause | [url_launcher](https://pub.dev/packages/url_launcher/versions/6.3.3/license) |
| webview_flutter and its Android and WKWebView implementations | BSD-3-Clause | [Flutter WebView packages](https://github.com/flutter/packages/tree/main/packages/webview_flutter) |

The locked Dart package licenses were reviewed. The additional license families found include BSD-2-Clause (e.g. asn1lib), MIT (e.g. pinenacl and Pointy Castle), and Apache-2.0 (e.g. material_color_utilities and portions of file_selector_android). These permissive terms are compatible with the project's AGPL v3 distribution when their notice conditions are preserved. Flutter engine and font components carry separate notices bundled by the Flutter tooling.

macOS/Xcode, WebKit, the Android SDK and system WebView come from their respective platform vendors. The build uses the Gradle toolchain and AndroidX libraries under their published terms. Paramiko and its dependencies run in a test-only Python subprocess and are absent from the app binaries. See [Paramiko's license](https://github.com/paramiko/paramiko/blob/main/LICENSE).


## Flutter template license text

```text
Copyright 2014 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
