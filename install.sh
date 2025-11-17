#!/bin/bash

# Hata olursa işlemi durdur
set -e

echo "#######################################################"
echo "### Hunyuan3D-2.1 RunPod Otomatik Kurulum Başlıyor ###"
echo "#######################################################"

# Adım 0 & 1: Sistem Paketleri ve Python 3.11
echo ">>> [1/7] Sistem paketleri ve Python 3.11 kuruluyor..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3.11 python3.11-venv python3.11-dev
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git git-lfs build-essential cmake ninja-build pkg-config \
    python3-dev unzip wget p7zip-full rar \
    libxrender1 libxext6 libxi6 libxrandr2 libx11-6 \
    libxkbcommon0 libglib2.0-0 libglu1-mesa libsm6 \
    libgl1-mesa-glx  # Demo hatası düzeltmesi için eklendi

git lfs install

# Adım 2: Projeyi Klonlama
echo ">>> [2/7] Proje GitHub'dan çekiliyor..."
cd /workspace
if [ -d "Hunyuan3D-2.1" ]; then
    echo "Klasör zaten var, silinip tekrar çekiliyor..."
    rm -rf Hunyuan3D-2.1
fi
git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git
cd Hunyuan3D-2.1

# Adım 3: Sanal Ortam (Venv)
echo ">>> [3/7] Python sanal ortamı oluşturuluyor..."
python3.11 -m venv venv
source venv/bin/activate

# Adım 4: Python Kütüphaneleri
echo ">>> [4/7] Python kütüphaneleri yükleniyor (Bu işlem zaman alabilir)..."
python -m pip install --upgrade pip
# RunPod CUDA uyumlu Torch kurulumu
pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu124

# Bpy düzeltmesi
echo ">>> 'bpy' sürüm düzeltmesi uygulanıyor..."
sed -i 's/bpy==4.0/bpy==4.2.0/' requirements.txt

# Diğer gereksinimler ve demo hatası önleyiciler
pip install -r requirements.txt
pip install trimesh pyvista open3d pyrender

# Adım 5: C++ Eklentileri Derleme
echo ">>> [5/7] C++ eklentileri derleniyor..."

# Custom Rasterizer
cd hy3dpaint/custom_rasterizer
python setup.py develop
cd ../..

# Differentiable Renderer
cd hy3dpaint/DifferentiableRenderer
if [ -f "*.so" ]; then rm -f *.so; fi
echo ">>> Mesh işlemcisi derleniyor..."
g++ -O3 -Wall -shared -std=c++11 -fPIC $(python -m pybind11 --includes) mesh_inpaint_processor.cpp -o mesh_inpaint_processor$(python -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")
cd ../..

# Adım 6: Model Dosyası
echo ">>> [6/7] RealESRGAN modeli indiriliyor..."
mkdir -p hy3dpaint/ckpt
wget -nc https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P hy3dpaint/ckpt

# Adım 7: Orijinal Dosyaları Geri Yükleme
echo ">>> [7/7] Kod orijinale döndürülüyor..."
git checkout -- hy3dpaint/DifferentiableRenderer/mesh_utils.py
git checkout -- hy3dpaint/textureGenPipeline.py

echo "#######################################################"
echo "### KURULUM BAŞARIYLA TAMAMLANDI! ###"
echo "#######################################################"
echo "Lütfen şu komutu çalıştırarak sanal ortamı aktif et:"
echo "source /workspace/Hunyuan3D-2.1/venv/bin/activate"
echo "Ardından: python demo.py"
