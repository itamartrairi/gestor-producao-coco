#!/usr/bin/env bash
# Gera as pastas android/ e ios/ (se ainda não existirem) e aplica as
# permissões necessárias. Rode uma vez na raiz do projeto:
#   bash tool/preparar_plataformas.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ] || [ ! -d web ]; then
  flutter create --platforms=android,ios,web --org br.com.gestorcoco --project-name gestor_producao_coco .
  # O template cria um teste de exemplo que não se aplica a este app.
  rm -f test/widget_test.dart
fi

# Nome exibido no aparelho.
if [ -f android/app/src/main/AndroidManifest.xml ]; then
  sed -i.bak 's/android:label="[^"]*"/android:label="Gestor do Coco"/' android/app/src/main/AndroidManifest.xml
  rm -f android/app/src/main/AndroidManifest.xml.bak
fi

PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ] && ! grep -q NSPhotoLibraryUsageDescription "$PLIST"; then
  # Insere as chaves antes do último </dict>.
  python3 - "$PLIST" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
extra = """	<key>NSPhotoLibraryUsageDescription</key>
	<string>Usado para escolher a logomarca da propriedade.</string>
	<key>UIFileSharingEnabled</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<true/>
	<key>CFBundleDisplayName</key>
	<string>Gestor do Coco</string>
"""
s = s.replace("<key>CFBundleDisplayName</key>\n\t<string>Gestor Producao Coco</string>\n", "")
i = s.rfind('</dict>')
s = s[:i] + extra + s[i:]
open(p, 'w', encoding='utf-8').write(s)
EOF
fi

# Versão web (PWA): nome, cores e modo "app" ao adicionar à tela inicial.
if [ -f web/manifest.json ]; then
  python3 - <<'EOF2'
import json, re
m = json.load(open('web/manifest.json', encoding='utf-8'))
m.update({'name': 'Gestor do Coco', 'short_name': 'Gestor do Co', 'background_color': '#FFFFFF',
          'theme_color': '#2E6B3A', 'display': 'standalone', 'orientation': 'portrait'})
json.dump(m, open('web/manifest.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
h = open('web/index.html', encoding='utf-8').read()
h = re.sub(r'<title>.*?</title>', '<title>Gestor do Coco</title>', h)
h = re.sub(r'(name="apple-mobile-web-app-title" content=")[^"]*', r'\1Gestor do Coco', h)
if 'theme-color' not in h:
    h = h.replace('</head>', '  <meta name="theme-color" content="#2E6B3A">\n</head>')
open('web/index.html', 'w', encoding='utf-8').write(h)
EOF2
fi

# Ícone do app (Android e iPhone) a partir de assets/icon.
flutter pub get
dart run flutter_launcher_icons

echo "Plataformas prontas. Agora: flutter run"
