// Checks how Glance's language follows the system language. No UI, no App build. swiftc only treats a file
// named main.swift as top-level code, so compile a copy under that name:
//   mkdir -p /tmp/sl-test && cp clients/macos/scripts/test-system-language.swift /tmp/sl-test/main.swift
//   swiftc clients/macos/Glance/Sources/SystemLanguage.swift /tmp/sl-test/main.swift -o /tmp/sl-test/run && /tmp/sl-test/run
import Foundation

var failures = 0
func check(_ name: String, _ actual: String, _ expected: String) {
    if actual == expected { print("ok   \(name)") } else { failures += 1; print("FAIL \(name): got \(actual), expected \(expected)") }
}

check("English", SystemLanguage.code(for: ["en-US"]), "en")
check("British English", SystemLanguage.code(for: ["en-GB", "zh-Hans-CN"]), "en")
check("Simplified Chinese (script and region)", SystemLanguage.code(for: ["zh-Hans-CN", "en-US"]), "zh-Hans")
check("Simplified Chinese (region only)", SystemLanguage.code(for: ["zh-CN"]), "zh-Hans")
check("Simplified Chinese (Singapore)", SystemLanguage.code(for: ["zh-SG"]), "zh-Hans")
check("Simplified Chinese with a Taiwan region still wins on the script", SystemLanguage.code(for: ["zh-Hans-TW"]), "zh-Hans")
check("bare zh", SystemLanguage.code(for: ["zh"]), "zh-Hans")
check("Traditional Chinese is not supported", SystemLanguage.code(for: ["zh-Hant-TW"]), "en")
check("Traditional Chinese (Hong Kong)", SystemLanguage.code(for: ["zh-HK"]), "en")
check("Traditional Chinese (Taiwan)", SystemLanguage.code(for: ["zh-TW", "ja-JP"]), "en")
check("Japanese", SystemLanguage.code(for: ["ja-JP"]), "ja")
check("German", SystemLanguage.code(for: ["de-DE"]), "de")
check("German (Switzerland)", SystemLanguage.code(for: ["de-CH"]), "de")
check("underscore identifiers", SystemLanguage.code(for: ["zh_Hans_CN"]), "zh-Hans")
check("unsupported language falls back to English", SystemLanguage.code(for: ["fr-FR", "de-DE"]), "en")
check("only the primary language counts", SystemLanguage.code(for: ["ko-KR", "ja-JP"]), "en")
check("empty list", SystemLanguage.code(for: []), "en")
check("empty identifier", SystemLanguage.code(for: [""]), "en")
check("every result is a supported Glance language",
      ["en-US", "zh-Hans", "zh-Hant", "ja", "de", "fr", "es", "pt-BR", "ru", "ar", "ko"].allSatisfy {
          ["en", "zh-Hans", "ja", "de"].contains(SystemLanguage.code(for: [$0]))
      } ? "yes" : "no", "yes")
let live = SystemLanguage.systemIdentifiers()
check("the system list can be read", live.isEmpty ? "empty" : "not empty", "not empty")

if failures == 0 { print("All system language checks passed.") } else { print("\(failures) check(s) failed."); exit(1) }
