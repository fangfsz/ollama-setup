#!/bin/sh
# This script installs Ollama on Linux and macOS.
# It detects the current operating system architecture and installs the appropriate version of Ollama.

# Wrap script in main function so that a truncated partial download doesn't end
# up executing half a script.
main() {

set -eu

red="$( (/usr/bin/tput bold || :; /usr/bin/tput setaf 1 || :) 2>&-)"
plain="$( (/usr/bin/tput sgr0 || :) 2>&-)"

# 检测调试模式
DEBUG_MODE="${OLLAMA_DEBUG:-0}"

# status 函数 - 始终显示（主要步骤）
status() { echo ">>> $*" >&2; }

# debug 函数 - 仅在 OLLAMA_DEBUG=1 时显示
debug() {
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "    $*" >&2
    fi
}

# 分支日志函数 - 仅在 OLLAMA_DEBUG=1 时显示
branch() {
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "    [BRANCH] $*" >&2
    fi
}

# 错误日志函数 - 仅在 OLLAMA_DEBUG=1 时显示
branch_error() {
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "    [BRANCH-ERROR] $*" >&2
    fi
}

error() { echo "${red}ERROR:${plain} $*" >&2; exit 1; }
warning() { echo "${red}WARNING:${plain} $*" >&2; }

TEMP_DIR=$(mktemp -d)
cleanup() { rm -rf $TEMP_DIR; }
trap cleanup EXIT

available() { command -v $1 >/dev/null; }
require() {
    local MISSING=''
    for TOOL in $*; do
        if ! available $TOOL; then
            MISSING="$MISSING $TOOL"
        fi
    done

    echo $MISSING
}

OS="$(uname -s)"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) error "Unsupported architecture: $ARCH" ;;
esac

VER_PARAM="${OLLAMA_VERSION:+?version=$OLLAMA_VERSION}"

###########################################
# Mirror 加速配置
###########################################

# 定义可用的Mirror列表（按测速结果排序，越快越前）
MIRROR_LIST="https://gh-proxy.com https://ghfile.geekertao.top https://cdn.gh-proxy.com https://gh.927223.xyz https://ghproxy.net https://github.tbap.top https://cdn.akaere.online https://tvv.tw https://jiashu.1win.eu.org https://github.dpik.top https://gh.bugdey.us.kg https://gh.dpik.top https://gh.felicity.ac.cn https://down.mxw.xx.kg https://down.mxw.qzz.io https://github.mxw.qzz.io https://gh.inkchills.cn https://github.chenc.dev https://gh.jjj.gv.uy https://gh.acmsz.top https://gh.b52m.cn https://gitproxy.mrhjx.cn https://gh.jasonzeng.dev https://gp.zkitefly.eu.org https://fastgit.cc https://gh.sixyin.com https://github.ednovas.xyz https://ghproxy.imciel.com https://github.xxlab.tech https://ghproxy.cxkpro.top https://ghfast.top https://git.669966.xyz https://ghp.keleyaa.com https://githubdog.com https://js.jiangss.shop https://ghproxy.monkeyray.net https://g.z321.cc.cd https://777.z321.cc.cd https://gg.z321.cc.cd https://g.blfrp.cn https://gh.noki.icu https://gh.my-website.ccwu.cc https://github.nswrz.cn https://xsadwsd.kdns.fr https://gh.qfmc0721.cc.cd https://gh.zhai.edu.pl https://gh.07150721.xyz https://ghproxy.felicity.land"

# 可通过环境变量覆盖默认Mirror顺序
if [ -n "${OLLAMA_MIRROR:-}" ]; then
    MIRROR_LIST="$OLLAMA_MIRROR"
fi

# 测速超时时间（秒）
SPEED_TEST_TIMEOUT=5

# 获取脚本所在目录（支持 curl ... | bash 方式执行）
# 尝试多种方法获取脚本目录
get_script_dir() {
    # 方法1：如果通过环境变量指定
    if [ -n "${OLLAMA_SCRIPT_DIR:-}" ]; then
        echo "$OLLAMA_SCRIPT_DIR"
        return
    fi
    
    # 方法2：如果 $0 是有效路径
    if [ -f "$0" ] && [ -n "$(dirname "$0")" ]; then
        (cd "$(dirname "$0")" && pwd)
        return
    fi
    
    # 方法3：尝试从 /proc 获取
    if [ -L "/proc/self/exe" ]; then
        local self_exe=$(readlink /proc/self/exe 2>/dev/null)
        if [ -n "$self_exe" ]; then
            (cd "$(dirname "$self_exe")" && pwd)
            return
        fi
    fi
    
    # 方法4：使用当前工作目录
    pwd
}

