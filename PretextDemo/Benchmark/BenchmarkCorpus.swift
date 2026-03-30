import Foundation

enum BenchmarkCorpus {
    /// 500 texts of varying lengths derived from the editorial engine body text.
    /// 200 short (5-20 words), 200 medium (20-80 words), 100 long (80-300 words).
    static let texts: [String] = buildCorpus()

    nonisolated(unsafe) static let font = OrbEditorialMetrics.bodyFont()
    static let fontSize: Double = 18
    static let lineHeight: Double = 24
    static let testWidth: Double = 400

    private static func buildCorpus() -> [String] {
        let words = OrbEditorialText.body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var result: [String] = []
        var index = 0

        func take(_ count: Int) -> String {
            var collected: [String] = []
            for _ in 0..<count {
                collected.append(words[index % words.count])
                index += 1
            }
            return collected.joined(separator: " ")
        }

        // 200 short texts (5-20 words)
        for i in 0..<200 {
            let wordCount = 5 + (i % 16)
            result.append(take(wordCount))
        }

        // 200 medium texts (20-80 words)
        for i in 0..<200 {
            let wordCount = 20 + (i % 61)
            result.append(take(wordCount))
        }

        // 100 long texts (80-300 words)
        for i in 0..<100 {
            let wordCount = 80 + (i * 220 / 100)
            result.append(take(wordCount))
        }

        return result
    }
}
