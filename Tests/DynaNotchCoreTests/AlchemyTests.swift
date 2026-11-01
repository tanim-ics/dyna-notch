import XCTest
@testable import DynaNotchCore

final class AlchemyTests: XCTestCase {
    func testAccepts() {
        XCTAssertTrue(AlchemyAction.cutout.accepts(fileExtension: "HEIC"))
        XCTAssertFalse(AlchemyAction.cutout.accepts(fileExtension: "pdf"))
        XCTAssertTrue(AlchemyAction.text.accepts(fileExtension: "pdf"))
        XCTAssertTrue(AlchemyAction.shrink.accepts(fileExtension: "pdf"))
        XCTAssertFalse(AlchemyAction.png.accepts(fileExtension: "txt"))
    }

    func testOutputNames() {
        XCTAssertEqual(AlchemyAction.cutout.outputName(for: "Photo.jpg", existing: []), "Photo (cutout).png")
        XCTAssertEqual(AlchemyAction.shrink.outputName(for: "Photo.heic", existing: []), "Photo (small).jpg")
        XCTAssertEqual(AlchemyAction.shrink.outputName(for: "Logo.png", existing: []), "Logo (small).jpg")
        XCTAssertEqual(AlchemyAction.shrink.outputName(for: "Logo.png", existing: [], keepsTransparency: true),
                       "Logo (small).png")
        XCTAssertEqual(AlchemyAction.shrink.outputName(for: "Report.pdf", existing: []), "Report (small).pdf")
        XCTAssertEqual(AlchemyAction.png.outputName(for: "Shot.heic", existing: []), "Shot.png")
        XCTAssertEqual(AlchemyAction.png.outputName(for: "Shot.png", existing: []), "Shot 2.png")   // never itself
        XCTAssertEqual(AlchemyAction.jpeg.outputName(for: "Shot.png", existing: ["Shot.jpg", "Shot 2.jpg"]), "Shot 3.jpg")
        XCTAssertNil(AlchemyAction.text.outputName(for: "Scan.png", existing: []))
    }
}
