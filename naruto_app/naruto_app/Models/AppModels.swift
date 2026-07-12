import Foundation
import CoreGraphics

enum AppMode: String, CaseIterable, Hashable {
    case battle
    case free
    case speed
    case tutorial

    var title: String {
        switch self {
        case .battle: return "Battle"
        case .free: return "Free"
        case .speed: return "Speed"
        case .tutorial: return "Tutorial"
        }
    }

    var icon: String {
        switch self {
        case .battle: return "shield.lefthalf.filled"
        case .free: return "flame.fill"
        case .speed: return "bolt.fill"
        case .tutorial: return "book.fill"
        }
    }
}

enum JutsuType: String, CaseIterable, Hashable {
    case burningAsh
    case fireball
    case fire
    case kuchiyose
    case lightning
    case rasengan
    case waterDragon
    case wind

    var title: String {
        switch self {
        case .burningAsh: return "Fire Style: Burning Ash"
        case .fireball: return "Fire Style: Fireball Jutsu"
        case .fire: return "Fire"
        case .kuchiyose: return "Kuchiyose no Jutsu"
        case .lightning: return "Chidori"
        case .rasengan: return "Rasengan"
        case .waterDragon: return "Water Style: Water Dragon Bullet"
        case .wind: return "Wind Style: Rasengan"
        }
    }

    var originContext: String {
        switch self {
        case .rasengan:
            return "Naruto"
        case .lightning:
            return "Sasuke"
        case .fireball:
            return "Uchiha Clan"
        case .burningAsh:
            return "Asuma Sarutobi"
        case .kuchiyose:
            return "Summoning Technique"
        case .waterDragon:
            return "Tobirama Senju"
        case .fire:
            return "General Ninja"
        case .wind:
            return "Naruto"
        }
    }

    var icon: String {
        switch self {
        case .burningAsh: return "smoke.fill"
        case .fireball: return "flame.circle.fill"
        case .fire: return "flame.fill"
        case .kuchiyose: return "pawprint.fill"
        case .lightning: return "bolt.fill"
        case .rasengan: return "sparkles"
        case .waterDragon: return "drop.fill"
        case .wind: return "wind"
        }
    }

    var signSequence: [String] {
        switch self {
        case .burningAsh:
            return ["dragon", "ox", "dog", "horse"]
        case .fireball:
            return ["horse", "snake", "monkey", "boar", "horse"]
        case .fire:
            return ["bird", "snake"]
        case .kuchiyose:
            return ["boar", "horse", "monkey", "bird"]
        case .lightning:
            return ["ox", "monkey"]
        case .rasengan:
            return ["monkey","bird"]
        case .waterDragon:
            return ["monkey", "boar", "bird", "ox", "horse", "bird", "dog", "snake"]
        case .wind:
            return ["horse", "monkey"]
        }
    }

    var signs: Set<String> {
        Set(signSequence)
    }
}

enum SummonAnimal: String, CaseIterable, Hashable {
    case kyuubi
    case shukaku
    case gamabunta
    case katsuryu
    case manda

    var title: String {
        switch self {
        case .kyuubi:
            return "Kyuubi"
        case .shukaku:
            return "Shukaku"
        case .gamabunta:
            return "Gamabunta"
        case .katsuryu:
            return "Katsuryu"
        case .manda:
            return "Manda"
        }
    }

    var assetNameCandidates: [String] {
        switch self {
        case .kyuubi:
            return ["baby kyuubi", "kyuubi"]
        case .shukaku:
            return ["baby shukaku", "shukaku"]
        case .gamabunta:
            return ["gamabunta"]
        case .katsuryu:
            return ["katsuryu"]
        case .manda:
            return ["manda"]
        }
    }
}

struct GameConfig: Hashable {
    let mode: AppMode
    let selectedJutsu: JutsuType?
    let selectedSummon: SummonAnimal
    let initialSasukeHP: Int

    init(
        mode: AppMode,
        selectedJutsu: JutsuType?,
        selectedSummon: SummonAnimal = .kyuubi,
        initialSasukeHP: Int = 120
    ) {
        self.mode = mode
        self.selectedJutsu = selectedJutsu
        self.selectedSummon = selectedSummon
        self.initialSasukeHP = max(60, min(300, initialSasukeHP))
    }
}

struct FaceVector3D {
    let x: CGFloat
    let y: CGFloat
    let z: CGFloat
}

struct FaceDirectionObservation {
    let nosePoint: CGPoint
    let leftMouthPoint: CGPoint
    let rightMouthPoint: CGPoint
    let upperLipPoint: CGPoint
    let lowerLipPoint: CGPoint
    let mouthPoint: CGPoint
    let deltaX: CGFloat
    let deltaY: CGFloat
    let deltaZ: CGFloat
    let vectorX: CGFloat
    let vectorY: CGFloat
    let vectorZ: CGFloat
    let mouthOpenDistance: CGFloat
    let faceScale: CGFloat
    let normalizedMouthOpen: CGFloat
    let mouthOpen: Bool
    let backendName: String

    var debugPoints: [CGPoint] {
        [nosePoint, leftMouthPoint, rightMouthPoint, upperLipPoint, lowerLipPoint]
    }

    var directionVector: CGVector {
        CGVector(dx: vectorX, dy: vectorY)
    }

    var directionVector3D: FaceVector3D {
        FaceVector3D(x: vectorX, y: vectorY, z: vectorZ)
    }

    var isFacingTowardScreen: Bool {
        vectorZ < 0
    }

    var depthScaleFactor: CGFloat {
        let toward = max(0, -vectorZ)
        let away = max(0, vectorZ)
        return max(0.6, (1.0 + (toward * 0.5)) - (away * 0.35))
    }

    var depthOpacityBoost: CGFloat {
        max(0, -vectorZ) * 0.3
    }

    var angleDegrees: CGFloat {
        atan2(vectorY, vectorX) * 180.0 / .pi
    }

    var debugLine: String {
        String(
            format: "Face[%@] vx=%.2f vy=%.2f vz=%.2f open=%.3f mouth=%@ scale=%.2f",
            backendName,
            vectorX,
            vectorY,
            vectorZ,
            normalizedMouthOpen,
            mouthOpen ? "open" : "closed",
            depthScaleFactor,
        )
    }
}

struct GestureObservation {
    let modeText: String
    let label: String
    let score: Double
    let topText: String
    let overlayHands: [[CGPoint]]
    let mouthPoint: CGPoint?
    let faceDirection: FaceDirectionObservation?
}

struct JutsuState {
    var fireActive = false
    var fireHands: [CGPoint] = []
    var fireScales: [CGFloat] = []
    var mouthPoint: CGPoint?
    var fireballDirectionVector: CGVector?
    var fireballDirectionVector3D: FaceVector3D?
    var fireballMouthOpen = false
    var fireballMouthOpenNormalized: CGFloat = 0
    var fireballDepthScale: CGFloat = 1.0
    var activeEffectJutsu: JutsuType?
    var seenSigns: Set<String> = []
    var sequenceProgressCount: Int = 0
    var triggeredJutsu: JutsuType?
    var statusMessage = ""
}
