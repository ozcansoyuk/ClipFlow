# ClipFlow

macOS menü çubuğunda yaşayan, hafif ve tamamen yerel bir **pano geçmişi yöneticisi** ve **notlu ekran görüntüsü aracı**.

*A lightweight, fully local clipboard history manager and annotated screenshot tool for the macOS menu bar.*

## Özellikler

- **Pano geçmişi** — son 10 metin/görsel kopyalama bellekte tutulur; `⌘⇧V` ile imlecin yanında açılan panelden ok tuşları + Return ile seçilir.
- **Sabitleme** — sık kullanılan ögeler sabitlenir ve yeniden başlatmada korunur.
- **Doğrudan yapıştır (isteğe bağlı)** — Erişilebilirlik izni verilirse seçilen öge imlecin olduğu yere otomatik yapıştırılır; izin yoksa öge panoya kopyalanır, `⌘V` ile siz yapıştırırsınız.
- **Ekran görüntüsü** — `⌘⇧S` ekranı dondurur; bölge seçip kalem, çizgi, ok, dikdörtgen, elips ve metin notları ekleyip sonucu panoya kopyalarsınız.
- **Ayarlanabilir kısayollar** — her iki kısayol da Ayarlar'dan değiştirilebilir.

## Gizlilik

- Uygulamada **hiç ağ kodu yok**, ağ yetkisi istenmez; veri cihazdan çıkmaz.
- Geçmiş yalnızca bellekte tutulur; diske yalnızca sabitlenen ögeler yazılır.
- Parola yöneticilerinin gizli/geçici olarak işaretlediği ögeler (`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`) **hiç kaydedilmez**.
- Klavye izlenmez: global kısayol `RegisterEventHotKey` ile kaydedilir, olay dinleyicisi (event tap) yoktur.

## Gereksinimler

- macOS 14 (Sonoma) veya üstü — Apple Silicon ve Intel (universal binary)
- Swift 5.9+ (Xcode veya Command Line Tools)
- Kod imzalama için bir **Apple Development** sertifikası (ücretsiz Apple hesabıyla Xcode'dan oluşturulabilir)

## Kurulum

```sh
git clone https://github.com/ozcansoyuk/ClipFlow.git
cd ClipFlow
./install.sh            # ~/Applications/ClipFlow.app olarak derler, imzalar, başlatır
```

`install.sh` anahtar zincirindeki ilk Apple Development sertifikasını kullanır. Başka bir kimlik için:

```sh
CLIPFLOW_SIGN_IDENTITY="Apple Development: ad@ornek.com (TEAMID)" ./install.sh
```

> **Neden ad-hoc imza değil?** macOS Erişilebilirlik iznini kod imzasına bağlar. Ad-hoc imza (`-`) her derlemede değiştiği için izin her seferinde sıfırlanır; sabit bir geliştirici kimliği bu sorunu ortadan kaldırır.

`install-sandboxed.sh`, Mac App Store yapılandırmasının (App Sandbox açık) yerel provasıdır ve varsa eski sabitlenmiş ögeleri sandbox container'ına taşır.

## İzinler

| İzin | Ne için | Verilmezse |
|---|---|---|
| Erişilebilirlik | Seçilen ögeyi `⌘V` tuş vuruşuyla doğrudan yapıştırmak | Öge yine panoya kopyalanır |
| Ekran ve Sistem Sesi Kaydı | Yalnızca kısayola basıldığında tek kare ekran görüntüsü almak | Yalnızca ekran görüntüsü özelliği kapanır |

## Proje yapısı

```
Sources/ClipFlow/
├── AppDelegate.swift, main.swift      # menü çubuğu uygulaması
├── PasteboardMonitor.swift            # pano değişikliklerini izler
├── ClipboardStore.swift, ImageStore.swift, ClipboardItem.swift
├── PanelController.swift, ClipboardPanel.swift, Paster.swift
├── HotkeyManager.swift, HotkeyConfig.swift
├── Capture/                           # ekran görüntüsü + not araçları
└── UI/                                # SwiftUI görünümleri (liste, ayarlar, tanıtım)
Support/                               # Info.plist, entitlements
AppStore/                              # App Review notları
```

## Lisans

[MIT](LICENSE) © 2026 Özcan Soyuk
