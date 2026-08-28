import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Session phrase adversarial", .serialized)
struct SessionPhraseAdversarialTests {
    private struct Gym {
        let store: PersistenceStore
        let press: String
        let ext: String
        let rdl: String
        let curl: String
        let hammerCable: String
        let hammerDB: String
        let facePull: String
        let bandFace: String
        let benchDip: String
        let chestDip: String
        let hipBarbell: String
        let hipMachine: String
        let kbSwing: String

        var names: [String: String] {
            [
                press: "Leg Press Horizontal (Machine)",
                ext: "Leg Extension (Machine)",
                rdl: "Romanian Deadlift (Barbell)",
                curl: "Bicep Curl (Dumbbell)",
                hammerCable: "Hammer Curl (Cable)",
                hammerDB: "Hammer Curl (Dumbbell)",
                facePull: "Face Pull",
                bandFace: "Band Face Pull",
                benchDip: "Bench Dip",
                chestDip: "Chest Dip",
                hipBarbell: "Hip Thrust (Barbell)",
                hipMachine: "Hip Thrust (Machine)",
                kbSwing: "Kettlebell Swing",
            ]
        }

        static func seed() throws -> Gym {
            let store = try PersistenceStore.inMemory()
            func lift(
                _ id: String,
                _ display: String,
                muscle: String,
                aliases: [String]
            ) throws {
                try store.exercises.upsert(
                    id: id,
                    canonicalName: display.lowercased(),
                    displayName: display,
                    exerciseMode: .weightReps,
                    primaryMuscleGroup: muscle,
                    isPickerDefault: true
                )
                for (index, alias) in aliases.enumerated() {
                    try store.exercises.addAlias(
                        id: "\(id)-alias-\(index)",
                        exerciseID: id,
                        alias: alias
                    )
                }
            }

            let press = "seed-leg-press"
            let ext = "seed-leg-extension"
            let rdl = "seed-rdl"
            let curl = "seed-bicep-curl"
            let hammerCable = "seed-cam-hammer-curl-cable"
            let hammerDB = "seed-cam-hammer-curl-dumbbell"
            let facePull = "seed-face-pull"
            let bandFace = "seed-band-face-pull"
            let benchDip = "seed-bench-dip"
            let chestDip = "seed-chest-dip"
            let hipBarbell = "seed-hip-thrust"
            let hipMachine = "seed-cam-hip-thrust-machine"
            let kbSwing = "seed-kb-swing"

            try lift(press, "Leg Press Horizontal (Machine)", muscle: "quadriceps", aliases: ["leg press", "horizontal leg press"])
            try lift(ext, "Leg Extension (Machine)", muscle: "quadriceps", aliases: ["leg extension", "leg extensions"])
            try lift(rdl, "Romanian Deadlift (Barbell)", muscle: "hamstrings", aliases: ["romanian deadlift", "rdl", "bb rdl"])
            try lift(curl, "Bicep Curl (Dumbbell)", muscle: "biceps", aliases: ["bicep curl", "dumbbell curl"])
            try lift(hammerCable, "Hammer Curl (Cable)", muscle: "biceps", aliases: [
                "Hammer Curl (Cable)", "cable hammer curl", "rope hammer curl", "hammer curl",
            ])
            try lift(hammerDB, "Hammer Curl (Dumbbell)", muscle: "biceps", aliases: [
                "Hammer Curl (Dumbbell)", "dumbbell hammer curl", "db hammer curl", "hammer curl",
            ])
            try lift(facePull, "Face Pull", muscle: "shoulders", aliases: ["face pull", "face pulls"])
            try lift(bandFace, "Band Face Pull", muscle: "shoulders", aliases: ["band face pull", "banded face pull"])
            try lift(benchDip, "Bench Dip", muscle: "chest", aliases: ["bench dip", "bench dips"])
            try lift(chestDip, "Chest Dip", muscle: "chest", aliases: ["chest dip", "chest dips"])
            try lift(hipBarbell, "Hip Thrust (Barbell)", muscle: "glutes", aliases: ["hip thrust", "barbell hip thrust"])
            try lift(hipMachine, "Hip Thrust (Machine)", muscle: "glutes", aliases: ["machine hip thrust", "hip thrust machine"])
            try lift(kbSwing, "Kettlebell Swing", muscle: "hamstrings", aliases: ["kettlebell swing", "kb swing"])

            CoachArchetypeSupport.configure(
                with: CoachArchetypeCatalog(
                    schemaVersion: "coach_archetype_catalog.v1",
                    archetypes: [
                        CoachArchetype(
                            id: "hammer_curl",
                            displayName: "Hammer Curl",
                            coachAliases: ["hammer curl", "rope hammer curl", "dumbbell hammer curl"]
                        ),
                        CoachArchetype(
                            id: "hip_thrust",
                            displayName: "Hip Thrust",
                            coachAliases: ["hip thrust"]
                        ),
                        CoachArchetype(
                            id: "face_pull",
                            displayName: "Face Pull",
                            coachAliases: ["face pull"]
                        ),
                    ],
                    mapping: [
                        hammerCable: "hammer_curl",
                        hammerDB: "hammer_curl",
                        hipBarbell: "hip_thrust",
                        hipMachine: "hip_thrust",
                        facePull: "face_pull",
                        bandFace: "face_pull",
                    ],
                    variants: [
                        "hammer_curl": CoachArchetypeVariants(
                            members: [hammerCable, hammerDB],
                            preferredDefaultExerciseId: hammerDB
                        ),
                        "hip_thrust": CoachArchetypeVariants(
                            members: [hipBarbell, hipMachine],
                            preferredDefaultExerciseId: hipBarbell
                        ),
                        "face_pull": CoachArchetypeVariants(
                            members: [facePull, bandFace],
                            preferredDefaultExerciseId: facePull
                        ),
                    ]
                )
            )

            return Gym(
                store: store,
                press: press,
                ext: ext,
                rdl: rdl,
                curl: curl,
                hammerCable: hammerCable,
                hammerDB: hammerDB,
                facePull: facePull,
                bandFace: bandFace,
                benchDip: benchDip,
                chestDip: chestDip,
                hipBarbell: hipBarbell,
                hipMachine: hipMachine,
                kbSwing: kbSwing
            )
        }
    }

