import Foundation
import Lista

// Based on: https://github.com/chrisakroyd/robots-txt-parser/blob/master/src/parser.js

struct Robots {
    struct GroupMemberRecord {
        let specificity: Int
        let regex: Regex<Substring>

        init?(_ value: String) {
            do {
                regex = try Self.parsePattern(value)
            } catch {
                return nil
            }
            specificity = value.count
        }

        init(_ regex: Regex<Substring>, specificity: Int) {
            self.regex = regex
            self.specificity = specificity
        }

        static let regexSpecialChars = /[\-\[\]\/\{\}\(\)\+\?\.\\\^\$\|]/
        static let wildCardPattern = /\*/
        static let EOLPattern = /\\\$$/

        static func parsePattern(_ pattern: String) throws -> Regex<Substring> {
            var pattern = pattern
            for match in pattern.matches(of: regexSpecialChars).reversed() {
                pattern.replaceSubrange(match.range, with: "\\\(match.output)")
            }
            pattern = pattern
                .replacing(wildCardPattern, with: ".*")
                .replacing(EOLPattern, with: "$")

            return try Regex(pattern, as: Substring.self)
        }

        func matches(_ text: String) -> Bool {
            guard let match = text.prefixMatch(of: regex) else {
                return false
            }
            if text.count <= match.count || text[match.range].hasSuffix("/") {
                // rule was either a directory, or the path was a subset of the rule
                return true
            }
            // text was larger, only match if matched text was a directory component of the rule
            let endOfMatch = text.index(text.startIndex, offsetBy: match.count)
            return text[endOfMatch] == "/"
        }
    }

    struct Agent {
        let allow = Lista<GroupMemberRecord>()
        let disallow = Lista<GroupMemberRecord>()
        var crawlDelay = 0

        func canProceedTo(to: String) -> Decision {
            let allowingRecords = allow.filter { $0.matches(to) }
            let maxAllow = allowingRecords.max { $0.specificity < $1.specificity }
            let disallowingRecords = disallow.filter { $0.matches(to) }
            let maxDisallow = disallowingRecords.max { $0.specificity < $1.specificity }

            if let maxAllow, let maxDisallow {
                if maxAllow.specificity > maxDisallow.specificity {
                    return .allowed
                } else {
                    return .disallowed
                }
            } else if maxDisallow != nil {
                return .disallowed
            } else if maxAllow != nil {
                return .allowed
            } else {
                return .noComment
            }
        }
    }

    enum Decision {
        case allowed, disallowed, noComment
    }

