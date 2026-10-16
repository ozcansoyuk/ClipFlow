#!/bin/zsh
# ClipFlow: derle, paketle, SABİT kimlikle imzala ve yeniden başlat.
#
# ÖNEMLİ: Ad-hoc imza ("-") KULLANMAYIN! macOS, Erişilebilirlik iznini kod
# imzasına bağlar; ad-hoc imza her derlemede değiştiği için izin sıfırlanır.
# Apple Development sertifikası Team ID tabanlı sabit kimlik sağlar — izin
# yeniden derlemelerde korunur.
set -e

# İmza kimliği: CLIPFLOW_SIGN_IDENTITY ile verilebilir; verilmezse anahtar
# zincirindeki ilk "Apple Development" sertifikası kullanılır.
IDENTITY="${CLIPFLOW_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
    echo "✗ İmza kimliği bulunamadı. Xcode'da bir Apple Development sertifikası oluşturun"
    echo "  veya CLIPFLOW_SIGN_IDENTITY=\"...\" ile belirtin (security find-identity -v -p codesigning)."
    exit 1
fi
APP="$HOME/Applications/ClipFlow.app"

cd "$(dirname "$0")"
# Yalnızca Command Line Tools kuruluysa: macOS 27 SDK'sında SwiftUI @State bir
# makrodur ve makro eklentisi (SwiftUIMacros) yalnızca Xcode ile gelir. Bu
# durumda eklenti gerektirmeyen son SDK (26.5) ile derlenir.
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d "$CLT_SDK" ]]; then
    export SDKROOT="$CLT_SDK"
fi
# Universal binary: hem Apple Silicon (arm64) hem Intel (x86_64) Mac'lerde
# çalışır. Tek mimarili derleme Intel MacBook'larda hiç açılmaz.
swift build -c release --arch arm64 --arch x86_64

pkill -x ClipFlow 2>/dev/null || true
sleep 1

mkdir -p "$APP/Contents/MacOS"
# Çıktı klasörü Swift sürümüne göre değişir (.build/apple → .build/out);
# yolu SwiftPM'e sor, sabit yazma.
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_PATH/ClipFlow" "$APP/Contents/MacOS/ClipFlow"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" "$APP"

open "$APP"
echo "✓ ClipFlow kuruldu ve başlatıldı: $APP"
