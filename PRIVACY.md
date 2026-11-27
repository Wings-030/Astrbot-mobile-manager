# Privacy / 隐私说明

AstrBot Mobile Manager uses the SSH server and WebUI you configure. It includes no advertising, analytics, telemetry, cloud accounts or synchronization service.

- SSH passwords, imported private keys, passphrases and saved host fingerprints are stored using iOS Keychain or Android Keystore-backed encrypted storage. The configured host, ports, SSH username, authentication method, theme and preferred loopback port are kept in application preferences.
- AstrBot's own sign-in data can persist in the system WebView's site storage. The app clears cookies, local storage and caches when the configured dashboard identity changes. **Settings → Clear local connection data** removes the saved SSH data and clears the WebView's sign-in data. An exported file remains at the destination you selected.
- Uploads go to AstrBot. Downloads are staged in the app's temporary directory before you select where to save them. A system document picker may offer cloud storage providers that you installed.
- The dashboard or its plugins can load resources and make network requests according to the configuration of your AstrBot instance. The app opens About links in your external browser only when you tap them.

App 不提供广告、统计、遥测、云端账户或同步。SSH 密码、私钥、口令和主机指纹保存在 iOS Keychain 或 Android Keystore 支持的加密存储中。主机、端口、用户名、认证方式、主题与优先复用的回环端口保存在普通配置中。

AstrBot 登录数据由系统 WebView 保存。修改服务器目标时，App 清除 WebView 的 Cookie、本地存储和缓存。**设置 → 清除本机连接数据**删除 SSH 配置、凭据、主机指纹和 WebUI 登录数据。已导出的文件保留在你选定的位置。

上传文件发送到 AstrBot。下载文件暂存在 App 的临时目录，随后由系统文件选择器保存到你选定的位置。AstrBot 页面和插件的网络行为由其内容和服务器配置决定。点击关于页面中的链接会打开系统浏览器。
