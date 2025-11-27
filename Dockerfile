# 镜像创建命令: docker build -t blog-server:ffmpeg .

# 1、使用 Debian Trixie 作为编译环境
FROM debian:trixie-slim AS builder

# 设置环境变量, 避免交互提示
ENV DEBIAN_FRONTEND=noninteractive

# 2、将 build 安装脚本拷贝到镜像中
COPY build.sh /tmp/build.sh

# 3、赋予脚本执行权限, 执行 build
RUN chmod +x /tmp/build.sh && \
    /tmp/build.sh

# 验证版本信息
RUN ffmpeg -version
RUN ffprobe -version

# 4、使用 Debian Trixie-slim 作为最终镜像
FROM debian:trixie-slim

# 设置环境变量, 避免交互提示
ENV DEBIAN_FRONTEND=noninteractive

# 5、安装 tzdata 用于设置时区, 设置时区为: Asia/Shanghai
# 卸载安装时用到的临时工具和脚本, 减小镜像体积
RUN apt update && \
    apt install -y --no-install-recommends \
    tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# 6、从编译环境中复制 ffmpeg 和 ffprobe 到最终镜像
COPY --from=builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=builder /usr/local/bin/ffprobe /usr/local/bin/ffprobe

# 设置执行权限
RUN chmod +x /usr/local/bin/ffmpeg && \
    chmod +x /usr/local/bin/ffprobe


# 设置默认命令
CMD ["/bin/bash"]
