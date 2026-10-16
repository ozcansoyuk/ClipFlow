import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Model

/// Hoş geldiniz / izin tanıtım ekranının durumu.
///
/// Erişilebilirlik izni için TCC değişiklik bildirimi olmadığından pencere
/// açıkken kısa aralıklarla yoklanır; kullanıcı Sistem Ayarları'nda anahtarı
/// açtığı anda arayüz "verildi" durumuna geçer.
final class OnboardingModel: ObservableObject {
    @Published var axGranted = AXIsProcessTrusted()
    @Published var screenGranted = ScreenCapturer.hasPermission
    @Published var hotkeyDisplay: String

    /// "Başla" düğmesi pencereyi kapatır.
    var onFinish: (() -> Void)?

    private var pollTimer: Timer?

    init(hotkeyDisplay: String) {
        self.hotkeyDisplay = hotkeyDisplay
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        axGranted = AXIsProcessTrusted()
        screenGranted = ScreenCapturer.hasPermission
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Sistem diyaloğunu tetikler (uygulamayı Erişilebilirlik listesine
    /// kaydettirir) ve kullanıcıyı doğrudan ilgili ayar bölmesine götürür.
    func requestPermission() {
        Paster.ensureAccessibilityPermission(prompt: true)
        openAccessibilitySettings()
    }

    /// İlk seferde sistem diyaloğunu gösterir, ardından ayar bölmesini açar.
    func requestScreenPermission() {
        ScreenCapturer.requestPermission()
        ScreenCapturer.openPermissionSettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Görünüm

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                Text("ClipFlow'a Hoş Geldiniz")
                    .font(.title2.weight(.bold))
                Text("Menü çubuğunda yaşayan hafif, hızlı pano geçmişi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            // Özellikler
            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    symbol: "keyboard",
                    title: "Her yerden açın",
                    detail: "\(model.hotkeyDisplay) ile panel imlecin yanında belirir. " +
                        "Ok tuşları, ↩ ve 1–9 ile seçim yapın; kısayolu Ayarlar'dan değiştirin."
                )
                featureRow(
                    symbol: "camera.viewfinder",
                    title: "Ekran görüntüsü + işaretleme",
                    detail: "Ekran görüntüsü kısayoluyla bir bölge seçin; ok, çizgi, şekil ve yazı " +
                        "ekleyip ⌘C ile panoya kopyalayın. Görüntü geçmişe de eklenir."
                )
                featureRow(
                    symbol: "pin.fill",
                    title: "Önemlileri sabitleyin",
                    detail: "Sabitlenen ögeler yeniden başlatmalarda korunur; " +
                        "geri kalan geçmiş yalnızca bellekte tutulur."
                )
                featureRow(
                    symbol: "lock.shield.fill",
                    title: "Gizlilik önce gelir",
                    detail: "Tüm veriler yalnızca bu Mac'te kalır — ClipFlow internete hiç bağlanmaz. " +
                        "Parola yöneticilerinden kopyalananlar asla kaydedilmez."
                )
            }
            .padding(.horizontal, 28)

            Divider()
                .padding(.vertical, 18)
                .padding(.horizontal, 28)

            // Erişilebilirlik izni (isteğe bağlı)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: model.axGranted ? "checkmark.circle.fill" : "hand.raised.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(model.axGranted ? Color.green : Color.orange)
                    Text("Otomatik Yapıştırma")
                        .font(.headline)
                    Text("— isteğe bağlı")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Seçtiğiniz ögenin imlecin olduğu yere kendiliğinden yapıştırılması için " +
                    "macOS, Erişilebilirlik izni ister. ClipFlow bu izni yalnızca tek bir ⌘V " +
                    "tuş vuruşu göndermek için kullanır; klavyeniz asla izlenmez veya kaydedilmez."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.axGranted {
                    Label("İzin verildi — otomatik yapıştırma hazır.", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.green)
                        .padding(.top, 2)
                } else {
                    HStack(spacing: 10) {
                        Button("İzin Ver…") {
                            model.requestPermission()
                        }
                        .keyboardShortcut(.defaultAction)

                        Button("Sistem Ayarları'nı Aç") {
                            model.openAccessibilitySettings()
                        }
                    }
                    .padding(.top, 2)

                    Text(
                        "İzin vermeseniz de ClipFlow eksiksiz çalışır: seçtiğiniz öge panoya " +
                        "kopyalanır, ⌘V ile kendiniz yapıştırırsınız."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)

            Divider()
                .padding(.vertical, 18)
                .padding(.horizontal, 28)

            // Ekran Kaydı izni (yalnızca ekran görüntüsü için)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: model.screenGranted ? "checkmark.circle.fill" : "hand.raised.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(model.screenGranted ? Color.green : Color.orange)
                    Text("Ekran Görüntüsü")
                        .font(.headline)
                    Text("— Ekran Kaydı izni")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Bölge seçip işaretleyebilmeniz için macOS, Ekran Kaydı izni ister. ClipFlow " +
                    "ekranı yalnızca kısayola bastığınız anda bir kez yakalar; video kaydetmez, " +
                    "hiçbir görüntüyü bu Mac'in dışına göndermez."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.screenGranted {
                    Label("İzin verildi — ekran görüntüsü hazır.", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.green)
                        .padding(.top, 2)
                } else {
                    HStack(spacing: 10) {
                        Button("İzin Ver…") {
                            model.requestScreenPermission()
                        }

                        Button("Sistem Ayarları'nı Aç") {
                            ScreenCapturer.openPermissionSettings()
                        }
                    }
                    .padding(.top, 2)

                    Text("İzni verdikten sonra macOS, ClipFlow'u yeniden açmanızı isteyebilir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)

            // Alt çubuk
            HStack {
                Spacer()
                Button("Başla") {
                    model.onFinish?()
                }
                .controlSize(.large)
                .keyboardShortcut(model.axGranted ? .defaultAction : .cancelAction)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
        .frame(width: 470)
    }

    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Pencere denetleyicisi

/// İlk açılışta ve menüden "Hoş Geldiniz…" ile gösterilen tanıtım penceresi.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: OnboardingModel

    init(model: OnboardingModel) {
        self.model = model
        super.init()
        model.onFinish = { [weak self] in
            self?.window?.close()
        }
    }

    func show(hotkeyDisplay: String) {
        model.hotkeyDisplay = hotkeyDisplay
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "ClipFlow"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            window.delegate = self
            self.window = window
        }
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}
