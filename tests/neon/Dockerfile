# Image for tests/neon/run.sh: an ARM cross compiler, what QEMU needs to
# build, and FFmpeg with x264 to make the test streams.
FROM debian:bookworm
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential gcc-arm-linux-gnueabihf libc6-dev-armhf-cross binutils-arm-linux-gnueabihf \
    python3 python3-venv ninja-build pkg-config libglib2.0-dev flex bison \
    curl xz-utils bzip2 ca-certificates ffmpeg perl \
    && rm -rf /var/lib/apt/lists/*
