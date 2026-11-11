import UtterCore
import AppKit
import SwiftUI

// MARK: - License

final class LicenseForm: ObservableObject {
    @Published var key = ""
    @Published var message = ""
}

struct LicensePage: View {
    @ObservedObject private var license = LicenseManager.shared
    @StateObject private var form = LicenseForm()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "License", subtitle: "Utter is free to try for \(Trial.days) days.")

            Card {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .licensed = license.state {
                        Button("Remove") { license.deactivate() }.buttonStyle(SoftButtonStyle())
                    } else {
                        Button("Buy Utter") { NSWorkspace.shared.open(LicenseManager.purchaseURL) }
                            .buttonStyle(BrandButtonStyle())
                    }
                }
            }

            if case .licensed = license.state {} else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("License key").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 8) {
                            TextField("UTTER-…", text: $form.key)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                            Button("Activate") {
                                form.message = license.activate(form.key) ?? ""
                                if form.message.isEmpty { form.key = "" }
                            }
                            .buttonStyle(BrandButtonStyle())
                        }
                        Text(form.message.isEmpty ? "Paste the key from your purchase email. It's checked on this Mac; nothing is sent anywhere." : form.message)
                            .font(.system(size: 11))
                            .foregroundStyle(form.message.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.coral))
                    }
                }
            }
        }
        .onAppear { license.refresh() }
    }

    private var title: String {
        switch license.state {
        case .licensed(let info): "Licensed to \(info.name)"
        case .trial(let days): "Free trial: \(days) \(days == 1 ? "day" : "days") left"
        case .expired: "Your free trial has ended"
        }
    }

    private var detail: String {
        switch license.state {
        case .licensed(let info): "\(info.email) · \(info.edition.capitalized) · since \(info.issued.formatted(date: .abbreviated, time: .omitted))"
        case .trial: "Everything works during the trial."
        case .expired: "Buy a license to keep dictating. Your settings and dictionary are kept."
        }
    }

    private var icon: String {
        switch license.state {
        case .licensed: "checkmark.seal.fill"
        case .trial: "hourglass"
        case .expired: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch license.state {
        case .licensed: Theme.mint
        case .trial: Theme.violet
        case .expired: Theme.coral
        }
    }
}
