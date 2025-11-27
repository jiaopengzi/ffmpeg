#!/bin/bash
# FilePath    : ffmpeg_build.sh

set -e

# ========== 用户可配置参数 ==========
# 版本: n8.0.1
FFMPEG_TAG="n8.0.1"

# 临时构建目录
BUILD_DIR="/tmp/ffmpeg_build"

# 源码目录
SRC_DIR="$BUILD_DIR/src"

# ========== 第一步:安装编译依赖 ==========
echo "【1/6】正在安装编译所需的依赖包..."

apt update

# 基础构建工具
apt install -y \
    build-essential \
    git \
    wget \
    yasm \
    nasm \
    pkg-config \
    autoconf \
    automake \
    libtool \
    cmake

# 安装 zlib 开发包 (用于 PNG/JPEG 图像支持)
apt install -y zlib1g-dev

# 注意:不通过 apt 安装 libx264-dev！
# 因为它只提供动态库 (.so), 而我们需要静态库 (.a) 用于生成无依赖二进制.
# x264 自行静态编译.

# ========== 第二步:静态编译 x264(用于 H.264 编码)==========
echo "【2/6】正在静态编译 x264(用于 HLS 转码)..."

X264_SRC="$SRC_DIR/x264"
if [ -d "$X264_SRC" ]; then
    rm -rf "$X264_SRC"
fi

git clone --depth=1 https://code.videolan.org/videolan/x264.git "$X264_SRC"
cd "$X264_SRC"

# 静态编译 x264:仅生成 libx264.a, 不生成命令行工具或动态库
./configure \
    --enable-static \
    --disable-cli \
    --disable-opencl \
    --disable-win32thread \
    --prefix=/usr/local

make -j "$(nproc)"
make install

# 查看静态库是否安装成功
if [ ! -f "/usr/local/lib/libx264.a" ]; then
    echo "❌ x264 静态库编译失败！"
    exit 1
fi

echo "✅ x264 静态库已安装至 /usr/local/lib/libx264.a"

# ========== 第三步:准备 ffmpeg 源码 ==========
echo "【3/6】正在准备源码目录..."

mkdir -p "$SRC_DIR"
cd "$SRC_DIR"

# 移除旧的 ffmpeg 目录(如果存在)
if [ -d "ffmpeg" ]; then
    echo "发现旧的 ffmpeg 目录, 正在删除并重新克隆..."
    rm -rf ffmpeg
fi

# 克隆仓库(指定 tag)
git clone --depth=1 --branch "$FFMPEG_TAG" https://git.ffmpeg.org/ffmpeg.git ffmpeg

echo "✅ 已成功检出 FFmpeg tag: $FFMPEG_TAG"

# ========== 第四步:配置 FFmpeg 编译选项(最小化 + 静态 + 满足你的命令需求)==========
echo "【4/6】正在配置 FFmpeg 编译选项..."

cd "$SRC_DIR/ffmpeg"

# 核心原则:
# - 使用 --disable-everything 然后精准启用所需组件
# - 启用 libx264(H.264 编码)、AAC(音频)、PNG(封面)
# - 支持 HLS 加密(crypto 协议)、多码率转码(split/scale)、TS 切片
# - 纯静态构建, 确保可直接复制到 debian-slim 容器运行

