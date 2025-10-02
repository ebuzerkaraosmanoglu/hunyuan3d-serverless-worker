#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get install -y \
    git git-lfs build-essential cmake ninja-build pkg-config \
    python3 python3-venv python3-dev python3-pip unzip wget p7zip-full \
    libxrender1 libxext6 libxi6 libxrandr2 libx11-6 libxkbcommon0 libglib2.0-0 libglu1-mesa libsm6

git lfs install || true

cd /workspace
if [ ! -d Hunyuan3D-2.1 ]; then
  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git
fi

cd Hunyuan3D-2.1

python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip
pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu124

sed -i 's/bpy==4.0/bpy==4.2.0/' requirements.txt || true
pip install -r requirements.txt

cd hy3dpaint/custom_rasterizer
python setup.py develop
cd ../..

cd hy3dpaint/DifferentiableRenderer
rm -f *.so || true
g++ -O3 -Wall -shared -std=c++11 -fPIC `python -m pybind11 --includes` mesh_inpaint_processor.cpp -o mesh_inpaint_processor`python -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))"`
cd ../..

mkdir -p hy3dpaint/ckpt
wget -c https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P hy3dpaint/ckpt

git checkout -- hy3dpaint/DifferentiableRenderer/mesh_utils.py || true
git checkout -- hy3dpaint/textureGenPipeline.py || true
