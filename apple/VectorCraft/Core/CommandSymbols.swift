import UIKit

/// SF Symbol names for tools and panels (icons are SF Symbols only; no upstream or third-party artwork).
/// Every name here is checked against the runtime's `CoreGlyphs.bundle/name_availability.plist`, and
/// `symbol(forTool:)` / `symbol(forPanel:)` fall back to a generic symbol if one is missing on a given OS.
extension CommandCatalog {
    private static let toolSymbols: [String: String] = [
        "selection": "cursorarrow",
        "directSelection": "cursorarrow.click",
        "groupSelection": "cursorarrow.rays",
        "magicWand": "wand.and.stars",
        "lasso": "lasso",
        "pen": "pencil.tip",
        "addAnchor": "plus.circle",
        "deleteAnchor": "minus.circle",
        "anchorPoint": "angle",
        "curvature": "point.topleft.down.to.point.bottomright.curvepath",
        "type": "textformat",
        "areaType": "text.alignleft",
        "typeOnPath": "point.topleft.down.to.point.bottomright.curvepath.fill",
        "verticalType": "text.justify.trailing",
        "verticalAreaType": "text.justify",
        "verticalTypeOnPath": "arrow.turn.right.down",
        "touchType": "character.cursor.ibeam",
        "lineSegment": "line.diagonal",
        "arc": "point.topleft.down.to.point.bottomright.curvepath.fill",
        "spiral": "hurricane",
        "rectangularGrid": "grid",
        "polarGrid": "circle.grid.cross",
        "rectangle": "rectangle",
        "roundedRectangle": "app",
        "ellipse": "circle",
        "polygon": "hexagon",
        "star": "star",
        "flare": "sparkle",
        "paintbrush": "paintbrush.pointed",
        "blobBrush": "paintbrush",
        "shaper": "scribble.variable",
        "pencil": "pencil",
        "smooth": "waveform.path",
        "pathEraser": "eraser.line.dashed",
        "join": "link",
        "eraser": "eraser",
        "scissors": "scissors",
        "knife": "scissors.badge.ellipsis",
        "mirrorCut": "square.split.diagonal",
        "lineCut": "line.diagonal.arrow",
        "rectCut": "rectangle.split.2x1",
        "rotate": "rotate.right",
        "reflect": "arrow.left.and.right.righttriangle.left.righttriangle.right",
        "scale": "arrow.up.left.and.arrow.down.right",
        "shear": "rhombus",
        "reshape": "slider.horizontal.below.rectangle",
        "width": "arrow.left.and.right",
        "warp": "wind",
        "twirl": "tornado",
        "pucker": "arrow.down.right.and.arrow.up.left",
        "bloat": "arrow.up.left.and.arrow.down.right.circle",
        "scallop": "seal",
        "crystallize": "diamond",
        "wrinkle": "water.waves",
        "freeTransform": "rectangle.and.arrow.up.right.and.arrow.down.left",
        "puppetWarp": "pin",
        "shapeBuilder": "square.on.circle",
        "livePaintBucket": "drop",
        "livePaintSelection": "drop.circle",
        "perspectiveGrid": "perspective",
        "perspectiveSelection": "cube",
        "mesh": "squareshape.split.3x3",
        "gradient": "rectangle.fill.on.rectangle.fill",
        "eyedropper": "eyedropper",
        "measure": "ruler",
        "blend": "square.on.square.dashed",
        "objectsOnPath": "point.bottomleft.forward.to.point.topright.scurvepath",
        "dimension": "arrow.left.and.right.square",
        "columnGraph": "chart.bar",
        "stackedColumnGraph": "chart.bar.fill",
        "barGraph": "chart.bar.xaxis",
        "stackedBarGraph": "chart.bar.doc.horizontal",
        "lineGraph": "chart.xyaxis.line",
        "areaGraph": "chart.line.uptrend.xyaxis",
        "scatterGraph": "chart.dots.scatter",
        "pieGraph": "chart.pie",
        "radarGraph": "pentagon",
        "artboard": "rectangle.dashed",
        "slice": "square.split.2x2",
        "sliceSelection": "square.split.2x2.fill",
        "hand": "hand.raised",
        "rotateView": "rotate.3d",
        "printTiling": "square.grid.2x2",
        "zoom": "magnifyingglass",
    ]

    private static let panelSymbols: [String: String] = [
        "properties": "slider.horizontal.3",
        "layers": "square.3.layers.3d",
        "color": "paintpalette",
        "swatches": "swatchpalette",
        "stroke": "lineweight",
        "gradient": "rectangle.lefthalf.filled",
        "transparency": "circle.lefthalf.striped.horizontal",
        "appearance": "paintbrush",
        "align": "align.horizontal.center",
        "pathfinder": "square.on.square.intersection.dashed",
        "transform": "arrow.up.and.down.and.arrow.left.and.right",
        "artboards": "rectangle.on.rectangle",
        "character": "textformat.size",
        "paragraph": "paragraphsign",
        "history": "clock.arrow.circlepath",
        "symbols": "burst",
        "brushes": "paintbrush.pointed",
        "graphicStyles": "wand.and.rays",
        "docInfo": "doc.text",
        "info": "info.circle",
        "navigator": "map",
        // Panels reached through the generic page.
        "actions": "play.rectangle",
        "attributes": "checklist",
        "blend": "square.on.square.dashed",
        "colorGuide": "eyedropper.halffull",
        "colorThemes": "paintpalette.fill",
        "imageTrace": "photo.badge.arrow.down",
        "libraries": "books.vertical",
        "magicWand": "wand.and.stars",
        "navigatorPanel": "map",
        "glyphs": "character",
        "openType": "textformat.alt",
        "charStyles": "textformat",
        "paraStyles": "paragraphsign",
        "tabs": "arrow.right.to.line",
        "patternOptions": "square.grid.3x3",
        "separations": "circle.hexagongrid",
    ]

    /// The SF Symbol for a tool id ("pen"), falling back to a generic one.
    func symbol(forTool id: String) -> String {
        Self.validated(Self.toolSymbols[id], fallback: "wrench.and.screwdriver")
    }

    /// The SF Symbol for a panel id ("layers"), falling back to a generic one.
    func symbol(forPanel id: String) -> String {
        Self.validated(Self.panelSymbols[id], fallback: "square.stack")
    }

    private static func validated(_ name: String?, fallback: String) -> String {
        if let name, UIImage(systemName: name) != nil { return name }
        return fallback
    }

    /// Every symbol name used above (for the validation script and tests).
    static var allSymbolNames: [String] {
        Array(toolSymbols.values) + Array(panelSymbols.values)
    }
}
