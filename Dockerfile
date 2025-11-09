# 1、使用 Debian Trixie 作为基础镜像
FROM debian:trixie

# 设置环境变量, 避免交互提示
ENV DEBIAN_FRONTEND=noninteractive

# 2、安装必要的工具(wget, tar, xz-utils), 用于下载和解压 ffmpeg
RUN apt update && \
    apt install -y --no-install-recommends \
    wget \
    xz-utils \
    ca-certificates \
    tzdata

# 3、将 ffmpeg 安装脚本拷贝到镜像中
COPY ffmpeg.sh /tmp/ffmpeg.sh

# 4、赋予脚本执行权限, 并运行它来安装 ffmpeg
RUN chmod +x /tmp/ffmpeg.sh && \
    /tmp/ffmpeg.sh

# 5、设置时区为: Asia/Shanghai
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 6、卸载安装时用到的临时工具和脚本, 减小镜像体积
RUN apt remove -y --purge \
    wget \
    xz-utils && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /tmp/ffmpeg.sh

# # 7、验证 ffmpeg 是否安装成功
# RUN ffmpeg -version

# 设置默认命令
CMD ["/bin/bash"]
