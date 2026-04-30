import Foundation
import Testing
@testable import SwiftZint

private let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

private func expectPNG(_ data: Data) {
    #expect(data.count > pngMagic.count)
    for (i, byte) in pngMagic.enumerated() {
        #expect(data[i] == byte)
    }
}

// MARK: - Basic symbology coverage

@Test func renderQRCode() throws {
    let data = try Zint.renderPNG("Hello, World!", symbology: .qrCode)
    expectPNG(data)
}

@Test func renderCode128() throws {
    let data = try Zint.renderPNG("ABC-12345", symbology: .code128)
    expectPNG(data)
}

@Test func renderEAN13() throws {
    let data = try Zint.renderPNG("590123412345", symbology: .ean13)
    expectPNG(data)
}

@Test func renderDataMatrix() throws {
    let data = try Zint.renderPNG("DM-CONTENT", symbology: .dataMatrix)
    expectPNG(data)
}

@Test func renderPDF417() throws {
    let data = try Zint.renderPNG("PDF417 payload", symbology: .pdf417)
    expectPNG(data)
}

@Test func renderAztec() throws {
    let data = try Zint.renderPNG("aztec test", symbology: .aztec)
    expectPNG(data)
}

@Test func unicodeContent() throws {
    let data = try Zint.renderPNG("你好,世界 🌍", symbology: .qrCode)
    expectPNG(data)
}

// MARK: - Basic options

@Test func customColors() throws {
    let baseline = try Zint.renderPNG("colour", symbology: .qrCode)
    var options = Zint.Options()
    options.foregroundHex = "1A1A1A"
    options.backgroundHex = "FAFAFA"
    let recoloured = try Zint.renderPNG("colour", symbology: .qrCode, options: options)
    expectPNG(recoloured)
    #expect(recoloured != baseline)  // colour change must affect bitmap
}

@Test func hideText() throws {
    let withText = try Zint.renderPNG("no-text", symbology: .code128)
    var options = Zint.Options()
    options.showText = false
    let withoutText = try Zint.renderPNG("no-text", symbology: .code128, options: options)
    expectPNG(withoutText)
    #expect(withoutText.count < withText.count)  // hiding HRT shrinks the image
}

// MARK: - Error paths

@Test func invalidColorThrows() {
    var options = Zint.Options()
    options.foregroundHex = "ZZZ"
    #expect(throws: ZintError.self) {
        _ = try Zint.renderPNG("x", symbology: .qrCode, options: options)
    }
}

@Test func invalidEncodeThrows() {
    #expect(throws: ZintError.self) {
        _ = try Zint.renderPNG("not-numeric", symbology: .ean13)
    }
}

// MARK: - Extended options coverage

@Test func qrECCLevel() throws {
    // option_1 = 4 → highest QR error correction level (H, ~30%)
    var options = Zint.Options()
    options.option1 = 4
    let high = try Zint.renderPNG("ECC level test payload", symbology: .qrCode, options: options)
    expectPNG(high)

    options.option1 = 1 // Low ECC
    let low = try Zint.renderPNG("ECC level test payload", symbology: .qrCode, options: options)
    expectPNG(low)

    // Different ECC levels yield different bitmaps.
    #expect(high != low)
}

@Test func whitespaceAndBorder() throws {
    var bare = Zint.Options()
    let baseline = try Zint.renderPNG("123", symbology: .code128, options: bare)
    expectPNG(baseline)

    bare.whitespaceWidth = 10
    bare.whitespaceHeight = 10
    bare.borderWidth = 4
    let bordered = try Zint.renderPNG("123", symbology: .code128, options: bare)
    expectPNG(bordered)

    #expect(bordered.count > baseline.count)
}

@Test func outputOptionsBindAndBox() throws {
    let baseline = try Zint.renderPNG("BIND+BOX", symbology: .code128)
    var options = Zint.Options()
    options.outputOptions = [.bind, .box]
    options.borderWidth = 2
    let bordered = try Zint.renderPNG("BIND+BOX", symbology: .code128, options: options)
    expectPNG(bordered)
    #expect(bordered != baseline)
    #expect(bordered.count > baseline.count)
}

