#!/usr/bin/env bash
  # ============================================================
  # build.sh — Watchtower Telegram Source Plugin Builder
  # Produit telegram_plugin.zip avec :
  #   script.py       ← code du plugin
  #   pyrogram/       ← vendoré ARM64 (pip install --target)
  #   tgcrypto/       ← vendoré ARM64 (inclut _tgcrypto.so si dispo)
  #   manifest.json   ← métadonnées du plugin
  #   ui/main.dart    ← UI Flutter Eval
  # Runtime Python (.so) fourni par l'APK Watchtower — pas dans ce zip.
  # ============================================================
  set -euo pipefail

  PLUGIN_ID="com.watchtower.telegram-source"
  PLUGIN_VERSION="1.0.0"
  OUTPUT_DIR="dist"
  ZIP_NAME="${PLUGIN_ID}_${PLUGIN_VERSION}.zip"
  APK_NAME="${PLUGIN_ID}_${PLUGIN_VERSION}.apk"

  echo "📦 Build Watchtower Telegram Source Plugin v${PLUGIN_VERSION}"
  echo "=================================================="

  check_deps() {
      for cmd in zip python3; do
          if ! command -v "$cmd" &>/dev/null; then
              echo "❌ Manque : $cmd"
              exit 1
          fi
      done
      command -v pip3 &>/dev/null || command -v pip &>/dev/null || {
          echo "❌ pip non trouvé"
          exit 1
      }
      echo "✅ Dépendances système OK"
  }

  setup_dirs() {
      rm -rf build/ "$OUTPUT_DIR/"
      mkdir -p build/plugin
      mkdir -p build/plugin/ui
      mkdir -p "$OUTPUT_DIR"
      echo "✅ Dossiers créés"
  }

  vendor_python_deps() {
      echo "📦 Vendorisation pyrogram + tgcrypto (ARM64)..."
      local pip_cmd="pip3"
      command -v pip3 &>/dev/null || pip_cmd="pip"

      # Priorité 1 : wheels Android ARM64 natifs (tgcrypto contient _tgcrypto.so ARM64)
      if "$pip_cmd" install \
          pyrogram==2.0.106 \
          tgcrypto==1.2.5 \
          --target build/plugin \
          --platform android_arm64_v8a \
          --only-binary=:all: \
          --python-version 3.11 \
          --implementation cp \
          --no-compile \
          -q 2>&1 | grep -v "WARNING"; then
          echo "✅ Wheels Android ARM64 installés"
      # Priorité 2 : wheels manylinux aarch64 (compatible Android)
      elif "$pip_cmd" install \
          pyrogram==2.0.106 \
          tgcrypto==1.2.5 \
          --target build/plugin \
          --platform manylinux2014_aarch64 \
          --only-binary=:all: \
          --python-version 3.11 \
          --implementation cp \
          --no-compile \
          -q 2>&1 | grep -v "WARNING"; then
          echo "✅ Wheels manylinux aarch64 installés"
      # Fallback : version native du runner (x86_64 — fonctionne si Python interprète le .so)
      else
          echo "⚠️  Wheels ARM64 indisponibles — fallback native (sans extension C pour tgcrypto)"
          "$pip_cmd" install \
              pyrogram==2.0.106 \
              --target build/plugin \
              --no-compile \
              -q
          # pyaes comme fallback crypto pur Python si tgcrypto absent
          "$pip_cmd" install pyaes \
              --target build/plugin \
              --no-compile \
              -q
          echo "⚠️  tgcrypto remplacé par pyaes (crypto pur Python — plus lent)"
      fi

      # Vérifier si _tgcrypto.so est présent (extension C ARM64)
      if find build/plugin -name "_tgcrypto*.so" | grep -q .; then
          echo "  ✅ tgcrypto extension C (.so) présente :"
          find build/plugin -name "_tgcrypto*.so" -exec ls -lh {} \;
      else
          echo "  ⚠️  tgcrypto .so absent — mode pur Python actif"
      fi

      # Nettoyer métadonnées pip (inutiles au runtime)
      find build/plugin -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true
      find build/plugin -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
      find build/plugin -name "*.pyc" -delete 2>/dev/null || true
      echo "✅ Dépendances vendorisées"
  }

  copy_assets() {
      echo "📋 Copie des assets du plugin..."
      # Fichiers Python à la racine du plugin (même niveau que pyrogram/)
      cp script.py       build/plugin/script.py
      cp manifest.json   build/plugin/manifest.json
      cp requirements.txt build/plugin/requirements.txt 2>/dev/null || true

      # UI Flutter Eval
      cp ui/main.dart    build/plugin/ui/main.dart

      echo "✅ Assets copiés"
  }

  create_zip() {
      echo "🔧 Création du ZIP plugin..."
      cd build/plugin
      zip -qr "../../${OUTPUT_DIR}/${ZIP_NAME}" . \
          -x "*.DS_Store" \
          -x "__MACOSX/*" \
          -x "*.pyc" \
          -x "*/__pycache__/*"
      cd ../..
      echo "✅ ZIP créé : ${OUTPUT_DIR}/${ZIP_NAME} ($(du -sh ${OUTPUT_DIR}/${ZIP_NAME} | cut -f1))"
  }

  create_apk() {
      cp "${OUTPUT_DIR}/${ZIP_NAME}" "${OUTPUT_DIR}/${APK_NAME}"
      echo "✅ APK : ${OUTPUT_DIR}/${APK_NAME} ($(du -sh ${OUTPUT_DIR}/${APK_NAME} | cut -f1))"
  }

  verify() {
      echo "🔍 Vérification de la structure..."
      local ok=true
      for entry in "script.py" "manifest.json" "pyrogram/" "ui/main.dart"; do
          if unzip -l "${OUTPUT_DIR}/${ZIP_NAME}" | grep -qE "\s+${entry%%/}"; then
              echo "  ✅ $entry"
          else
              echo "  ❌ $entry MANQUANT"
              ok=false
          fi
      done
      echo "--- Dépôt complet des packages ---"
      unzip -l "${OUTPUT_DIR}/${ZIP_NAME}" | awk '{print $NF}' | \
          awk -F/ '{print $1}' | sort -u | grep -v "^$"
      $ok && echo "✅ Structure valide" || { echo "❌ Structure incomplète"; exit 1; }
  }

  # ── Pipeline ─────────────────────────────────────────────────────────────────
  check_deps
  setup_dirs
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
  echo "Pour tester :"
  echo "  python3 build/plugin/script.py --help"
  