    private func swapPayload(from: String, to: String, reply: String = "Swapping.") -> SessionAdjustmentPayload {
        SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: reply,
            operations: [
                SessionAdjustmentOperation(kind: .swap, fromExerciseID: from, toExerciseID: to)
            ]
        )
    }

    private func addPayload(to: String, reply: String = "Adding.") -> SessionAdjustmentPayload {
        SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: reply,
            operations: [
                SessionAdjustmentOperation(kind: .addExercise, toExerciseID: to, targetSets: 3)
            ]
        )
    }

    // MARK: - Parse

    @Test("parse matrix covers gym-floor wording")
    func parseMatrix() {
        let cases: [(phrase: String, from: String, to: String)] = [
            ("replace leg press with leg extension", "leg press", "leg extension"),
            ("swap the leg press for leg extension", "leg press", "leg extension"),
            ("switch out the leg press for leg extension", "leg press", "leg extension"),
            ("change leg press to leg extension", "leg press", "leg extension"),
            ("REPLACE LEG PRESS WITH LEG EXTENSION", "leg press", "leg extension"),
            ("replace  the  leg press   with  leg extensions.", "leg press", "leg extensions"),
            ("please replace leg press with leg extension", "leg press", "leg extension"),
            ("i want hammer curls instead of face pull", "face pull", "hammer curls"),
            ("use rope hammer instead of face pull", "face pull", "rope hammer"),
            ("hammer curls instead of face pull thanks", "face pull", "hammer curls"),
            ("instead of face pull, use cable hammer curl", "face pull", "cable hammer curl"),
            ("swap it for leg extension", "it", "leg extension"),
            ("replace that with leg extension", "that", "leg extension"),
            ("replace leg press with leg extension and then move it to the start", "leg press", "leg extension"),
            ("switch the cable hammers to dumbbells", "cable hammers", "dumbbells"),
            ("change bench dip to chest dip", "bench dip", "chest dip"),
        ]
        for item in cases {
            let parsed = SessionSwapPhrase.parse(item.phrase)
            #expect(parsed?.from.lowercased() == item.from, "from mismatch: \(item.phrase)")
            #expect(parsed?.to.lowercased() == item.to, "to mismatch: \(item.phrase)")
        }
    }

    @Test("garbage and identity phrases do not parse as swaps")
    func garbageDoesNotParse() {
        #expect(SessionSwapPhrase.parse("what's the weather") == nil)
        #expect(SessionSwapPhrase.parse("bump the load 2.5kg") == nil)
        #expect(SessionSwapPhrase.parse("add a set") == nil)
        #expect(SessionSwapPhrase.parse("replace hammer curl with hammer curl") == nil)
        #expect(SessionSwapPhrase.parse("") == nil)
        #expect(SessionSwapPhrase.parseAdd("replace leg press with leg extension") == nil)
        #expect(SessionSwapPhrase.parseAdd("add face pull and move it to the start") == "face pull")
        #expect(SessionSwapPhrase.parseAdd("include some kb swing please") == "kb swing")
        #expect(SessionSwapPhrase.parseAdd("add 3 sets of face pull") == "face pull")
        #expect(SessionSwapPhrase.parseAdd("throw in rope hammers") == nil)
    }

    @Test("move parser covers start/end synonyms and ignores replace")
    func moveParserVariants() {
        #expect(SessionSwapPhrase.parseMove("move it to the beginning")?.position == .start)
        #expect(SessionSwapPhrase.parseMove("place it at the front")?.position == .start)
        #expect(SessionSwapPhrase.parseMove("put them last")?.position == .end)
        #expect(SessionSwapPhrase.parseMove("move it to the last")?.position == .end)
        #expect(SessionSwapPhrase.parseMove("replace leg press with leg extension") == nil)
        #expect(SessionSwapPhrase.parseMove("and then move it to the start")?.target == nil)
    }

    @Test("expand order never drops unnamed session rows")
    func expandOrderKeepsTheRest() {
        let five = ["a", "b", "c", "d", "e"]
        let moved = SessionSwapPhrase.expandOrder(
            sessionOrder: five,
            replacing: "c",
            with: "x",
            moving: "x",
            to: .start
        )
        #expect(moved == ["x", "a", "b", "d", "e"])
        #expect(Set(moved).count == 5)

        let added = SessionSwapPhrase.expandOrder(
            sessionOrder: ["a", "b"],
            replacing: nil,
            with: "new",
            moving: "new",
            to: .start
        )
        #expect(added == ["new", "a", "b"])

        let alreadyEnd = SessionSwapPhrase.expandOrder(
            sessionOrder: ["a", "b", "c"],
            replacing: nil,
            with: nil,
            moving: "c",
            to: .end
        )
        #expect(alreadyEnd == ["a", "b", "c"])
    }

    // MARK: - Bind

    @Test("Gemini chest_dip does not steal a live bench dip")
    func chestDipDoesNotStealBenchDip() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: "chest_dip", to: gym.hammerDB),
            sessionExerciseIDs: [gym.benchDip, gym.rdl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "replace bench dip with dumbbell hammer curl",
            orderedSessionExerciseIDs: [gym.benchDip, gym.rdl]
        )
        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.fromExerciseID == gym.benchDip)
        #expect(result.payload.operations.first?.toExerciseID == gym.hammerDB)
    }

    @Test("Gemini Face Pull loses to cable hammer wording")
    func facePullLosesToCableHammer() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: gym.facePull),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add cable hammer curl"
        )
        #expect(result.payload.operations.first?.toExerciseID == gym.hammerCable)
    }

    @Test("empty phrase keeps a valid model catalog ID")
    func emptyPhraseKeepsModelID() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: gym.ext),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "what's up"
        )
        #expect(result.payload.operations.first?.toExerciseID == gym.ext)
    }

    @Test("add face pull and put it first inserts without dropping the session")
    func addAndMoveToStart() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: "face_pull"),
            sessionExerciseIDs: [gym.press, gym.rdl, gym.curl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add face pull and put it first",
            orderedSessionExerciseIDs: [gym.press, gym.rdl, gym.curl]
        )
        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first { $0.kind == .addExercise }?.toExerciseID == gym.facePull)
        #expect(
            result.payload.operations.first { $0.kind == .reorder }?.orderedExerciseIDs
                == [gym.facePull, gym.press, gym.rdl, gym.curl]
        )
    }

    @Test("swap it for extension uses model from and still binds to")
    func pronounFromUsesModelSource() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: gym.press, to: "face_pull"),
            sessionExerciseIDs: [gym.press, gym.rdl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "swap it for leg extension and move it to the start",
            orderedSessionExerciseIDs: [gym.rdl, gym.press]
        )
        #expect(result.payload.operations.first { $0.kind == .swap }?.fromExerciseID == gym.press)
        #expect(result.payload.operations.first { $0.kind == .swap }?.toExerciseID == gym.ext)
        #expect(
            result.payload.operations.first { $0.kind == .reorder }?.orderedExerciseIDs
                == [gym.ext, gym.rdl]
        )
    }

    @Test("switch dumbbell hammers to cables picks cable sibling")
    func switchToCables() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: gym.hammerDB, to: "hammer_curl"),
            sessionExerciseIDs: [gym.hammerDB, gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "switch it to cables"
        )
        #expect(result.payload.operations.first?.fromExerciseID == gym.hammerDB)
        #expect(result.payload.operations.first?.toExerciseID == gym.hammerCable)
    }

    @Test("five-exercise swap+move keeps every remaining lift")
    func fiveExerciseSessionStaysIntact() throws {
        let gym = try Gym.seed()
        let order = [gym.press, gym.rdl, gym.curl, gym.facePull, gym.kbSwing]
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: "squat", to: "face_pull"),
            sessionExerciseIDs: Set(order),
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "replace the leg press with leg extension and move it to the end",
            orderedSessionExerciseIDs: order
        )
        let reorder = result.payload.operations.first { $0.kind == .reorder }?.orderedExerciseIDs ?? []
        #expect(result.payload.operations.first { $0.kind == .swap }?.fromExerciseID == gym.press)
        #expect(result.payload.operations.first { $0.kind == .swap }?.toExerciseID == gym.ext)
        #expect(reorder == [gym.rdl, gym.curl, gym.facePull, gym.kbSwing, gym.ext])
        #expect(Set(reorder).count == 5)
    }

    @Test("machine hip thrust binds when the variant exists")
    func machineHipThrustBinds() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: gym.hipBarbell, to: "hip_thrust"),
            sessionExerciseIDs: [gym.hipBarbell],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "change hip thrust to the machine"
        )
        #expect(result.payload.operations.first?.toExerciseID == gym.hipMachine)
    }

    @Test("kb swing and bb rdl bind via synonyms")
    func synonymPhrasesBind() throws {
        let gym = try Gym.seed()
        let addKB = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: "unknown"),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add kb swing"
        )
        #expect(addKB.payload.operations.first?.toExerciseID == gym.kbSwing)

        let addRDL = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: "unknown"),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "include some BB rdl"
        )
        #expect(addRDL.payload.operations.first?.toExerciseID == gym.rdl)
    }

    @Test("parenthetical cable and all-caps still bind hammer cable")
    func punctuationAndCapsHammer() throws {
        let gym = try Gym.seed()
        let parens = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: gym.facePull),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add Hammer Curl (Cable)!!!"
        )
        #expect(parens.payload.operations.first?.toExerciseID == gym.hammerCable)

        let caps = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: gym.facePull),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "ADD ROPE HAMMER CURL"
        )
        #expect(caps.payload.operations.first?.toExerciseID == gym.hammerCable)
    }

    @Test("bare curls with hammer and bicep stays unresolved not Face Pull")
    func vagueCurlsDoNotBecomeFacePull() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: gym.facePull),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add curls"
        )
        #expect(result.payload.operations.first?.toExerciseID != gym.facePull)
    }

    @Test("typo extentions does not bind rdl or hammer")
    func typoDoesNotJumpLiftFamily() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: gym.press, to: gym.hammerDB),
            sessionExerciseIDs: [gym.press, gym.rdl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "replace leg press with leg extentions"
        )
        #expect(result.payload.operations.first?.toExerciseID != gym.rdl)
        #expect(result.payload.operations.first?.toExerciseID != gym.hammerDB)
    }

    @Test("in-session adjustLoad cannot escape to a catalog-only lift")
    func sessionAdjustStaysInSession() throws {
        let gym = try Gym.seed()
        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Bump hammers.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: gym.hammerDB,
                    massDeltaKg: 2.5
                )
            ]
        )
        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [gym.press, gym.rdl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add 2.5kg to hammer curls"
        )
        #expect(result.payload.operations.first?.exerciseID != gym.hammerDB)
        #expect(result.unresolvedExerciseIDs.isEmpty == false || result.payload.operations.first?.exerciseID == nil)
    }

    @Test("recents band face pull beats aliased cable for bare face pull")
    func recentsBandFacePull() throws {
        let gym = try Gym.seed()
        let result = ExerciseResolver.resolve(
            "face pull",
            context: ExerciseResolver.Context(
                sessionExerciseIDs: [],
                recentExerciseIDs: [gym.bandFace],
                mustBeInSession: false
            ),
            persistence: gym.store
        )
        #expect(result.exerciseID == gym.bandFace)
    }

    @Test("bare face pull with no recents stays on unique alias or refuses a band steal")
    func bareFacePullWithoutRecents() throws {
        let gym = try Gym.seed()
        let result = ExerciseResolver.resolve(
            "face pull",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: gym.store
        )
        #expect(result.exerciseID == gym.facePull || result.exerciseID == nil)
        #expect(result.exerciseID != gym.bandFace)
    }

    @Test("add 3 sets of face pull still binds the lift")
    func addSetsOfStillBinds() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: addPayload(to: "unknown"),
            sessionExerciseIDs: [gym.press],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "add 3 sets of face pull"
        )
        #expect(result.payload.operations.first?.toExerciseID == gym.facePull)
    }

    @Test("swap of a lift that is not in session does not steal another session row")
    func missingFromDoesNotStealNeighbor() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: "preacher_curl", to: gym.ext),
            sessionExerciseIDs: [gym.press, gym.rdl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "replace preacher curl with leg extension",
            orderedSessionExerciseIDs: [gym.press, gym.rdl]
        )
        #expect(result.payload.operations.first?.fromExerciseID != gym.press)
        #expect(result.payload.operations.first?.fromExerciseID != gym.rdl)
        #expect(result.payload.operations.first?.toExerciseID == gym.ext)
    }

    @Test("equipment-only machine with no sibling stays unresolved")
    func equipmentOnlyWithoutSibling() throws {
        let gym = try Gym.seed()
        let result = try SessionExerciseIDResolver.normalize(
            payload: swapPayload(from: gym.rdl, to: "leg_press"),
            sessionExerciseIDs: [gym.rdl],
            exerciseDisplayNames: gym.names,
            persistence: gym.store,
            phraseHint: "switch it to the machine"
        )
        let to = result.payload.operations.first?.toExerciseID
        #expect(to != gym.rdl)
        #expect(to != gym.hipMachine)
        #expect(to != gym.ext)
        #expect(to == gym.press || to == nil || result.unresolvedExerciseIDs.isEmpty == false)
    }

    @Test("quoted and extra-please wording still splits")
    func quotedPleaseWording() {
        let parsed = SessionSwapPhrase.parse("replace \"leg press\" with \"leg extension\" please")
        #expect(parsed?.from.lowercased() == "leg press")
        #expect(parsed?.to.lowercased() == "leg extension")
    }
}