    private static func cleanComments(_ text: String) -> String {
        text.replacing(/#.*$/, with: "")
    }

    private static func cleanSpaces(_ text: String) -> String {
        text.replacing(" ", with: "")
    }

    private static func splitOnLines(_ text: String) -> [String] {
        text.split(separator: /[\r\n]+/).map { String($0) }
    }

    private static func robustSplit(_ text: String) -> [String] {
        if text.localizedCaseInsensitiveContains("<html>") {
            []
        } else {
            text.matches(of: /(\w+-)?\w+:\s\S*/).map { cleanSpaces(String($0.output.0)) }
        }
    }

    private static func parseRecord(_ line: String) -> (field: String, value: String)? {
        if let firstColonI = line.firstIndex(of: ":") {
            let field = line[line.startIndex ..< firstColonI].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let afterColon = line.index(after: firstColonI)
            let value = line[afterColon ..< line.endIndex]
            return (field: field, value: String(value))
        } else {
            return nil
        }
    }

    let host: String?
    let sitemaps: Set<String>
    var agents: [String: Agent]

    init() {
        self.init(host: nil, sitemaps: [], agents: [:])
    }

    init(host: String?, sitemaps: Set<String>, agents: [String: Agent]) {
        self.host = host
        self.sitemaps = sitemaps
        self.agents = agents
    }

    static func parse(_ rawString: String?) -> Robots {
        guard let rawString, !rawString.isEmpty else {
            return Robots()
        }

        var lines = splitOnLines(cleanSpaces(cleanComments(rawString)))

        // Fallback to the record based split method if we find only one line.
        if lines.count == 1 {
            lines = robustSplit(cleanComments(rawString))
        }

        var agent = ""
        var _agents = [String: Agent]()
        var _sitemaps = Set<String>()
        var _host: String?

        for line in lines {
            guard let record = parseRecord(line) else {
                continue
            }

            switch record.field {
            case "user-agent":
                let recordValue = record.value.lowercased()
                if recordValue != agent, recordValue.isPopulated {
                    agent = recordValue
                    _agents[agent] = Agent()

                } else if recordValue.isEmpty {
                    agent = ""
                }
                // https://developers.google.com/webmasters/control-crawl-index/docs/robots_txt#order-of-precedence-for-group-member-records

            case "allow" where agent.isPopulated && record.value.isPopulated:
                if let r = GroupMemberRecord(record.value), let a = _agents[agent] {
                    a.allow.append(r)
                    _agents[agent] = a
                }

            case "disallow" where agent.isPopulated && record.value.isPopulated:
                if let r = GroupMemberRecord(record.value), let a = _agents[agent] {
                    a.disallow.append(r)
                    _agents[agent] = a
                }

            // Non standard but support by google therefore included.
            case "sitemap" where record.value.isPopulated:
                _sitemaps.insert(record.value)

            case "crawl-delay" where agent.isPopulated:
                let i = Int(record.value) ?? 1
                if var a = _agents[agent] {
                    a.crawlDelay = i
                    _agents[agent] = a
                }

            // Non standard but included for completeness.
            case "host" where _host == nil && record.value.isPopulated:
                _host = record.value

            default:
                break
            }
        }

        return Robots(host: _host, sitemaps: _sitemaps, agents: _agents)
    }

    func agent(_ agent: String, canProceedTo url: String) -> Bool {
        guard let path = URL(string: url)?.path else {
            return false
        }

        if let thisAgent = agents[agent.lowercased()] {
            switch thisAgent.canProceedTo(to: path) {
            case .allowed:
                return true
            case .disallowed:
                return false
            case .noComment:
                break
            }
        }

        if let all = agents["*"] {
            switch all.canProceedTo(to: path) {
            case .allowed:
                return true
            case .disallowed:
                return false
            case .noComment:
                break
            }
        }

        if let local = agents["_bloo_local_domain_agent"] {
            switch local.canProceedTo(to: path) {
            case .allowed:
                return true
            case .disallowed:
                return false
            case .noComment:
                break
            }
        }

        return true
    }
}

/*
 let text =
 """
 # Comments should be ignored.
 # Short bot test part 1.
 User-agent: Longbot
 Allow: /cheese
 Allow: /swiss
 Allow: /swissywissy
 Disallow: /swissy
 Crawl-delay: 3
 Sitemap: http://www.bbc.co.uk/news_sitemap.xml
 Sitemap: http://www.bbc.co.uk/video_sitemap.xml
 Sitemap: http://www.bbc.co.uk/sitemap.xml

 User-agent: MoreBot
 Allow: /test
 Allow: /special
 Disallow: /search
 Disallow: /news
 Crawl-delay: 89
 Sitemap: http://www.bbc.co.uk/sitemap.xml

 User-agent: *
 Allow: /news
 Allow: /Testytest
 Allow: /Test/small-test
 Disallow: /
 Disallow: /spec
 Crawl-delay: 64
 Sitemap: http://www.bbc.co.uk/mobile_sitemap.xml

 Sitemap: http://www.bbc.co.uk/test.xml
 host: http://www.bbc.co.uk
 """

 let robots = Robots.parse(text)
 robots.agent("Longbot", canProceedTo: "/cheese") // true
 robots.agent("Longbot", canProceedTo: "/cheeses") // false
 robots.agent("Longbot", canProceedTo: "/swis") // false
 robots.agent("Longbot", canProceedTo: "/swiss") // true
 robots.agent("Longbot", canProceedTo: "/swissy") // false
 robots.agent("Longbot", canProceedTo: "/swissyw") // false
 robots.agent("Longbot", canProceedTo: "/swissywissy") //true
 robots.agent("Longbot", canProceedTo: "/swissywissyssss") //false

 robots.agent("Longbot", canProceedTo: "/cheese/a") // true
 robots.agent("Longbot", canProceedTo: "/cheeses/a") // false
 robots.agent("Longbot", canProceedTo: "/swis/a") // false
 robots.agent("Longbot", canProceedTo: "/swiss/a") // true
 robots.agent("Longbot", canProceedTo: "/swissy/a") // false
 robots.agent("Longbot", canProceedTo: "/swissyw/a") // false
 robots.agent("Longbot", canProceedTo: "/swissywissy/a") //true
 robots.agent("Longbot", canProceedTo: "/swissywissys/a") //false
 */
