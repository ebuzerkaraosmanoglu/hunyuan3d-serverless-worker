#!/bin/bash

# Hata olursa işlemi durdur
set -e

echo "#######################################################"
echo "### Hunyuan3D-2.1 RunPod Full Stack Kurulum Başlıyor ###"
echo "#######################################################"

# --- Adım 1: Sistem Paketleri ve Python 3.11 ---
echo ">>> [1/8] Sistem paketleri ve Python 3.11 kuruluyor..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3.11 python3.11-venv python3.11-dev
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git git-lfs build-essential cmake ninja-build pkg-config \
    python3-dev unzip wget p7zip-full rar \
    libxrender1 libxext6 libxi6 libxrandr2 libx11-6 \
    libxkbcommon0 libglib2.0-0 libglu1-mesa libsm6 \
    libgl1-mesa-glx 

git lfs install

# --- Adım 2: Projeyi Klonlama ---
echo ">>> [2/8] Proje GitHub'dan çekiliyor..."
cd /workspace
if [ -d "Hunyuan3D-2.1" ]; then
    echo "Klasör zaten var, silinip tekrar çekiliyor..."
    rm -rf Hunyuan3D-2.1
fi
git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git
cd Hunyuan3D-2.1

# --- Adım 3: Sanal Ortam (Venv) ---
echo ">>> [3/8] Python sanal ortamı oluşturuluyor..."
python3.11 -m venv venv
source venv/bin/activate

# --- Adım 4: Python Kütüphaneleri ---
echo ">>> [4/8] Python kütüphaneleri yükleniyor..."
python -m pip install --upgrade pip
# RunPod CUDA uyumlu Torch
pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu124

# Bpy düzeltmesi
sed -i 's/bpy==4.0/bpy==4.2.0/' requirements.txt

# Gereksinimler, Monitor için Flask ve Grafik kütüphaneleri
pip install -r requirements.txt
pip install trimesh pyvista open3d pyrender flask

# --- Adım 5: C++ Eklentileri Derleme ---
echo ">>> [5/8] C++ eklentileri derleniyor..."

# Custom Rasterizer
cd hy3dpaint/custom_rasterizer
python setup.py develop
cd ../..

