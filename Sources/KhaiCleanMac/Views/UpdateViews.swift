import SwiftUI

/// Settings › About: installed vs. latest version, a manual check, and the download button.
struct UpdateStatusCard: View {
    private var checker: UpdateChecker { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GradientIcon(symbol: symbol, colors: colors, size: 36, corner: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if checker.status == .checking {
                    ProgressView().controlSize(.small)
                } else if checker.isUpdateAvailable {
                    UpdateButton()
                } else {
                    Button(L("Cek sekarang", "Check now")) { Task { await checker.check() } }
                        .buttonStyle(SoftButtonStyle())
                }
            }
            if checker.isUpdateAvailable, let notes = checker.latest?.notes {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
            if checker.isUpdateAvailable { InstallProgressNote() }
        }
    }

    private var title: String {
        switch checker.status {
        case .checking:
            return L("Mengecek pembaruan…", "Checking for updates…")
        case .failed:
            return L("Tidak bisa mengecek pembaruan", "Couldn't check for updates")
        case .idle:
            return L("Versi \(AppInfo.version) terpasang", "Version \(AppInfo.version) installed")
        case .upToDate, .available:
            guard let latest = checker.latest else { return "" }
            if checker.isUpdateAvailable {
                return L("Versi \(latest.version) sudah tersedia", "Version \(latest.version) is available")
            }
            return checker.installed == nil
                ? L("Versi terbaru: \(latest.version)", "Latest version: \(latest.version)")
                : L("Kamu memakai versi terbaru", "You're up to date")
        }
    }

    private var subtitle: String {
        switch checker.status {
        case .failed:
            return L("Periksa koneksi internet, lalu coba lagi.", "Check your internet connection and try again.")
        case .idle, .checking:
            return L("Terpasang: \(AppInfo.version)", "Installed: \(AppInfo.version)")
        case .upToDate, .available:
            var parts = [L("Terpasang: \(AppInfo.version)", "Installed: \(AppInfo.version)")]
            if let latest = checker.latest {
                if checker.isUpdateAvailable, let size = latest.size { parts.append(size.formattedBytes) }
                if let date = latest.releasedAt {
                    let when = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppSettings.shared.locale))
                    parts.append(L("rilis \(when)", "released \(when)"))
                }
            }
            if let last = AppSettings.shared.lastUpdateCheck {
                let when = last.formatted(Date.RelativeFormatStyle(presentation: .named).locale(AppSettings.shared.locale))
                parts.append(L("dicek \(when)", "checked \(when)"))
            }
            return parts.joined(separator: " · ")
        }
    }

    private var symbol: String {
        switch checker.status {
        case .available: "arrow.down.circle.fill"
        case .failed: "wifi.exclamationmark"
        case .upToDate: "checkmark.seal.fill"
        case .idle, .checking: "arrow.triangle.2.circlepath"
        }
    }

    private var colors: [Color] {
        switch checker.status {
        case .available: Palette.mint
        case .failed: Palette.berry
        case .upToDate: Palette.leaf
        case .idle, .checking: Palette.lavender
        }
    }
}

/// Home: shown only when a newer version is out.
struct UpdateBanner: View {
    private var checker: UpdateChecker { .shared }

    var body: some View {
        if checker.isUpdateAvailable, let latest = checker.latest {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    GradientIcon(symbol: "arrow.down.circle.fill", colors: Palette.mint, size: 40, corner: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("KhaiCleanMac \(latest.version) sudah tersedia", "KhaiCleanMac \(latest.version) is available"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(latest.notes ?? (checker.canInstallInApp
                            ? L("Kamu memakai versi \(AppInfo.version). Perbarui sekarang, aplikasi akan dibuka ulang otomatis.",
                                "You have version \(AppInfo.version). Update now; the app reopens by itself.")
                            : L("Kamu memakai versi \(AppInfo.version). Unduh versi baru lalu ganti aplikasi di folder Applications.",
                                "You have version \(AppInfo.version). Download the new one and replace the app in Applications.")))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    Button(L("Apa yang baru", "What's new")) { checker.openProjectPage() }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(checker.installStep.isBusy)
                    UpdateButton(showsSize: true)
                }
                InstallProgressNote()
            }
            .softCard(padding: 16)
        }
    }
}

/// "Update" installs in place when the release has a checksum; otherwise it opens the browser download.
struct UpdateButton: View {
    var showsSize = false
    private var checker: UpdateChecker { .shared }

    var body: some View {
        if checker.installStep.isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(InstallProgressNote.busyText(checker.installStep))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        } else if checker.canInstallInApp {
            Button {
                Task { await checker.install() }
            } label: {
                Label(sized(L("Perbarui", "Update")), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(GradientButtonStyle(colors: Palette.mint))
            .help(L("Diunduh, dicek SHA-256 dan tanda tangannya, lalu dipasang dan dibuka ulang.",
                    "Downloaded, checked against its SHA-256 and signature, then installed and reopened."))
        } else {
            Button {
                checker.openDownload()
            } label: {
                Label(sized(L("Unduh", "Download")), systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(GradientButtonStyle(colors: Palette.mint))
        }
    }

    private func sized(_ title: String) -> String {
        guard showsSize, let size = checker.latest?.size else { return title }
        return "\(title) · \(size.formattedBytes)"
    }
}

/// Explains a failed in-app install, with the manual download as the way out.
struct InstallProgressNote: View {
    private var checker: UpdateChecker { .shared }

    static func busyText(_ step: UpdateChecker.InstallStep) -> String {
        switch step {
        case .downloading: L("Mengunduh…", "Downloading…")
        case .verifying: L("Memeriksa keaslian…", "Verifying…")
        case .installing: L("Memasang…", "Installing…")
        case .idle, .failed: ""
        }
    }

    static func failureText(_ failure: AppUpdater.Failure) -> String {
        switch failure {
        case .download:
            L("Unduhan gagal. Periksa koneksi lalu coba lagi.", "The download failed. Check your connection and try again.")
        case .checksumMismatch:
            L("File unduhan tidak cocok dengan checksum resmi, jadi tidak dipasang.",
              "The download doesn't match the official checksum, so it wasn't installed.")
        case .mount:
            L("File DMG tidak bisa dibuka.", "The disk image couldn't be opened.")
        case .appMissing, .wrongApp, .wrongVersion:
            L("Isi DMG bukan KhaiCleanMac versi yang diumumkan, jadi tidak dipasang.",
              "The disk image doesn't hold the announced KhaiCleanMac version, so it wasn't installed.")
        case .badSignature:
            L("Tanda tangan kode versi baru tidak cocok, jadi tidak dipasang.",
              "The new version's code signature doesn't check out, so it wasn't installed.")
        case .notInstallable, .install:
            L("Aplikasi tidak bisa diganti dari sini. Unduh manual lalu ganti di folder Applications.",
              "The app couldn't be replaced from here. Download it and replace it in Applications.")
        }
    }

    var body: some View {
        if case .failed(let failure) = checker.installStep {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.berry[0])
                Text(Self.failureText(failure))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(L("Unduh manual", "Download manually")) { checker.openDownload() }
                    .buttonStyle(SoftButtonStyle())
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.berry[0].opacity(0.08)))
        }
    }
}
