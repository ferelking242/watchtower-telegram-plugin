PLUGIN_ID      := com.watchtower.telegram-source
PLUGIN_VERSION := 1.0.0
OUTPUT_DIR     := dist
APK_NAME       := $(PLUGIN_ID)_$(PLUGIN_VERSION).apk

.PHONY: all build clean test lint help

all: build

build:
	@echo "▶ Building $(PLUGIN_ID) v$(PLUGIN_VERSION)..."
	@bash build.sh

clean:
	@echo "🧹 Nettoyage..."
	@rm -rf build/ dist/
	@echo "✅ Nettoyé"

test:
	@echo "🧪 Test du script (dry-run syntax check)..."
	@python3 -m py_compile script.py && echo "✅ Syntaxe Python OK"
	@python3 -c "import json; json.load(open('manifest.json')); print('✅ manifest.json valide')"

lint:
	@echo "🔍 Lint..."
	@command -v flake8 >/dev/null 2>&1 && flake8 script.py --max-line-length=120 || echo "⚠️  flake8 non installé"

deps:
	@echo "📦 Installation des dépendances de dev..."
	@pip3 install pyrogram==2.0.106 tgcrypto==1.2.5

help:
	@echo "Watchtower Telegram Source Plugin — Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make build   — Build l'APK plugin (dist/$(APK_NAME))"
	@echo "  make clean   — Supprime build/ et dist/"
	@echo "  make test    — Vérifie la syntaxe Python et le manifest JSON"
	@echo "  make lint    — Lint avec flake8"
	@echo "  make deps    — Installe les dépendances Python"
	@echo "  make help    — Affiche cette aide"
