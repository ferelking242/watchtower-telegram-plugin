#!/usr/bin/env bash
# ============================================================
# build.sh — Watchtower Telegram Source Plugin Builder
# Crée un ZIP plugin avec libpython.so + script.py + deps vendorées
# Même pattern que ZeusDL / MPV dans Watchtower
# ============================================================
set -euo pipefail

PLUGIN_ID="com.watchtower.telegram-source"
PLUGIN_VERSION="1.0.0"
OUTPUT_DIR="dist"
PLUGIN_NAME="${PLUGIN_ID}_${PLUGIN_VERSION}"
ZIP_NAME="${PLUGIN_NAME}.zip"
APK_NAME="${PLUGIN_NAME}.apk"

LIBPYTHON_ARM64_URL="https://github.com/ferelking242/watchtower-extensions/releases/download/libpython/libpython3.11_arm64.so"
LIBPYTHON_X86_URL="https://github.com/ferelking242/watchtower-extensions/releases/download/libpython/libpython3.11_x86_64.so"

echo "📦 Build Watchtower Telegram Source Plugin v${PLUGIN_VERSION}"
echo "=================================================="

check_deps() {
    for cmd in zip curl; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ Manque : $cmd"
            exit 1
        fi
    done
    if ! command -v pip3 &>/dev/null && ! command -v pip &>/dev/null; then
        echo "⚠️  pip non trouvé — les deps Python ne seront pas vendorisées"
    fi
    echo "✅ Dépendances OK"
}

setup_dirs() {
    rm -rf build/
    mkdir -p build/lib/arm64-v8a
    mkdir -p build/lib/x86_64
    mkdir -p build/assets/vendor
    mkdir -p build/ui
    mkdir -p build/res/xml
    mkdir -p "$OUTPUT_DIR"
    echo "✅ Dossiers créés"
}

download_libpython() {
    echo "⬇️  libpython3.11 ARM64..."
    curl -fsSL "$LIBPYTHON_ARM64_URL" -o "build/lib/arm64-v8a/libpython3.11.so" 2>/dev/null \
        && echo "✅ ARM64 OK" \
        || { echo "⚠️  ARM64 non disponible (stub)"; printf 'STUB_ARM64_LIBPYTHON' > "build/lib/arm64-v8a/libpython3.11.so"; }

    echo "⬇️  libpython3.11 x86_64..."
    curl -fsSL "$LIBPYTHON_X86_URL" -o "build/lib/x86_64/libpython3.11.so" 2>/dev/null \
        && echo "✅ x86_64 OK" \
        || { echo "⚠️  x86_64 non disponible (stub)"; printf 'STUB_X86_LIBPYTHON' > "build/lib/x86_64/libpython3.11.so"; }
}

vendor_python_deps() {
    echo "📦 Vendorisation des dépendances Python..."
    local pip_cmd="pip3"
    command -v pip3 &>/dev/null || pip_cmd="pip"

    # Tente d'abord un téléchargement cross-compilé pour aarch64
    "$pip_cmd" download \
        --dest build/assets/vendor \
        --platform manylinux2014_aarch64 \
        --only-binary=:all: \
        --python-version 3.11 \
        --implementation cp \
        pyrogram==2.0.106 tgcrypto==1.2.5 2>/dev/null \
    && echo "✅ Wheels ARM64 téléchargés" \
    || {
        echo "⚠️  Wheels ARM64 non disponibles, fallback téléchargement générique..."
        "$pip_cmd" download \
            --dest build/assets/vendor \
            pyrogram==2.0.106 tgcrypto==1.2.5 2>/dev/null \
        && echo "✅ Wheels génériques téléchargés" \
        || echo "⚠️  Wheels non téléchargés (seront installés au runtime)"
    }

    # Crée requirements.txt dans vendor pour le runtime
    cp requirements.txt build/assets/vendor/requirements.txt
    echo "✅ Dépendances vendorisées"
}

copy_assets() {
    echo "📋 Copie des assets..."
    cp script.py              build/assets/script.py
    cp requirements.txt       build/assets/requirements.txt
    cp manifest.json          build/assets/manifest.json
    cp ui/main.dart           build/ui/main.dart
    cp AndroidManifest.xml    build/AndroidManifest.xml
    cp res/xml/network_security_config.xml build/res/xml/
    echo "✅ Assets copiés"
}

create_zip() {
    echo "🔧 Création du ZIP plugin..."
    cd build
    zip -r "../${OUTPUT_DIR}/${ZIP_NAME}" . -x "*.DS_Store" -x "__MACOSX/*"
    cd ..
    local size
    size=$(du -sh "${OUTPUT_DIR}/${ZIP_NAME}" | cut -f1)
    echo "✅ ZIP créé : ${OUTPUT_DIR}/${ZIP_NAME} (${size})"
}

create_apk() {
    echo "🔧 Création de l'APK (ZIP renommé)..."
    cp "${OUTPUT_DIR}/${ZIP_NAME}" "${OUTPUT_DIR}/${APK_NAME}"
    local size
    size=$(du -sh "${OUTPUT_DIR}/${APK_NAME}" | cut -f1)
    echo "✅ APK créé : ${OUTPUT_DIR}/${APK_NAME} (${size})"
}

verify() {
    echo "🔍 Vérification de la structure..."
    local required=(
        "AndroidManifest.xml"
        "assets/manifest.json"
        "assets/script.py"
        "assets/requirements.txt"
        "assets/vendor/requirements.txt"
        "ui/main.dart"
        "lib/arm64-v8a/libpython3.11.so"
    )

    local ok=true
    for f in "${required[@]}"; do
        if unzip -l "${OUTPUT_DIR}/${ZIP_NAME}" | grep -q "$f"; then
            echo "  ✅ $f"
        else
            echo "  ❌ $f MANQUANT"
            ok=false
        fi
    done

    $ok && echo "✅ Structure valide" || { echo "❌ Structure incomplète"; exit 1; }
}

# ── Pipeline ─────────────────────────────────────────────────────────────────
check_deps
setup_dirs
download_libpython
vendor_python_deps
copy_assets
create_zip
create_apk
verify

echo ""
echo "🎉 Build terminé !"
echo "   ZIP : ${OUTPUT_DIR}/${ZIP_NAME}"
echo "   APK : ${OUTPUT_DIR}/${APK_NAME}"
echo ""
echo "Pour tester le script :"
echo "  pip3 install pyrogram tgcrypto"
echo "  python3 script.py --api_id ID --api_hash HASH --auth --phone +242XXX"
