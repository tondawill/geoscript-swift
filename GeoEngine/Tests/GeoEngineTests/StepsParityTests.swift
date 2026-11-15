import Foundation
import Testing
@testable import GeoEngine

/// Compares the Swift engine with the TypeScript one on every typed step of the web test suite.
/// Set GEO_PARITY_OUT to also write files for parity/steps.ts to open with the web code.
@Suite struct StepsParity {
    struct Dump: Decodable {
        let ok: Bool?
        let error: String?
        let label: String?
        let select: String?
        let texts: [[String]]?
        let positions: [String: [Double]]?
        let objects: [[String]]?
    }

    struct Scenario: Decodable {
        let steps: [String]
        let results: [Dump]
        let later: [Dump]
        let frozen: Dump
        let file: String
        let handWritten: String
        let handResult: Dump
    }

    struct Correction: Decodable {
        let text: String
        let caret: Int
        let input: Int
        let corrected: String

        enum Keys: String, CodingKey { case text, caret, input }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            corrected = try c.decode(String.self, forKey: .text)
            caret = try c.decode(Int.self, forKey: .caret)
            input = try c.decode(Int.self, forKey: .input)
            text = corrected
        }
    }

    struct SuggestCase: Decodable {
        let text: String
        let from: Int
        let to: Int
        let items: [String]
    }

    struct Corpus: Decodable {
        let scenarios: [Scenario]
        let suggestions: [SuggestCase]
    }

    private let ctx = TypingContext(center: Vec(x: 0, y: 0))
    private let format = ProtocolFormat(dim: { formatDimension($0) }, deg: { formatDimension($0) })

    private func kind(_ o: GeoObject) -> String {
        String(String(describing: o).prefix { $0 != "(" })
    }

    private func texts(_ c: Construction) -> [[String]] {
        c.buildProtocol(format).map { [$0.objectId, $0.text, $0.objects.joined(separator: ","), $0.exercise ? "x" : ""] }
    }

    private func compare(_ c: Construction, _ want: Dump, _ where_: String) {
        #expect(texts(c) == want.texts ?? [], "\(where_)")
        #expect(c.objects.map { [$0.id, kind($0), $0.name ?? ""] } == want.objects ?? [], "\(where_)")
        let got = c.resolve()
        let expected = want.positions ?? [:]
        #expect(Set(got.keys) == Set(expected.keys), "\(where_)")
        for (id, xy) in expected {
            guard let p = got[id] else { continue }
            #expect(abs(p.x - xy[0]) < 1e-9 && abs(p.y - xy[1]) < 1e-9, "\(where_) \(id)")
        }
    }

    private func check(_ r: Result<TypingResult, TypingFailure>, _ want: Dump, _ where_: String) {
        switch r {
        case .success(let value):
            #expect(want.ok == true, "\(where_): Swift accepted, web said \(want.error ?? "")")
            if want.ok == true {
                #expect(value.select ?? "" == want.select ?? "", "\(where_) selection")
                compare(value.construction, want, where_)
            }
        case .failure(let failure):
            #expect(want.ok == false, "\(where_): Swift refused with \(failure.error.rawValue)")
            if want.ok == false { #expect(failure.error.rawValue == want.error, "\(where_)") }
        }
    }

    private func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("steps-parity.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    @Test func matchesTypeScriptOnEveryStep() throws {
        let corpus = try corpus()
        #expect(corpus.scenarios.count > 30)
        for scenario in corpus.scenarios {
            let name = scenario.steps.joined(separator: " / ")
            var c = Construction()
            for (text, want) in zip(scenario.steps, scenario.results) {
                let r = c.applyStep(text, ctx)
                check(r, want, "\(name) @ \(text)")
                if case .success(let value) = r { c = value.construction }
            }

            let steps = c.buildProtocol(format)
            var later = scenario.later.makeIterator()
            for (i, step) in steps.enumerated() {
                if let want = later.next() { check(c.editStep(step, step.text, ctx), want, "\(name) same \(i)") }
                if let want = later.next() { check(c.editStep(step, "", ctx), want, "\(name) delete \(i)") }
                if step.text.contains("|"), step.text.contains("cm"), let want = later.next() {
                    let resized = step.text.replacing(/= [0-9,.]+ cm/, with: "= 7 cm", maxReplacements: 1)
                    check(c.editStep(step, resized, ctx), want, "\(name) resize \(i)")
                }
            }
            if let want = later.next() { check(c.insertStep("Z", ctx, index: 0), want, "\(name) insert first") }
            if let want = later.next() { check(c.insertStep("Y", ctx), want, "\(name) insert last") }

            var frozen = c
            frozen.setExercise(Array(c.objects.prefix(1).map(\.id)), on: true)
            compare(frozen, scenario.frozen, "\(name) frozen")
        }
    }

    @Test func opensWebFiles() throws {
        for scenario in try corpus().scenarios {
            let name = scenario.steps.joined(separator: " / ")
            guard case .success(let contents) = importFile(scenario.file, ctx) else {
                Issue.record("could not open the web file of \(name)")
                continue
            }
            compare(contents.construction, scenario.frozen, "\(name) file")
            if !contents.construction.objects.isEmpty {
                #expect(contents.sketch == [SketchStroke(tool: "pen", color: "red", pts: [1, 2, 3, 4])], "\(name)")
            }

            let opened = importFile(scenario.handWritten, ctx)
            if case .success(let hand) = opened {
                #expect(scenario.handResult.ok == true, "\(name) hand-written")
                if scenario.handResult.ok == true { compare(hand.construction, scenario.handResult, "\(name) hand-written") }
            } else {
                #expect(scenario.handResult.ok == false, "\(name) hand-written")
            }
        }
    }

    @Test func writesFilesTheWebCanOpen() throws {
        guard let out = ProcessInfo.processInfo.environment["GEO_PARITY_OUT"] else { return }
        for (i, scenario) in try corpus().scenarios.enumerated() {
            var c = Construction()
            for text in scenario.steps {
                if case .success(let value) = c.applyStep(text, ctx) { c = value.construction }
            }
            c.setExercise(Array(c.objects.prefix(1).map(\.id)), on: true)
            let steps = c.buildProtocol(format)
            let text = exportFile(FileContents(construction: c, sketch: [SketchStroke(tool: "eraser", color: "ink", pts: [0.5, 1.5])]),
                                  steps: steps, stepsTitle: "Konstrukce", exerciseTitle: "Zadání")
            try text.write(toFile: "\(out)/\(i).geoscript", atomically: true, encoding: .utf8)
            let expected = try JSONSerialization.data(withJSONObject: ["texts": texts(c)])
            try expected.write(to: URL(fileURLWithPath: "\(out)/\(i).geoscript.json"))
        }
    }

    @Test func suggestsLikeTypeScript() throws {
        let names = ["A", "A₁", "B", "k", "k₁", "k₂", "p"]
        for item in try corpus().suggestions {
            let got = suggest(item.text, caret: (item.text as NSString).length, names: names)
            #expect(got?.from ?? -1 == item.from, "\(item.text)")
            #expect(got?.items ?? [] == item.items, "\(item.text)")
        }
    }

    @Test func autocorrects() {
        #expect(autocorrect("A->B", caret: 4).text == "A↦B")
        #expect(autocorrect("A<->B", caret: 5).text == "A↔B")
        #expect(autocorrect("a _|_ b", caret: 7).text == "a ⊥ b")
        #expect(autocorrect("p ^ q", caret: 5).text == "p ∧ q")
        #expect(autocorrect("p || q", caret: 6).text == "p ∥ q")
        #expect(autocorrect("|AB|", caret: 4).text == "|AB|")
        #expect(autocorrect("<BAC = 60deg", caret: 12).text == "∠BAC = 60°")
        #expect(autocorrect("C e p", caret: 5).text == "C ∈ p")
        #expect(autocorrect("k n l", caret: 5).text == "k ∩ l")
        #expect(autocorrect("k1", caret: 2).text == "k₁")
        #expect(autocorrect("A->B", caret: 4).caret == 3)
    }
}
