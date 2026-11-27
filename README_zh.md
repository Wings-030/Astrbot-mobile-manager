# AstrBot Mobile Manager

[English](README.md) · v0.1.0 · AGPL-3.0-or-later

AstrBot Mobile Manager 是一个独立的非官方社区客户端，用于在 Android 和 iOS 上管理已部署的 AstrBot。App 直接打开服务器上的 AstrBot WebUI，继续使用 AstrBot 的登录、权限验证和已配置的双因素认证。

手机直接连接服务器已有的 SSH 服务。AstrBot 管理端口无需对公网开放，也无需配置域名、HTTPS 反向代理、VPN 或额外部署服务。

## 服务器要求

- 手机必须能够访问服务器的 SSH 端口。SSH 账户必须允许向 WebUI 目标进行本地 TCP 转发。OpenSSH 用户可检查适用于该账户的 `AllowTcpForwarding` 和 `PermitOpen` 设置。
- SSH 服务器必须能访问 AstrBot 的 HTTP WebUI。默认目标是 **SSH 服务器视角**的 `127.0.0.1:6185`。Docker 部署可以使用 `127.0.0.1:6185:6185` 将 WebUI 端口仅映射到宿主机回环地址。容器内的进程需要监听映射可以访问的接口。
- 请通过 AstrBot 的正常初始化流程设置强密码，按需要启用 TOTP，并继续使用 AstrBot 自己的登录机制。

## 使用

1. 填写 SSH 主机、端口和用户名。选择密码认证，或导入 OpenSSH 或受支持的 PEM 私钥并填写口令。
2. 填写 WebUI 的目标地址和端口，点击 **保存并连接**。
3. 将 App 显示的 SHA256 主机指纹与服务器控制台或管理员提供的指纹核对。在 SSH 服务器上运行 `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256` 可以查看 Ed25519 指纹。其他算法需选择相应的主机公钥文件。
4. 在 WebUI 中登录 AstrBot。工具栏可刷新页面，设置中可修改服务器、断开连接或切换浅色、深色与系统主题。初版支持一份连接配置。
5. 发现主机指纹变化时，先通过可信渠道确认新指纹。确认是服务器更换了密钥，再进入 **设置 → 重置主机指纹**，重新连接并确认。

## 隧道与会话

```text
WebView → 127.0.0.1:<手机本地端口> → SSH 本地端口转发 → AstrBot HTTP WebUI
```

首次连接由操作系统分配可用端口。App 仅监听 IPv4 回环地址，每个本地 TCP 连接使用独立的 SSH direct-tcpip 通道。HTTP、WebSocket、SSE 和文件请求使用同一条 SSH 连接，并保留 WebUI 原有的登录流程。

自动重连时保留本地监听端口和当前 WebView。手动断开或重启后也会优先复用之前的端口。如果端口被占用、更换了目标服务器或清除了 WebUI 数据，可能需要重新登录。App 回到前台时检查 SSH 会话，必要时恢复连接。系统挂起 App 时，正在进行的上传或流式请求可能中断。

手机与 SSH 服务器之间的通信经过 SSH 加密。若 WebUI 部署在另一台主机，SSH 服务器到该主机的最后一段遵循该网络的 HTTP 安全条件。WebUI 的主题与语言在 AstrBot 中选择。

## 安装

在你的 GitHub 仓库中打开 **Actions**，选择 **Android test APK** 或 **iOS unsigned IPA**，在包含工作流的分支点击 **Run workflow**。构建成功后从该次运行的 **Artifacts** 下载。

- **Android 7.0 及以上（API 24）** — 解压并安装 `app-debug.apk`。测试包使用调试密钥，只有签名一致才能覆盖安装。不同 GitHub Runner 生成的调试签名可能不同。
- **iOS 15 及以上** — 解压 `astrbot-mobile-unsigned.ipa`。用 SideStore、Sideloadly 或 Xcode 的签名流程完成签名后安装。使用支持个人 Apple ID 的自签工具可进行真机测试。签名团队或 Bundle ID 改变后，之前的 Keychain 数据可能无法读取。

## 开发与构建

使用 **Flutter 3.50.1**（Dart 3.14）。Android 需要 JDK 21、Android SDK 平台 35 和 36、Build Tools 36.0.0、NDK 28.2.13676358 和 CMake 3.22.1。iOS 构建需要 macOS 和 Xcode。GitHub Actions 使用同一 Flutter 版本及锁定依赖。

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

在 macOS 上执行以下命令。Flutter 在构建过程中使用 Swift Package Manager 解析 iOS 插件依赖。

```sh
flutter precache --ios
flutter build ios --release --no-codesign
python3 tool/package_ipa.py build/ios/iphoneos/Runner.app build/astrbot-mobile-unsigned.ipa
```

SSH 集成测试、移动端测试和真机验收项见 [贡献指南](CONTRIBUTING.md)。

## 初版范围与上游

初版支持一个 AstrBot 实例的 HTTP WebUI。内嵌浏览器的顶层页面限于当前隧道地址。Android 一次可导出一个最多 256 MiB 的 WebUI 文件。个别插件页面可能依赖独立浏览器中的额外能力。

上游项目和文档包括 [AstrBot](https://github.com/AstrBotDevs/AstrBot)、[AstrBot Desktop](https://github.com/AstrBotDevs/AstrBot-desktop)、[AstrBot 官方网站](https://astrbot.app/)、[官方最终用户许可协议](https://github.com/AstrBotDevs/AstrBot/blob/master/EULA.md)与[项目声明](https://github.com/AstrBotDevs/AstrBot/blob/master/FIRST_NOTICE.md)。本项目为独立开发的社区客户端。开发时核对的上游版本为 [AstrBot f37e158](https://github.com/AstrBotDevs/AstrBot/tree/f37e158dc1a5b5f2d90515a937e1c1aabde6b4ce)与 [AstrBot Desktop 32b0e69](https://github.com/AstrBotDevs/AstrBot-desktop/tree/32b0e693ca865276f8162bab9fdf7ecb08d11fa9)。

项目采用 [AGPL-3.0-or-later](LICENSE) 开源许可。发布二进制时请同时提供完整的对应源代码和构建流程。另见[隐私说明](PRIVACY.md)及[第三方许可](THIRD_PARTY_NOTICES.md)。
