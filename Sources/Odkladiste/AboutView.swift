import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject private var l10n = L10n.shared

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 84)

            VStack(spacing: 4) {
                Text("Odkladiště")
                    .font(.system(size: 20, weight: .bold))

                Text(l10n.t("Verze \(appVersion)", "Version \(appVersion)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(l10n.t(
                "Minimalistické plovoucí poličky pro bezpečné odkládání a předávání souborů mezi okny, aplikacemi a monitory.",
                "Minimalist floating shelves for safely staging and transferring files across windows, apps, and displays."
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                badge(l10n.t("Licence MIT", "MIT License"))
                badge(l10n.t("Bez telemetrie", "Zero Telemetry"))
                badge("macOS 14+")
            }

            Divider()
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/zyxlit/odkladiste")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: URL(string: "https://buymeacoffee.com/cameklibor")!) {
                    Label(l10n.t("Podpořit kávou", "Buy Me a Coffee"), systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("© 2026 Odkladiste Contributors")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 340)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
