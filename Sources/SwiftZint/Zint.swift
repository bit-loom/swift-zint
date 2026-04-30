import CZint
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ZintError: Error {
    case createFailed
    case invalidColor(String)
    case primaryTooLong
    case structuredAppendIDTooLong
    case encodeFailed(code: Int32, message: String)
    case renderFailed
}

public enum Zint {

    /// Render a barcode and return PNG-encoded bytes.
    ///
    /// libzint is per-symbol reentrant; each call creates and destroys its own
    /// `zint_symbol`, so this method is safe to invoke from multiple queues.
    public static func renderPNG(
        _ text: String,
        symbology: Symbology,
        options: Options = .init()
    ) throws -> Data {
        guard let symbol = ZBarcode_Create() else {
            throw ZintError.createFailed
        }
        defer { ZBarcode_Delete(symbol) }

        symbol.pointee.symbology = symbology.rawValue
        try apply(options, to: symbol)

        let utf8 = Array(text.utf8)
        let rc = utf8.withUnsafeBufferPointer { buf in
            ZBarcode_Encode_and_Buffer(
                symbol, buf.baseAddress, Int32(buf.count), options.rotation.rawValue
            )
        }
        if rc >= Int32(ZINT_ERROR) {
            let msg = readErrtxt(&symbol.pointee.errtxt)
            throw ZintError.encodeFailed(code: rc, message: msg)
        }

        return try encodePNG(from: symbol.pointee)
    }

    // MARK: - Options

    public struct Options: Sendable {
        // Geometry
        public var scale: Float = 1.0
        public var height: Float = 0
        /// Resolution metadata in dots-per-mm. `0` = default. Affects raster scaling.
        public var dpmm: Float = 0
        public var whitespaceWidth: Int32 = 0
        public var whitespaceHeight: Int32 = 0
        public var borderWidth: Int32 = 0

        // Colour (6-character RGB hex; case-insensitive)
        public var foregroundHex: String = "000000"
        public var backgroundHex: String = "FFFFFF"

        // Text
        public var showText: Bool = true
        public var textGap: Float = 1.0
        public var guardDescent: Float = 5.0

        // Encoding
        public var inputMode: InputMode = .unicode
        public var inputModeFlags: InputModeFlags = []
        /// Extended Channel Interpretation. `0` = none.
        public var eci: Int32 = 0

        /// Symbology-specific option 1 (e.g. QR ECC level 1–4, PDF417 ECC level).
        /// `-1` = unset (Zint default). See https://zint.org.uk/manual.
        public var option1: Int32 = -1
        /// Symbology-specific option 2 (e.g. QR version, PDF417 columns, Data Matrix size).
        public var option2: Int32 = 0
        /// Symbology-specific option 3 (e.g. Aztec full / DM_SQUARE / Ultra compression).
        public var option3: Int32 = 0

        /// Layout / appearance flags. Only flags relevant to the bitmap path are exposed.
        public var outputOptions: OutputOptions = []

        /// Dot diameter in `BARCODE_DOTTY_MODE`. Default `0.8`.
        public var dotSize: Float = 0.8

        /// Primary message buffer (MaxiCode and Composite codes). `nil` = unused.
        /// Max 127 bytes when UTF-8 encoded.
        public var primary: String? = nil

        /// Structured-Append sequence info (QR / Aztec / PDF417 / Data Matrix etc).
        /// `nil` = single symbol.
        public var structuredAppend: StructuredAppend? = nil

        /// Treat warnings as errors when set to `.failAll`.
        public var warnLevel: WarnLevel = .default

        /// Rotation passed to `ZBarcode_Encode_and_Buffer`. Only 0/90/180/270 valid.
        public var rotation: Rotation = .zero

        public init() {}
    }

    // MARK: - Sub-types

    public enum InputMode: Int32, Sendable {
        case binary  = 0  // DATA_MODE
        case unicode = 1  // UNICODE_MODE
        case gs1     = 2  // GS1_MODE
    }

