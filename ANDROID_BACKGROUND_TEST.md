# LocalSend-x Android 最终版（2026-10-23）

用户已反馈：联想小新 Pad Pro 12.7 再次重启、首次解锁后运行正常。将当前 V3 功能定为最终版，仅调整 Android 应用名和常驻通知名称为 LocalSend-x。

- 最终 APK：`app/dist/LocalSend-x-arm64-final-2026-10-23.apk`；SHA-256 见同目录 `.apk.sha256`。
- 版本：1.18.2，ARM64 versionCode 673，可覆盖安装 V3（663）。
- 最终 APK SHA-256：`e6ba80835051bfb16b50ab61cc3ff391612cf7cfa33bf7c53cc0058b0a2a0a48`。
- 最终构建验证：修改的 Dart 文件分析通过；5 项后台接收单元测试通过；APK 签名验证通过且证书与 V3 相同；ZIP 和全部 5 个 ARM64 原生库通过 16 KB 对齐检查。重命名后的 APK 尚未在联想真机重新安装验证。
- 保留包名 `org.localsend.localsend_app.backgroundtest` 和原本地调试签名，确保测试版原有设置可延续。此包是个人使用的最终交付，不是上游官方签名发行包。签名私钥不提交到仓库。
- 构建命令：`powershell -ExecutionPolicy Bypass -File support/scripts/build_android_background_test.ps1`。需要项目指定的 Flutter、Android SDK/NDK、JDK 和 Rust/本机编译工具链；脚本默认构建号 67。
- 继续保持自动接收、通知允许、电池无限制；系统若提供自启动权限也需允许。
- 下文保留 V3 实现、测试及历史交付记录；真机成功为用户反馈，不代表所有厂商设备均已测试。

---

# Android 16 后台接收与开机自启测试（V3）

V3 在 V2 后台接收基础上，增加重启后首次解锁自动恢复接收。仅修改 Android 启动、引擎复用和无界面接收所需的代码，不修改网络协议或 Rust 核心。

## 交付文件

- APK：`app/dist/LocalSend-background-test-arm64-v3-2026-10-23.apk`。
- 校验文件：同目录下的 `.apk.sha256`。
- SHA-256：`5f12024f647aa7fa8ba4a9c3a24d41e7b07a7a4de8e837cdbf69b5e595f53cfa`（46,845,174 字节）。
- 应用版本：1.18.2；ARM64 拆分包 versionCode：663，可覆盖安装 V2 测试包，保留设置。

上一版（文件名不含 `v2`、versionCode 643）有启动错误，请使用修正版。Windows 上依赖准备曾因桌面插件符号链接权限失败而中断，之后跳过准备构建，造成 Android 的 `GeneratedPluginRegistrant` 未生成。Android 16 模拟器已复现注册类缺失及截图中的 `SharedPreferencesApi.getAll` 通道错误。修正版完整执行插件生成，并在构建脚本中增加失败即停止和注册文件检查；没有通过忽略设置读取错误来绕过问题。

模拟器进一步发现 `flutter_foreground_task` 9.2.2 的 Dart `stopWithTask=true` 会安装 Activity 可见性监听，按 Home 时即停止服务。修正版不设置这个 Dart 选项，只保留清单中的 `android:stopWithTask=true`，用于用户清理最近任务时停止服务。

## 方案与范围

- 原实现仅在传输开始后启动 `dataSync` 前台服务，最后一次传输结束即停止，不能保护锁屏后的空闲接收。
- 复用既有前台服务：接收服务器运行且开启“自动保存”或“仅收藏设备自动保存”时，保留通知、CPU/Wi-Fi 锁；增加组播锁，使局域网发现数据能交给现有发现模块处理。
- 使用 `connectedDevice` 服务类型，对应局域网设备交互；不再把长期等待放进受累计时限约束的 `dataSync` 服务。
- 关闭自动保存后，空闲保护停止；已有传输继续，全部传输结束后停止服务。关闭接收服务器也会取消空闲保护。
- 自动接收、收藏设备、PIN、文件保存位置等仍由原有逻辑决定。没有新增绕过确认的通道。
- 从最近任务中移除应用后停止服务；不尝试自动复活只有通知、没有接收服务器的进程。进程被系统杀死后需要重新打开应用。
- 通知使用现有翻译，空闲时显示接收、自动保存模式与设备名称，传输时显示进度。

