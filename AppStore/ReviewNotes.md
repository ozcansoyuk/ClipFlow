# App Review Notes — ClipFlow (Clipboard Manager)

> App Store Connect → App Review Information → Notes alanına aşağıdaki İngilizce
> metni yapıştırın.

---

Dear App Review Team,

ClipFlow is a lightweight, fully sandboxed clipboard history manager that lives
exclusively in the macOS menu bar. We would like to proactively explain our use
of system capabilities so you can verify that the app complies with the App
Sandbox and all privacy requirements.

## 1. What the app does

ClipFlow keeps the user's 10 most recent clipboard items (text and images) in
memory, lets the user pin favorites for persistence, and presents them in a
small panel summoned with a user-configurable global keyboard shortcut
(default: Cmd+Shift+V). Selecting an item places it back on the system
pasteboard.

ClipFlow also includes a screenshot tool: a second user-configurable shortcut
(default: Cmd+Shift+S) freezes the screen, lets the user select a region, add
simple annotations (pen, line, arrow, rectangle, ellipse, text) and copy the
result to the pasteboard.

## 2. Why the app asks the user for Accessibility permission (optional feature)

When the user selects an item from the panel, ClipFlow offers an optional
convenience called "paste directly": it synthesizes a single Cmd+V keystroke
via the CGEvent API so the selected item is inserted at the user's current
cursor location, exactly like established clipboard managers on the Mac App
Store.

Key facts we would like to highlight:

- **This permission is granted solely by the user** in System Settings >
  Privacy & Security > Accessibility. The app contains no entitlement
  exceptions for it and never attempts to bypass consent.
- **The feature is strictly optional and the app degrades gracefully.** If the
  user declines, every feature of the app continues to work: the selected item
  is still copied to the pasteboard and the user simply presses Cmd+V
  themselves. The app never blocks functionality behind the permission.
- **We never observe, intercept, or record keyboard input.** The CGEvent API is
  used in one direction only — to *send* one Cmd+V keystroke, only at the
  moment the user explicitly clicks or selects an item. There are no event
  taps, no input monitoring, and no key logging of any kind.
- **The global hotkey does not monitor the keyboard either.** It is implemented
  with the system-provided `RegisterEventHotKey` API, which invokes the app
  only when the exact registered combination is pressed and exposes no other
  keystrokes to the app.

## 2b. Why the app asks for Screen Recording permission (screenshot feature)

The screenshot tool uses ScreenCaptureKit (`SCScreenshotManager`) to take a
single still image of the displays **only at the moment the user presses the
screenshot shortcut or chooses "Ekran Görüntüsü Al" from the menu**. There is
no continuous capture, no video recording, and nothing is captured in the
background. The image stays in memory until the user copies the selected
region to the pasteboard or cancels with Esc. If permission is not granted,
only the screenshot feature is unavailable; the clipboard manager keeps
working.

## 3. Privacy: 100% local, zero data collection

- The app contains **no networking code whatsoever** and requests **no network
  entitlements** — this is verifiable in the binary's entitlements. Clipboard
  data cannot leave the device through the app.
- Clipboard history lives in memory only. The only data written to disk are the
  items the user explicitly pins, stored as a small JSON file plus image files
  inside the app's own sandbox container.
- ClipFlow respects the standard clipboard privacy conventions: items flagged
  by password managers as concealed/transient
  (`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`) are
  **never** recorded.
- No analytics, no third-party SDKs, no accounts, no data collection of any
  kind.

## 4. How to test

1. Launch ClipFlow — a clipboard icon appears in the menu bar (the app is a
   menu bar utility; it intentionally shows no Dock icon).
2. Copy a few pieces of text and/or images in any app.
3. Press Cmd+Shift+V — the history panel opens at the cursor. Navigate with the
   arrow keys, press Return (or click) to select.
4. *Without* Accessibility permission: the item is copied to the clipboard and
   can be pasted manually with Cmd+V — the app remains fully functional.
5. *With* Accessibility permission (System Settings > Privacy & Security >
   Accessibility > enable ClipFlow): selecting an item additionally pastes it
   directly at the cursor position.
6. Pin an item with the pin button, relaunch the app, and observe that pinned
   items persist while regular history does not.
7. Grant Screen Recording (System Settings > Privacy & Security > Screen &
   System Audio Recording > enable ClipFlow), relaunch, press Cmd+Shift+S,
   drag a region, draw an arrow, press Cmd+C and paste into any app (or open
   the history panel with Cmd+Shift+V to see the screenshot there).

Thank you for your time reviewing ClipFlow. We are happy to provide any
additional technical details, a demo video, or source-level explanations on
request.

Best regards,
The ClipFlow Team

---

## Ek: App Store Connect kontrol listesi (dahili, başvuruya eklemeyin)

- [ ] Hedef: "App Sandbox" capability açık, `ClipFlow.entitlements` bağlı.
- [ ] İmza: "Apple Distribution" sertifikası + Mac App Store provisioning
      profile (geliştirme sertifikası MAS'a yüklenemez).
- [ ] Kategori: Productivity / Utilities.
- [ ] Privacy "Nutrition Label": **Data Not Collected** (ağ kodu yok — bu beyanla
      birebir tutarlı).
- [ ] Uygulama içi onboarding: Erişilebilirlik iznini İSTEĞE BAĞLI olarak sunan,
      "Sistem Ayarları'nı Aç" düğmeli bir ekran (App Review, izin akışının
      kullanıcıya net anlatılmasını ister).
- [ ] Ekran görüntülerinde panel + sabitleme + kısayol ayarı gösterilsin.
- [ ] Ekran Kaydı izni tanıtım ekranında gerekçesiyle sunuluyor (ekran görüntüsü
      özelliği); izin yoksa yalnızca bu özellik devre dışı kalır.