SCRIPT_DIR="$(get_script_dir)"

###########################################
# 本地文件检测与Mirror选择函数
###########################################

# 检查本地是否存在同名文件
# 会在脚本目录和当前目录都查找
# 返回值: 0=找到且有效, 1=未找到或无效
check_local_file() {
    local filename="$1"
    local remote_size="$2"
    
    # 优先检查脚本目录
    local local_path="$SCRIPT_DIR/$filename"
    debug "Checking script directory: $SCRIPT_DIR"
    
    if [ -f "$local_path" ]; then
        debug "Found in script directory: $local_path"
        # 检查文件大小
        local local_size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null)
        
        # 如果远程文件大小已知，进行大小匹配
        if [ -n "$remote_size" ] && [ "$remote_size" -gt 0 ]; then
            if [ "$local_size" -eq "$remote_size" ] 2>/dev/null; then
                debug "Size match: local=$local_size, remote=$remote_size"
                return 0
            else
                debug "Size mismatch: local=$local_size, remote=$remote_size, continuing..."
            fi
        fi
        
        # 如果大小不匹配或未知，只要有文件就尝试使用
        if [ "$local_size" -gt 0 ]; then
            debug "Using local file (size: $local_size bytes)"
            return 0
        fi
    fi
    
    # 备选：检查当前工作目录
    local cwd_path="$(pwd)/$filename"
    debug "Checking current directory: $(pwd)"
    
    if [ -f "$cwd_path" ]; then
        debug "Found in current directory: $cwd_path"
        local local_size=$(stat -c%s "$cwd_path" 2>/dev/null || stat -f%z "$cwd_path" 2>/dev/null)
        
        # 如果远程文件大小已知，进行大小匹配
        if [ -n "$remote_size" ] && [ "$remote_size" -gt 0 ]; then
            if [ "$local_size" -eq "$remote_size" ] 2>/dev/null; then
                debug "Size match: local=$local_size, remote=$remote_size"
                # 返回当前目录的路径
                echo "$cwd_path" > /dev/null
                return 0
            else
                debug "Size mismatch: local=$local_size, remote=$remote_size, continuing..."
            fi
        fi
        
        # 如果大小不匹配或未知，只要有文件就尝试使用
        if [ "$local_size" -gt 0 ]; then
            debug "Using local file from current directory (size: $local_size bytes)"
            return 0
        fi
    fi
    
    debug "Local file not found: $filename"
    return 1
}

# 测速并返回最优Mirror
# 参数1: 原始URL
# 返回: 最优Mirror前缀（不带尾部斜杠）
select_best_mirror() {
    local original_url="$1"
    local best_mirror=""
    local best_speed=0

    # 如果设置了跳过测速的环境变量，直接使用第一个可用Mirror
    if [ -n "${OLLAMA_SKIP_SPEED_TEST:-}" ]; then
        echo "$MIRROR_LIST" | awk '{print $1}' | tr -d ' '
        return
    fi

    status "Testing mirror speeds..."

    for mirror in $MIRROR_LIST; do
        mirror=$(echo "$mirror" | tr -d ' ')
        [ -z "$mirror" ] && continue

        local test_url="${mirror}/${original_url}"

        # 使用curl测速，获取连接时间
        local speed=$(curl -o /dev/null -s -w "%{speed_download}" \
            --connect-timeout "$SPEED_TEST_TIMEOUT" \
            --max-time "$SPEED_TEST_TIMEOUT" \
            "$test_url" 2>/dev/null || echo "0")

        # 解析速度值（bytes/s）
        speed=$(echo "$speed" | awk '{print int($1)}')

        if [ "$speed" -gt "$best_speed" ]; then
            best_speed="$speed"
            best_mirror="$mirror"
        fi
    done

    # 如果所有Mirror都失败，使用第一个作为默认
    if [ -z "$best_mirror" ]; then
        best_mirror=$(echo "$MIRROR_LIST" | awk '{print $1}' | tr -d ' ')
    fi

    echo "$best_mirror"
}

