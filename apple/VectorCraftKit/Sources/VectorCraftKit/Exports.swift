// Re-exports nothing by itself: the UniFFI-generated `vectorcraft_apple.swift` (produced by
// apple/scripts/build-xcframework.sh) is compiled into this module, so `import VectorCraftKit`
// exposes DocumentHandle, CommandInfo, DocState, SelectionInfo, ViewParams, etc.
// This file keeps the source directory present before the first bridge build.
@_exported import Foundation