`connectedDevice` 没有 `dataSync` 的六小时累计限制，但这不是永久运行保证。Doze、电池限制、厂商进程管理、Wi-Fi 中断、系统内存回收仍可能影响接收。前台服务和组播锁也会增加耗电。

## 安装和设置

测试构建是 arm64 Release 模式、使用本机 Android 调试证书签名；独立包名 `org.localsend.localsend_app.backgroundtest`，名称“LocalSend 后台测试”，可以与官方应用并存。不是商店发行包。

1. 测试前退出原版 LocalSend，避免两个实例争用同一个端口。无需卸载原版。
2. 打开测试版，为它设置容易辨认的设备名称。独立包名不会继承原版设置，需要重新选择保存目录、自动保存和收藏设备。
3. 开启自动保存；若启用仅收藏设备自动保存，先收藏发送端。允许通知，确认出现持续接收通知后再锁屏。
4. 在系统电池设置中，将**测试版**加入电池优化豁免名单／设为不限制后台活动；仅锁定最近任务不等同于获得 Doze 豁免。
5. vivo X200 Pro、华为 Mate40 Pro、联想小新 Pad Pro 12.7 的菜单随系统版本不同。检查应用电池管理、允许后台运行和最近任务锁定等设置，以设备实际显示为准。V3 具备首次解锁后开机自启；如果系统有“允许自启动”选项，也需要允许测试版自启动。
6. 发送端与接收端处于同一局域网，路由器不能启用客户端隔离。为排查问题，先使用默认端口并确认前台收发正常。

## 真机验收

每种设备分别记录系统版本、测试包版本、设置、锁屏时长、发现结果、接收结果。以下均需要真机执行，不能用自动化单元测试替代。

| 场景 | 操作与通过条件 |
| --- | --- |
| 前台基线 | 电脑和另一台安卓设备都能发现测试版，并成功发送文件。 |
| 短时锁屏 | 按 Home 后锁屏 5 分钟，在发送端重新打开 LocalSend／刷新设备列表，重新发现并发送新文件。 |
| 长时锁屏 | 拔掉充电器，静置锁屏 30～60 分钟、超过 6 小时、隔夜各测试一次；每次都重新发现并发起新的传输。 |
| 连续接收 | 第一批传输完成后继续锁屏，隔一段时间再发送第二、第三批，仍能接收。 |
| 收发并发 | 进行发送时接收另一批文件；关闭自动保存不应中断已开始的传输。 |
| 授权回归 | 仅收藏模式不能自动接收陌生设备；关闭自动保存后前台仍按原规则确认。若设置了 PIN，保留原验证行为。 |
| 关闭保护 | 空闲时关闭两种自动保存选项，通知消失；重新开启可恢复。清理最近任务或强行停止后，不应再宣称设备在线。 |
| 网络恢复 | Wi-Fi 断开后重新连回，检查重新发现和新传输；若失败，记录是否必须打开应用才能恢复。此项未新增网络重连机制。 |
| 文件完整性 | 对比发送端与接收端文件大小和 SHA-256；图片/视频也应测试，不能只凭通知显示完成判断。 |

发现通过必须是发送端重新发现当前接收端；缓存设备卡片、手工 IP 直连、只验证已经开始的传输继续完成，都不能替代该证据。

可选 ADB 诊断（需启用 USB 调试；测试结束恢复系统状态）：

