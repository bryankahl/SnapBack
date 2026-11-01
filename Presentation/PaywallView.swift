//
//  PaywallView.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/31/26.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var store: PaywallStore
    let importedSoFar: Int
    let onUnlocked: () -> Void
    let onClose: () -> Void

    @State private var buying = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("You've seen the beginning of time.")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                Text("Like what you see? Pay once to get your life back.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text("\(importedSoFar) memories are already home. The rest are waiting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                if store.loading {
                    ProgressView()
                } else if let product = store.product {
                    Button {
                        buying = true
                        Task {
                            let ok = await store.purchase()
                            buying = false
                            if ok { onUnlocked() }
                        }
                    } label: {
                        Text("Pay \(product.displayPrice) once")
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(buying)
                }
                Button("Restore purchase") {
                    Task {
                        if await store.restore() { onUnlocked() }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button("Maybe later") { onClose() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let errorText = store.errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .task {
            await store.load()
        }
    }
}
