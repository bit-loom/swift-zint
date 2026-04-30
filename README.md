# swift-zint

A lightweight Swift wrapper around [Zint](https://github.com/zint/zint) for generating barcode PNGs in memory on iOS.

The Zint backend C source is vendored directly (BSD-3-Clause) and compiled with the package. PNG encoding is performed by Apple's `ImageIO`, so there is no `libpng` / `zlib` dependency.

## Requirements

- Swift 6.3+
- iOS 15+ / macOS 12+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/bit-loom/swift-zint.git", from: "0.0.1"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SwiftZint", package: "swift-zint"),
        ]
    ),
]
```

## Usage

```swift
import SwiftZint

// Default options
let png = try Zint.renderPNG("Hello, World!", symbology: .qrCode)

// Customised
var options = Zint.Options()
options.scale = 4.0
options.showText = false
options.foregroundHex = "1A1A1A"
options.backgroundHex = "FFFFFF"

let code128 = try Zint.renderPNG(
    "ABC-12345",
    symbology: .code128,
    options: options
)
```

## Symbologies

Every Zint symbology is exposed via `Zint.Symbology` (`.qrCode`, `.code128`, `.dataMatrix`, `.pdf417`, `.aztec`, `.ean13`, `.upca`, etc. — ~100 cases).

## Advanced options

`Zint.Options` exposes the full input surface of `zint_symbol`, including:

- **Geometry**: `scale`, `height`, `dpmm`, `whitespaceWidth/Height`, `borderWidth`
- **Symbology-specific**: `option1`/`option2`/`option3` (e.g. QR ECC level, PDF417 columns, Data Matrix size — see [Zint manual](https://zint.org.uk/manual))
- **Layout flags** (`OutputOptions`): `.bind` / `.box` / `.dottyMode` / `.quietZones` / `.smallText` / `.boldText` / `.eanUPCGuardWhitespace` / …
- **Encoding** (`InputMode` + `InputModeFlags`): `.binary` / `.unicode` / `.gs1`, plus `.escape` / `.fast` / `.gs1Parens` / …
- **ECI** (`eci`)
- **Composite** / **MaxiCode** primary message (`primary`)
- **Structured Append** (`structuredAppend`)
- **Rotation** (0 / 90 / 180 / 270)

Output-format-only flags (`STDOUT`, `CMYK_COLOUR`, `MEMORY_FILE`, vector embedding, …) are intentionally not exposed because they would corrupt the in-memory PNG path.

```swift
// Example: high-ECC QR with bind+box layout, custom margins
var options = Zint.Options()
options.option1 = 4                  // ECC level H (~30%)
options.outputOptions = [.bind, .box, .quietZones]
options.borderWidth = 2
options.whitespaceWidth = 4
options.whitespaceHeight = 4
let png = try Zint.renderPNG("payload", symbology: .qrCode, options: options)

// Example: GS1-128 with parenthesised AIs
var gs1 = Zint.Options()
gs1.inputMode = .gs1
gs1.inputModeFlags = [.gs1Parens]
let gs1Code = try Zint.renderPNG(
    "(01)04912345123459(15)970331(30)128",
    symbology: .gs1_128,
    options: gs1
)
```

## License

MIT — see [LICENSE](LICENSE).

The vendored Zint backend (`Sources/CZint/zint/backend/`) is BSD-3-Clause; see [`Sources/CZint/zint/UPSTREAM-LICENSE`](Sources/CZint/zint/UPSTREAM-LICENSE).
