import Core
import Foundation
import Testing

@Suite("EvidenceRecord decoding")
struct EvidenceRecordDecodingTests {
    @Test("string citation and missing url decode")
    func stringCitation() throws {
        let json = """
        {
          "id": "ev-test",
          "title": "Title",
          "summary": "Summary",
          "citation": "Morton RW, et al. (2018). Br J Sports Med.",
          "placeholder": false
        }
        """
        let record = try JSONDecoder().decode(EvidenceRecord.self, from: Data(json.utf8))
        #expect(record.citation.contains("Morton"))
        #expect(record.url == nil)
        #expect(!record.placeholder)
    }

    @Test("object citation flattens to string")
    func objectCitation() throws {
        let json = """
        {
          "id": "ev-recovery",
          "title": "ARC",
          "summary": "SDNN z-score.",
          "citation": {
            "source": "Autoregulation, Drift Management, and Periodization Policies for Helm",
            "line": "L8-9, L40-41"
          },
          "placeholder": false
        }
        """
        let record = try JSONDecoder().decode(EvidenceRecord.self, from: Data(json.utf8))
        #expect(record.citation.contains("Autoregulation"))
        #expect(record.citation.contains("L8-9"))
    }

    @Test("empty url string becomes nil")
    func emptyURL() throws {
        let json = """
        {
          "id": "ev-url",
          "title": "Title",
          "summary": "Summary",
          "citation": "Paper",
          "url": "",
          "placeholder": true
        }
        """
        let record = try JSONDecoder().decode(EvidenceRecord.self, from: Data(json.utf8))
        #expect(record.url == nil)
        #expect(record.placeholder)
    }

    @Test("methodology document still decodes mixed evidence shapes")
    func mixedDocument() throws {
        let json = """
        {
          "seedVersion": 3,
          "placeholder": false,
          "modules": [],
          "topics": [],
          "evidence": [
            {
              "id": "ev-a",
              "title": "A",
              "summary": "A",
              "citation": "Named paper",
              "url": "",
              "placeholder": false
            },
            {
              "id": "ev-b",
              "title": "B",
              "summary": "B",
              "citation": { "source": "Helm research", "line": "L1" },
              "placeholder": false
            }
          ]
        }
        """
        let document = try JSONDecoder().decode(MethodologyDocument.self, from: Data(json.utf8))
        #expect(!document.placeholder)
        #expect(document.evidence.count == 2)
        #expect(document.evidence[0].url == nil)
        #expect(document.evidence[1].citation == "Helm research. L1")
    }

    @Test("app methodology seed decodes as a real library")
    func productionSeed() throws {
        let seed = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helm/Resources/MethodologySeed/methodology.json")
        #expect(FileManager.default.fileExists(atPath: seed.path), "missing \(seed.path)")

        let document = try JSONDecoder().decode(MethodologyDocument.self, from: Data(contentsOf: seed))
        #expect(!document.placeholder)
        #expect(document.seedVersion >= 3)
        #expect(document.modules.count == 7)
        #expect(document.topics.count >= 50)
        #expect(document.evidence.count >= 90)
        #expect(document.evidence.allSatisfy { $0.citation != "Content to be authored with specific citations." || $0.placeholder })
    }
}
