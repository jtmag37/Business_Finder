import Foundation
import Observation
import StoreKit
import CitySprintCore

/// StoreKit 2. Entitlements come only from transactions that pass on-device
/// JWS verification (`VerificationResult.verified`). Unverified transactions
/// are ignored and never finished as successful grants.
@MainActor
@Observable
final class StoreService {
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pending
        case failed(String)
    }

    private(set) var supporterProduct: Product?
    private(set) var isSupporter: Bool
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var productsLoaded = false

    private let keychain: KeychainStore
    private let enabled: Bool
    private var updatesTask: Task<Void, Never>?
    private static let entitlementCacheKey = "supporter.entitlement"

    init(keychain: KeychainStore = KeychainStore(), enabled: Bool = AppConfig.appleServicesEnabled) {
        self.keychain = keychain
        self.enabled = enabled
        // Offline fallback until StoreKit answers. StoreKit's own on-device
        // signed cache is authoritative and refreshes this at launch.
        isSupporter = enabled ? keychain.bool(for: StoreService.entitlementCacheKey) : false
    }

    func start() {
        guard enabled, updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        guard enabled else { return }
        do {
            let products = try await Product.products(for: AppConfig.knownProductIDs)
            supporterProduct = products.first { $0.id == AppConfig.supporterProductID }
        } catch {
            supporterProduct = nil
        }
        productsLoaded = true
    }

    func purchaseSupporter() async {
        guard let product = supporterProduct, purchaseState != .purchasing else { return }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// "Restore Purchases": asks the App Store to resync, then re-reads the
    /// verified entitlements.
    func restore() async {
        guard enabled else { return }
        do {
            try await AppStore.sync()
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        guard enabled else { return }
        var snapshots: [TransactionSnapshot] = []
        for await entitlement in Transaction.currentEntitlements {
            snapshots.append(Self.snapshot(entitlement))
        }
        apply(EntitlementResolver.activeProducts(from: snapshots, knownProducts: AppConfig.knownProductIDs,
                                                 now: Date()))
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            // Never grant content for a transaction that failed verification.
            return
        }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func apply(_ active: Set<String>) {
        let supporter = active.contains(AppConfig.supporterProductID)
        isSupporter = supporter
        keychain.setBool(supporter, for: StoreService.entitlementCacheKey)
    }

    nonisolated static func snapshot(_ result: VerificationResult<Transaction>) -> TransactionSnapshot {
        switch result {
        case .verified(let t):
            return TransactionSnapshot(productID: t.productID, isVerified: true, revocationDate: t.revocationDate,
                                       expirationDate: t.expirationDate, isUpgraded: t.isUpgraded)
        case .unverified(let t, _):
            return TransactionSnapshot(productID: t.productID, isVerified: false)
        }
    }
}
