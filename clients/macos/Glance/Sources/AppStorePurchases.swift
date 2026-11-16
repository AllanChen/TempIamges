#if MAS
import AppKit
import StoreKit

enum AppStorePurchaseError: LocalizedError {
    case cancelled
    case pending
    case productUnavailable
    case accountUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "The purchase was cancelled. You were not charged.".localized
        case .pending:
            return "Your purchase is waiting for approval. Glance adds it automatically once the App Store approves it.".localized
        case .productUnavailable:
            return "This product isn't available in the App Store right now. You were not charged. Try again later.".localized
        case .accountUnavailable:
            return "Glance couldn't confirm your account before the purchase. You were not charged. Check your connection and try again.".localized
        }
    }
}

/// Mac App Store purchases (StoreKit 2).
///
/// Every transaction goes to the Glance service, which fetches it from Apple
/// again before granting anything. A transaction is finished only after the
/// service has recorded it, so a purchase interrupted by a crash, network
/// failure or sign-out is retried at the next launch or sign-in, never lost.
/// The service records each transaction once, so retries never grant twice.
final class AppStorePurchases {
    static let shared = AppStorePurchases()

    // Read synchronously by billing views; filled from StoreKit tasks.
    private let lock = NSLock()
    private var products: [String: Product] = [:]
    private var loading: Set<String> = []
    private var updates: Task<Void, Never>?

    private func product(_ id: String) -> Product? {
        lock.lock(); defer { lock.unlock() }
        return products[id]
    }
    private func store(_ loaded: [Product]) {
        lock.lock(); defer { lock.unlock() }
        for product in loaded { products[product.id] = product }
    }

    private static var prefix: String { Bundle.main.bundleIdentifier ?? "com.glance.app" }
    static func productID(pack: BillingPack) -> String { "\(prefix).credits.\(pack.id)" }
    static func productID(tier: BillingTier) -> String { "\(prefix).pro.\(tier.id)" }

    /// Apple's price in the user's storefront, once the product has loaded.
    func displayPrice(_ productID: String) -> String? { product(productID)?.displayPrice }
    func isAvailable(_ productID: String) -> Bool { product(productID) != nil }
    /// The cheapest loaded product's price among `productIDs`.
    func lowestDisplayPrice(_ productIDs: [String]) -> String? {
        productIDs.compactMap(product).min { $0.price < $1.price }?.displayPrice
    }

    /// Starts listening for purchases completed outside the purchase sheet
    /// (Ask to Buy approvals, other Macs) and replays unfinished ones.
    func start() {
        guard updates == nil else { return }
        updates = Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                _ = await self?.record(update)
            }
        }
        processUnfinished()
    }

    /// Sends every unfinished transaction to the service. Safe to call often.
    func processUnfinished() {
        guard AuthManager.shared.isSignedIn else { return }
        Task { @MainActor in
            for await result in Transaction.unfinished { _ = await record(result) }
        }
    }

    /// Loads the App Store products for the current offer, then refreshes
    /// any billing window showing prices.
    func loadProducts(for pricing: BillingPricing) {
        lock.lock()
        let ids = Set(pricing.packs.filter(\.enabled).map(Self.productID(pack:))
            + pricing.proTiers.filter(\.enabled).map(Self.productID(tier:)))
            .subtracting(products.keys).subtracting(loading)
        loading.formUnion(ids)
        lock.unlock()
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            defer { self.lock.lock(); self.loading.subtract(ids); self.lock.unlock() }
            do {
                store(try await Product.products(for: ids))
                NotificationCenter.default.post(name: BillingManager.didChange, object: nil)
            } catch {
                Logger.warning("AppStorePurchases: Could not load products: \(error.localizedDescription)")
            }
        }
    }

    func purchase(_ productID: String, completion: @escaping (Result<BillingOrderStatus, Error>) -> Void) {
        Task { @MainActor in
            completion(await purchase(productID))
        }
    }

    @MainActor
    private func purchase(_ productID: String) async -> Result<BillingOrderStatus, Error> {
        if product(productID) == nil, let loaded = try? await Product.products(for: [productID]) {
            store(loaded)
        }
        guard let product = product(productID) else { return .failure(AppStorePurchaseError.productUnavailable) }
        guard let token = await accountToken() else { return .failure(AppStorePurchaseError.accountUnavailable) }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let verification):
                return await record(verification)
            case .userCancelled:
                return .failure(AppStorePurchaseError.cancelled)
            case .pending:
                return .failure(AppStorePurchaseError.pending)
            @unknown default:
                return .failure(AppStorePurchaseError.pending)
            }
        } catch {
            return .failure(error)
        }
    }

    /// Restores non-consumable purchases (Pro) and any unfinished credit packs.
    func restore(completion: @escaping (Result<Int, Error>) -> Void) {
        Task { @MainActor in
            do {
                try await AppStore.sync()
            } catch {
                completion(.failure(error))
                return
            }
            var restored = 0
            var lastError: Error?
            for await result in Transaction.currentEntitlements {
                switch await record(result) {
                case .success: restored += 1
                case .failure(let error): lastError = error
                }
            }
            for await result in Transaction.unfinished {
                if case .success = await record(result) { restored += 1 }
            }
            if restored == 0, let lastError {
                completion(.failure(lastError))
            } else {
                completion(.success(restored))
            }
        }
    }

    /// The account UUID the service expects on purchases from this account.
    @MainActor
    private func accountToken() async -> UUID? {
        if let raw = BillingManager.shared.entitlements?.appStoreAccountToken { return UUID(uuidString: raw) }
        return await withCheckedContinuation { continuation in
            BillingManager.shared.refreshEntitlements { result in
                let raw = try? result.get().appStoreAccountToken
                continuation.resume(returning: raw.flatMap(UUID.init(uuidString:)))
            }
        }
    }

    /// Records one transaction with the service; finishes it once recorded or
    /// once the service confirms it can never be granted.
    @MainActor
    private func record(_ verification: VerificationResult<Transaction>) async -> Result<BillingOrderStatus, Error> {
        // The service re-fetches the transaction from Apple, so the ID is all
        // it needs even when the local signature check failed.
        let transaction = verification.unsafePayloadValue
        let result: Result<BillingOrderStatus, Error> = await withCheckedContinuation { continuation in
            BillingManager.shared.request(
                "/api/v2/app-store/transactions",
                body: ["transactionID": String(transaction.id),
                       "language": Preferences.shared.appLanguage == .chinese ? "zh-Hans" : "en"]
            ) { continuation.resume(returning: $0) }
        }
        switch result {
        case .success(let status):
            await transaction.finish()
            AuthManager.shared.updateCredits(status.balance)
            BillingManager.shared.refreshWallet()
            BillingManager.shared.refreshEntitlements(activate: true)
        case .failure(let error as BillingAPIError)
            where ["app_store_revoked", "app_store_wrong_app"].contains(error.code):
            await transaction.finish()
        case .failure(let error):
            // Kept unfinished: retried at the next launch, sign-in or restore.
            Logger.warning("AppStorePurchases: Transaction not recorded yet: \(error.localizedDescription)")
        }
        return result
    }
}
#endif
