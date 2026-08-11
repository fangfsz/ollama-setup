# Ollama 安装脚本（支持本地文件 + Mirror 加速）

支持本地文件检测和 GitHub Mirror 加速的 Ollama 安装脚本，适用于 Linux 和 Windows。

## 功能特性

- **本地文件检测**: 自动识别脚本同级目录下的安装文件，优先级最高
- **Mirror 加速**: 内置 48 个 GitHub 镜像节点，自动测速选择最优节点
- **智能下载**: 测速比较官网与 Mirror 速度，选择更快的下载源
- **版本兼容**: 自动回退机制，新版本使用 .tar.zst，旧版本使用 .tgz
- **详细日志**: 支持调试模式输出完整的安装流程日志

## 脚本说明

| 脚本                       | 平台        | 说明            |
| -------------------------- | ----------- | --------------- |
| `install-ollama-local.sh`  | Linux/macOS | Shell 脚本      |
| `install-ollama-local.ps1` | Windows     | PowerShell 脚本 |

## 使用方法

### 直接运行（自动检测）

```bash
# Linux/macOS
chmod +x install-ollama-local.sh
sudo ./install-ollama-local.sh

# Windows (PowerShell)
.\install-ollama-local.ps1
```

### 指定版本

```bash
# Linux/macOS
OLLAMA_VERSION=0.32.9 sudo ./install-ollama-local.sh

# Windows
$env:OLLAMA_VERSION = "0.32.9"
.\install-ollama-local.ps1
```

### 自定义 Mirror 列表

内置的 Mirror 可能会失效，可通过环境变量指定自定义 Mirror：

```bash
# Linux/macOS - 用空格分隔多个 Mirror
OLLAMA_MIRROR="https://gh-proxy.com https://fastgit.cc https://cdn.gh-proxy.com" \
  sudo ./install-ollama-local.sh

# Windows - 用空格分隔多个 Mirror
$env:OLLAMA_MIRROR = "https://gh-proxy.com https://fastgit.cc https://cdn.gh-proxy.com"
.\install-ollama-local.ps1
```

### 启用详细日志

```bash
# Linux/macOS
OLLAMA_DEBUG=1 sudo ./install-ollama-local.sh

# Windows (PowerShell)
$env:OLLAMA_DEBUG = "1"
.\install-ollama-local.ps1
```

会输出详细的安装流程日志，包括：

- `[BRANCH]` - 关键分支判断（如版本检测、本地文件检测、下载源选择）
- `[BRANCH-ERROR]` - 异常处理分支（如工具缺失、下载失败）
- 其他调试信息（如 Mirror 测速、文件大小等）

默认情况下（未设置 `OLLAMA_DEBUG`），仅显示主要步骤和关键信息。

### 本地文件使用

将安装文件放到脚本同级目录，脚本会自动检测并使用。

**文件名规则：** 本地文件名需要与下载URL中的文件名一致（不包含版本号）。

**Linux/macOS:**

```bash
# 文件名（无论是否指定版本，都是这个文件名）：
ollama-linux-amd64.tar.zst    # x86_64 架构（推荐）
ollama-linux-arm64.tar.zst    # ARM64 架构
ollama-linux-amd64.tgz        # 旧版本格式（兼容）
ollama-linux-arm64.tgz
```

**Windows:**

```bash
# 文件名（无论是否指定版本，都是这个文件名）：
OllamaSetup.exe
```

> 💡 本地文件优先级最高。如果本地文件名与下载URL中的文件名不匹配，脚本会从网络下载。

**JetPack 版本（Linux/Jetson）:**

- `ollama-linux-amd64-jetpack6.tar.zst`
- `ollama-linux-arm64-jetpack6.tar.zst`
- `ollama-linux-amd64-jetpack5.tar.zst`
- `ollama-linux-arm64-jetpack5.tar.zst`

## 内置 Mirror 列表（按速度排序）

| 响应时间 | Mirror 数量 | 示例                                         |
| -------- | ----------- | -------------------------------------------- |
| <500ms   | 2 个        | gh-proxy.com, ghfile.geekertao.top           |
| 500ms-1s | 3 个        | cdn.gh-proxy.com, gh.927223.xyz, ghproxy.net |
| 1-2s     | 8 个        | github.tbap.top, cdn.akaere.online, ...      |
| 2-4s     | 15 个       | github.chenc.dev, fastgit.cc, ...            |
| >4s      | 20 个       | 其他节点                                     |
| **总计** | **48 个**   |                                              |

> ⚠️ Mirror 可能会失效，建议收藏可靠的 Mirror 地址，出现下载问题时通过 `OLLAMA_MIRROR` 环境变量指定有效的 Mirror。

## 环境变量

| 变量                     | 说明                                     | 示例       | 平台  |
| ------------------------ | ---------------------------------------- | ---------- | ----- |
| `OLLAMA_VERSION`         | 指定 Ollama 版本                         | `0.32.9`   | 全部  |
| `OLLAMA_MIRROR`          | 自定义 Mirror 节点（支持多个，空格分隔） | 见下方说明 | 全部  |
| `OLLAMA_DEBUG`           | 启用详细日志                             | `1`        | 全部  |
| `OLLAMA_SKIP_SPEED_TEST` | 跳过 Mirror 测速，直接使用第一个         | `1`        | Linux |

### OLLAMA_MIRROR 用法

```bash
# 单个 Mirror
OLLAMA_MIRROR="https://gh-proxy.com" sudo ./install-ollama-local.sh

# 多个 Mirror（空格分隔，脚本会自动测速选择最优）
OLLAMA_MIRROR="https://gh-proxy.com https://fastgit.cc https://cdn.gh-proxy.com" \
  sudo ./install-ollama-local.sh
```

> 💡 提示：只需指定 Mirror 域名，脚本会自动拼接完整下载链接。多个 Mirror 时，脚本会测速后自动选择最快的节点。

## 下载优先级

脚本按以下优先级选择下载源：

1. **本地文件** - 检查脚本同级目录是否有同名文件（优先级最高）
2. **官网 vs Mirror** - 测速比较，选择更快的下载源
   - 如果官网速度快 → 使用官网下载
   - 如果 Mirror 速度快 → 使用最优 Mirror 下载

## 系统要求

### Linux/macOS

- curl, tar, zstd
- sudo 权限（用于安装）

### Windows

- PowerShell 3.0+
- 管理员权限（安装时需要）

## 安装依赖

### Linux/macOS - zstd 工具

```bash
# Debian/Ubuntu
sudo apt-get install zstd

# RHEL/CentOS/Fedora
sudo dnf install zstd

# Arch
sudo pacman -S zstd
```

## 故障排查

### 查看详细日志

```bash
# Linux/macOS
OLLAMA_DEBUG=1 sudo ./install-ollama-local.sh

# Windows PowerShell
$env:OLLAMA_DEBUG = "1"
.\install-ollama-local.ps1
```

日志会显示：

- 版本参数检测结果
- 本地文件检测状态
- 每个 Mirror 的测速结果
- 最终选择的下载源
- 安装过程中的每一步操作

### 自定义 Mirror 无效

如果内置 Mirror 全部失效，可以：

1. 访问 [gh-proxy.com](https://gh-proxy.com) 等网站获取新的 Mirror 地址
2. 使用 `OLLAMA_MIRROR` 环境变量指定新的 Mirror
3. 或直接下载安装包到脚本同级目录使用本地文件安装

### 本地文件未被识别

请确认文件名完全一致：

- Linux: `ollama-linux-amd64.tar.zst`（不含版本号）
- Windows: `OllamaSetup.exe`（不含版本号）
