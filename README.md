# 系统状态监视器

一个轻量级的 macOS 状态栏应用，实时显示系统运行状态。

## 功能

在菜单栏显示以下信息：

| 指标 | 数据来源 | 说明 |
|------|---------|------|
| 向下箭头 下载速度 | `getifaddrs` | 显示实时下载速度，监控 en0-en4 接口 |
| 向上箭头 上传速度 | `getifaddrs` | 显示实时上传速度，监控 en0-en4 接口 |
| 硬盘图标 磁盘占用 | `NSURLResourceValues` | 显示根卷已用空间百分比 |
| 温度计图标 CPU 温度 | IOKit SMC | 读取 CPU 芯片温度 (°C) |
| 气流图标 风扇转速 | IOKit SMC | 读取风扇平均转速 (RPM) |

数据每秒刷新一次。

## 系统要求

- macOS 13 (Ventura) 或更高版本
- Intel 或 Apple Silicon Mac

> **注意**：CPU 温度和风扇转速通过 IOKit 访问 SMC（系统管理控制器）获取。
> 在 Apple Silicon Mac 上，SMC 访问可能需要额外的权限。如果显示 "N/A"，
> 请尝试从终端运行一次应用以观察权限提示。

## 构建

确保已安装 Xcode Command Line Tools：

```bash
xcode-select --install
```

然后运行构建脚本：

```bash
cd 系统状态监视器
bash build.sh
```

构建完成后，App 位于 `build/系统状态监视器.app`。

## 使用

### 方式一：直接运行

```bash
open "build/系统状态监视器.app"
```

### 方式二：安装到应用程序文件夹

将 `build/系统状态监视器.app` 拖入 `/Applications/` 文件夹。

### 设置开机自启

1. 打开 **系统设置** → **通用** → **登录项**
2. 点击 **+** 添加 `系统状态监视器.app`
3. 将其设置为后台运行

## 操作

- **左键点击** 状态栏图标：显示菜单
- **右键点击** 状态栏图标：显示菜单
- 菜单中包含 **关于** 和 **退出** 选项

## 技术实现

- **语言**：Swift 5.7+
- **框架**：AppKit、Foundation、IOKit
- **SMC 通信**：通过 `IOConnectCallStructMethod` 与 AppleSMC 服务交互
- **网络监控**：使用 `getifaddrs()` 读取网络接口字节计数，计算每秒差值
- **磁盘监控**：使用 `NSURL.resourceValues` 获取卷容量信息

## 文件结构

```
系统状态监视器/
├── Sources/
│   ├── main.swift                    # 应用入口
│   ├── StatusBarController.swift     # 状态栏管理
│   ├── Monitors/
│   │   ├── NetworkMonitor.swift      # 网络速度监控
│   │   ├── DiskMonitor.swift         # 磁盘使用监控
│   │   └── SMCMonitor.swift          # SMC 传感器监控
│   └── SMC/
│       └── SMCKit.swift              # SMC 通信库
├── Resources/
│   ├── AppIcon.icns                  # 应用图标
│   ├── AppIcon.iconset/              # 图标源尺寸
│   ├── AppIconPreview.png            # 图标预览
│   └── Info.plist                    # 应用配置 (LSUIElement=YES)
├── build.sh                          # 构建脚本
└── README.md
```

## 常见问题

**Q: CPU 温度/风扇转速显示 "N/A"？**

A: 通常是因为 SMC 访问失败。可能原因：
- 在 Apple Silicon Mac 上缺少必要权限
- 系统未加载 AppleSMC 驱动
- 尝试从终端手动运行 `./build/系统状态监视器.app/Contents/MacOS/SystemMonitor` 查看错误日志

**Q: 网络速度不准确？**

A: 应用监控 en0-en4 网络接口的字节计数器。如果使用其他接口（如 VPN 创建的 utun 接口），可能需要修改 `NetworkMonitor.swift` 中的 `trackedInterfaces`。

**Q: 如何退出应用？**

A: 右键点击状态栏图标，选择 **退出**。

## 许可证

MIT License
