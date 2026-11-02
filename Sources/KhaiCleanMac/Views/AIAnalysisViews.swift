import SwiftUI

/// "Ask AI" next to a screen's main action. Hidden until a provider is picked in Settings › AI.
struct AIReviewButton: View {
    let inputs: () -> [AIAnalyst.Input]
    @State private var shown: [AIAnalyst.Input]?
    private var settings: AppSettings { .shared }

    var body: some View {
        if settings.aiProvider != .off {
            Button {
                shown = inputs()
            } label: {
                Label(L("Tanya AI", "Ask AI"), systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle())
            .help(L("Pendapat kedua untuk paling banyak \(AIAnalyst.maxItems) item yang dipilih", "A second opinion on up to \(AIAnalyst.maxItems) selected items"))
            .sheet(isPresented: Binding(get: { shown != nil }, set: { if !$0 { shown = nil } })) {
                if let shown { AIAnalysisSheet(inputs: shown) }
            }
        }
    }
}

struct AIAnalysisSheet: View {
    let inputs: [AIAnalyst.Input]
    @Environment(\.dismiss) private var dismiss
    @State private var verdicts: [AIVerdict] = []
    @State private var error: AIAnalysisError?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GradientIcon(symbol: "sparkles", colors: Palette.grape, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Pendapat kedua dari AI", "AI second opinion"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(L("\(AppSettings.shared.aiProvider.title) · hanya saran, keputusan tetap di kamu", "\(AppSettings.shared.aiProvider.title) · advice only, the choice stays yours"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if isLoading {
                ProgressView(L("Menunggu jawaban…", "Waiting for an answer…"))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let error {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.berry[1])
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(inputs, id: \.path) { input in
                            row(input, verdict: verdicts.first { $0.path == input.path })
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            HStack {
                Text(L("AI bisa salah. Item yang ditandai aman tidak dipilih otomatis.", "AI can be wrong. Items marked safe aren't selected for you."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(L("Tutup", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .task {
            do {
                verdicts = try await AIAnalyst.analyze(inputs, provider: AppSettings.shared.aiProvider)
            } catch let failure as AIAnalysisError {
                error = failure
            } catch {
                self.error = .failed(error.localizedDescription)
            }
            isLoading = false
        }
    }

    private func row(_ input: AIAnalyst.Input, verdict: AIVerdict?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            badge(verdict?.verdict)
            VStack(alignment: .leading, spacing: 2) {
                Text(input.path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(verdict?.reason ?? L("Tidak ada jawaban untuk item ini.", "No answer for this item."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(input.size.formattedBytes)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func badge(_ kind: AIVerdict.Kind?) -> some View {
        let (title, colors): (String, [Color]) = switch kind {
        case .safe: (L("Aman", "Safe"), Palette.leaf)
        case .check: (L("Periksa", "Check"), Palette.sunny)
        case .keep: (L("Simpan", "Keep"), Palette.berry)
        case nil: ("—", Palette.slate)
        }
        return Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 58)
            .padding(.vertical, 3)
            .background(Capsule().fill(LinearGradient.soft(colors)))
    }
}