    public struct InputModeFlags: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        /// Process `\xNN`, `\t`, `\n` etc escape sequences in input.
        public static let escape          = Self(rawValue: 0x0008)
        /// Use `()` instead of `[]` as GS1 AI delimiters.
        public static let gs1Parens       = Self(rawValue: 0x0010)
        /// Skip GS1 data validity check.
        public static let gs1NoCheck      = Self(rawValue: 0x0020)
        /// Interpret `height` as per-row instead of overall height.
        public static let heightPerRow    = Self(rawValue: 0x0040)
        /// Use faster (less optimal) encoder shortcuts where available.
        public static let fast            = Self(rawValue: 0x0080)
        /// Process special symbology-specific escape sequences (Aztec / Code128 / DM only).
        public static let extraEscape     = Self(rawValue: 0x0100)
        /// Use the GS1 Syntax Engine to strictly validate GS1 input.
        public static let gs1SyntaxEngine = Self(rawValue: 0x0200)
        /// Process GS1 data literally (no AI delimiters), parsing GSs as FNC1s.
        public static let gs1Raw          = Self(rawValue: 0x0400)
    }

    public struct OutputOptions: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        /// Boundary bar above the symbol only.
        public static let bindTop               = Self(rawValue: 0x00001)
        /// Boundary bars above & below the symbol.
        public static let bind                  = Self(rawValue: 0x00002)
        /// Box around the symbol.
        public static let box                   = Self(rawValue: 0x00004)
        /// Reader Initialisation (Programming).
        public static let readerInit            = Self(rawValue: 0x00010)
        public static let smallText             = Self(rawValue: 0x00020)
        public static let boldText              = Self(rawValue: 0x00040)
        /// Plot a matrix symbol using dots rather than squares.
        public static let dottyMode             = Self(rawValue: 0x00100)
        /// Use GS instead of FNC1 as GS1 separator (Data Matrix).
        public static let gs1GSSeparator        = Self(rawValue: 0x00200)
        /// Add compliant quiet zones (additional to any specified whitespace).
        public static let quietZones            = Self(rawValue: 0x00800)
        /// Disable default quiet zones.
        public static let noQuietZones          = Self(rawValue: 0x01000)
        /// Warn if height not compliant, or use standard height as default.
        public static let compliantHeight       = Self(rawValue: 0x02000)
        /// Add quiet-zone indicators (`<` `>`) to HRT whitespace (EAN/UPC).
        public static let eanUPCGuardWhitespace = Self(rawValue: 0x04000)
    }

    public struct StructuredAppend: Sendable {
        /// Position in the sequence, 1-based. Must be `<= count`.
        public var index: Int32
        /// Number of symbols in the sequence. `0` = none, `>= 2` to enable.
        public var count: Int32
        /// Optional ASCII identifier, max 32 bytes (no NUL needed at exactly 32).
        public var id: String?

        public init(index: Int32, count: Int32, id: String? = nil) {
            self.index = index
            self.count = count
            self.id = id
        }
    }

    public enum Rotation: Int32, Sendable {
        case zero       = 0
        case ninety     = 90
        case oneEighty  = 180
        case twoSeventy = 270
    }

    public enum WarnLevel: Int32, Sendable {
        case `default` = 0
        case failAll   = 2
    }

    // MARK: - Symbology

    public enum Symbology: Int32, Sendable {
        case code11        = 1
        case c25standard   = 2
        case c25inter      = 3
        case c25iata       = 4
        case c25logic      = 6
        case c25ind        = 7
        case code39        = 8
        case excode39      = 9
        case ean8          = 10
        case ean2Addon     = 11
        case ean5Addon     = 12
        case eanxLegacy    = 13
        case eanxChkLegacy = 14
        case ean13         = 15
        case gs1_128       = 16
        case codabar       = 18
        case code128       = 20
        case dpLeit        = 21
        case dpIdent       = 22
        case code16k       = 23
        case code49        = 24
        case code93        = 25
        case flat          = 28
        case dbarOmn       = 29
        case dbarLtd       = 30
        case dbarExp       = 31
        case telepen       = 32
        case upca          = 34
        case upcaChk       = 35
        case upce          = 37
        case upceChk       = 38
        case postnet       = 40
        case msiPlessey    = 47
        case fim           = 49
        case logmars       = 50
        case pharma        = 51
        case pzn           = 52
        case pharmaTwo     = 53
        case cepnet        = 54
        case pdf417        = 55
        case pdf417Comp    = 56
        case maxicode      = 57
        case qrCode        = 58
        case code128AB     = 60
        case auspost       = 63
        case ausreply      = 66
        case ausroute      = 67
        case ausredirect   = 68
        case isbnx         = 69
        case rm4scc        = 70
        case dataMatrix    = 71
        case ean14         = 72
        case vin           = 73
        case codablockF    = 74
        case nve18         = 75
        case japanpost     = 76
        case koreapost     = 77
        case dbarStk       = 79
        case dbarOmnStk    = 80
        case dbarExpStk    = 81
        case planet        = 82
        case microPdf417   = 84
        case uspsImail     = 85
        case plessey       = 86
        case telepenNum    = 87
        case itf14         = 89
        case kix           = 90
        case aztec         = 92
        case daft          = 93
        case dpd           = 96
        case microQr       = 97
        case hibc128       = 98
        case hibc39        = 99
        case hibcDM        = 102
        case hibcQR        = 104
        case hibcPDF       = 106
        case hibcMicPdf    = 108
        case hibcBlockF    = 110
        case hibcAztec     = 112
        case dotcode       = 115
        case hanxin        = 116
        case mailmark2D    = 119
        case upuS10        = 120
        case mailmark4S    = 121
        case azrune        = 128
        case code32        = 129
        case eanxCC        = 130
        case gs1_128_CC    = 131
        case dbarOmnCC     = 132
        case dbarLtdCC     = 133
        case dbarExpCC     = 134
        case upcaCC        = 135
        case upceCC        = 136
        case dbarStkCC     = 137
        case dbarOmnStkCC  = 138
        case dbarExpStkCC  = 139
        case channel       = 140
        case codeOne       = 141
        case gridmatrix    = 142
        case upnqr         = 143
        case ultra         = 144
        case rmqr          = 145
        case bc412         = 146
        case dxFilmEdge    = 147
        case ean8CC        = 148
        case ean13CC       = 149
    }
}