# 构建下载URL
# 参数1: 原始URL
# 返回: 完整下载URL
build_download_url() {
    local original_url="$1"

    debug "===== build_download_url() ====="
    debug "Input URL: $original_url"

    # 判断是否需要使用Mirror加速
    case "$original_url" in
        *github.com*)
            debug "[BRANCH] GitHub URL detected"
            
            # 提取文件名（去掉查询参数）
            local filename=$(basename "$original_url" | sed 's/\?.*//')
            debug "Extracted filename: $filename"

            # 优先检查本地文件 - 不需要等待远程响应
            local local_file=""
            
            # 检查脚本目录
            if [ -f "$SCRIPT_DIR/$filename" ]; then
                local_file="$SCRIPT_DIR/$filename"
                branch "LOCAL file found in script dir: $local_file"
                debug "Local file check PASSED"
            # 检查当前目录
            elif [ -f "$(pwd)/$filename" ]; then
                local_file="$(pwd)/$filename"
                branch "LOCAL file found in current dir: $local_file"
                debug "Local file check PASSED"
            fi
            
            if [ -n "$local_file" ]; then
                echo "LOCAL:$local_file"
                return
            fi
            branch "No local file found, fetching remote file size..."
            
            # 获取远程文件大小用于后续参考
            debug "Fetching remote file size..."
            local remote_size=$(curl -sI "$original_url" 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r')
            debug "Remote file size: $remote_size bytes"

            # 本地不存在，进行测速选择
            debug "No local file, starting Mirror speed test..."
            local best_mirror=$(select_best_mirror "$original_url")
            debug "Best mirror selected: $best_mirror"

            # 比较官网和Mirror速度
            debug "Comparing official GitHub speed with mirror..."
            local official_speed=$(curl -o /dev/null -s -w "%{speed_download}" \
                --connect-timeout "$SPEED_TEST_TIMEOUT" \
                --max-time "$SPEED_TEST_TIMEOUT" \
                "$original_url" 2>/dev/null || echo "0")

            official_speed=$(echo "$official_speed" | awk '{print int($1)}')

            local mirror_speed=$(curl -o /dev/null -s -w "%{speed_download}" \
                --connect-timeout "$SPEED_TEST_TIMEOUT" \
                --max-time "$SPEED_TEST_TIMEOUT" \
                "${best_mirror}/${original_url}" 2>/dev/null || echo "0")

            mirror_speed=$(echo "$mirror_speed" | awk '{print int($1)}')

            debug "Official speed: $official_speed bytes/s ($(echo "scale=2; $official_speed/1024" | bc 2>/dev/null || echo "$official_speed") KB/s)"
            debug "Mirror speed: $mirror_speed bytes/s ($(echo "scale=2; $mirror_speed/1024" | bc 2>/dev/null || echo "$mirror_speed") KB/s)"

            # 选择速度较快的
            if [ "$official_speed" -ge "$mirror_speed" ]; then
                branch "Choosing OFFICIAL GitHub (official speed >= mirror speed)"
                debug "Final URL: $original_url"
                echo "$original_url"
            else
                branch "Choosing MIRROR (mirror speed > official speed)"
                debug "Final URL: ${best_mirror}/${original_url}"
                echo "${best_mirror}/${original_url}"
            fi
            ;;
        *)
            # 非GitHub链接，直接返回
            branch "Non-GitHub URL, using directly"
            debug "Final URL: $original_url"
            echo "$original_url"
            ;;
    esac
}

###########################################
# macOS
###########################################

if [ "$OS" = "Darwin" ]; then
    NEEDS=$(require curl unzip)
    if [ -n "$NEEDS" ]; then
        status "ERROR: The following tools are required but missing:"
        for NEED in $NEEDS; do
            echo "  - $NEED"
        done
        exit 1
    fi

    DOWNLOAD_URL="https://ollama.com/download/Ollama-darwin.zip${VER_PARAM}"

    if pgrep -x Ollama >/dev/null 2>&1; then
        status "Stopping running Ollama instance..."
        pkill -x Ollama 2>/dev/null || true
        sleep 2
    fi

    if [ -d "/Applications/Ollama.app" ]; then
        status "Removing existing Ollama installation..."
        rm -rf "/Applications/Ollama.app"
    fi

    status "Downloading Ollama for macOS..."
    curl --fail --show-error --location --progress-bar \
        -o "$TEMP_DIR/Ollama-darwin.zip" "$DOWNLOAD_URL"

    status "Installing Ollama to /Applications..."
    unzip -q "$TEMP_DIR/Ollama-darwin.zip" -d "$TEMP_DIR"
    mv "$TEMP_DIR/Ollama.app" "/Applications/"

    if [ ! -L "/usr/local/bin/ollama" ] || [ "$(readlink "/usr/local/bin/ollama")" != "/Applications/Ollama.app/Contents/Resources/ollama" ]; then
        status "Adding 'ollama' command to PATH (may require password)..."
        mkdir -p "/usr/local/bin" 2>/dev/null || sudo mkdir -p "/usr/local/bin"
        ln -sf "/Applications/Ollama.app/Contents/Resources/ollama" "/usr/local/bin/ollama" 2>/dev/null || \
            sudo ln -sf "/Applications/Ollama.app/Contents/Resources/ollama" "/usr/local/bin/ollama"
    fi

    if [ -z "${OLLAMA_NO_START:-}" ]; then
        status "Starting Ollama..."
        open -a Ollama --args hidden
    fi

    status "Install complete. You can now run 'ollama'."
    exit 0
