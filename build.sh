#!/usr/bin/env bash
# ============================================================
# build.sh — Watchtower Telegram Source Plugin Builder
# tgcrypto compilé ARM64 nativement (NDK) — pas de fallback
# Structure ZIP plate : script.py + pyrogram/ + tgcrypto/ à la racine
# ============================================================
set -euo pipefail

PLUGIN_ID="com.watchtower.telegram-source"
PLUGIN_VERSION="1.0.0"
OUTPUT_DIR="dist"
ZIP_NAME="${PLUGIN_ID}_${PLUGIN_VERSION}.zip"
APK_NAME="${PLUGIN_ID}_${PLUGIN_VERSION}.apk"
PLUGIN_DIR="build/plugin"

echo "📦 Build Watchtower Telegram Source Plugin v${PLUGIN_VERSION}"
echo "=================================================="

check_deps() {
    for cmd in zip python3 pip3; do
        command -v "$cmd" &>/dev/null || { echo "❌ Manque : $cmd"; exit 1; }
    done
    echo "✅ Dépendances système OK"
}

setup_dirs() {
    rm -rf build/ "${OUTPUT_DIR}/"
    mkdir -p "${PLUGIN_DIR}/ui"
    mkdir -p "${OUTPUT_DIR}"
    echo "✅ Dossiers créés"
}

install_pyrogram() {
    echo "📦 Installation pyrogram ARM64..."
    pip3 install \
        pyrogram==2.0.106 \
        --target "${PLUGIN_DIR}" \
        --platform manylinux2014_aarch64 \
        --only-binary=:all: \
        --python-version 3.11 \
        --implementation cp \
        --no-compile \
        -q || \
    pip3 install \
        pyrogram==2.0.106 \
        --target "${PLUGIN_DIR}" \
        --no-compile -q
    echo "✅ pyrogram installé"
}