@Test func dottyMode() throws {
    let squares = try Zint.renderPNG("dotty", symbology: .qrCode)
    var options = Zint.Options()
    options.outputOptions = [.dottyMode]
    let dots = try Zint.renderPNG("dotty", symbology: .qrCode, options: options)
    expectPNG(dots)
    #expect(dots != squares)  // dotty mode must change the bitmap
}

@Test func gs1InputMode() throws {
    // QR Code can carry either plain text or GS1 data. Setting `.gs1` parses brackets as
    // AI delimiters and inserts FNC1, producing a different bitmap than the literal encode.
    var gs1 = Zint.Options()
    gs1.inputMode = .gs1
    let asGS1 = try Zint.renderPNG("[01]04912345123459", symbology: .qrCode, options: gs1)
    expectPNG(asGS1)

    var unicode = Zint.Options()
    unicode.inputMode = .unicode
    let asUnicode = try Zint.renderPNG("[01]04912345123459", symbology: .qrCode, options: unicode)
    expectPNG(asUnicode)

    #expect(asGS1 != asUnicode)

    // Sanity: GS1-128 still encodes the bracketed input.
    let gs1_128 = try Zint.renderPNG("[01]04912345123459", symbology: .gs1_128, options: gs1)
    expectPNG(gs1_128)
}

@Test func escapeFlag() throws {
    var options = Zint.Options()
    options.inputModeFlags = [.escape]
    // With .escape, "\\x41\\x42" is processed to "AB" → bitmap matches encoding "AB" directly.
    let escaped = try Zint.renderPNG("\\x41\\x42", symbology: .qrCode, options: options)
    let direct  = try Zint.renderPNG("AB",          symbology: .qrCode)
    expectPNG(escaped)
    #expect(escaped == direct)

    // Without .escape, the raw "\x41\x42" string is encoded literally — different bitmap.
    let literal = try Zint.renderPNG("\\x41\\x42", symbology: .qrCode)
    #expect(literal != direct)
}

@Test func structuredAppendQR() throws {
    let single = try Zint.renderPNG("part 1 of 2", symbology: .qrCode)
    var options = Zint.Options()
    options.structuredAppend = .init(index: 1, count: 2, id: "123")
    let part1 = try Zint.renderPNG("part 1 of 2", symbology: .qrCode, options: options)
    expectPNG(part1)
    #expect(part1 != single)  // structured append header changes the encoding
}

@Test func rotation90() throws {
    let upright = try Zint.renderPNG("rotate", symbology: .code128)
    expectPNG(upright)

    var options = Zint.Options()
    options.rotation = .ninety
    let rotated = try Zint.renderPNG("rotate", symbology: .code128, options: options)
    expectPNG(rotated)
    #expect(rotated != upright)
}

@Test func quietZones() throws {
    let baseline = try Zint.renderPNG("QZ", symbology: .qrCode)
    var options = Zint.Options()
    options.outputOptions = [.quietZones]
    let withZones = try Zint.renderPNG("QZ", symbology: .qrCode, options: options)
    expectPNG(withZones)
    #expect(withZones.count > baseline.count)  // quiet zones add area
}

@Test func primaryTooLongThrows() {
    var options = Zint.Options()
    options.primary = String(repeating: "A", count: 200)
    #expect(throws: ZintError.self) {
        _ = try Zint.renderPNG("data", symbology: .maxicode, options: options)
    }
}

@Test func structuredAppendIDTooLongThrows() {
    var options = Zint.Options()
    options.structuredAppend = .init(
        index: 1, count: 2, id: String(repeating: "x", count: 33)
    )
    #expect(throws: ZintError.self) {
        _ = try Zint.renderPNG("data", symbology: .qrCode, options: options)
    }
}
