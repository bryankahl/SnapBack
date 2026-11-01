//
//  PaywallStore.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/31/26.
//

import StoreKit
internal import Combine

@MainActor
final class PaywallStore: ObservableObject {
    static let productID = "com.bryankahl.SnapBack.fullimport"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var loading = false
    @Published private(set) var errorText: String?

    /// Listens for transaction updates from launch. StoreKit requires this:
    /// without it, confirmed purchases have nowhere to land, purchase()
    /// silently reports failure, and every retry piles up another unfinished
    /// transaction. The listener also recovers purchases from earlier runs:
    /// unfinished transactions redeliver here on launch.
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                switch result {
                case .verified(let transaction):
                    let granted = transaction.productID == Self.productID && transaction.revocationDate == nil
                    await transaction.finish()
                    if granted {
                        await MainActor.run { self.isPurchased = true }
                    }
                case .unverified:
                    break
                }
            }
        }
    }

    func load() async {
        loading = true
        errorText = nil
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                errorText = "Purchase option not found. Check the StoreKit configuration."
            }
        } catch {
            errorText = "Couldn't load the purchase option. Check your connection and try again."
        }
        await refreshPurchased()
        loading = false
    }

    func purchase() async -> Bool {
        guard let product else {
            errorText = "Purchase option not found. Check the StoreKit configuration."
            return false
        }
        errorText = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorText = "Purchase couldn't be verified. Nothing was charged — try again."
                    return false
                }
                await transaction.finish()
                isPurchased = true
                return true
            case .userCancelled:
                errorText = "Purchase cancelled. Nothing was charged."
                return false
            case .pending:
                errorText = "Purchase is pending approval. It will unlock once approved."
                return false
            @unknown default:
                errorText = "Purchase didn't complete. Nothing was charged — try again."
                return false
            }
        } catch {
            errorText = "Purchase failed. Nothing was charged — try again."
            return false
        }
    }

    /// Returns true when a purchase is now on file, so the caller can unlock.
    func restore() async -> Bool {
        await refreshPurchased()
        if isPurchased {
            return true
        }
        errorText = "No purchase found to restore."
        return false
    }

    func refreshPurchased() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID && transaction.revocationDate == nil {
                isPurchased = true
                return
            }
        }
        // Deliberately does not clear isPurchased: the updates listener may
        // have granted from a transaction this read hasn't seen yet, and a
        // missed read must never undo a verified grant.
    }
}
