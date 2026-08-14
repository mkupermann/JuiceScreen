import Foundation
import Testing
@testable import JuiceScreen

@MainActor
@Suite("FreeformModeHolder")
struct FreeformModeHolderTests {

    @Test("Starts in freehand")
    func startsFreehand() {
        #expect(FreeformModeHolder().mode == .freehand)
    }

    @Test("Toggle alternates freehand and polygon")
    func toggleAlternates() {
        let holder = FreeformModeHolder()
        holder.toggle()
        #expect(holder.mode == .polygon)
        holder.toggle()
        #expect(holder.mode == .freehand)
    }

    /// Mirrors `FreeformSelection.setMode`: switching mid-shape would leave the
    /// points half-freehand and half-polygon.
    @Test("Freezing stops the mode from changing")
    func freezeStopsToggling() {
        let holder = FreeformModeHolder()
        holder.freeze()
        holder.toggle()
        #expect(holder.mode == .freehand)
    }

    @Test("Freezing is idempotent and never reverses the mode already chosen")
    func freezeKeepsTheChosenMode() {
        let holder = FreeformModeHolder()
        holder.toggle()
        holder.freeze()
        holder.freeze()
        holder.toggle()
        #expect(holder.mode == .polygon)
    }

    /// The regression this whole holder exists for. Two overlays used to keep
    /// `mode` in per-overlay `@State`, and only the key window saw Tab — so
    /// screen 0 could sit in freehand while screen 1 showed polygon. Here both
    /// overlays are seeded from, and synced to, the one shared holder.
    @Test("Two overlays seeded from one holder never disagree about the mode")
    func overlaysNeverDisagree() {
        let holder = FreeformModeHolder()
        var screen0 = FreeformSelection(mode: holder.mode)
        var screen1 = FreeformSelection(mode: holder.mode)

        holder.toggle()                     // Tab, wherever the key window is
        screen0.setMode(holder.mode)
        screen1.setMode(holder.mode)
        #expect(screen0.mode == .polygon)
        #expect(screen1.mode == .polygon)

        // Drawing starts on screen 0. `onBegan` freezes the shared mode, so a
        // later Tab cannot drop the untouched overlay back to freehand while
        // screen 0 is mid-polygon.
        holder.freeze()
        screen0.appendVertex(CGPoint(x: 10, y: 10))

        holder.toggle()
        screen0.setMode(holder.mode)
        screen1.setMode(holder.mode)
        #expect(screen0.mode == .polygon)
        #expect(screen1.mode == .polygon)
    }
}
