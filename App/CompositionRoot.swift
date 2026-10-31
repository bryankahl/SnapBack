//
//  CompositionRoot.swift
//  SnapBack
//
//  Created by Bryan Kahl on 10/27/26.
//

import SwiftUI

/// The one wiring place for the app.
/// Product UI is the default. To get the dev console back (probe buttons,
/// small-batch testing), build the same objects plus inspector, probe,
/// matcher, census, uuidProbe, linkProbe, and return ContentView(...)
/// instead of ProductView(...) below.
enum CompositionRoot {
    static func makeRootView() -> some View {
        let parser: MemoriesParsing = MemoriesParser()
        let pairer: MemoryPairing = MemoryPairer()
        let importer: MemoryImporting = MemoryImporter(pairer: pairer)
        return ProductView(parser: parser, importer: importer, pairer: pairer)
    }
}