// MARK: - Private helpers

private func apply(_ options: Zint.Options, to symbol: UnsafeMutablePointer<zint_symbol>) throws {
    symbol.pointee.scale             = options.scale
    symbol.pointee.height            = options.height
    symbol.pointee.dpmm              = options.dpmm
    symbol.pointee.whitespace_width  = options.whitespaceWidth
    symbol.pointee.whitespace_height = options.whitespaceHeight
    symbol.pointee.border_width      = options.borderWidth
    symbol.pointee.show_hrt          = options.showText ? 1 : 0
    symbol.pointee.text_gap          = options.textGap
    symbol.pointee.guard_descent     = options.guardDescent
    symbol.pointee.input_mode        = options.inputMode.rawValue | options.inputModeFlags.rawValue
    symbol.pointee.eci               = options.eci
    symbol.pointee.option_1          = options.option1
    symbol.pointee.option_2          = options.option2
    symbol.pointee.option_3          = options.option3
    symbol.pointee.output_options    = options.outputOptions.rawValue
    symbol.pointee.dot_size          = options.dotSize
    symbol.pointee.warn_level        = options.warnLevel.rawValue

    try writeColor(options.foregroundHex, into: &symbol.pointee.fgcolour)
    try writeColor(options.backgroundHex, into: &symbol.pointee.bgcolour)

    if let primary = options.primary {
        try writePrimary(primary, into: &symbol.pointee.primary)
    }

    if let sa = options.structuredAppend {
        try writeStructapp(sa, into: &symbol.pointee.structapp)
    }
}

private func encodePNG(from symbol: zint_symbol) throws -> Data {
    let width  = Int(symbol.bitmap_width)
    let height = Int(symbol.bitmap_height)
    guard width > 0, height > 0, let bitmap = symbol.bitmap else {
        throw ZintError.renderFailed
    }
    let bytesPerRow = width * 3 // Zint raster output is packed RGB, no row padding.
    let pixelData = Data(bytes: bitmap, count: bytesPerRow * height)

    guard let provider = CGDataProvider(data: pixelData as CFData) else {
        throw ZintError.renderFailed
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 24,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw ZintError.renderFailed
    }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        out, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw ZintError.renderFailed
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw ZintError.renderFailed
    }
    return out as Data
}

/// Writes a 6-character RGB hex string into a `char[16]` colour field.
private func writeColor<T>(_ hex: String, into field: UnsafeMutablePointer<T>) throws {
    let cleaned = hex.uppercased().filter { $0.isHexDigit }
    guard cleaned.count == 6 else {
        throw ZintError.invalidColor(hex)
    }
    let bytes: [UInt8] = Array(cleaned.utf8) + [0]
    UnsafeMutableRawPointer(field).copyMemory(from: bytes, byteCount: bytes.count)
}

/// Writes a string into the `char[128]` `primary` buffer (NUL-terminated).
private func writePrimary<T>(_ str: String, into field: UnsafeMutablePointer<T>) throws {
    let utf8 = Array(str.utf8)
    guard utf8.count <= 127 else {
        throw ZintError.primaryTooLong
    }
    UnsafeMutableRawPointer(field).copyMemory(from: utf8, byteCount: utf8.count)
    UnsafeMutableRawPointer(field).advanced(by: utf8.count).storeBytes(of: 0, as: UInt8.self)
}

/// Writes a `Zint.StructuredAppend` value into the `zint_structapp` C struct.
private func writeStructapp(_ sa: Zint.StructuredAppend, into field: UnsafeMutablePointer<zint_structapp>) throws {
    field.pointee.index = sa.index
    field.pointee.count = sa.count
    if let id = sa.id {
        let utf8 = Array(id.utf8)
        guard utf8.count <= 32 else {
            throw ZintError.structuredAppendIDTooLong
        }
        withUnsafeMutableBytes(of: &field.pointee.id) { buf in
            buf.copyBytes(from: utf8)
            // Pad remainder with zeros (NUL-terminate if room).
            for i in utf8.count..<buf.count {
                buf[i] = 0
            }
        }
    }
}

/// Reads a NUL-terminated `char[160]` Zint error message into a Swift String.
private func readErrtxt<T>(_ field: UnsafePointer<T>) -> String {
    withUnsafeBytes(of: field.pointee) { raw in
        guard let base = raw.baseAddress else { return "" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }
}