fi

###########################################
# Linux
###########################################

[ "$OS" = "Linux" ] || error 'This script is intended to run on Linux and macOS only.'

IS_WSL2=false

KERN=$(uname -r)
case "$KERN" in
    *icrosoft*WSL2 | *icrosoft*wsl2) IS_WSL2=true;;
    *icrosoft) error "Microsoft WSL1 is not currently supported. Please use WSL2 with 'wsl --set-version <distro> 2'" ;;
    *) ;;
esac

SUDO=
if [ "$(id -u)" -ne 0 ]; then
    # Running as root, no need for sudo
    if ! available sudo; then
        error "This script requires superuser permissions. Please re-run as root."
    fi

    SUDO="sudo"
fi

NEEDS=$(require curl awk grep sed tee xargs)
if [ -n "$NEEDS" ]; then
    status "ERROR: The following tools are required but missing:"
    for NEED in $NEEDS; do
        echo "  - $NEED"
    done
    exit 1
fi

# Function to download and extract with fallback from zst to tgz
download_and_extract() {
    local url_base="$1"
    local dest_dir="$2"
    local filename="$3"

    debug "===== download_and_extract() ====="
    debug "URL Base: $url_base"
    debug "Destination: $dest_dir"
    debug "Filename: $filename"

    # 确定要下载的完整URL（包括可能的版本参数）
    local full_url="${url_base}/${filename}"
    debug "Full URL (without format): $full_url"

    status "====== Download Source Selection ======"
    if [ -n "${OLLAMA_VERSION:-}" ]; then
        branch "Version specified: v$OLLAMA_VERSION"
        branch "Version parameter: $VER_PARAM"
        debug "OLLAMA_VERSION is set"
    else
        branch "No version specified, using LATEST"
        debug "OLLAMA_VERSION is not set, using LATEST"
    fi

    # 优先检查本地文件 - 不需要等待远程响应
    local zst_local=""
    local tgz_local=""
    
    debug "Checking for local files..."
    debug "Script dir: $SCRIPT_DIR"
    debug "Current dir: $(pwd)"
    
    # 检查脚本目录 - .tar.zst
    if [ -f "$SCRIPT_DIR/${filename}.tar.zst" ]; then
        zst_local="$SCRIPT_DIR/${filename}.tar.zst"
        branch "LOCAL .tar.zst found in script dir: $zst_local"
        debug "Local .tar.zst check PASSED"
    # 检查当前目录 - .tar.zst
    elif [ -f "$(pwd)/${filename}.tar.zst" ]; then
        zst_local="$(pwd)/${filename}.tar.zst"
        branch "LOCAL .tar.zst found in current dir: $zst_local"
        debug "Local .tar.zst check PASSED"
    fi
    
    # 检查脚本目录 - .tgz
    if [ -f "$SCRIPT_DIR/${filename}.tgz" ]; then
        tgz_local="$SCRIPT_DIR/${filename}.tgz"
        branch "LOCAL .tgz found in script dir: $tgz_local"
        debug "Local .tgz check PASSED"
    # 检查当前目录 - .tgz
    elif [ -f "$(pwd)/${filename}.tgz" ]; then
        tgz_local="$(pwd)/${filename}.tgz"
        branch "LOCAL .tgz found in current dir: $tgz_local"
        debug "Local .tgz check PASSED"
    fi

    # 针对tar.zst和tgz格式分别处理
    # 先检查zst格式
    local original_zst_url="${full_url}.tar.zst${VER_PARAM}"
    debug "Original .tar.zst URL: $original_zst_url"
    
    debug "Calling build_download_url() for .tar.zst..."
    local final_url=$(build_download_url "$original_zst_url")
    debug "build_download_url() returned: $final_url"

    # Check if .tar.zst is available
    debug "Checking if .tar.zst is available..."
    if curl --fail --silent --head --location "$original_zst_url" >/dev/null 2>&1 || \
       [ -n "$zst_local" ]; then
        # zst file exists - check if we have zstd tool
        debug "[BRANCH] .tar.zst availability check: PASSED"
        branch ".tar.zst available (file exists or local found)"
        branch "Selected format: .tar.zst"
        if ! available zstd; then
            debug "[BRANCH-ERROR] zstd tool check: FAILED"
            branch_error "zstd tool NOT available!"
            branch_error "Cannot extract .tar.zst format"
            error "This version requires zstd for extraction. Please install zstd and try again:
  - Debian/Ubuntu: sudo apt-get install zstd
  - RHEL/CentOS/Fedora: sudo dnf install zstd
  - Arch: sudo pacman -S zstd"
        fi
        debug "zstd tool check: PASSED"

        status "Downloading ${filename}.tar.zst"
        debug "Destination directory: $dest_dir"

        # 处理本地文件
        if [ -n "$zst_local" ]; then
            debug "[BRANCH] Using LOCAL .tar.zst file"
            branch "Using LOCAL .tar.zst file"
            status "Local file: $zst_local"
            debug "Extracting local file with zstd..."
            if ! zstd -d "$zst_local" -c | $SUDO tar -xf - -C "${dest_dir}"; then
                debug "[BRANCH-ERROR] Local .tar.zst extraction: FAILED"
                branch_error "Local .tar.zst extraction FAILED"
                error "Failed to extract local file: $zst_local"
            fi
            debug "Local .tar.zst extraction: SUCCESS"
            branch "Local .tar.zst extraction SUCCESS"
        else
            debug "[BRANCH] Using NETWORK download"
            branch "Using NETWORK download"
            status "Download URL: $final_url"
            debug "Starting download with curl and zstd pipe..."
            
            # 记录下载开始时间
            debug "Download start time: $(date '+%Y-%m-%d %H:%M:%S')"
            _download_start=$(date +%s)
            
            if ! curl --fail --show-error --location --progress-bar \
                "$final_url" 2>/dev/null | \
                zstd -d | $SUDO tar -xf - -C "${dest_dir}"; then
                # 记录失败时的耗时
                _download_end=$(date +%s)
                _download_duration=$((_download_end - _download_start))
                debug "[BRANCH-ERROR] NETWORK .tar.zst download/extraction FAILED (took ${_download_duration}s)"
                branch_error "NETWORK .tar.zst download/extraction FAILED"
                branch_error "Trying fallback to .tgz format..."
                # 继续执行回退逻辑
            else
                # 记录下载结束时间
                _download_end=$(date +%s)
                _download_duration=$((_download_end - _download_start))
                debug "Download end time: $(date '+%Y-%m-%d %H:%M:%S')"
                debug "Download duration: ${_download_duration} seconds"
                debug "NETWORK .tar.zst download/extraction: SUCCESS"
                branch "NETWORK .tar.zst download/extraction SUCCESS (${_download_duration}s)"
            fi
        fi
        debug "download_and_extract() returning (zst path)"
        return 0
    fi

    debug "[BRANCH] .tar.zst availability check: FAILED (404 or local not found)"
    branch ".tar.zst NOT available (404 or HEAD check failed)"
    branch "Falling back to .tgz format for older versions"
    branch "Selected format: .tgz"
    
    local original_tgz_url="${full_url}.tgz${VER_PARAM}"
    debug "Original .tgz URL: $original_tgz_url"
    
    debug "Calling build_download_url() for .tgz..."
    final_url=$(build_download_url "$original_tgz_url")
    debug "build_download_url() returned: $final_url"

    # Check if .tgz is available
    debug "Checking if .tgz is available..."
    if curl --fail --silent --head --location "$original_tgz_url" >/dev/null 2>&1 || \
       [ -n "$tgz_local" ]; then
        debug "[BRANCH] .tgz availability check: PASSED"
        branch ".tgz available (file exists or local found)"
    else
        debug "[BRANCH-ERROR] .tgz availability check: FAILED"
        branch_error ".tgz NOT available (404 or HEAD check failed)"
        branch_error "Neither .tar.zst nor .tgz format is available!"
        branch_error "URL: $original_tgz_url"
        error "No downloadable Ollama package found for your system."
    fi

    status "Downloading ${filename}.tgz"
    debug "Destination directory: $dest_dir"

    # 处理本地文件
    if [ -n "$tgz_local" ]; then
        debug "[BRANCH] Using LOCAL .tgz file"
        branch "Using LOCAL .tgz file"
        status "Local file: $tgz_local"
        debug "Extracting local file with tar..."
        if ! cat "$tgz_local" | $SUDO tar -xzf - -C "${dest_dir}"; then
            debug "[BRANCH-ERROR] Local .tgz extraction: FAILED"
            branch_error "Local .tgz extraction FAILED"
            error "Failed to extract local file: $tgz_local"
        fi
        debug "Local .tgz extraction: SUCCESS"
        branch "Local .tgz extraction SUCCESS"
    else
        debug "[BRANCH] Using NETWORK download"
        branch "Using NETWORK download"
        status "Download URL: $final_url"
        debug "Starting download with curl and tar pipe..."
        
        # 记录下载开始时间
        debug "Download start time: $(date '+%Y-%m-%d %H:%M:%S')"
        _download_start=$(date +%s)
        
        if ! curl --fail --show-error --location --progress-bar \
            "$final_url" 2>/dev/null | \
            $SUDO tar -xzf - -C "${dest_dir}"; then
            # 记录失败时的耗时
            _download_end=$(date +%s)
            _download_duration=$((_download_end - _download_start))
            debug "[BRANCH-ERROR] NETWORK .tgz download/extraction: FAILED (took ${_download_duration}s)"
            branch_error "NETWORK .tgz download/extraction FAILED"
            error "Failed to download or extract Ollama package."
        fi
        # 记录下载结束时间
        _download_end=$(date +%s)
        _download_duration=$((_download_end - _download_start))
        debug "Download end time: $(date '+%Y-%m-%d %H:%M:%S')"
        debug "Download duration: ${_download_duration} seconds"
        debug "NETWORK .tgz download/extraction: SUCCESS"
        branch "NETWORK .tgz download/extraction SUCCESS (${_download_duration}s)"
    fi
    debug "===== download_and_extract() COMPLETE ====="
}

