import Foundation

/// 只给「当前可见的几十行」做 SQL 轻量着色，成本与文件大小无关。
enum SQLLineTokenizer {
    enum Kind {
        case keyword
        case string
        case number
        case comment
        case identifier
    }

    struct Run {
        let range: NSRange
        let kind: Kind
    }

    private static let keywords: Set<String> = [
        "select", "insert", "update", "delete", "replace", "create", "drop", "alter", "truncate",
        "table", "into", "values", "set", "where", "from", "as", "and", "or", "not", "null", "is",
        "in", "like", "between", "order", "by", "group", "having", "limit", "offset", "union", "all",
        "distinct", "join", "inner", "left", "right", "outer", "cross", "on", "using", "case", "when",
        "then", "else", "end", "exists", "if", "primary", "key", "unique", "index", "constraint",
        "foreign", "references", "cascade", "default", "auto_increment", "comment", "engine",
        "charset", "collate", "begin", "commit", "rollback", "lock", "unlock", "tables", "read",
        "write", "disable", "enable", "keys", "use", "database", "schema", "view", "trigger",
        "procedure", "function", "delimiter", "show", "describe", "explain", "count", "sum", "avg",
        "min", "max", "cast", "convert", "now", "current_timestamp", "interval", "int", "integer",
        "bigint", "smallint", "tinyint", "mediumint", "decimal", "numeric", "float", "double",
        "varchar", "char", "text", "longtext", "mediumtext", "tinytext", "blob", "longblob",
        "datetime", "timestamp", "date", "time", "year", "json", "enum", "binary", "varbinary",
        "unsigned", "signed", "zerofill", "bit", "boolean", "bool", "definer", "sql", "security",
        "invoker", "returns", "deterministic", "temporary", "exists"
    ]

    static func runs(in text: String) -> [Run] {
        guard !text.isEmpty else { return [] }

        let units = Array(text.utf16)
        var runs: [Run] = []
        var index = 0

        while index < units.count {
            let unit = units[index]

            if unit == 45, index + 1 < units.count, units[index + 1] == 45 {
                runs.append(Run(range: NSRange(location: index, length: units.count - index), kind: .comment))
                break
            }

            if unit == 47, index + 1 < units.count, units[index + 1] == 42 {
                let end = scanBlockComment(units, from: index + 2)
                runs.append(Run(range: NSRange(location: index, length: end - index), kind: .comment))
                index = end
                continue
            }

            if unit == 39 || unit == 34 {
                let end = scanQuoted(units, from: index, quote: unit)
                runs.append(Run(range: NSRange(location: index, length: end - index), kind: .string))
                index = end
                continue
            }

            if unit == 96 {
                let end = scanBacktick(units, from: index + 1)
                runs.append(Run(range: NSRange(location: index, length: end - index), kind: .identifier))
                index = end
                continue
            }

            if isDigit(unit), index == 0 || !isWordUnit(units[index - 1]) {
                var end = index + 1
                while end < units.count, isDigit(units[end]) || units[end] == 46 {
                    end += 1
                }
                runs.append(Run(range: NSRange(location: index, length: end - index), kind: .number))
                index = end
                continue
            }

            if isLetter(unit) || unit == 95 {
                var end = index + 1
                while end < units.count, isWordUnit(units[end]) {
                    end += 1
                }
                let word = String(decoding: units[index..<end], as: UTF16.self).lowercased()
                if keywords.contains(word) {
                    runs.append(Run(range: NSRange(location: index, length: end - index), kind: .keyword))
                }
                index = end
                continue
            }

            index += 1
        }

        return runs
    }

    private static func scanBlockComment(_ units: [UInt16], from start: Int) -> Int {
        var index = start
        while index + 1 < units.count {
            if units[index] == 42, units[index + 1] == 47 {
                return index + 2
            }
            index += 1
        }
        return units.count
    }

    private static func scanQuoted(_ units: [UInt16], from start: Int, quote: UInt16) -> Int {
        var index = start + 1
        while index < units.count {
            if units[index] == 92 {
                index += 2
                continue
            }
            if units[index] == quote {
                if index + 1 < units.count, units[index + 1] == quote {
                    index += 2
                    continue
                }
                return index + 1
            }
            index += 1
        }
        return units.count
    }

    private static func scanBacktick(_ units: [UInt16], from start: Int) -> Int {
        var index = start
        while index < units.count {
            if units[index] == 96 {
                return index + 1
            }
            index += 1
        }
        return units.count
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 48 && unit <= 57
    }

    private static func isLetter(_ unit: UInt16) -> Bool {
        (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122)
    }

    private static func isWordUnit(_ unit: UInt16) -> Bool {
        isLetter(unit) || isDigit(unit) || unit == 95 || unit == 36
    }
}
