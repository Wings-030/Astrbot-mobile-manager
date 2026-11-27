# Privacy / 隐私说明

## English

AstrBot Mobile Manager uses the SSH server and WebUI you configure. It includes no advertising, analytics, telemetry, cloud accounts or synchronization service.

- SSH passwords, imported private keys, passphrases and saved host fingerprints are stored using iOS Keychain or Android Keystore-backed encrypted storage. The configured host, ports, SSH username, authentication method, theme and preferred loopback port are kept in application preferences.
- AstrBot's own sign-in data can persist in the system WebView's site storage. The app clears cookies, local storage and caches when the configured dashboard identity changes. **Settings → Clear local connection data** removes the saved SSH data and clears the WebView's sign-in data. An exported file remains at the destination you selected.
- The WebUI handles uploads. The page and its plugins can send requests to external services according to their implementation and your AstrBot configuration.
- Downloads are staged in the app's temporary directory before you select where to save them. If you choose cloud storage in the system document picker, that provider handles the file.
- Tapping a link in About opens your external browser.

## 简体中文

App 不提供广告、统计、遥测、云端账户或同步。SSH 密码、私钥、口令和主机指纹保存在 iOS Keychain 或 Android Keystore 支持的加密存储中。主机、端口、用户名、认证方式、主题与优先复用的回环端口保存在普通配置中。

AstrBot 登录数据由系统 WebView 保存。修改服务器目标时，App 清除 WebView 的 Cookie、本地存储和缓存。**设置 → 清除本机连接数据**删除 SSH 配置、凭据、主机指纹和 WebUI 登录数据。已导出的文件保留在你选定的位置。

上传由 WebUI 处理。页面和插件可以按其实现及 AstrBot 服务器配置向外部服务发起请求。

下载文件暂存在 App 的临时目录，随后由系统文件选择器保存到你选定的位置。如果你在文件选择器中选择云盘，文件由对应的存储服务处理。点击关于页面中的链接会打开系统浏览器。