for BINDIR in /usr/local/bin /usr/bin /bin; do
    echo $PATH | grep -q $BINDIR && break || continue
done
OLLAMA_INSTALL_DIR=$(dirname ${BINDIR})

debug "===== Main Installation Process ====="
debug "BINDIR: $BINDIR"
debug "OLLAMA_INSTALL_DIR: $OLLAMA_INSTALL_DIR"
debug "ARCH: $ARCH"

status "====== Installation Process Starting ======"
if [ -d "$OLLAMA_INSTALL_DIR/lib/ollama" ] ; then
    debug "[BRANCH] Old version detected"
    branch "Old version detected, cleaning up"
    status "Cleaning up old version at $OLLAMA_INSTALL_DIR/lib/ollama"
    $SUDO rm -rf "$OLLAMA_INSTALL_DIR/lib/ollama"
fi
status "Installing ollama to $OLLAMA_INSTALL_DIR"
$SUDO install -o0 -g0 -m755 -d $BINDIR
$SUDO install -o0 -g0 -m755 -d "$OLLAMA_INSTALL_DIR/lib/ollama"
status "====== Download Source Selection ======"
download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}"

if [ "$OLLAMA_INSTALL_DIR/bin/ollama" != "$BINDIR/ollama" ] ; then
    status "Making ollama accessible in the PATH in $BINDIR"
    $SUDO ln -sf "$OLLAMA_INSTALL_DIR/ollama" "$BINDIR/ollama"
