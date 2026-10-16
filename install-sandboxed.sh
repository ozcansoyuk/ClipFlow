#!/bin/zsh
# ClipFlow: SANDBOX'lı test derlemesi — Mac App Store yapılandırmasının
# birebir yerel provası.
#
# Sandbox açıkken uygulamanın tüm verisi container'a taşınır:
#   ~/Library/Containers/com.ozcan.clipflow/Data/Library/Application Support/ClipFlow
# Bu betik, eski (sandbox'sız) kurulumun sabitlenmiş ögelerini ilk geçişte
# container'a kopyalar; mevcut veriniz kaybolmaz.
#
# İmza kuralı install.sh ile aynıdır: ad-hoc imza ("-") KULLANMAYIN —
# Erişilebilirlik izni kod imzasına bağlıdır, sabit kimlik şarttır.
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
ENTITLEMENTS="Support/ClipFlow.entitlements"
CONTAINER="$HOME/Library/Containers/com.ozcan.clipflow"
CONTAINER_DATA="$CONTAINER/Data/Library/Application Support/ClipFlow"
LEGACY="$HOME/Library/Application Support/ClipFlow"

cd "$(dirname "$0")"
# Yalnızca Command Line Tools kuruluysa: macOS 27 SDK'sında SwiftUI @State bir
# makrodur ve makro eklentisi (SwiftUIMacros) yalnızca Xcode ile gelir. Bu
# durumda eklenti gerektirmeyen son SDK (26.5) ile derlenir.
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d "$CLT_SDK" ]]; then
    export SDKROOT="$CLT_SDK"
fi
# Universal binary: Apple Silicon + Intel.
swift build -c release --arch arm64 --arch x86_64

pkill -x ClipFlow 2>/dev/null || true
sleep 1

mkdir -p "$APP/Contents/MacOS"
# Çıktı klasörü Swift sürümüne göre değişir (.build/apple → .build/out);
# yolu SwiftPM'e sor, sabit yazma.
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_PATH/ClipFlow" "$APP/Contents/MacOS/ClipFlow"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Tek fark: --entitlements ile App Sandbox açılır.
codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"

# Eski veri var, container'da henüz yok → göç gerekiyor mu?
NEEDS_MIGRATION=0
if [[ -d "$LEGACY" && ! -e "$CONTAINER_DATA/pinned.json" ]]; then
    NEEDS_MIGRATION=1
fi

open "$APP"

if [[ $NEEDS_MIGRATION == 1 ]]; then
    # Container, ilk sandbox'lı açılışta containermanagerd tarafından
    # oluşturulur (elle oluşturmak güvenli değildir) — hazır olmasını bekle.
    for i in {1..20}; do
        [[ -d "$CONTAINER/Data/Library/Application Support" ]] && break
        sleep 0.5
    done
    pkill -x ClipFlow 2>/dev/null || true
    sleep 1
    mkdir -p "$CONTAINER_DATA"
    cp -R "$LEGACY/." "$CONTAINER_DATA/"
    echo "✓ Eski sabitlenmiş ögeler container'a taşındı: $CONTAINER_DATA"
    open "$APP"
fi

echo "✓ Sandbox'lı ClipFlow kuruldu ve başlatıldı: $APP"
echo "— Entitlement doğrulaması:"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -B1 -A1 "app-sandbox" || true
