import Foundation

/// 决定某个文件用哪种高亮引擎。
enum HighlightEngine: Equatable {
    /// 交给 CodeEditLanguages 按扩展名/shebang 检测 tree-sitter 语法
    case treeSitter
    /// Vue SFC：分区投影，template 走 html 语法，script/style 走 js|ts|css 语法
    case vueSFC
    /// 没有 tree-sitter 语法，用内置正则规则
    case regex(RegexSyntax)
    case none
}

enum RegexSyntax: String, Equatable {
    case xml
    case propertyList
    case diff
    case nginx
    case graphQL
    case gitignore
    case environment
}

enum FileKind: Equatable {
    case plainText
    case markdown
    case vue
    case xml
    case propertyList
    case diff
    case nginx
    case gitIgnore
    case environment
    case graphQL
    case json
    case javascript
    case jsx
    case typescript
    case tsx
    case html
    case css
    case java
    case c
    case cpp
    case objectiveC
    case csharp
    case swift
    case python
    case ruby
    case go
    case goModule
    case kotlin
    case rust
    case php
    case lua
    case bash
    case sql
    case scala
    case dart
    case elixir
    case haskell
    case ocaml
    case zig
    case toml
    case yaml
    case dockerfile

    init(fileURL: URL) {
        let name = fileURL.lastPathComponent.lowercased()
        let ext = fileURL.pathExtension.lowercased()

        // 没有扩展名的点文件与固定文件名，只能按名字判断
        if name == "dockerfile" {
            self = .dockerfile
            return
        }
        if name == ".gitignore" || name.hasSuffix(".gitignore") {
            self = .gitIgnore
            return
        }
        if name == ".env" || name.hasPrefix(".env.") {
            self = .environment
            return
        }
        if name == "nginx.conf" {
            self = .nginx
            return
        }

        switch ext {
        case "md", "markdown", "mdown", "mkd", "mkdn", "mdwn":
            self = .markdown
        case "vue":
            self = .vue
        case "xml", "svg":
            self = .xml
        case "plist":
            self = .propertyList
        case "diff", "patch":
            self = .diff
        case "nginx":
            self = .nginx
        case "graphql", "gql":
            self = .graphQL
        case "json":
            self = .json
        case "js", "mjs", "cjs":
            self = .javascript
        case "jsx":
            self = .jsx
        case "ts", "cts", "mts":
            self = .typescript
        case "tsx":
            self = .tsx
        case "html", "htm", "shtml":
            self = .html
        case "css":
            self = .css
        case "java", "jav":
            self = .java
        case "c", "h":
            self = .c
        case "cc", "cpp", "c++", "hpp":
            self = .cpp
        case "m":
            self = .objectiveC
        case "cs":
            self = .csharp
        case "swift":
            self = .swift
        case "py":
            self = .python
        case "rb":
            self = .ruby
        case "go":
            self = .go
        case "mod":
            self = .goModule
        case "kt", "kts":
            self = .kotlin
        case "rs":
            self = .rust
        case "php":
            self = .php
        case "lua":
            self = .lua
        case "sh", "bash":
            self = .bash
        case "sql":
            self = .sql
        case "scala", "sc":
            self = .scala
        case "dart":
            self = .dart
        case "ex", "exs":
            self = .elixir
        case "hs":
            self = .haskell
        case "ml", "mli":
            self = .ocaml
        case "zig":
            self = .zig
        case "toml":
            self = .toml
        case "yml", "yaml":
            self = .yaml
        default:
            self = .plainText
        }
    }

    private var profile: (name: String, icon: String, engine: HighlightEngine) {
        switch self {
        case .plainText: return ("Text", "doc.plaintext", .treeSitter)
        case .markdown: return ("Markdown", "text.document", .treeSitter)
        case .vue: return ("Vue", "v.square", .vueSFC)
        case .xml: return ("XML", "chevron.left.forwardslash.chevron.right", .regex(.xml))
        case .propertyList: return ("Property List", "list.bullet.rectangle", .regex(.propertyList))
        case .diff: return ("Diff", "arrow.left.arrow.right", .regex(.diff))
        case .nginx: return ("Nginx", "network", .regex(.nginx))
        case .gitIgnore: return ("Gitignore", "eye.slash", .regex(.gitignore))
        case .environment: return ("Env", "key", .regex(.environment))
        case .graphQL: return ("GraphQL", "point.3.connected.trianglepath.dotted", .regex(.graphQL))
        case .json: return ("JSON", "curlybraces.square", .treeSitter)
        case .javascript: return ("JavaScript", "curlybraces", .treeSitter)
        case .jsx: return ("JSX", "curlybraces", .treeSitter)
        case .typescript: return ("TypeScript", "t.square", .treeSitter)
        case .tsx: return ("TSX", "t.square", .treeSitter)
        case .html: return ("HTML", "chevron.left.forwardslash.chevron.right", .treeSitter)
        case .css: return ("CSS", "paintbrush", .treeSitter)
        case .java: return ("Java", "cup.and.saucer", .treeSitter)
        case .c: return ("C", "c.square", .treeSitter)
        case .cpp: return ("C++", "plus.square", .treeSitter)
        case .objectiveC: return ("Objective-C", "o.square", .treeSitter)
        case .csharp: return ("C#", "number.square", .treeSitter)
        case .swift: return ("Swift", "swift", .treeSitter)
        case .python: return ("Python", "p.square", .treeSitter)
        case .ruby: return ("Ruby", "r.square", .treeSitter)
        case .go: return ("Go", "g.square", .treeSitter)
        case .goModule: return ("go.mod", "g.square.fill", .treeSitter)
        case .kotlin: return ("Kotlin", "k.square", .treeSitter)
        case .rust: return ("Rust", "r.square.fill", .treeSitter)
        case .php: return ("PHP", "elephant", .treeSitter)
        case .lua: return ("Lua", "l.square", .treeSitter)
        case .bash: return ("Shell", "terminal", .treeSitter)
        case .sql: return ("SQL", "cylinder.split.1x2", .treeSitter)
        case .scala: return ("Scala", "s.square", .treeSitter)
        case .dart: return ("Dart", "d.square", .treeSitter)
        case .elixir: return ("Elixir", "drop", .treeSitter)
        case .haskell: return ("Haskell", "h.square", .treeSitter)
        case .ocaml: return ("OCaml", "o.square", .treeSitter)
        case .zig: return ("Zig", "z.square", .treeSitter)
        case .toml: return ("TOML", "curlybraces.square", .treeSitter)
        case .yaml: return ("YAML", "list.bullet.rectangle", .treeSitter)
        case .dockerfile: return ("Dockerfile", "shippingbox", .treeSitter)
        }
    }

    var displayName: String { profile.name }

    var systemImageName: String { profile.icon }

    var highlighting: HighlightEngine { profile.engine }

    var supportsFormatting: Bool {
        switch self {
        case .json, .javascript, .html, .css:
            return true
        default:
            return false
        }
    }

    var isMarkdown: Bool {
        self == .markdown
    }

    var showsLineNumbers: Bool {
        !isMarkdown
    }
}