# Differentiable Renderer
cd hy3dpaint/DifferentiableRenderer
if [ -f "*.so" ]; then rm -f *.so; fi
g++ -O3 -Wall -shared -std=c++11 -fPIC $(python -m pybind11 --includes) mesh_inpaint_processor.cpp -o mesh_inpaint_processor$(python -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")
cd ../..

# --- Adım 6: Model Dosyası ---
echo ">>> [6/8] RealESRGAN modeli indiriliyor..."
mkdir -p hy3dpaint/ckpt
wget -nc https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P hy3dpaint/ckpt

# --- Adım 7: Orijinal Dosyaları Geri Yükleme ---
echo ">>> [7/8] Kod orijinale döndürülüyor..."
git checkout -- hy3dpaint/DifferentiableRenderer/mesh_utils.py
git checkout -- hy3dpaint/textureGenPipeline.py

# --- Adım 8: Otomasyon Dosyalarının Oluşturulması (run.py & monitor.py) ---
echo ">>> [8/8] Otomasyon scriptleri (run.py ve monitor.py) oluşturuluyor..."

# 1. run.py OLUŞTURMA
cat << 'EOF' > run.py
import os
import sys
import zipfile
from PIL import Image
import argparse

# --- Hunyuan3D Kütüphanelerini Dahil Etme ---
sys.path.insert(0, './hy3dshape')
sys.path.insert(0, './hy3dpaint')
from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig

# --- AYARLAR ---
INPUT_DIR = "images"
OUTPUT_DIR = "models"
OUTPUT_ZIP_FILE = "models.zip"

# --- KOMUT SATIRI ARGÜMANLARI ---
parser = argparse.ArgumentParser(description="Belirtilen ID aralığındaki PNG dosyalarından 3D modeller üretir.")
parser.add_argument("--start", type=int, required=True, help="Baslangic ID")
parser.add_argument("--end", type=int, required=True, help="Bitis ID")
args = parser.parse_args()

# --- HAZIRLIK ---
os.makedirs(OUTPUT_DIR, exist_ok=True)

try:
    if not os.path.exists(INPUT_DIR):
        print(f"❌ HATA: Girdi klasörü bulunamadı: '{INPUT_DIR}'")
        exit()

    all_image_files = [f for f in os.listdir(INPUT_DIR) if f.lower().endswith('.png')]
    image_files = []
    for filename in all_image_files:
        try:
            file_id = int(filename.split('_')[0])
            if args.start <= file_id <= args.end:
                image_files.append(filename)
        except (ValueError, IndexError):
            continue

    if not image_files:
        print(f"❌ HATA: Aralığında dosya bulunamadı: {args.start}-{args.end}")
        exit()
        
    print(f"✅ {len(image_files)} adet resim işlenecek (ID: {args.start}-{args.end}).")

    # --- MODELLERİ YÜKLEME ---
    try:
        from torchvision_fix import apply_fix
        apply_fix()
    except:
        pass

    print("🚀 Modeller GPU'ya yükleniyor...")
    model_path = 'tencent/Hunyuan3D-2.1'
    pipeline_shapegen = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(model_path)
    conf = Hunyuan3DPaintConfig(max_num_view=6, resolution=512)
    conf.realesrgan_ckpt_path = "hy3dpaint/ckpt/RealESRGAN_x4plus.pth"
    conf.multiview_cfg_path = "hy3dpaint/cfgs/hunyuan-paint-pbr.yaml"
    conf.custom_pipeline = "hy3dpaint/hunyuanpaintbr"
    paint_pipeline = Hunyuan3DPaintPipeline(conf)
    print("✅ Modeller hazır.")

    # --- ÜRETİM DÖNGÜSÜ ---
    total_models = len(image_files)
    processed_count = 0

    for filename in image_files:
        processed_count += 1
        print(f"--- ({processed_count}/{total_models}) İşleniyor: {filename} ---", flush=True)
        
        base_name = os.path.splitext(filename)[0]
        image_path = os.path.join(INPUT_DIR, filename)
        model_output_dir = os.path.join(OUTPUT_DIR, base_name)
        os.makedirs(model_output_dir, exist_ok=True)
        
        untextured_glb_path = os.path.join(model_output_dir, f"{base_name}_temp.glb")
        final_glb_path = os.path.join(model_output_dir, f"{base_name}.glb")

        try:
            image = Image.open(image_path).convert("RGBA")
            mesh = pipeline_shapegen(image=image)[0]
            mesh.export(untextured_glb_path)

            paint_pipeline(
                mesh_path=untextured_glb_path,
                image_path=image_path,
                output_mesh_path=final_glb_path
            )
            print(f"✅ Tamamlandı: {final_glb_path}", flush=True)

        except Exception as e:
            print(f"❌ HATA: {filename} - {e}", flush=True)
        
        finally:
            if os.path.exists(untextured_glb_path):
                os.remove(untextured_glb_path)

    # --- ZİPLEME ---
    print("🎉 Zipleniyor...")
    with zipfile.ZipFile(OUTPUT_ZIP_FILE, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(OUTPUT_DIR):
            for file in files:
                file_path = os.path.join(root, file)
                zipf.write(file_path, arcname=os.path.relpath(file_path, OUTPUT_DIR))
    print("🎉 Tüm işlemler bitti!")

except Exception as e:
    print(f"Genel Hata: {e}")
EOF

# 2. monitor.py OLUŞTURMA
cat << 'EOF' > monitor.py
import os, re, time
from flask import Flask, jsonify, render_template_string

app = Flask(__name__)
LOG_FILE = "islem_logu.txt"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Hunyuan3D Monitor</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<style>
body{background:#121212;color:#e0e0e0;font-family:'Consolas',monospace}
.log-container{background:#000;border:1px solid #333;height:60vh;overflow-y:scroll;padding:15px;font-size:14px;white-space:pre-wrap;color:#00ff41}
.status-card{background:#1e1e1e;border:1px solid #333;padding:20px;border-radius:8px;margin-bottom:20px}
</style>
</head>
<body>
<div class="container mt-4">
<h2 class="text-center mb-4">RunPod 3D Üretim Takibi</h2>
<div class="status-card"><div class="row text-center">
<div class="col-md-4"><h5>Durum</h5><div id="status" class="fw-bold">...</div></div>
<div class="col-md-4"><h5>İlerleme</h5><div id="prog-txt">0/0</div></div>
<div class="col-md-4"><h5>Son Dosya</h5><div id="last" class="text-info">-</div></div></div>
<div class="progress mt-3"><div id="bar" class="progress-bar progress-bar-striped progress-bar-animated" style="width:0%">0%</div></div></div>
<h5>Canlı Log:</h5><div class="log-container" id="log">Loglar bekleniyor...</div></div>
<script>
const logBox=document.getElementById('log');
let autoScroll=true;
logBox.addEventListener('scroll',()=>autoScroll=(logBox.scrollTop+logBox.clientHeight>=logBox.scrollHeight-50));
setInterval(()=>{
fetch('/api/data').then(r=>r.json()).then(d=>{
logBox.textContent=d.logs;
if(autoScroll)logBox.scrollTop=logBox.scrollHeight;
document.getElementById('status').textContent=d.run?"ÇALIŞIYOR 🚀":"BEKLEMEDE 🛑";
document.getElementById('status').className=d.run?"fw-bold text-success":"fw-bold text-danger";
document.getElementById('prog-txt').textContent=`${d.cur}/${d.tot}`;
document.getElementById('last').textContent=d.last;
document.getElementById('bar').style.width=d.pct+"%";
document.getElementById('bar').textContent=d.pct+"%";
});},2000);
</script></body></html>
"""
@app.route('/')
def index(): return render_template_string(HTML_TEMPLATE)
@app.route('/api/data')
def data():
    c=""; cur=0; tot=0; last="-"; run=False
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE,'r',errors='ignore') as f: c=f.read()
        if (time.time()-os.path.getmtime(LOG_FILE))<60: run=True
    m=re.findall(r'---\s*\((\d+)/(\d+)\)\s*İşleniyor:\s*(.*?)\s*---',c)
    if m: cur=int(m[-1][0]); tot=int(m[-1][1]); last=m[-1][2]
    pct=int((cur/tot)*100) if tot>0 else 0
    return jsonify({"logs":c,"cur":cur,"tot":tot,"pct":pct,"last":last,"run":run})
if __name__=='__main__': app.run(host='0.0.0.0',port=8000)
EOF

echo "#######################################################"
echo "### KURULUM TAMAMLANDI! ###"
echo "#######################################################"
echo "Sistemi kullanmak için:"
echo "1. Resimlerini 'images' klasörüne yükle."
echo "2. Şu komutları çalıştır:"
echo ""
echo "   source /workspace/Hunyuan3D-2.1/venv/bin/activate"
echo "   nohup python monitor.py > monitor_log.txt 2>&1 &"
echo "   nohup python run.py --start 1 --end 100 > islem_logu.txt 2>&1 &"
echo ""
echo "Ardından 'Connect -> HTTP Service (8000)' ile takibe başla!"
