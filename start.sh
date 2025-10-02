#!/usr/bin/env bash
set -euo pipefail
WORKDIR=/workspace/Hunyuan3D-2.1

if [ -d "$WORKDIR" ]; then
  source $WORKDIR/venv/bin/activate
  cd $WORKDIR
  echo "Hunyuan3D hazır. Demo başlatılıyor..."
  python demo.py
else
  echo "Kurulum bulunamadı. setup.sh çalıştırmalısınız."
fi