fi

# Check for NVIDIA JetPack systems with additional downloads
if [ -f /etc/nv_tegra_release ] ; then
    if grep R36 /etc/nv_tegra_release > /dev/null ; then
        branch "NVIDIA JetPack R36 detected"
        download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}-jetpack6"
    elif grep R35 /etc/nv_tegra_release > /dev/null ; then
        branch "NVIDIA JetPack R35 detected"
        download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}-jetpack5"
    else
        warning "[BRANCH] Unsupported JetPack version detected.  GPU may not be supported"
    fi
fi

install_success() {
    status 'The Ollama API is now available at 127.0.0.1:11434.'
    status 'Install complete. Run "ollama" from the command line.'
}
trap install_success EXIT

# Everything from this point onwards is optional.

configure_systemd() {
    if ! id ollama >/dev/null 2>&1; then
        status "Creating ollama user..."
        $SUDO useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
    fi
    if getent group render >/dev/null 2>&1; then
        status "Adding ollama user to render group..."
        $SUDO usermod -a -G render ollama
    fi
    if getent group video >/dev/null 2>&1; then
        status "Adding ollama user to video group..."
        $SUDO usermod -a -G video ollama
    fi

    status "Adding current user to ollama group..."
    $SUDO usermod -a -G ollama $(whoami)

    status "Creating ollama systemd service..."
    cat <<EOF | $SUDO tee /etc/systemd/system/ollama.service >/dev/null
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=$BINDIR/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=$PATH"

[Install]
WantedBy=default.target
EOF
    SYSTEMCTL_RUNNING="$(systemctl is-system-running || true)"
    case $SYSTEMCTL_RUNNING in
        running|degraded)
            status "Enabling and starting ollama service..."
            $SUDO systemctl daemon-reload
            $SUDO systemctl enable ollama

            start_service() { $SUDO systemctl restart ollama; }
            trap start_service EXIT
            ;;
        *)
            warning "systemd is not running"
            if [ "$IS_WSL2" = true ]; then
                warning "see https://learn.microsoft.com/en-us/windows/wsl/systemd#how-to-enable-systemd to enable it"
            fi
            ;;
    esac
}

