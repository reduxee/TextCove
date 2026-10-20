import AppKit
import SwiftUI

struct SyntaxHighlightStyle {
    let color: NSColor
    var bold = false
    var underlined = false
}

struct EditorTheme {
    let background: NSColor
    let foreground: NSColor
    let comment: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let function: NSColor
    let type: NSColor
    let property: NSColor
    let tag: NSColor
    let attribute: NSColor
    let punctuation: NSColor
    let operatorColor: NSColor
    let heading: NSColor
    let link: NSColor
    let errorColor: NSColor

    let font: NSFont
    let emphasizedFont: NSFont
    let paragraphStyle: NSParagraphStyle

    static func resolve(colorScheme: ColorScheme) -> EditorTheme {
        colorScheme == .dark ? dark : light
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraphStyle
        ]
    }

    func style(forCapture capture: String) -> SyntaxHighlightStyle? {
        guard capture != "none" else { return nil }

        if capture == "string.special.key" {
            return SyntaxHighlightStyle(color: property)
        }
        if capture == "identifier.parameter" {
            return SyntaxHighlightStyle(color: attribute)
        }
        if capture == "text.title" {
            return SyntaxHighlightStyle(color: heading, bold: true)
        }
        if capture == "text.strong" {
            return SyntaxHighlightStyle(color: foreground, bold: true)
        }
        if capture == "text.uri" {
            return SyntaxHighlightStyle(color: link, underlined: true)
        }
        if capture == "tag.error" {
            return SyntaxHighlightStyle(color: errorColor, bold: true)
        }

        let components = capture.split(separator: ".")
        guard let first = components.first else { return nil }

        switch first {
        case "comment":
            return SyntaxHighlightStyle(color: comment)
        case "keyword":
            return SyntaxHighlightStyle(color: keyword)
        case "string":
            return SyntaxHighlightStyle(color: string)
        case "escape":
            return SyntaxHighlightStyle(color: keyword)
        case "embedded":
            return SyntaxHighlightStyle(color: string)
        case "number", "boolean", "constant", "float":
            return SyntaxHighlightStyle(color: number)
        case "function":
            return SyntaxHighlightStyle(color: function)
        case "constructor", "type", "label":
            return SyntaxHighlightStyle(color: type)
        case "property":
            return SyntaxHighlightStyle(color: property)
        case "attribute":
            return SyntaxHighlightStyle(color: attribute)
        case "tag":
            return SyntaxHighlightStyle(color: tag)
        case "variable", "identifier":
            return SyntaxHighlightStyle(color: foreground)
        case "parameter":
            return SyntaxHighlightStyle(color: attribute)
        case "method":
            return SyntaxHighlightStyle(color: function)
        case "field":
            return SyntaxHighlightStyle(color: property)
        case "module", "interface":
            return SyntaxHighlightStyle(color: type)
        case "character", "symbol":
            return SyntaxHighlightStyle(color: string)
        case "delimiter":
            return SyntaxHighlightStyle(color: punctuation)
        case "conditional", "repeat", "include", "storageclass", "exception", "preproc":
            return SyntaxHighlightStyle(color: keyword)
        case "diff":
            switch capture {
            case "diff.inserted":
                return SyntaxHighlightStyle(color: type)
            case "diff.deleted":
                return SyntaxHighlightStyle(color: keyword)
            case "diff.header":
                return SyntaxHighlightStyle(color: heading, bold: true)
            case "diff.chunk":
                return SyntaxHighlightStyle(color: function)
            default:
                return SyntaxHighlightStyle(color: comment)
            }
        case "operator":
            return SyntaxHighlightStyle(color: operatorColor)
        case "punctuation":
            return SyntaxHighlightStyle(color: punctuation)
        case "charset", "import", "media", "supports", "keyframes", "namespace":
            return SyntaxHighlightStyle(color: keyword)
        case "protocol", "selector", "implementation", "interface_extension", "synthesize",
             "dynamic", "defs", "end", "synchronized", "try", "catch", "finally", "throw",
             "available", "autoreleasepool", "required", "optional", "category",
             "cImport", "compatibility_alias":
            return SyntaxHighlightStyle(color: keyword)
        case "text":
            if capture == "text.literal" {
                return SyntaxHighlightStyle(color: string)
            }
            if capture == "text.reference" {
                return SyntaxHighlightStyle(color: function)
            }
            if capture == "text.emphasis" {
                return SyntaxHighlightStyle(color: heading)
            }
            return SyntaxHighlightStyle(color: foreground)
        case "_function", "__name__":
            return SyntaxHighlightStyle(color: function)
        case "_class":
            return SyntaxHighlightStyle(color: type)
        case "_bool":
            return SyntaxHighlightStyle(color: number)
        case "_pipe":
            return SyntaxHighlightStyle(color: operatorColor)
        default:
            return nil
        }
    }

    private static let light: EditorTheme = {
        EditorTheme(
            background: color(0xFFFFFF),
            foreground: color(0x1F2328),
            comment: color(0x6E7781),
            keyword: color(0xCF222E),
            string: color(0x0A3069),
            number: color(0x0550AE),
            function: color(0x8250DF),
            type: color(0x116329),
            property: color(0x953800),
            tag: color(0x116329),
            attribute: color(0x0550AE),
            punctuation: color(0x57606A),
            operatorColor: color(0xCF222E),
            heading: color(0x0550AE),
            link: color(0x0969DA),
            errorColor: color(0xCF222E)
        )
    }()

    private static let dark: EditorTheme = {
        EditorTheme(
            background: color(0x1E1E1E),
            foreground: color(0xD4D4D4),
            comment: color(0x8B949E),
            keyword: color(0xF97583),
            string: color(0xA5D6FF),
            number: color(0x79C0FF),
            function: color(0xD2A8FF),
            type: color(0x7EE787),
            property: color(0xFFA657),
            tag: color(0x7EE787),
            attribute: color(0x79C0FF),
            punctuation: color(0x8B949E),
            operatorColor: color(0xF97583),
            heading: color(0x79C0FF),
            link: color(0x58A6FF),
            errorColor: color(0xFF7B72)
        )
    }()

    private init(
        background: NSColor,
        foreground: NSColor,
        comment: NSColor,
        keyword: NSColor,
        string: NSColor,
        number: NSColor,
        function: NSColor,
        type: NSColor,
        property: NSColor,
        tag: NSColor,
        attribute: NSColor,
        punctuation: NSColor,
        operatorColor: NSColor,
        heading: NSColor,
        link: NSColor,
        errorColor: NSColor
    ) {
        self.background = background
        self.foreground = foreground
        self.comment = comment
        self.keyword = keyword
        self.string = string
        self.number = number
        self.function = function
        self.type = type
        self.property = property
        self.tag = tag
        self.attribute = attribute
        self.punctuation = punctuation
        self.operatorColor = operatorColor
        self.heading = heading
        self.link = link
        self.errorColor = errorColor

        self.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        self.emphasizedFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .semibold)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.5
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.defaultTabInterval = 28
        paragraphStyle.lineBreakMode = .byWordWrapping
        self.paragraphStyle = paragraphStyle
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
