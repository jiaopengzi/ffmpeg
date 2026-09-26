# ffmpeg

为博客服务（`blog-server`）定制的**最小化、静态链接**的 FFmpeg 构建方案，面向 **HLS 视频转码** 场景（H.264 多码率切片、AES-128 加密、封面抽取），并以 Docker 镜像形式交付。

## 特性

- **精简体积**：以 `--disable-everything` 为起点，仅按需启用所需的复用器 / 解复用器 / 编解码器 / 滤镜，显著减小二进制体积。
- **静态链接**：静态编译 x264（`libx264.a`），并以 `--enable-static --disable-shared` 构建 FFmpeg，产物仅依赖 glibc 与 zlib 等基础库，可直接在 `debian:trixie-slim` 中运行。
- **多阶段构建**：编译环境（`debian:trixie`）与运行环境（`debian:trixie-slim`）分离，最终镜像仅包含 `ffmpeg` / `ffprobe` 两个可执行文件及 GPL 许可文本。
- **时区就绪**：最终镜像已安装 `tzdata` 并将时区设置为 `Asia/Shanghai`。

## 功能范围

| 类别 | 启用内容 |
| --- | --- |
| 程序 | `ffmpeg`、`ffprobe`（不含 `ffplay`） |
| 协议 | `file`、`pipe`、`crypto`（HLS AES-128 加密核心） |
| 复用器（输出） | `hls`、`segment`、`mp4`、`mpegts`、`image2` |
| 解复用器（输入） | `mov`、`matroska`、`mpegts`、`flv`、`avi` |
| 解码器 | `h264`、`hevc`、`aac`、`mp3`、`ac3`、`eac3`、`opus`、`vorbis`、`flac`、`pcm_s16le`、`dca`（DTS） |
| 编码器 | `libx264`（H.264）、`aac`、`png` |
| 滤镜 | `scale`（缩放）、`split`（多码率分流）、`aresample`（音频采样率/声道/采样格式转换） |
| 第三方库 | x264（GPL）、zlib（PNG 编码） |

> 注意：启用 `--enable-gpl` + `libx264`，最终产物受 **GPL** 许可约束。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| [Dockerfile](Dockerfile) | 多阶段构建定义：编译 FFmpeg 并生成精简运行镜像。 |
| [build.sh](build.sh) | 核心构建脚本：安装依赖 → 静态编译 x264 → 拉取指定 tag 的 FFmpeg 源码 → 精细化 `configure` → 编译安装 → 验证。 |

## 使用方法

### 方式一：Docker 镜像构建（推荐）

```bash
# 构建镜像
docker build -t blog-server:ffmpeg .

# 验证版本
docker run --rm blog-server:ffmpeg ffmpeg -version
docker run --rm blog-server:ffmpeg ffprobe -version
```

如需在其它镜像中复用，可直接从本镜像拷贝二进制：

```dockerfile
COPY --from=blog-server:ffmpeg /usr/local/bin/ffmpeg  /usr/local/bin/ffmpeg
COPY --from=blog-server:ffmpeg /usr/local/bin/ffprobe /usr/local/bin/ffprobe
```

> 目标镜像需基于 glibc 2.41 及以上（如 `debian:trixie` 系列）并包含 `zlib1g`，不适用于 alpine 等 musl 镜像。

### 方式二：本地/容器内源码编译

在 Debian（Trixie）环境中直接运行构建脚本（需 root 权限）：

```bash
chmod +x build.sh
./build.sh
```

可在脚本顶部修改 `FFMPEG_TAG`、`X264_COMMIT` 切换版本（如 `n8.1.2`、`n9.0.2` 等）。

## 版本信息

- FFmpeg 源码 tag：`n9.0.2`（可在 [build.sh](build.sh) 中调整）
- 基础镜像：`debian:trixie` / `debian:trixie-slim`
- x264：锁定 commit 静态编译（见 [build.sh](build.sh) 中的 `X264_COMMIT`）

## 许可证

- 本项目代码基于 [MIT License](LICENSE) 发布。
- 编译产物包含 x264 并启用了 `--enable-gpl`，最终 FFmpeg 二进制受 **GPL** 许可约束，请遵守相应条款。
- 镜像内 `/usr/local/share/licenses/ffmpeg/` 附带 GPL 许可文本及 `BUILD_INFO`（FFmpeg tag 与 x264 commit）。
