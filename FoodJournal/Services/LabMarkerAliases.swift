import Foundation

/// v2.3a — Manual marker-merge layer for grouping LabResults across panels.
///
/// Marker grouping has two stages:
///   1. AUTO-merge by exact `LabMarker.normalize(testName)` match. Catches
///      "HbA1c" vs "Hb A1c" vs "HB-A1C" (all → "hba1c").
///   2. MANUAL-merge via this alias map. Catches "Hemoglobin A1c"
///      ("hemoglobina1c") and "HbA1c" ("hba1c") being the same marker.
///
/// Why manual-only for non-exact: a wrong auto-merge (two distinct tests on
/// one trend) is worse than an unnecessary split. The user reviews + commits
/// each merge in `LabMarkerMergeSheet`.
///
/// STORAGE: a single `@AppStorage("labMarkerAliases")` JSON-encoded
/// `[String: String]` map from `normalizedName → canonical normalizedName`.
/// Lighter than a new @Model (would have been a 17th type with no schema
/// benefit). The map doesn't survive a full app delete, but the underlying
/// LabResults DO survive via CSV — re-running merges is a one-time cost
/// against a small number of pairs, paid only after a schema-change reinstall.
///
/// CYCLE SAFETY: `canonical(of:aliases:)` follows the chain with a visited
/// set so a hand-edited map containing a → b → a returns a stable answer
/// instead of looping.
enum LabMarkerAliases {
    static let storageKey = "labMarkerAliases"

    /// Decode the @AppStorage JSON blob into a usable map. Empty / invalid
    /// blob → empty map (the merge tool just starts fresh).
    static func decode(_ json: String) -> [String: String] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    static func encode(_ map: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(map),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Resolve a normalizedName to its canonical form. Follows the alias
    /// chain transitively; a visited set guards against self-loops or
    /// hand-edited cycles. A name with no alias returns itself.
    static func canonical(of normalizedName: String, aliases: [String: String]) -> String {
        var current = normalizedName
        var visited: Set<String> = [current]
        while let next = aliases[current], !visited.contains(next), next != current {
            visited.insert(next)
            current = next
        }
        return current
    }

    /// Merge a set of `other` normalizedNames into the chosen `canonical`.
    /// Removes a self-mapping if one snuck in. Doesn't compact the existing
    /// chain — repeated merges naturally collapse via `canonical(of:...)`.
    static func merge(canonical: String,
                      others: Set<String>,
                      into aliases: inout [String: String]) {
        for other in others where other != canonical {
            aliases[other] = canonical
        }
        aliases.removeValue(forKey: canonical)
    }
}
