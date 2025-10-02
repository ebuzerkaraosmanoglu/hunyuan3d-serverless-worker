FROM nvidia/cuda:12.2.2-devel-ubuntu22.04

# Sistem paketleri
RUN apt-get update && apt-get install -y \
    git git-lfs build-essential cmake ninja-build pkg-config python3-dev unzip wget p7zip-full rar \
    libxrender1 libxext6 libxi6 libxrandr2 libx11-6 libxkbcommon0 libglib2.0-0 libglu1-mesa libsm6 \
    && rm -rf /var/lib/apt/lists/*

# Çalışma dizini
WORKDIR /workspace

# Repo dosyalarını kopyala
COPY . .

# setup.sh çalıştır
RUN bash setup.sh
