import SpriteKit
import SwiftUI
import UIKit

/// Transparent SpriteKit overlay that plays a particle burst per jutsu cast.
/// All textures are generated in code — no bundled art assets.
struct JutsuEffectsView: UIViewRepresentable {
    /// Incremented by the owner every time a cast should play.
    let castID: Int
    let jutsu: Jutsu?

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let scene = JutsuScene(size: UIScreen.main.bounds.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        view.presentScene(scene)
        context.coordinator.scene = scene
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let jutsu, context.coordinator.lastPlayedCastID != castID else { return }
        context.coordinator.lastPlayedCastID = castID
        context.coordinator.scene?.play(jutsu)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var scene: JutsuScene?
        var lastPlayedCastID = 0
    }
}

// MARK: - Scene

final class JutsuScene: SKScene {
    private static let particleTexture: SKTexture = {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 16, y: 16), startRadius: 1,
                endCenter: CGPoint(x: 16, y: 16), endRadius: 16,
                options: []
            )
        }
        return SKTexture(image: image)
    }()

    func play(_ jutsu: Jutsu) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        switch jutsu.nature {
        case .fire:
            addBurst(at: center, color: .orange, secondary: .red, count: 220, speed: 260, lifetime: 1.1, rise: 90)
        case .lightning:
            addBurst(at: center, color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), secondary: .white, count: 160, speed: 420, lifetime: 0.55, rise: 0)
            addBolts(around: center, color: UIColor(red: 0.62, green: 0.85, blue: 1, alpha: 1))
        case .water:
            addBurst(at: center, color: UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1), secondary: .cyan, count: 200, speed: 230, lifetime: 1.2, rise: -160)
        case .wind:
            addVortex(at: center, color: UIColor(red: 0.7, green: 0.98, blue: 0.95, alpha: 1))
        case .summoning:
            addBurst(at: center, color: UIColor(red: 0.98, green: 0.8, blue: 0.4, alpha: 1), secondary: .white, count: 260, speed: 300, lifetime: 1.3, rise: 40)
            addSealRing(at: center, color: UIColor(red: 0.98, green: 0.8, blue: 0.4, alpha: 1))
        }
    }

    private func addBurst(at position: CGPoint, color: UIColor, secondary: UIColor, count: Int, speed: CGFloat, lifetime: CGFloat, rise: CGFloat) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.particleTexture
        emitter.position = position
        emitter.numParticlesToEmit = count
        emitter.particleBirthRate = CGFloat(count) / 0.18
        emitter.particleLifetime = lifetime
        emitter.particleLifetimeRange = lifetime * 0.5
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.6
        emitter.yAcceleration = rise
        emitter.particleAlpha = 0.95
        emitter.particleAlphaSpeed = -1.1 / lifetime
        emitter.particleScale = 0.55
        emitter.particleScaleRange = 0.35
        emitter.particleScaleSpeed = -0.35
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor.white, color, secondary.withAlphaComponent(0.6)],
            times: [0, 0.25, 1]
        )
        emitter.particleBlendMode = .add
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: Double(lifetime) + 0.6), .removeFromParent()]))
    }

    private func addBolts(around center: CGPoint, color: UIColor) {
        for _ in 0..<5 {
            let path = CGMutablePath()
            var point = center
            path.move(to: point)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            for _ in 0..<6 {
                point.x += cos(angle) * .random(in: 18...44) + .random(in: -22...22)
                point.y += sin(angle) * .random(in: 18...44) + .random(in: -22...22)
                path.addLine(to: point)
            }
            let bolt = SKShapeNode(path: path)
            bolt.strokeColor = color
            bolt.lineWidth = 2.4
            bolt.glowWidth = 6
            bolt.alpha = 0
            addChild(bolt)
            bolt.run(.sequence([
                .wait(forDuration: .random(in: 0...0.15)),
                .fadeIn(withDuration: 0.03),
                .wait(forDuration: 0.06),
                .fadeOut(withDuration: 0.10),
                .removeFromParent(),
            ]))
        }
    }

    private func addVortex(at center: CGPoint, color: UIColor) {
        for ring in 0..<3 {
            let emitter = SKEmitterNode()
            emitter.particleTexture = Self.particleTexture
            emitter.position = center
            emitter.numParticlesToEmit = 120
            emitter.particleBirthRate = 400
            emitter.particleLifetime = 1.0
            emitter.emissionAngleRange = .pi * 2
            emitter.particleSpeed = 120 + CGFloat(ring) * 70
            emitter.particleRotationSpeed = 6
            emitter.xAcceleration = 0
            emitter.yAcceleration = 30
            emitter.particleAlpha = 0.8
            emitter.particleAlphaSpeed = -0.8
            emitter.particleScale = 0.4
            emitter.particleScaleSpeed = -0.2
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            // Swirl: give particles tangential motion by rotating the emitter node.
            emitter.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.8)))
            addChild(emitter)
            emitter.run(.sequence([.wait(forDuration: 1.8), .removeFromParent()]))
        }
    }

    private func addSealRing(at center: CGPoint, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: 20)
        ring.position = center
        ring.strokeColor = color
        ring.lineWidth = 3
        ring.glowWidth = 8
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 7, duration: 0.7), .fadeOut(withDuration: 0.7)]),
            .removeFromParent(),
        ]))
    }
}
