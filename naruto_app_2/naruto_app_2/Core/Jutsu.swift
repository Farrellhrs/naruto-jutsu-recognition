import SwiftUI

// MARK: - Hand signs (the 12 classifier classes)

enum HandSign: String, CaseIterable, Identifiable, Codable {
    case bird, boar, dog, dragon, hare, horse, monkey, ox, ram, rat, snake, tiger

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    /// Maps raw classifier labels (including aliases) to a sign.
    static func from(label: String) -> HandSign? {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned == "rabbit" { return .hare }
        return HandSign(rawValue: cleaned)
    }

    /// Freshly written how-to text so the Academy needs no reference images.
    var howTo: String {
        switch self {
        case .bird: return "Interlock your middle and ring fingers into a cage; touch fingertips together like a beak."
        case .boar: return "Press both palms together flat, fingers curled inward, wrists touching."
        case .dog: return "Lay your open left palm on top of your right fist."
        case .dragon: return "Stack both hands, interlace all fingers, and raise both thumbs like a crest."
        case .hare: return "Make a fist with one hand; extend index and middle fingers of the other behind it like ears."
        case .horse: return "Touch elbows outward and press index fingers together, other fingers interlocked."
        case .monkey: return "Lay both hands flat, palm over palm, thumbs pointing in opposite directions."
        case .ox: return "Right hand horizontal fingers over left vertical fingers, forming a grid."
        case .ram: return "Press palms together with index and middle fingers extended upward, others folded."
        case .rat: return "Wrap your left fingers over your raised right index and middle fingers."
        case .snake: return "Clasp hands together, all fingers fully interlaced, palms tight."
        case .tiger: return "Press palms together with both index fingers and thumbs extended upward."
        }
    }

    var glyph: String {
        switch self {
        case .bird: return "bird.fill"
        case .boar: return "hare.fill"
        case .dog: return "dog.fill"
        case .dragon: return "lizard.fill"
        case .hare: return "hare.fill"
        case .horse: return "figure.equestrian.sports"
        case .monkey: return "figure.climbing"
        case .ox: return "steeringwheel"
        case .ram: return "tornado"
        case .rat: return "pawprint.fill"
        case .snake: return "scribble.variable"
        case .tiger: return "cat.fill"
        }
    }
}

// MARK: - Elements

enum ChakraNature: String, CaseIterable {
    case fire, lightning, water, wind, summoning

    var color: Color {
        switch self {
        case .fire: return Color(red: 1.0, green: 0.45, blue: 0.15)
        case .lightning: return Color(red: 0.45, green: 0.75, blue: 1.0)
        case .water: return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .wind: return Color(red: 0.62, green: 0.95, blue: 0.9)
        case .summoning: return Color(red: 0.95, green: 0.75, blue: 0.35)
        }
    }

    var symbol: String {
        switch self {
        case .fire: return "flame.fill"
        case .lightning: return "bolt.fill"
        case .water: return "drop.fill"
        case .wind: return "wind"
        case .summoning: return "pawprint.circle.fill"
        }
    }
}

// MARK: - Jutsu catalog

enum Jutsu: String, CaseIterable, Identifiable {
    case fireStyleEmber
    case fireballJutsu
    case burningAsh
    case chidori
    case rasengan
    case windRasengan
    case waterDragon
    case summoning

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fireStyleEmber: return "Fire Style: Ember"
        case .fireballJutsu: return "Fire Style: Fireball Jutsu"
        case .burningAsh: return "Fire Style: Burning Ash"
        case .chidori: return "Chidori"
        case .rasengan: return "Rasengan"
        case .windRasengan: return "Wind Style: Rasengan"
        case .waterDragon: return "Water Style: Water Dragon"
        case .summoning: return "Summoning Jutsu"
        }
    }

    var nature: ChakraNature {
        switch self {
        case .fireStyleEmber, .fireballJutsu, .burningAsh: return .fire
        case .chidori: return .lightning
        case .rasengan, .windRasengan: return .wind
        case .waterDragon: return .water
        case .summoning: return .summoning
        }
    }

    var sequence: [HandSign] {
        switch self {
        case .fireStyleEmber: return [.bird, .snake]
        case .fireballJutsu: return [.horse, .snake, .monkey, .boar, .horse]
        case .burningAsh: return [.dragon, .ox, .dog, .horse]
        case .chidori: return [.ox, .monkey]
        case .rasengan: return [.monkey, .bird]
        case .windRasengan: return [.horse, .monkey]
        case .waterDragon: return [.monkey, .boar, .bird, .ox, .horse, .bird, .dog, .snake]
        case .summoning: return [.boar, .horse, .monkey, .bird]
        }
    }

    var soundFile: String? {
        switch self {
        case .fireStyleEmber, .fireballJutsu: return "Fireball"
        case .burningAsh: return "Burning Ash"
        case .chidori: return "Chidori"
        case .rasengan: return "Rasengan"
        case .windRasengan: return "wind style rasengan"
        case .waterDragon, .summoning: return nil
        }
    }

    /// Difficulty rank shown in the Trials screen.
    var rank: String {
        switch sequence.count {
        case ...2: return "D"
        case 3...4: return "C"
        case 5...6: return "B"
        default: return "A"
        }
    }
}