```powershell
adb shell dumpsys activity services org.localsend.localsend_app.backgroundtest
adb shell dumpsys deviceidle whitelist
adb shell dumpsys wifi
adb shell dumpsys battery unplug
adb shell dumpsys deviceidle force-idle
# 在另一设备重新搜索并发送文件，然后恢复：
adb shell dumpsys deviceidle unforce
adb shell dumpsys battery reset
```

不要把 ADB 强制豁免当成普通用户已经完成了系统设置。验收时需要观察通知、真实服务、重新发现和文件结果。

## V3 开机自启

安装 V3 后先手动打开一次，确认通知权限、自动保存、保存目录和电池无限制设置。保持自动保存（或仅收藏设备自动保存）开启。随后重启设备、首次输入密码解锁，等待常驻接收通知出现；无需再次打开应用界面。从另一台设备重新发现该设备并发送新文件。

- 只接收 `BOOT_COMPLETED`：该广播在首次解锁、凭据存储可访问后送达。没有接收 `LOCKED_BOOT_COMPLETED` 或每次亮屏解锁的 `USER_PRESENT`。
- 原生引导前台服务先显示启动通知，创建一个 Flutter 引擎，读取原有配置，启动 Rust 接收服务器、发现监听与 V2 常驻服务，然后结束引导服务。失败或 60 秒内未完成时结束引导，不留只有通知的假接收状态。
- 用户之后打开界面时复用该引擎；不会创建第二个接收实例。正常手动启动仍沿用原流程。Android 文件/SAF 通道中不依赖 Activity 的原有方法移至 `AndroidReceiveChannel.kt`，供两种启动方式共用，文件保存算法不变。
- 没有界面时只处理原规则允许自动接受的文件；需要人工确认的请求拒绝，不能绕过收藏设备和 PIN 等原有校验。
- 关闭自动保存后，下一次重启不恢复接收。没有新增常驻重试、定时唤醒、卸载防护或后台被清理后复活功能。
- 必须保留通知和电池无限制设置；厂商可能另需允许自启动。系统“强行停止”后需要手动打开一次。具体厂商的开机广播投递仍需真机测试。

参考 Android 官方资料：

