import SwiftUI
import StoreKit
import CitySprintCore

struct GarageView: View {
    @Environment(AppModel.self) private var app
    @State private var slot: CosmeticSlot = .bike

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RiderPreview(bike: app.item(for: .bike), jersey: app.item(for: .jersey), helmet: app.item(for: .helmet))
                    .frame(height: 170)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Your rider: \(app.item(for: .bike).displayName) bike, \(app.item(for: .jersey).displayName) jersey, \(app.item(for: .helmet).displayName) helmet"))

                Picker("Category", selection: $slot) {
                    ForEach(CosmeticSlot.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("garageSlotPicker")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(CosmeticCatalog.items(for: slot)) { item in
                        CosmeticTile(item: item)
                    }
                }

                SupporterSection()

                Text("Everything here is cosmetic and earned by riding. Nothing affects gameplay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Garage")
    }
}

private struct CosmeticTile: View {
    @Environment(AppModel.self) private var app
    let item: CosmeticItem

    var body: some View {
        let unlocked = CosmeticCatalog.isUnlocked(item, in: app.progress, isSupporter: app.isSupporter)
        let equipped = app.progress.loadout.id(for: item.slot) == item.id && unlocked
        let progress = item.requirement.progress(in: app.progress, isSupporter: app.isSupporter)
        Button {
            app.equip(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(item.primary.color).frame(width: 28, height: 28)
                    Circle().fill(item.secondary.color).frame(width: 18, height: 18)
                    Spacer()
                    if equipped {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if !unlocked {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                }
                Text(item.displayName).font(.headline).lineLimit(2)
                if !unlocked {
                    Text(item.requirement.displayText).font(.caption).foregroundStyle(.secondary)
                    if item.requirement != .supporter {
                        ProgressView(value: progress)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(equipped ? Color.green : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.displayName))
        .accessibilityValue(equipped ? Text("Equipped") : (unlocked ? Text("Unlocked") : Text("Locked. \(item.requirement.displayText)")))
        .accessibilityAddTraits(equipped ? [.isButton, .isSelected] : .isButton)
    }
}

private struct SupporterSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Supporter Pack", systemImage: "heart.fill").font(.headline)
            Text("A one-time purchase that supports development and adds three gold cosmetic items. It does not change gameplay.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if app.isSupporter {
                Label("Thank you for your support!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if let product = app.store.supporterProduct {
                Button {
                    Task { await app.store.purchaseSupporter() }
                } label: {
                    Text("Buy for \(product.displayPrice)")
                }
                .buttonStyle(PrimaryButtonStyle(tint: .pink))
                .disabled(app.store.purchaseState == .purchasing)
            } else {
                Text(app.store.productsLoaded ? LocalizedStringKey("Not available right now.") : LocalizedStringKey("Loading…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            switch app.store.purchaseState {
            case .pending:
                Text("Purchase pending approval.").font(.footnote)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            default:
                EmptyView()
            }
            Button("Restore Purchases") {
                Task { await app.store.restore() }
            }
            .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Top-down rider preview matching the in-game sprite.
struct RiderPreview: View {
    let bike: CosmeticItem
    let jersey: CosmeticItem
    let helmet: CosmeticItem

    var body: some View {
        Canvas { ctx, size in
            let w = min(size.width, size.height * 0.5)
            let h = w * 2
            let r = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
            let wheelW = r.width * 0.16
            ctx.fill(Path(roundedRect: CGRect(x: r.midX - wheelW / 2, y: r.minY, width: wheelW, height: r.height * 0.32),
                          cornerRadius: wheelW / 2), with: .color(.black))
            ctx.fill(Path(roundedRect: CGRect(x: r.midX - wheelW / 2, y: r.minY + r.height * 0.68, width: wheelW,
                                              height: r.height * 0.32), cornerRadius: wheelW / 2), with: .color(.black))
            ctx.fill(Path(CGRect(x: r.midX - wheelW * 0.35, y: r.minY + r.height * 0.15, width: wheelW * 0.7,
                                 height: r.height * 0.7)), with: .color(bike.primary.color))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.2, width: r.width * 0.76,
                                              height: r.height * 0.05), cornerRadius: 2), with: .color(bike.secondary.color))
            let torso = CGRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.3, width: r.width * 0.64,
                               height: r.height * 0.36)
            ctx.fill(Path(roundedRect: torso, cornerRadius: r.width * 0.3), with: .color(jersey.primary.color))
            ctx.fill(Path(CGRect(x: torso.minX + torso.width * 0.12, y: torso.midY - 3, width: torso.width * 0.76, height: 6)),
                     with: .color(jersey.secondary.color))
            let hd = r.width * 0.44
            let helmetRect = CGRect(x: r.midX - hd / 2, y: r.minY + r.height * 0.24, width: hd, height: hd * 1.15)
            ctx.fill(Path(ellipseIn: helmetRect), with: .color(helmet.primary.color))
            ctx.fill(Path(CGRect(x: helmetRect.midX - 2, y: helmetRect.minY + 4, width: 4, height: helmetRect.height - 8)),
                     with: .color(helmet.secondary.color))
        }
    }
}