if available systemctl; then
    configure_systemd
fi

# WSL2 only supports GPUs via nvidia passthrough
# so check for nvidia-smi to determine if GPU is available
if [ "$IS_WSL2" = true ]; then
    if available nvidia-smi && [ -n "$(nvidia-smi | grep -o "CUDA Version: [0-9]*\.[0-9]*")" ]; then
        status "Nvidia GPU detected."
    fi
    install_success
    exit 0
fi

# Don't attempt to install drivers on Jetson systems
if [ -f /etc/nv_tegra_release ] ; then
    status "NVIDIA JetPack ready."
    install_success
    exit 0
fi

# Install GPU dependencies on Linux
if ! available lspci && ! available lshw; then
    warning "Unable to detect NVIDIA/AMD GPU. Install lspci or lshw to automatically detect and install GPU dependencies."
    exit 0
fi

check_gpu() {
    # Look for devices based on vendor ID for NVIDIA and AMD
    case $1 in
        lspci)
            case $2 in
                nvidia) available lspci && lspci -d '10de:' | grep -q 'NVIDIA' || return 1 ;;
                amdgpu) available lspci && lspci -d '1002:' | grep -q 'AMD' || return 1 ;;
            esac ;;
        lshw)
            case $2 in
                nvidia) available lshw && $SUDO lshw -c display -numeric -disable network | grep -q 'vendor: .* \[10DE\]' || return 1 ;;
                amdgpu) available lshw && $SUDO lshw -c display -numeric -disable network | grep -q 'vendor: .* \[1002\]' || return 1 ;;
            esac ;;
        nvidia-smi) available nvidia-smi || return 1 ;;
    esac
}

if check_gpu nvidia-smi; then
    branch "NVIDIA GPU installed (nvidia-smi detected)."
    exit 0
fi

if ! check_gpu lspci nvidia && ! check_gpu lshw nvidia && ! check_gpu lspci amdgpu && ! check_gpu lshw amdgpu; then
    branch "No NVIDIA/AMD GPU detected (CPU-only mode)."
    install_success
    warning "No NVIDIA/AMD GPU detected. Ollama will run in CPU-only mode."
    exit 0
fi

if check_gpu lspci amdgpu || check_gpu lshw amdgpu; then
    branch "AMD GPU detected (ROCm version)"
    download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}-rocm"

    install_success
    status "AMD GPU ready."
    exit 0
fi

CUDA_REPO_ERR_MSG="NVIDIA GPU detected, but your OS and Architecture are not supported by NVIDIA.  Please install the CUDA driver manually https://docs.nvidia.com/cuda/cuda-installation-guide-linux/"
# ref: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#rhel-7-centos-7
# ref: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#rhel-8-rocky-8
# ref: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#rhel-9-rocky-9
# ref: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#fedora
install_cuda_driver_yum() {
    status 'Installing NVIDIA repository...'
    
    case $PACKAGE_MANAGER in
        yum)
            $SUDO $PACKAGE_MANAGER -y install yum-utils
            if curl -I --silent --fail --location "https://developer.download.nvidia.com/compute/cuda/repos/$1$2/$(uname -m | sed -e 's/aarch64/sbsa/')/cuda-$1$2.repo" >/dev/null ; then
                $SUDO $PACKAGE_MANAGER-config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/$1$2/$(uname -m | sed -e 's/aarch64/sbsa/')/cuda-$1$2.repo
            else
                error $CUDA_REPO_ERR_MSG
            fi
            ;;
        dnf)
            if curl -I --silent --fail --location "https://developer.download.nvidia.com/compute/cuda/repos/$1$2/$(uname -m | sed -e 's/aarch64/sbsa/')/cuda-$1$2.repo" >/dev/null ; then
                $SUDO $PACKAGE_MANAGER config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/$1$2/$(uname -m | sed -e 's/aarch64/sbsa/')/cuda-$1$2.repo
            else
                error $CUDA_REPO_ERR_MSG
            fi
            ;;
    esac

    case $1 in
        rhel)
            status 'Installing EPEL repository...'
            # EPEL is required for third-party dependencies such as dkms and libvdpau
            $SUDO $PACKAGE_MANAGER -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$2.noarch.rpm || true
            ;;
    esac

    status 'Installing CUDA driver...'

    if [ "$1" = 'centos' ] || [ "$1$2" = 'rhel7' ]; then
        $SUDO $PACKAGE_MANAGER -y install nvidia-driver-latest-dkms
    fi

    $SUDO $PACKAGE_MANAGER -y install cuda-drivers
}