install_tgcrypto() {
    echo "🔧 Installation tgcrypto ARM64 (natif)..."

    # Si le CI a pré-compilé le .so, l'utiliser directement
    if [ -n "${TGCRYPTO_PREBUILT_SO:-}" ] && [ -f "${TGCRYPTO_PREBUILT_SO}" ]; then
        echo "  Utilisation du .so pré-compilé par le CI : ${TGCRYPTO_PREBUILT_SO}"
        mkdir -p "${PLUGIN_DIR}/tgcrypto"
        cp "${TGCRYPTO_PREBUILT_SO}" "${PLUGIN_DIR}/tgcrypto/"

        # Créer __init__.py minimal pour que Python reconnaisse le package
        cat > "${PLUGIN_DIR}/tgcrypto/__init__.py" << 'PYEOF'
import os as _os, importlib.util as _iu
_here = _os.path.dirname(_os.path.abspath(__file__))
for _f in _os.listdir(_here):
    if _f.startswith('_tgcrypto') and _f.endswith('.so'):
        _spec = _iu.spec_from_file_location('_tgcrypto', _os.path.join(_here, _f))
        _mod  = _iu.module_from_spec(_spec)
        _spec.loader.exec_module(_mod)
        from _mod import *
        break
PYEOF
        echo "✅ tgcrypto ARM64 .so installé :"
        ls -lh "${PLUGIN_DIR}/tgcrypto/"
        return
    fi

    # Tentative de compilation locale (si NDK disponible)
    NDK_ROOT=$(ls -d "${ANDROID_NDK_HOME:-/usr/local/lib/android/sdk/ndk}"/* 2>/dev/null | sort -V | tail -1 || true)
    if [ -n "$NDK_ROOT" ]; then
        echo "  NDK trouvé : $NDK_ROOT — compilation locale..."
        CC="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang"
        PY_INC=$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))")

        pip3 download tgcrypto==1.2.5 --no-binary tgcrypto -d /tmp/tgsrc -q
        cd /tmp && tar -xzf tgsrc/tgcrypto-1.2.5.tar.gz
        cd /tmp/tgcrypto-1.2.5
        C_SRC=$(find . -name "*.c" | grep -v test | head -1)
        mkdir -p "${OLDPWD}/${PLUGIN_DIR}/tgcrypto"
        SO_NAME="_tgcrypto.cpython-311-aarch64-linux-android.so"
        "$CC" -shared -fPIC -O2 -I"$PY_INC" "$C_SRC" \
            -o "${OLDPWD}/${PLUGIN_DIR}/tgcrypto/$SO_NAME"
        cd "$OLDPWD"

        ARCH=$(readelf -h "${PLUGIN_DIR}/tgcrypto/$SO_NAME" 2>/dev/null | grep "Machine" | grep -i "AArch64" || true)
        if [ -z "$ARCH" ]; then
            echo "❌ Compilation échouée : le .so n'est pas ARM64"
            exit 1
        fi
        echo "✅ tgcrypto compilé localement (ARM64 confirmé)"
        ls -lh "${PLUGIN_DIR}/tgcrypto/"
        return
    fi

    # Aucune option disponible → ERREUR (pas de fallback pur Python)
    echo "❌ ERREUR: Impossible de compiler tgcrypto ARM64 (NDK absent et pas de .so pré-compilé)"
    echo "   Lancer le build via GitHub Actions (build.yml) pour la compilation NDK automatique"
    exit 1
}

copy_assets() {
    echo "📋 Copie des assets..."
    cp script.py            "${PLUGIN_DIR}/script.py"
    cp manifest.json        "${PLUGIN_DIR}/manifest.json"
    cp requirements.txt     "${PLUGIN_DIR}/requirements.txt" 2>/dev/null || true
    cp ui/main.dart         "${PLUGIN_DIR}/ui/main.dart"

    # Nettoyer métadonnées pip
    find "${PLUGIN_DIR}" -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true
    find "${PLUGIN_DIR}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find "${PLUGIN_DIR}" -name "*.pyc" -delete 2>/dev/null || true
    echo "✅ Assets copiés"
}

create_zip() {
    echo "🔧 Création du ZIP..."
    cd "${PLUGIN_DIR}"
    zip -qr "../../${OUTPUT_DIR}/${ZIP_NAME}" . \
        -x "*.DS_Store" -x "__MACOSX/*" -x "*.pyc" -x "*/__pycache__/*"
    cd ../..
    echo "✅ ZIP : ${OUTPUT_DIR}/${ZIP_NAME} ($(du -sh ${OUTPUT_DIR}/${ZIP_NAME} | cut -f1))"
}

create_apk() {
    cp "${OUTPUT_DIR}/${ZIP_NAME}" "${OUTPUT_DIR}/${APK_NAME}"
    echo "✅ APK : ${OUTPUT_DIR}/${APK_NAME}"
}

verify() {
    echo "🔍 Vérification..."
    local ok=true
    for entry in "script.py" "manifest.json" "pyrogram" "tgcrypto" "ui/main.dart"; do
        if unzip -l "${OUTPUT_DIR}/${ZIP_NAME}" | grep -qE " ${entry}"; then
            echo "  ✅ $entry"
        else
            echo "  ❌ $entry MANQUANT"
            ok=false
        fi
    done
    # Vérifier que le .so tgcrypto est bien dans le zip
    if unzip -l "${OUTPUT_DIR}/${ZIP_NAME}" | grep -q "_tgcrypto.*\.so"; then
        echo "  ✅ _tgcrypto.so ARM64"
    else
        echo "  ❌ _tgcrypto.so MANQUANT — build invalide"
        ok=false
    fi
    $ok && echo "✅ Structure valide" || { echo "❌ Structure incomplète"; exit 1; }
}

check_deps
setup_dirs
install_pyrogram
install_tgcrypto
copy_assets
create_zip
create_apk
verify

echo ""
echo "🎉 Build terminé !"
echo "   ZIP : ${OUTPUT_DIR}/${ZIP_NAME}"
echo "   APK : ${OUTPUT_DIR}/${APK_NAME}"