- [前台服务类型与 connectedDevice 权限](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [dataSync 累计运行时限](https://developer.android.com/develop/background-work/services/fgs/timeout)
- [Doze、电池优化豁免与测试](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [后台启动限制及开机广播例外](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)

## 验证记录

复现 APK 构建（需要已配置的 Flutter、Android SDK/NDK、Rust，以及 Windows 主机构建所需的 MSVC 工具链）：

```powershell
cd D:\Projects\localsend-x
powershell -NoProfile -ExecutionPolicy Bypass -File support/scripts/build_android_background_test.ps1
```

脚本在当前进程临时设置 `LOCALSEND_BACKGROUND_TEST=true`，只切换本次构建的包名、名称及签名；并设置 `FLUTTER_WINDOWS=false`，避免 Android 构建准备被 Windows 桌面符号链接权限阻断。先成功执行 `pub get`、检查 Android 插件注册，再执行 `--no-pub` 构建，不能只以依赖解析完成的信息判断准备成功。本机临时包装脚本 `app/build/build-background-apk.ps1` 额外设置从微软官方下载并校验的局部 MSVC 工具路径；不改变系统环境变量。

2026-10-22 已执行：

- `app`：`fvm flutter analyze --no-pub` 无问题；`fvm flutter test --no-pub` 88 项通过。
- `packages/localsend_isolates`：`fvm flutter analyze --no-pub lib test` 无问题；`fvm flutter test --no-pub` 23 项通过（含新增 5 项后台生命周期测试），4 项因未构建 Windows Rust 动态库而跳过。跳过项不记为通过。
- 修改的 Dart 文件通过格式检查，`git diff --check` 通过。
- 源码和测试分析不包括独立的 vendored Cargokit 构建工具；其自身开发依赖尚未完整解析，直接分析整个目录曾报缺依赖。APK 使用的 Cargokit runner 已成功解析运行依赖。

2026-10-23 构建及产物检查：

- ARM64 Release APK 构建成功；独立包名、应用名称与仅 `arm64-v8a` 架构均由最终 APK 检查确认。
- `apksigner verify --verbose --print-certs` 通过，使用本机 Android Debug 证书的 APK v2 签名；Release 模式未开启 debuggable。
- APK 内前台服务类型为 `connectedDevice`，声明相应服务权限、组播权限和 `stopWithTask=true`。
- `zipalign -c -P 16 4` 通过；包内全部 5 个原生库（包括 Flutter、Dart、Rust、JNI 和 datastore 库）的 ELF LOAD 段对齐均不小于 16 KB。
- 交付副本与构建产物 SHA-256 一致。
- 未连接上述三款真机，未执行真机锁屏收发验收。

启动故障修复后补充验证：

- 在 Android 16 / API 36 模拟器（Google APIs x86_64，支持 ARM64 转译）安装实际交付的 ARM64 APK。旧版复现 `GeneratedPluginRegistrant` 缺失和相同设置通道错误；修正版覆盖安装成功，能进入接收页面，设置初始化、发现 isolate 和 HTTPS 接收服务器正常启动。
- 退出进程重新打开可读取已有设置；开启自动保存后升级至最终构建，设置仍保留，前台服务自动启动。
- 最终构建按 Home、熄屏后，`dumpsys activity services` 显示 `isForeground=true`、`types=0x00000010`，`dumpsys power` 显示服务的 `PARTIAL_WAKE_LOCK`，Wi-Fi 组播锁存在。该检查是模拟器短时生命周期验证，不代表局域网发现或长时间 Doze 验收通过。
- 再次运行后台生命周期测试：5 项通过。最终 APK 再次通过签名、ZIP/ELF 16 KB 对齐检查，版本号 653，交付副本校验一致。
- 本机诊断证据保存在 `app/build/startup-before.log`、`startup-v2-final.log`、`background-service-v2.txt` 和 `app/build-background-test-v2.log`。

锁屏发现、Doze、厂商后台策略和隔夜接收尚待上述三款真机验证。自动化测试中的平台服务使用测试替身，不能证明 Android 系统实际保活。

## V3 验证记录（2026-10-23）

- Android 16 / API 36 模拟器上对实际交付的 ARM64 APK 执行真实重启并设置测试 PIN。首次解锁前用户为 `RUNNING_LOCKED`，没有应用进程或服务；输入 PIN 后为 `RUNNING_UNLOCKED`，未打开应用，服务器启动，日志记录 `Receiver ready: true`，引导服务退出，常驻服务 `isForeground=true`。
- 在未打开界面时通过 ADB 端口转发和带客户端证书的 HTTPS 协议发送 3 个 34,816 字节测试文件。准备及上传均 HTTP 200；接收端三个保存文件的 SHA-256 均与发送内容一致。该测试证明接收链路，不视为真实局域网重新发现证据。
- 随后打开界面可正常进入接收/设置页面；进程 PID 不变，服务器没有重复启动。按 Home 并再次锁屏后服务仍在，HTTPS info 返回 200。
- 关闭自动保存后再次真实重启，首次解锁后没有接收服务、端口不提供服务（`v3-disabled-after-boot.txt`）。测试 PIN 已清除。
- 开机无 Activity 时，现有前台服务插件检查通知权限会抛出已捕获的警告；在已授权通知的测试配置下不影响启动和收发，不会在开机时弹出权限请求界面。
- `app` 现有 88 项测试、后台生命周期 5 项测试通过；本次变更的三个 Dart 文件静态分析无问题。APK 构建、v2 签名、ZIP 和全部五个 ELF 库的 16 KB 对齐检查通过。
- 模拟器证据：`app/build/v3-before-unlock.txt`、`v3-after-unlock.txt`、`v3-boot.log`、`v3-headless-transfers.log`，构建日志 `app/build-background-test-v3.log`。未连接用户真机，开机自启和局域网发现仍需在联想平板实际重启后确认。