declare -a configure_args=(
    # ========== 基础路径与全局策略 ==========
    "--prefix=/usr/local"  # 安装路径
    "--disable-everything" # 禁用所有组件,精简体积
    "--disable-autodetect" # 禁用自动探测外部库
    "--disable-network"    # 按需开启协议

    # ========== 核心程序与库 ==========
    "--enable-ffmpeg"     # 启用 ffmpeg 命令行工具
    "--enable-ffprobe"    # 启用 ffprobe(获取视频元信息)
    "--disable-ffplay"    # 不需要播放器
    "--enable-avcodec"    # 编解码核心库
    "--enable-avformat"   # 容器格式支持
    "--enable-swresample" # 音频重采样
    "--enable-swscale"    # 视频缩放
    "--enable-avutil"     # 工具库

    # ========== 协议(Protocols)==========
    "--enable-protocol=file"   # 本地文件读写
    "--enable-protocol=pipe"   # 管道支持
    "--enable-protocol=crypto" # HLS AES-128 加密核心(读写 .key 和加密 .ts)

    # ========== 复用器(Muxers)—— 输出格式 ==========
    "--enable-muxer=hls"     # 生成 HLS 播放列表(含加密)
    "--enable-muxer=segment" # 分段切片(.ts)
    "--enable-muxer=mp4"     # MP4 输出(备用)
    "--enable-muxer=mpegts"  # MPEG-TS 封装(HLS 片段底层格式)
    "--enable-muxer=image2"  # 图像序列输出(封面 PNG/JPEG)

    # ========== 解复用器(Demuxers)—— 输入格式 ==========
    "--enable-demuxer=mov"      # .mp4, .mov, .m4a, .m4v
    "--enable-demuxer=matroska" # MKV
    "--enable-demuxer=mpegts"   # TS 流
    "--enable-demuxer=flv"      # FLV
    "--enable-demuxer=avi"      # AVI

    # ========== 解码器(Decoders)—— 用于 ffprobe 和封面抽取 ==========
    "--enable-decoder=h264" # H.264 视频解码(输入)
    "--enable-decoder=hevc" # H.265/HEVC 解码(支持读取 HEVC 视频, 但不编码)
    "--enable-decoder=aac"  # AAC 音频解码
    "--enable-decoder=mp3"  # MP3 音频解码

    # ========== 编码器(Encoders)—— 根据你的命令需求 ==========
    "--enable-encoder=libx264" # H.264 编码(HLS 多码率转码必需)
    "--enable-encoder=aac"     # AAC 音频编码(使用 FFmpeg 内置 encoder)
    "--enable-encoder=png"     # PNG 图像编码(封面输出)

    # ========== 滤镜(Filters)—— 多码率 split 和封面缩放 ==========
    "--enable-filter=scale" # 视频缩放(1080p/720p 转码)
    "--enable-filter=split" # 视频流分发([0:v]split=2[v1][v2])

    # ========== 解析器与比特流过滤器(Parser & BSF)==========
    "--enable-parser=h264"          # H.264 流解析
    "--enable-parser=hevc"          # HEVC 流解析
    "--enable-parser=aac"           # AAC 音频解析
    "--enable-bsf=h264_mp4toannexb" # MP4 to Annex B(TS 封装必需)
    "--enable-bsf=hevc_mp4toannexb" # HEVC 的等效转换

    # ========== 静态链接与体积优化 ==========
    "--enable-static"     # 生成静态二进制
    "--disable-shared"    # 禁用动态库
    "--enable-small"      # 优化体积(启用内部 size-oriented 代码路径)
    "--disable-debug"     # 移除调试符号
    "--disable-doc"       # 不编译文档
    "--disable-htmlpages" # 禁用 HTML 文档
    "--disable-manpages"  # 禁用 man 手册
    "--disable-podpages"  # 禁用 POD 文档
    "--disable-txtpages"  # 禁用纯文本文档
    "--disable-symver"    # 减少符号版本信息

    # ========== 关闭非必要功能(避免隐式依赖)==========
    "--disable-iconv"   # 禁用字符编码转换
    "--disable-libxcb"  # 禁用 X11 截屏支持
    "--disable-xlib"    # 禁用 X11
    "--disable-sdl2"    # 禁用 SDL(ffplay 依赖)
    "--disable-vaapi"   # 禁用 VAAPI 硬件加速
    "--disable-vdpau"   # 禁用 VDPAU
    "--disable-cuda"    # 禁用 CUDA
    "--disable-opencl"  # 禁用 OpenCL
    "--disable-bzlib"   # 禁用 bz2
    "--disable-lzma"    # 禁用 xz/lzma
    "--disable-openssl" # crypto 协议使用内置 AES, 无需 OpenSSL
    "--disable-gnutls"  # 禁用 GnuTLS
    "--disable-libsrt"  # 禁用 SRT 协议
    "--disable-libssh"  # 禁用 SSH/SFTP

    # ========== 第三方库支持 ==========
    "--enable-gpl"     # 启用 GPL 组件(如 x264)
    "--enable-libx264" # 启用 x264 编码器(必须已静态安装 libx264.a)
    "--enable-zlib"    # 启用 zlib (PNG/JPEG 支持)

    # ========== 编译与链接标志 —— 拆开写, 不要用引号包裹 ==========
    "--extra-cflags=-I/usr/local/include" # 告诉编译器在哪里找 x264 头文件
    "--extra-cflags=-Os"                  # 优化代码体积
    "--extra-cflags=-ffunction-sections"  # 每个函数单独生成一个段, 便于链接时裁剪未使用代码
    "--extra-cflags=-fdata-sections"      # 同上, 但针对数据段
    "--extra-cflags=-fno-unwind-tables"   # 不生成异常处理相关表数据, 减少体积
    "--extra-ldflags=-L/usr/local/lib"    # 告诉链接器在哪里找 x264 静态库
    "--extra-libs=-lm -lpthread"          # 显式链接必要系统库(动态)
    "--extra-ldflags=-Wl,--gc-sections"   # 链接时去除未使用的函数和数据段
)

# 进行配置
./configure "${configure_args[@]}"

# ========== 第五步:编译与安装 ==========
echo "【5/6】正在编译 FFmpeg (使用 $(nproc) 个线程)..."

make -j "$(nproc)"

echo "【6/6】正在安装 FFmpeg 到 /usr/local..."

make install

# 更新动态链接库缓存
ldconfig

# ========== 第六步:验证结果 ==========
FFMPEG_BIN=$(which ffmpeg || echo "/usr/local/bin/ffmpeg")
FFPROBE_BIN=$(which ffprobe || echo "/usr/local/bin/ffprobe")

# 判断文件是否存在
if [ ! -x "$FFMPEG_BIN" ]; then
    echo "❌ ffmpeg 可执行文件未找到！尝试查找..."
    find /usr/local -name ffmpeg -type f
    exit 1
fi

echo ""
echo "🎉 FFmpeg (tag: $FFMPEG_TAG) 已成功安装！"
echo ""

# 给 ffmpeg 和 ffprobe 可执行权限
chmod +x "$FFMPEG_BIN"
chmod +x "$FFPROBE_BIN"

# 验证是否为静态二进制
echo "🔍 检查 ffmpeg 是否为静态链接:"
if ldd "$FFMPEG_BIN" 2>&1 | grep -q "not a dynamic executable"; then
    echo "✅ ffmpeg 是完全静态链接！"
elif ldd "$FFMPEG_BIN" 2>&1 | grep -q "statically linked"; then
    echo "✅ ffmpeg 标记为静态链接"
else
    echo "⚠️ 警告:ffmpeg 包含动态依赖:"
    ldd "$FFMPEG_BIN"
    echo "💡 提示:这是正常的(依赖 glibc), 但只要不依赖外部 .so 即可在容器中运行."
fi

echo ""
echo "📄 ffmpeg 版本信息:"
"$FFMPEG_BIN" -version

echo ""
echo "📄 ffprobe 版本信息:"
"$FFPROBE_BIN" -version
