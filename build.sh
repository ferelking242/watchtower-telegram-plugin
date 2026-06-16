#!/usr/bin/env bash
# ============================================================
# build.sh — Watchtower Telegram Source Plugin Builder
# Crée un APK plugin avec libpython.so + script.py embarqués
# ============================================================
set -euo pipefail

PLUGIN_ID="com.watchtower.telegram-source"
PLUGIN_VERSION="1.0.0"
OUTPUT_DIR="dist"
APK_NAME="${PLUGIN_ID}_${PLUGIN_VERSION}.apk"

PYTHON_VERSION="3.11.9"
LIBPYTHON_ARM64_URL="https://github.com/ferelking242/watchtower-extensions/releases/download/libpython/libpython3.11_arm64.so"
LIBPYTHON_X86_URL="https://github.com/ferelking242/watchtower-extensions/releases/download/libpython/libpython3.11_x86_64.so"

echo "📦 Build Watchtower Telegram Source Plugin v${PLUGIN_VERSION}"
echo "=================================================="

check_deps() {
    for cmd in zip curl python3; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ Dépendance manquante: $cmd"
            exit 1
        fi
    done
    echo "✅ Dépendances OK"
}

setup_dirs() {
    rm -rf build/
    mkdir -p build/lib/arm64-v8a
    mkdir -p build/lib/x86_64
    mkdir -p build/assets
    mkdir -p build/res/xml
    mkdir -p "$OUTPUT_DIR"
    echo "✅ Dossiers créés"
}

download_libpython() {
    echo "⬇️  Téléchargement libpython3.11 ARM64..."
    if curl -fsSL "$LIBPYTHON_ARM64_URL" -o "build/lib/arm64-v8a/libpython3.11.so"; then
        echo "✅ libpython ARM64 OK"
    else
        echo "⚠️  libpython ARM64 non disponible — utilisation du stub"
        echo "STUB_ARM64" > "build/lib/arm64-v8a/libpython3.11.so"
    fi

    echo "⬇️  Téléchargement libpython3.11 x86_64..."
    if curl -fsSL "$LIBPYTHON_X86_URL" -o "build/lib/x86_64/libpython3.11.so"; then
        echo "✅ libpython x86_64 OK"
    else
        echo "⚠️  libpython x86_64 non disponible — utilisation du stub"
        echo "STUB_X86" > "build/lib/x86_64/libpython3.11.so"
    fi
}

bundle_python_deps() {
    echo "📦 Bundle des dépendances Python..."
    mkdir -p build/assets/site-packages

    if command -v pip3 &>/dev/null; then
        pip3 install \
            --target build/assets/site-packages \
            --platform manylinux2014_aarch64 \
            --only-binary=:all: \
            --python-version 3.11 \
            pyrogram==2.0.106 tgcrypto==1.2.5 2>/dev/null || \
        pip3 install \
            --target build/assets/site-packages \
            pyrogram==2.0.106 tgcrypto==1.2.5
        echo "✅ Dépendances Python bundlées"
    else
        echo "⚠️  pip3 non disponible — dépendances non bundlées (seront installées au runtime)"
    fi
}

copy_assets() {
    echo "📋 Copie des assets..."
    cp script.py          build/assets/script.py
    cp requirements.txt   build/assets/requirements.txt
    cp manifest.json      build/assets/manifest.json
    cp AndroidManifest.xml build/AndroidManifest.xml
    cp res/xml/network_security_config.xml build/res/xml/

    python3 -c "
import json, base64, os
with open('manifest.json') as f:
    m = json.load(f)
print('Plugin ID     :', m['id'])
print('Version       :', m['version'])
print('Runtime       :', m.get('runtime'))
print('Entry         :', m.get('entry'))
"
    echo "✅ Assets copiés"
}

create_apk() {
    echo "🔧 Création de l'APK..."
    cd build
    zip -r "../${OUTPUT_DIR}/${APK_NAME}" . -x "*.DS_Store" -x "__MACOSX/*"
    cd ..
    SIZE=$(du -sh "${OUTPUT_DIR}/${APK_NAME}" | cut -f1)
    echo "✅ APK créé : ${OUTPUT_DIR}/${APK_NAME} (${SIZE})"
}

verify_apk() {
    echo "🔍 Vérification de la structure APK..."
    python3 -c "
import zipfile, sys

apk_path = '${OUTPUT_DIR}/${APK_NAME}'
required = [
    'AndroidManifest.xml',
    'assets/manifest.json',
    'assets/script.py',
    'assets/requirements.txt',
    'lib/arm64-v8a/libpython3.11.so',
]

with zipfile.ZipFile(apk_path) as z:
    names = z.namelist()
    ok = True
    for req in required:
        if req in names:
            print(f'  ✅ {req}')
        else:
            print(f'  ❌ {req} MANQUANT')
            ok = False

    print(f'Total fichiers: {len(names)}')
    if ok:
        print('✅ Structure APK valide')
    else:
        print('❌ Structure APK incomplète')
        sys.exit(1)
"
}

# ---- Pipeline principal ----
check_deps
setup_dirs
download_libpython
bundle_python_deps
copy_assets
create_apk
verify_apk

echo ""
echo "🎉 Build terminé !"
echo "   APK : ${OUTPUT_DIR}/${APK_NAME}"
echo ""
echo "Pour tester :"
echo "  python3 script.py --api_id YOUR_ID --api_hash YOUR_HASH --auth --phone +242XXXXXXXX"
echo "  python3 script.py --api_id YOUR_ID --api_hash YOUR_HASH --session 'STR' --channel @moncanal --action metadata"
