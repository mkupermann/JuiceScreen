import Testing
@testable import JuiceScreen

@Suite("ToolType")
struct ToolTypeTests {

    @Test("All 11 tools exist")
    func allToolsExist() {
        let all = ToolType.allCases
        #expect(all.count == 11)
        #expect(all.contains(.select))
        #expect(all.contains(.arrow))
        #expect(all.contains(.doubleArrow))
        #expect(all.contains(.line))
        #expect(all.contains(.rectangle))
        #expect(all.contains(.ellipse))
        #expect(all.contains(.pen))
        #expect(all.contains(.highlighter))
        #expect(all.contains(.text))
        #expect(all.contains(.blur))
        #expect(all.contains(.crop))
    }

    @Test("SF Symbol per tool")
    func sfSymbolPerTool() {
        #expect(ToolType.select.sfSymbol      == "cursorarrow")
        #expect(ToolType.arrow.sfSymbol       == "arrow.up.right")
        #expect(ToolType.doubleArrow.sfSymbol == "arrow.left.and.right")
        #expect(ToolType.line.sfSymbol        == "line.diagonal")
        #expect(ToolType.rectangle.sfSymbol   == "rectangle")
        #expect(ToolType.ellipse.sfSymbol     == "oval")
        #expect(ToolType.pen.sfSymbol         == "pencil.tip")
        #expect(ToolType.highlighter.sfSymbol == "highlighter")
        #expect(ToolType.text.sfSymbol        == "textformat")
        #expect(ToolType.blur.sfSymbol        == "square.dashed")
        #expect(ToolType.crop.sfSymbol        == "crop")
    }

    @Test("Display names per tool")
    func displayNamesPerTool() {
        #expect(ToolType.select.displayName      == "Select")
        #expect(ToolType.arrow.displayName       == "Arrow")
        #expect(ToolType.doubleArrow.displayName == "Double Arrow")
        #expect(ToolType.line.displayName        == "Line")
        #expect(ToolType.rectangle.displayName   == "Rectangle")
        #expect(ToolType.ellipse.displayName     == "Ellipse")
        #expect(ToolType.pen.displayName         == "Pen")
        #expect(ToolType.highlighter.displayName == "Highlighter")
        #expect(ToolType.text.displayName        == "Text")
        #expect(ToolType.blur.displayName        == "Blur")
        #expect(ToolType.crop.displayName        == "Crop")
    }
}
