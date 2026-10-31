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
        guard let product else { return false }
        errorText = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                await transaction.finish()
                await refreshPurchased()
                return isPurchased
            case .userCancelled:
                return false
            case .pending:
                errorText = "Purchase is pending approval. It will unlock once approved."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorText = "Purchase failed. Nothing was charged — try again."
            return false
        }
    }

    func restore() async {
        await refreshPurchased()
        if !isPurchased {
            errorText = "No purchase found to restore."
        }
    }

    func refreshPurchased() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID && transaction.revocationDate == nil {
                isPurchased = true
                return
            }
        }
        isPurchased = false
    }
}