# ref: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#ubuntu
# ref: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#debian
install_cuda_driver_apt() {
    status 'Installing NVIDIA repository...'
    if curl -I --silent --fail --location "https://developer.download.nvidia.com/compute/cuda/repos/$1$2/$(uname -m | sed -e 's/aarch64/sbsa/')/cuda-keyring_1.1-1_all.deb" >/dev/null ; then
        curl -fsSL -o $TEMP_DIR/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/$1$2/$(uname -m | sed -e 's/aarch64/sbsa/')/cuda-keyring_1.1-1_all.deb
    else
        error $CUDA_REPO_ERR_MSG
    fi

    case $1 in
        debian)
            status 'Enabling contrib sources...'
            $SUDO sed 's/main/contrib/' < /etc/apt/sources.list | $SUDO tee /etc/apt/sources.list.d/contrib.list > /dev/null
            if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
                $SUDO sed 's/main/contrib/' < /etc/apt/sources.list.d/debian.sources | $SUDO tee /etc/apt/sources.list.d/contrib.sources > /dev/null
            fi
            ;;
    esac

    status 'Installing CUDA driver...'
    $SUDO dpkg -i $TEMP_DIR/cuda-keyring.deb
    $SUDO apt-get update

    [ -n "$SUDO" ] && SUDO_E="$SUDO -E" || SUDO_E=
    DEBIAN_FRONTEND=noninteractive $SUDO_E apt-get -y install cuda-drivers -q
}

if [ ! -f "/etc/os-release" ]; then
    error "Unknown distribution. Skipping CUDA installation."
fi

. /etc/os-release

OS_NAME=$ID
OS_VERSION=$VERSION_ID

PACKAGE_MANAGER=
for PACKAGE_MANAGER in dnf yum apt-get; do
    if available $PACKAGE_MANAGER; then
        break
    fi
done

if [ -z "$PACKAGE_MANAGER" ]; then
    error "Unknown package manager. Skipping CUDA installation."
fi

if ! check_gpu nvidia-smi || [ -z "$(nvidia-smi | grep -o "CUDA Version: [0-9]*\.[0-9]*")" ]; then
    case $OS_NAME in
        centos|rhel) install_cuda_driver_yum 'rhel' $(echo $OS_VERSION | cut -d '.' -f 1) ;;
        rocky) install_cuda_driver_yum 'rhel' $(echo $OS_VERSION | cut -c1) ;;
        fedora) [ $OS_VERSION -lt '39' ] && install_cuda_driver_yum $OS_NAME $OS_VERSION || install_cuda_driver_yum $OS_NAME '39';;
        amzn) install_cuda_driver_yum 'fedora' '37' ;;
        debian) install_cuda_driver_apt $OS_NAME $OS_VERSION ;;
        ubuntu) install_cuda_driver_apt $OS_NAME $(echo $OS_VERSION | sed 's/\.//') ;;
        *) exit ;;
    esac
fi

if ! lsmod | grep -q nvidia || ! lsmod | grep -q nvidia_uvm; then
    KERNEL_RELEASE="$(uname -r)"
    case $OS_NAME in
        rocky) $SUDO $PACKAGE_MANAGER -y install kernel-devel kernel-headers ;;
        centos|rhel|amzn) $SUDO $PACKAGE_MANAGER -y install kernel-devel-$KERNEL_RELEASE kernel-headers-$KERNEL_RELEASE ;;
        fedora) $SUDO $PACKAGE_MANAGER -y install kernel-devel-$KERNEL_RELEASE ;;
        debian|ubuntu) $SUDO apt-get -y install linux-headers-$KERNEL_RELEASE ;;
        *) exit ;;
    esac

    NVIDIA_CUDA_VERSION=$($SUDO dkms status | awk -F: '/added/ { print $1 }')
    if [ -n "$NVIDIA_CUDA_VERSION" ]; then
        $SUDO dkms install $NVIDIA_CUDA_VERSION
    fi

    if lsmod | grep -q nouveau; then
        status 'Reboot to complete NVIDIA CUDA driver install.'
        exit 0
    fi

    $SUDO modprobe nvidia
    $SUDO modprobe nvidia_uvm
fi

# make sure the NVIDIA modules are loaded on boot with nvidia-persistenced
if available nvidia-persistenced; then
    $SUDO touch /etc/modules-load.d/nvidia.conf
    MODULES="nvidia nvidia-uvm"
    for MODULE in $MODULES; do
        if ! grep -qxF "$MODULE" /etc/modules-load.d/nvidia.conf; then
            echo "$MODULE" | $SUDO tee -a /etc/modules-load.d/nvidia.conf > /dev/null
        fi
    done
fi

status "NVIDIA GPU ready."
install_success
}

main
