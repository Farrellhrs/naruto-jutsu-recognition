import AVFoundation
import SpriteKit
import SwiftUI

struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    let hands: [[CGPoint]]
    let faceDebugPoints: [CGPoint]
    let fireHands: [CGPoint]
    let fireScales: [CGFloat]
    let mouthPoint: CGPoint?
    let fireballDirectionVector: CGVector?
    let fireballDirectionVector3D: FaceVector3D?
    let fireballMouthOpen: Bool
    let fireballMouthOpenNormalized: CGFloat
    let fireballDepthScale: CGFloat
    let fireActive: Bool
    let activeJutsu: JutsuType?
    let selectedSummon: SummonAnimal
    let orientation: AVCaptureVideoOrientation
    let mirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        view.updatePreviewConnection(orientation: orientation, mirrored: mirrored)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.videoPreviewLayer.videoGravity = .resizeAspect
        uiView.updatePreviewConnection(orientation: orientation, mirrored: mirrored)
        uiView.updateHands(hands)
        uiView.updateFaceDebug(points: faceDebugPoints)
        uiView.updateJutsuEffect(
            hands: fireHands,
            scales: fireScales,
            mouthPoint: mouthPoint,
            fireballDirectionVector: fireballDirectionVector,
            fireballDirectionVector3D: fireballDirectionVector3D,
            fireballMouthOpen: fireballMouthOpen,
            fireballMouthOpenNormalized: fireballMouthOpenNormalized,
            fireballDepthScale: fireballDepthScale,
            active: fireActive,
            jutsu: activeJutsu,
            selectedSummon: selectedSummon
        )
    }
}

private final class WaterDragonScene: SKScene {
    enum AttackDirection {
        case left
        case right
    }

    private enum Phase: String {
        case idle
        case waterRise
        case dragonForm
        case attack
        case impact
        case fadeOut
    }

    private struct DragonCurve {
        let p0: CGPoint
        let p1: CGPoint
        let p2: CGPoint
        let p3: CGPoint
    }

    private let blurNode = SKEffectNode()
    private let effectRoot = SKNode()
    private let headNode = SKShapeNode(circleOfRadius: 44)
    private let highlightNode = SKShapeNode(circleOfRadius: 16)
    private let jawNode = SKShapeNode()
    private let hornLeftNode = SKShapeNode()
    private let hornRightNode = SKShapeNode()
    private let eyeNode = SKShapeNode(circleOfRadius: 4)
    private let whiskerLeftNode = SKShapeNode()
    private let whiskerRightNode = SKShapeNode()
    private let splashNode = SKShapeNode(circleOfRadius: 52)
    private let bodyRibbonOuterNode = SKShapeNode()
    private let bodyRibbonInnerNode = SKShapeNode()
    private var bodyNodes: [SKShapeNode] = []
    private var crestNodes: [SKShapeNode] = []

    private let debugPathNode = SKShapeNode()
    private let phaseDebugLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let particleDebugLabel = SKLabelNode(fontNamed: "Menlo")
    private let impactFlashNode = SKSpriteNode(color: UIColor(red: 0.78, green: 0.94, blue: 1.0, alpha: 1.0), size: .zero)

    private var riseEmitter: SKEmitterNode?
    private var trailEmitter: SKEmitterNode?
    private var impactEmitter: SKEmitterNode?
    private var waterParticleTexture: SKTexture?

    private var phase: Phase = .idle
    private var phaseElapsed: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var curve: DragonCurve?
    private var trailPoints: [CGPoint] = []
    private var headPosition: CGPoint = .zero
    private var currentDirection: AttackDirection = .right
    private var impactDidTrigger = false
    private var debugEnabled = false
    private var headFacingAngle: CGFloat = 0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        setupScene()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        setupScene()
    }

    func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        debugPathNode.isHidden = !enabled
        phaseDebugLabel.isHidden = !enabled
        particleDebugLabel.isHidden = !enabled
    }

    func trigger(direction: AttackDirection) {
        guard size.width > 10, size.height > 10 else { return }

        resetEffect()
        currentDirection = direction
        impactDidTrigger = false

        let directionSign: CGFloat = direction == .right ? 1 : -1
        let startX = (size.width * 0.5) + CGFloat.random(in: -(size.width * 0.10)...(size.width * 0.10))
        let startPoint = CGPoint(x: startX, y: -170)
        let control1 = CGPoint(x: startX + (directionSign * CGFloat.random(in: 70...140)), y: size.height * 0.42)
        let control2 = CGPoint(x: startX + (directionSign * CGFloat.random(in: 320...540)), y: size.height * 1.05)
        let endPoint = CGPoint(
            x: directionSign > 0 ? size.width + 170 : -170,
            y: size.height * CGFloat.random(in: 0.34...0.62)
        )

        curve = DragonCurve(p0: startPoint, p1: control1, p2: control2, p3: endPoint)
        headPosition = startPoint
        headFacingAngle = directionSign > 0 ? 0 : .pi
        headNode.position = startPoint
        trailPoints = [startPoint]
        effectRoot.alpha = 1.0
        effectRoot.position = .zero

        prepareEmitters(at: startPoint)
        updateDebugPath()
        setPhase(.waterRise)
    }

    func resetEffect() {
        phase = .idle
        phaseElapsed = 0
        lastUpdateTime = 0
        curve = nil
        impactDidTrigger = false
        trailPoints.removeAll(keepingCapacity: true)
        effectRoot.removeAllActions()
        effectRoot.position = .zero
        effectRoot.alpha = 0

        headNode.alpha = 0
        splashNode.alpha = 0
        bodyRibbonOuterNode.path = nil
        bodyRibbonInnerNode.path = nil
        debugPathNode.path = nil

        riseEmitter?.removeFromParent()
        riseEmitter = nil
        trailEmitter?.removeFromParent()
        trailEmitter = nil
        impactEmitter?.removeFromParent()
        impactEmitter = nil

        for node in bodyNodes {
            node.alpha = 0
        }
        for node in crestNodes {
            node.alpha = 0
        }

        impactFlashNode.removeAllActions()
        impactFlashNode.alpha = 0

        updateDebugLabels()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        phaseDebugLabel.position = CGPoint(x: 12, y: size.height - 14)
        particleDebugLabel.position = CGPoint(x: 12, y: size.height - 34)
        impactFlashNode.size = size
        impactFlashNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        if phase != .idle {
            updateDebugPath()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime <= 0 {
            dt = 1.0 / 60.0
        } else {
            dt = max(1.0 / 240.0, min(1.0 / 20.0, currentTime - lastUpdateTime))
        }
        lastUpdateTime = currentTime

        guard let curve, phase != .idle else {
            updateDebugLabels()
            return
        }

        phaseElapsed += dt
        switch phase {
        case .waterRise:
            let progress = min(1.0, phaseElapsed / 1.0)
            let pathT = 0.18 * easeOut(progress)
            moveHead(to: point(on: curve, t: pathT), deltaTime: dt)
            riseEmitter?.particleBirthRate = 140 + (340 * CGFloat(progress))
            trailEmitter?.particleBirthRate = 60 + (120 * CGFloat(progress))
            if progress >= 1.0 {
                setPhase(.dragonForm)
            }

        case .dragonForm:
            let progress = min(1.0, phaseElapsed / 0.8)
            let pathT = 0.18 + (0.44 * easeInOut(progress))
            moveHead(to: point(on: curve, t: pathT), deltaTime: dt)
            riseEmitter?.particleBirthRate = 0
            trailEmitter?.particleBirthRate = 280 + (260 * CGFloat(progress))
            if progress >= 1.0 {
                setPhase(.attack)
            }

        case .attack:
            let progress = min(1.0, phaseElapsed / 0.5)
            let pathT = 0.62 + (0.38 * easeOut(progress))
            moveHead(to: point(on: curve, t: pathT), deltaTime: dt)

            trailEmitter?.particleBirthRate = 760
            trailEmitter?.particleSpeed = 320
            applyAttackShake(progress: CGFloat(progress))

            if progress >= 1.0 {
                setPhase(.impact)
            }

        case .impact:
            let progress = min(1.0, phaseElapsed / 0.3)
            if !impactDidTrigger {
                impactDidTrigger = true
                triggerImpact(at: clampedImpactPoint(from: headPosition))
            }
            headNode.alpha = CGFloat(max(0, 1.0 - progress))
            trailEmitter?.particleBirthRate = max(0, 260 * CGFloat(1.0 - progress))
            if progress >= 1.0 {
                setPhase(.fadeOut)
            }

        case .fadeOut:
            let progress = min(1.0, phaseElapsed / 0.35)
            effectRoot.alpha = CGFloat(max(0, 1.0 - progress))
            trailEmitter?.particleBirthRate = 0
            if progress >= 1.0 {
                resetEffect()
            }

        case .idle:
            break
        }

        updateBodyNodes()
        updateDebugLabels()
    }

    private func setupScene() {
        blurNode.shouldEnableEffects = true
        blurNode.shouldRasterize = true
        blurNode.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 1.4])
        blurNode.zPosition = 100
        addChild(blurNode)

        blurNode.addChild(effectRoot)
        effectRoot.alpha = 0

        configureBodyRibbon()
        configureHeadNode()
        configureSplashNode()
        configureBodyNodes(count: 42)
        configureCrestNodes(count: 18)
        configureDebugNodes()
        configureImpactFlashNode()
    }

    private func configureBodyRibbon() {
        bodyRibbonOuterNode.strokeColor = UIColor(red: 0.32, green: 0.78, blue: 1.0, alpha: 0.90)
        bodyRibbonOuterNode.fillColor = .clear
        bodyRibbonOuterNode.lineCap = .round
        bodyRibbonOuterNode.lineJoin = .round
        bodyRibbonOuterNode.lineWidth = 70
        bodyRibbonOuterNode.glowWidth = 16
        bodyRibbonOuterNode.alpha = 0
        bodyRibbonOuterNode.blendMode = .add
        bodyRibbonOuterNode.zPosition = 72
        effectRoot.addChild(bodyRibbonOuterNode)

        bodyRibbonInnerNode.strokeColor = UIColor(red: 0.86, green: 0.98, blue: 1.0, alpha: 0.92)
        bodyRibbonInnerNode.fillColor = .clear
        bodyRibbonInnerNode.lineCap = .round
        bodyRibbonInnerNode.lineJoin = .round
        bodyRibbonInnerNode.lineWidth = 34
        bodyRibbonInnerNode.glowWidth = 9
        bodyRibbonInnerNode.alpha = 0
        bodyRibbonInnerNode.blendMode = .add
        bodyRibbonInnerNode.zPosition = 73
        effectRoot.addChild(bodyRibbonInnerNode)
    }

    private func configureHeadNode() {
        headNode.fillColor = UIColor(red: 0.26, green: 0.76, blue: 1.0, alpha: 0.95)
        headNode.strokeColor = UIColor(red: 0.85, green: 0.97, blue: 1.0, alpha: 1.0)
        headNode.lineWidth = 2.8
        headNode.glowWidth = 24
        headNode.alpha = 0
        headNode.blendMode = .add

        highlightNode.fillColor = UIColor.white.withAlphaComponent(0.92)
        highlightNode.strokeColor = .clear
        highlightNode.alpha = 0.72
        highlightNode.position = CGPoint(x: 13, y: 17)
        highlightNode.blendMode = .add
        headNode.addChild(highlightNode)

        let jawPath = UIBezierPath()
        jawPath.move(to: CGPoint(x: 10, y: -4))
        jawPath.addLine(to: CGPoint(x: 58, y: -10))
        jawPath.addLine(to: CGPoint(x: 52, y: -25))
        jawPath.addLine(to: CGPoint(x: 10, y: -16))
        jawPath.close()
        jawNode.path = jawPath.cgPath
        jawNode.fillColor = UIColor(red: 0.68, green: 0.92, blue: 1.0, alpha: 0.86)
        jawNode.strokeColor = UIColor.white.withAlphaComponent(0.85)
        jawNode.lineWidth = 1.1
        jawNode.blendMode = .add
        headNode.addChild(jawNode)

        let hornPath = UIBezierPath()
        hornPath.move(to: CGPoint(x: -6, y: 22))
        hornPath.addLine(to: CGPoint(x: 22, y: 58))
        hornPath.addLine(to: CGPoint(x: 6, y: 20))
        hornPath.close()

        hornLeftNode.path = hornPath.cgPath
        hornLeftNode.fillColor = UIColor(red: 0.80, green: 0.97, blue: 1.0, alpha: 0.92)
        hornLeftNode.strokeColor = UIColor.white.withAlphaComponent(0.90)
        hornLeftNode.lineWidth = 1.0
        hornLeftNode.blendMode = .add
        headNode.addChild(hornLeftNode)

        hornRightNode.path = hornPath.cgPath
        hornRightNode.fillColor = hornLeftNode.fillColor
        hornRightNode.strokeColor = hornLeftNode.strokeColor
        hornRightNode.lineWidth = 1.0
        hornRightNode.blendMode = .add
        hornRightNode.xScale = -1
        headNode.addChild(hornRightNode)

        eyeNode.fillColor = UIColor.white.withAlphaComponent(0.96)
        eyeNode.strokeColor = UIColor(red: 0.08, green: 0.26, blue: 0.55, alpha: 0.75)
        eyeNode.lineWidth = 0.9
        eyeNode.position = CGPoint(x: 20, y: 6)
        eyeNode.blendMode = .add
        headNode.addChild(eyeNode)

        whiskerLeftNode.strokeColor = UIColor.white.withAlphaComponent(0.85)
        whiskerLeftNode.lineWidth = 1.6
        whiskerLeftNode.lineCap = .round
        whiskerLeftNode.blendMode = .add
        headNode.addChild(whiskerLeftNode)

        whiskerRightNode.strokeColor = whiskerLeftNode.strokeColor
        whiskerRightNode.lineWidth = whiskerLeftNode.lineWidth
        whiskerRightNode.lineCap = .round
        whiskerRightNode.blendMode = .add
        headNode.addChild(whiskerRightNode)

        effectRoot.addChild(headNode)
    }

    private func configureSplashNode() {
        splashNode.fillColor = UIColor(red: 0.55, green: 0.88, blue: 1.0, alpha: 0.85)
        splashNode.strokeColor = UIColor.white.withAlphaComponent(0.95)
        splashNode.lineWidth = 2.0
        splashNode.glowWidth = 14
        splashNode.blendMode = .add
        splashNode.alpha = 0
        effectRoot.addChild(splashNode)
    }

    private func configureBodyNodes(count: Int) {
        bodyNodes.forEach { $0.removeFromParent() }
        bodyNodes.removeAll(keepingCapacity: true)

        for index in 0..<count {
            let radius = max(8.0, 36.0 - (CGFloat(index) * 0.62))
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = UIColor(red: 0.20, green: 0.66, blue: 1.0, alpha: 0.60)
            node.strokeColor = UIColor(red: 0.84, green: 0.98, blue: 1.0, alpha: 0.96)
            node.lineWidth = 1.2
            node.glowWidth = 8.0
            node.alpha = 0
            node.blendMode = .add
            node.zPosition = CGFloat(80 - index)
            effectRoot.addChild(node)
            bodyNodes.append(node)
        }
    }

    private func configureCrestNodes(count: Int) {
        crestNodes.forEach { $0.removeFromParent() }
        crestNodes.removeAll(keepingCapacity: true)

        let crestPath = UIBezierPath()
        crestPath.move(to: CGPoint(x: 0, y: 0))
        crestPath.addLine(to: CGPoint(x: 7, y: 18))
        crestPath.addLine(to: CGPoint(x: -7, y: 18))
        crestPath.close()

        for index in 0..<count {
            let crest = SKShapeNode(path: crestPath.cgPath)
            crest.fillColor = UIColor(red: 0.90, green: 0.99, blue: 1.0, alpha: 0.88)
            crest.strokeColor = UIColor(red: 0.64, green: 0.90, blue: 1.0, alpha: 0.86)
            crest.lineWidth = 0.9
            crest.alpha = 0
            crest.blendMode = .add
            crest.zPosition = CGFloat(79 - index)
            effectRoot.addChild(crest)
            crestNodes.append(crest)
        }
    }

    private func configureImpactFlashNode() {
        impactFlashNode.size = size
        impactFlashNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        impactFlashNode.alpha = 0
        impactFlashNode.zPosition = 220
        impactFlashNode.blendMode = .add
        addChild(impactFlashNode)
    }

    private func configureDebugNodes() {
        debugPathNode.strokeColor = UIColor.systemTeal.withAlphaComponent(0.9)
        debugPathNode.lineWidth = 1.4
        debugPathNode.fillColor = UIColor.clear
        debugPathNode.zPosition = 140
        debugPathNode.isHidden = true
        addChild(debugPathNode)

        phaseDebugLabel.fontSize = 11
        phaseDebugLabel.horizontalAlignmentMode = .left
        phaseDebugLabel.verticalAlignmentMode = .top
        phaseDebugLabel.fontColor = .white
        phaseDebugLabel.zPosition = 145
        phaseDebugLabel.isHidden = true
        addChild(phaseDebugLabel)

        particleDebugLabel.fontSize = 11
        particleDebugLabel.horizontalAlignmentMode = .left
        particleDebugLabel.verticalAlignmentMode = .top
        particleDebugLabel.fontColor = .white
        particleDebugLabel.zPosition = 145
        particleDebugLabel.isHidden = true
        addChild(particleDebugLabel)

        phaseDebugLabel.position = CGPoint(x: 12, y: size.height - 14)
        particleDebugLabel.position = CGPoint(x: 12, y: size.height - 34)
    }

    private func prepareEmitters(at origin: CGPoint) {
        riseEmitter?.removeFromParent()
        riseEmitter = makeWaterEmitter(
            birthRate: 160,
            lifetime: 1.05,
            speed: 130,
            speedRange: 90,
            scale: 0.25,
            scaleRange: 0.22,
            alpha: 0.72
        )
        riseEmitter?.particlePositionRange = CGVector(dx: 26, dy: 18)
        riseEmitter?.emissionAngle = .pi / 2
        riseEmitter?.emissionAngleRange = .pi / 4
        riseEmitter?.position = origin
        if let riseEmitter {
            effectRoot.addChild(riseEmitter)
        }

        trailEmitter?.removeFromParent()
        trailEmitter = makeWaterEmitter(
            birthRate: 120,
            lifetime: 0.58,
            speed: 160,
            speedRange: 110,
            scale: 0.18,
            scaleRange: 0.14,
            alpha: 0.86
        )
        trailEmitter?.particlePositionRange = CGVector(dx: 14, dy: 14)
        trailEmitter?.emissionAngleRange = .pi / 2
        trailEmitter?.position = origin
        if let trailEmitter {
            effectRoot.addChild(trailEmitter)
        }
    }

    private func triggerImpact(at point: CGPoint) {
        trailEmitter?.particleBirthRate = 0
        riseEmitter?.particleBirthRate = 0

        let sideBoost: CGFloat = currentDirection == .left ? 1.40 : 1.22

        splashNode.removeAllActions()
        splashNode.position = point
        splashNode.alpha = 1.0
        splashNode.setScale(0.42)
        let splashScale = SKAction.scale(to: 3.6 * sideBoost, duration: 0.28)
        splashScale.timingMode = .easeOut
        let splashFade = SKAction.fadeOut(withDuration: 0.34)
        splashNode.run(.sequence([.group([splashScale, splashFade]), .hide()]))

        spawnImpactShockwave(at: point, sideBoost: sideBoost)
        spawnEdgeSplashSpray(at: point, sideBoost: sideBoost)

        impactEmitter?.removeFromParent()
        let mainEmitter = makeWaterEmitter(
            birthRate: 0,
            lifetime: 0.86,
            speed: 460 * sideBoost,
            speedRange: 280 * sideBoost,
            scale: 0.30,
            scaleRange: 0.26,
            alpha: 0.96
        )
        mainEmitter.numParticlesToEmit = Int(420 * sideBoost)
        mainEmitter.particlePositionRange = CGVector(dx: 34, dy: 34)
        mainEmitter.emissionAngleRange = .pi * 2
        mainEmitter.position = point
        impactEmitter = mainEmitter
        effectRoot.addChild(mainEmitter)
        mainEmitter.run(.sequence([.wait(forDuration: 1.1), .removeFromParent()]))

        let mistEmitter = makeWaterEmitter(
            birthRate: 0,
            lifetime: 1.0,
            speed: 230 * sideBoost,
            speedRange: 180 * sideBoost,
            scale: 0.44,
            scaleRange: 0.36,
            alpha: 0.62
        )
        mistEmitter.numParticlesToEmit = Int(300 * sideBoost)
        mistEmitter.particlePositionRange = CGVector(dx: 48, dy: 44)
        mistEmitter.emissionAngleRange = .pi * 2
        mistEmitter.position = point
        effectRoot.addChild(mistEmitter)
        mistEmitter.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))

        impactFlashNode.removeAllActions()
        impactFlashNode.alpha = 0.50
        let flashIn = SKAction.fadeAlpha(to: 0.50, duration: 0.03)
        let flashOut = SKAction.fadeOut(withDuration: 0.28)
        impactFlashNode.run(.sequence([flashIn, flashOut]))
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        phaseElapsed = 0

        if newPhase == .attack {
            let jitterA = SKAction.moveBy(x: CGFloat.random(in: -6...6), y: CGFloat.random(in: -6...6), duration: 0.022)
            let jitterB = SKAction.moveTo(x: 0, duration: 0.03)
            let jitterY = SKAction.moveTo(y: 0, duration: 0.03)
            let shake = SKAction.repeat(.sequence([jitterA, .group([jitterB, jitterY])]), count: 14)
            effectRoot.run(shake)
        }
    }

    private func moveHead(to point: CGPoint, deltaTime: TimeInterval) {
        let previous = headPosition
        headPosition = point
        headNode.position = point
        headNode.alpha = 1.0

        let velocity = CGVector(dx: point.x - previous.x, dy: point.y - previous.y)
        let speed = sqrt((velocity.dx * velocity.dx) + (velocity.dy * velocity.dy)) / max(0.0001, deltaTime)
        if speed > 1 {
            let travelAngle = atan2(velocity.dy, velocity.dx)
            headFacingAngle = interpolateAngle(from: headFacingAngle, to: travelAngle, factor: 0.28)
        }

        headNode.zRotation = headFacingAngle
        updateHeadFeatures(time: CGFloat(phaseElapsed), speed: CGFloat(speed))

        riseEmitter?.position = point
        trailEmitter?.position = point
        trailEmitter?.emissionAngle = headFacingAngle + .pi
        trailEmitter?.particleSpeed = 160 + (CGFloat(speed) * 0.52)

        trailPoints.append(point)
        if trailPoints.count > 340 {
            trailPoints.removeFirst(trailPoints.count - 340)
        }
    }

    private func updateBodyNodes() {
        guard !trailPoints.isEmpty else {
            bodyRibbonOuterNode.path = nil
            bodyRibbonInnerNode.path = nil
            for node in bodyNodes {
                node.alpha = 0
            }
            for node in crestNodes {
                node.alpha = 0
            }
            return
        }

        let baseAlpha = effectRoot.alpha
        for (index, node) in bodyNodes.enumerated() {
            let step = max(1, index * 2)
            let sampleIndex = trailPoints.count - 1 - step
            guard sampleIndex >= 0 else {
                node.alpha = 0
                continue
            }

            let point = trailPoints[sampleIndex]
            node.position = point

            let t = CGFloat(index) / CGFloat(max(1, bodyNodes.count - 1))
            node.alpha = max(0.0, (1.0 - (0.88 * t)) * baseAlpha)
            node.setScale(max(0.30, 1.0 - (0.60 * t)))
        }

        for (index, crest) in crestNodes.enumerated() {
            let sampleOffset = 8 + (index * 5)
            let sampleIndex = trailPoints.count - 1 - sampleOffset
            guard sampleIndex > 1 else {
                crest.alpha = 0
                continue
            }

            let p = trailPoints[sampleIndex]
            let prev = trailPoints[max(0, sampleIndex - 2)]
            let tangentAngle = atan2(p.y - prev.y, p.x - prev.x)
            crest.position = p
            crest.zRotation = tangentAngle + (.pi / 2.0)

            let t = CGFloat(index) / CGFloat(max(1, crestNodes.count - 1))
            crest.alpha = max(0.0, (1.0 - (0.95 * t)) * baseAlpha)
            crest.setScale(max(0.42, 1.0 - (0.58 * t)))
        }

        updateBodyRibbon(baseAlpha: baseAlpha)
    }

    private func updateHeadFeatures(time: CGFloat, speed: CGFloat) {
        let speedBoost = min(0.20, speed / 1900.0)
        let pulse = 0.96 + (0.04 * sin(time * 10.0))
        headNode.setScale(max(0.9, pulse + speedBoost))

        highlightNode.alpha = 0.66 + min(0.28, speed / 1400.0)
        jawNode.alpha = 0.82 + min(0.16, speed / 1600.0)
        hornLeftNode.alpha = 0.84
        hornRightNode.alpha = 0.84

        let whiskerAmplitude = 8 + min(20, speed / 80.0)
        whiskerLeftNode.path = makeWhiskerPath(length: 70, amplitude: whiskerAmplitude, mirrored: false).cgPath
        whiskerLeftNode.position = CGPoint(x: 34, y: -4)

        whiskerRightNode.path = makeWhiskerPath(length: 70, amplitude: whiskerAmplitude, mirrored: true).cgPath
        whiskerRightNode.position = CGPoint(x: 34, y: -8)
    }

    private func makeWhiskerPath(length: CGFloat, amplitude: CGFloat, mirrored: Bool) -> UIBezierPath {
        let sign: CGFloat = mirrored ? -1.0 : 1.0
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addCurve(
            to: CGPoint(x: length, y: sign * 3),
            controlPoint1: CGPoint(x: length * 0.26, y: sign * amplitude),
            controlPoint2: CGPoint(x: length * 0.70, y: sign * (amplitude * 0.22))
        )
        return path
    }

    private func updateBodyRibbon(baseAlpha: CGFloat) {
        guard trailPoints.count > 8 else {
            bodyRibbonOuterNode.path = nil
            bodyRibbonInnerNode.path = nil
            bodyRibbonOuterNode.alpha = 0
            bodyRibbonInnerNode.alpha = 0
            return
        }

        var sampled: [CGPoint] = []
        var index = trailPoints.count - 1
        while index >= 0 && sampled.count < 120 {
            sampled.append(trailPoints[index])
            index -= 2
        }

        guard sampled.count > 4 else {
            bodyRibbonOuterNode.path = nil
            bodyRibbonInnerNode.path = nil
            bodyRibbonOuterNode.alpha = 0
            bodyRibbonInnerNode.alpha = 0
            return
        }

        let path = UIBezierPath()
        path.move(to: sampled[0])
        for i in 1..<sampled.count {
            let prev = sampled[i - 1]
            let cur = sampled[i]
            let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
            path.addQuadCurve(to: mid, controlPoint: prev)
        }
        if let last = sampled.last {
            path.addLine(to: last)
        }

        let phaseBoost: CGFloat
        switch phase {
        case .waterRise: phaseBoost = 0.72
        case .dragonForm: phaseBoost = 0.92
        case .attack: phaseBoost = 1.28
        case .impact: phaseBoost = 1.10
        case .fadeOut: phaseBoost = 0.58
        case .idle: phaseBoost = 0.0
        }

        bodyRibbonOuterNode.path = path.cgPath
        bodyRibbonInnerNode.path = path.cgPath
        bodyRibbonOuterNode.lineWidth = 62 + (20 * phaseBoost)
        bodyRibbonInnerNode.lineWidth = 28 + (12 * phaseBoost)
        bodyRibbonOuterNode.alpha = max(0, min(1, (0.34 + (0.42 * phaseBoost)) * baseAlpha))
        bodyRibbonInnerNode.alpha = max(0, min(1, (0.28 + (0.34 * phaseBoost)) * baseAlpha))
    }

    private func clampedImpactPoint(from point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 18), max(18, size.width - 18)),
            y: min(max(point.y, 18), max(18, size.height - 18))
        )
    }

    private func spawnImpactShockwave(at point: CGPoint, sideBoost: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: 52 * sideBoost)
        ring.position = point
        ring.strokeColor = UIColor.white.withAlphaComponent(0.96)
        ring.fillColor = .clear
        ring.lineWidth = 5.0
        ring.glowWidth = 12
        ring.alpha = 0.95
        ring.blendMode = .add
        ring.zPosition = 132
        effectRoot.addChild(ring)

        let grow = SKAction.scale(to: 4.6, duration: 0.28)
        grow.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 0.28)
        ring.run(.sequence([.group([grow, fade]), .removeFromParent()]))

        let ring2 = SKShapeNode(circleOfRadius: 30 * sideBoost)
        ring2.position = point
        ring2.strokeColor = UIColor(red: 0.68, green: 0.94, blue: 1.0, alpha: 0.95)
        ring2.fillColor = .clear
        ring2.lineWidth = 3.4
        ring2.glowWidth = 8
        ring2.alpha = 0.92
        ring2.blendMode = .add
        ring2.zPosition = 131
        effectRoot.addChild(ring2)

        let delay = SKAction.wait(forDuration: 0.05)
        let grow2 = SKAction.scale(to: 5.8, duration: 0.26)
        grow2.timingMode = .easeOut
        let fade2 = SKAction.fadeOut(withDuration: 0.24)
        ring2.run(.sequence([delay, .group([grow2, fade2]), .removeFromParent()]))
    }

    private func spawnEdgeSplashSpray(at point: CGPoint, sideBoost: CGFloat) {
        let edgeEmitter = makeWaterEmitter(
            birthRate: 0,
            lifetime: 0.74,
            speed: 320 * sideBoost,
            speedRange: 170 * sideBoost,
            scale: 0.22,
            scaleRange: 0.20,
            alpha: 0.90
        )
        edgeEmitter.numParticlesToEmit = Int(260 * sideBoost)

        let hittingLeft = currentDirection == .left || point.x <= size.width * 0.15
        if hittingLeft {
            edgeEmitter.position = CGPoint(x: max(8, point.x), y: point.y)
            edgeEmitter.emissionAngle = 0
            edgeEmitter.emissionAngleRange = .pi / 2.8
            edgeEmitter.particlePositionRange = CGVector(dx: 0, dy: 140)
        } else {
            edgeEmitter.position = CGPoint(x: min(size.width - 8, point.x), y: point.y)
            edgeEmitter.emissionAngle = .pi
            edgeEmitter.emissionAngleRange = .pi / 2.8
            edgeEmitter.particlePositionRange = CGVector(dx: 0, dy: 140)
        }

        effectRoot.addChild(edgeEmitter)
        edgeEmitter.run(.sequence([.wait(forDuration: 0.88), .removeFromParent()]))
    }

    private func interpolateAngle(from current: CGFloat, to target: CGFloat, factor: CGFloat) -> CGFloat {
        let delta = atan2(sin(target - current), cos(target - current))
        return current + (delta * max(0, min(1, factor)))
    }

    private func updateDebugPath() {
        guard debugEnabled, let curve else {
            debugPathNode.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: curve.p0)
        path.addCurve(to: curve.p3, controlPoint1: curve.p1, controlPoint2: curve.p2)
        debugPathNode.path = path.cgPath
    }

    private func updateDebugLabels() {
        guard debugEnabled else {
            phaseDebugLabel.text = nil
            particleDebugLabel.text = nil
            return
        }

        phaseDebugLabel.text = "WaterDragon phase=\(phase.rawValue)"
        let visibleBody = bodyNodes.filter { $0.alpha > 0.05 }.count
        let trailCount = trailPoints.count
        particleDebugLabel.text = "body=\(visibleBody) trail=\(trailCount)"
    }

    private func point(on curve: DragonCurve, t: CGFloat) -> CGPoint {
        let clamped = max(0, min(1, t))
        let inv = 1 - clamped
        let a = inv * inv * inv
        let b = 3 * inv * inv * clamped
        let c = 3 * inv * clamped * clamped
        let d = clamped * clamped * clamped

        return CGPoint(
            x: (a * curve.p0.x) + (b * curve.p1.x) + (c * curve.p2.x) + (d * curve.p3.x),
            y: (a * curve.p0.y) + (b * curve.p1.y) + (c * curve.p2.y) + (d * curve.p3.y)
        )
    }

    private func easeOut(_ value: TimeInterval) -> CGFloat {
        let t = max(0, min(1, value))
        let g = CGFloat(t)
        return 1.0 - pow(1.0 - g, 3.0)
    }

    private func easeInOut(_ value: TimeInterval) -> CGFloat {
        let t = max(0, min(1, value))
        let g = CGFloat(t)
        if g < 0.5 {
            return 2.0 * g * g
        }
        return 1.0 - pow(-2.0 * g + 2.0, 2.0) * 0.5
    }

    private func makeWaterEmitter(
        birthRate: CGFloat,
        lifetime: CGFloat,
        speed: CGFloat,
        speedRange: CGFloat,
        scale: CGFloat,
        scaleRange: CGFloat,
        alpha: CGFloat
    ) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeWaterParticleTexture()
        emitter.particleBirthRate = birthRate
        emitter.particleLifetime = lifetime
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speedRange
        emitter.particleScale = scale
        emitter.particleScaleRange = scaleRange
        emitter.particleScaleSpeed = -0.22
        emitter.particleAlpha = alpha
        emitter.particleAlphaRange = 0.28
        emitter.particleAlphaSpeed = -1.35
        emitter.particleColor = UIColor(red: 0.66, green: 0.93, blue: 1.0, alpha: 1.0)
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 3
        emitter.particleRotationRange = .pi * 2
        emitter.particlePositionRange = CGVector(dx: 18, dy: 18)
        return emitter
    }

    private func makeWaterParticleTexture() -> SKTexture {
        if let waterParticleTexture {
            return waterParticleTexture
        }

        let size = CGSize(width: 30, height: 30)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor.white.withAlphaComponent(0.96).cgColor,
                UIColor(red: 0.78, green: 0.97, blue: 1.0, alpha: 0.86).cgColor,
                UIColor(red: 0.34, green: 0.73, blue: 1.0, alpha: 0.52).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.34, 0.70, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
                return
            }

            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width / 2,
                options: []
            )
        }

        let texture = SKTexture(image: image)
        waterParticleTexture = texture
        return texture
    }

    private func applyAttackShake(progress: CGFloat) {
        let intensity = max(0, 1 - progress)
        let x = CGFloat.random(in: -3.6...3.6) * intensity
        let y = CGFloat.random(in: -3.6...3.6) * intensity
        effectRoot.position = CGPoint(x: x, y: y)

        if progress >= 0.96 {
            effectRoot.position = .zero
        }
    }
}

private final class KuchiyoseScene: SKScene {
    private enum State: String {
        case idle
        case detectingSequence
        case sequenceComplete
        case smoke
        case summonReveal
        case active
        case reset
    }

    private let rootNode = SKNode()
    private let smokeBackNode = SKNode()
    private let smokeFrontNode = SKNode()
    private let summonNode = SKSpriteNode()
    private let burstRingNode = SKShapeNode(circleOfRadius: 68)
    private let debugStateLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let debugInfoLabel = SKLabelNode(fontNamed: "Menlo")

    private var frontSmokeEmitter: SKEmitterNode?
    private var backSmokeEmitter: SKEmitterNode?
    private var smokeTexture: SKTexture?

    private var state: State = .idle
    private var stateElapsed: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var summonAnimal: SummonAnimal = .kyuubi
    private var summonAnchor = CGPoint.zero
    private var smokeScaleFactor: CGFloat = 1.0
    private var breathingTime: CGFloat = 0
    private var debugEnabled = false

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        setupScene()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        setupScene()
    }

    func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        debugStateLabel.isHidden = !enabled
        debugInfoLabel.isHidden = !enabled
    }

    func triggerSummon(animal: SummonAnimal) {
        resetEffect()

        summonAnimal = animal
        summonAnchor = CGPoint(
            x: size.width * CGFloat.random(in: 0.70...0.79),
            y: size.height * CGFloat.random(in: 0.28...0.36)
        )

        configureSummonTexture(for: animal)
        summonNode.position = CGPoint(x: summonAnchor.x, y: summonAnchor.y - 20)
        summonNode.alpha = 0
        summonNode.setScale(0.42)

        spawnSmokeEmitters(at: summonAnchor)
        setState(.detectingSequence)
        rootNode.alpha = 1
        burstRingNode.alpha = 0
    }

    func resetEffect() {
        state = .idle
        stateElapsed = 0
        lastUpdateTime = 0
        breathingTime = 0
        smokeScaleFactor = 1.0
        rootNode.alpha = 0

        frontSmokeEmitter?.removeFromParent()
        frontSmokeEmitter = nil
        backSmokeEmitter?.removeFromParent()
        backSmokeEmitter = nil

        smokeFrontNode.removeAllActions()
        smokeBackNode.removeAllActions()
        smokeFrontNode.alpha = 0
        smokeBackNode.alpha = 0
        smokeFrontNode.zPosition = 126
        smokeBackNode.zPosition = 104

        summonNode.removeAllActions()
        summonNode.alpha = 0
        summonNode.setScale(0.42)
        summonNode.position = summonAnchor

        burstRingNode.removeAllActions()
        burstRingNode.alpha = 0

        updateDebugLabels()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        debugStateLabel.position = CGPoint(x: 12, y: size.height - 14)
        debugInfoLabel.position = CGPoint(x: 12, y: size.height - 34)
        if state != .idle {
            summonAnchor = CGPoint(x: size.width * 0.75, y: size.height * 0.32)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime <= 0 {
            dt = 1.0 / 60.0
        } else {
            dt = max(1.0 / 240.0, min(1.0 / 20.0, currentTime - lastUpdateTime))
        }
        lastUpdateTime = currentTime

        guard state != .idle else {
            updateDebugLabels()
            return
        }

        stateElapsed += dt
        switch state {
        case .detectingSequence:
            setState(.sequenceComplete)

        case .sequenceComplete:
            if stateElapsed >= 0.30 {
                setState(.smoke)
            }

        case .smoke:
            let progress = min(1.0, stateElapsed / 1.0)
            let eased = easeOut(progress)
            frontSmokeEmitter?.particleBirthRate = (380 + (520 * CGFloat(eased))) * smokeScaleFactor
            backSmokeEmitter?.particleBirthRate = (220 + (280 * CGFloat(eased))) * smokeScaleFactor
            smokeFrontNode.alpha = CGFloat(0.58 + (0.34 * eased))
            smokeBackNode.alpha = CGFloat(0.26 + (0.26 * eased))
            smokeFrontNode.position.y = CGFloat(8 * eased) * smokeScaleFactor
            smokeBackNode.position.y = CGFloat(5 * eased) * smokeScaleFactor

            if progress >= 1.0 {
                setState(.summonReveal)
            }

        case .summonReveal:
            let progress = min(1.0, stateElapsed / 0.58)
            let eased = easeOut(progress)
            summonNode.alpha = CGFloat(eased)
            summonNode.setScale(0.42 + (0.43 * CGFloat(eased)))
            summonNode.position = CGPoint(x: summonAnchor.x, y: summonAnchor.y - 24 + CGFloat(34 * eased))

            if progress < 0.45 {
                smokeFrontNode.zPosition = 126
                smokeFrontNode.alpha = CGFloat(0.90 - (0.18 * eased))
            } else {
                smokeFrontNode.zPosition = 106
                smokeFrontNode.alpha = CGFloat(0.58 - (0.34 * eased))
            }

            smokeBackNode.alpha = CGFloat(0.32 + (0.18 * (1.0 - eased)))
            frontSmokeEmitter?.particleBirthRate = max(0, (560 * CGFloat(1.0 - eased)) * smokeScaleFactor)
            backSmokeEmitter?.particleBirthRate = (200 + (160 * CGFloat(1.0 - eased))) * smokeScaleFactor

            if progress >= 1.0 {
                setState(.active)
            }

        case .active:
            breathingTime += CGFloat(dt * 2.5)
            let breathe = 0.84 + (sin(breathingTime) * 0.028)
            summonNode.alpha = 1.0
            summonNode.setScale(breathe)
            summonNode.position = CGPoint(x: summonAnchor.x, y: summonAnchor.y + 10)

            frontSmokeEmitter?.particleBirthRate = 0
            backSmokeEmitter?.particleBirthRate = 72 * smokeScaleFactor
            smokeFrontNode.alpha = 0.15
            smokeBackNode.alpha = 0.35

            if stateElapsed >= 4.0 {
                setState(.reset)
            }

        case .reset:
            let progress = min(1.0, stateElapsed / 0.55)
            let inv = 1.0 - progress
            summonNode.alpha = CGFloat(inv)
            summonNode.setScale(CGFloat(0.84 - (0.06 * progress)))

            backSmokeEmitter?.particleBirthRate = CGFloat(80 * inv) * smokeScaleFactor
            smokeBackNode.alpha = CGFloat(0.35 * inv)
            smokeFrontNode.alpha = CGFloat(0.12 * inv)

            if progress >= 1.0 {
                resetEffect()
            }

        case .idle:
            break
        }

        updateDebugLabels()
    }

    private func setupScene() {
        rootNode.alpha = 0
        addChild(rootNode)

        smokeBackNode.zPosition = 104
        rootNode.addChild(smokeBackNode)

        summonNode.zPosition = 112
        summonNode.blendMode = .alpha
        summonNode.colorBlendFactor = 0
        rootNode.addChild(summonNode)

        smokeFrontNode.zPosition = 126
        rootNode.addChild(smokeFrontNode)

        burstRingNode.strokeColor = UIColor.white.withAlphaComponent(0.95)
        burstRingNode.fillColor = .clear
        burstRingNode.lineWidth = 4.0
        burstRingNode.glowWidth = 10
        burstRingNode.alpha = 0
        burstRingNode.zPosition = 130
        rootNode.addChild(burstRingNode)

        debugStateLabel.fontSize = 11
        debugStateLabel.horizontalAlignmentMode = .left
        debugStateLabel.verticalAlignmentMode = .top
        debugStateLabel.fontColor = .white
        debugStateLabel.zPosition = 150
        debugStateLabel.isHidden = true
        addChild(debugStateLabel)

        debugInfoLabel.fontSize = 11
        debugInfoLabel.horizontalAlignmentMode = .left
        debugInfoLabel.verticalAlignmentMode = .top
        debugInfoLabel.fontColor = .white
        debugInfoLabel.zPosition = 150
        debugInfoLabel.isHidden = true
        addChild(debugInfoLabel)

        debugStateLabel.position = CGPoint(x: 12, y: size.height - 14)
        debugInfoLabel.position = CGPoint(x: 12, y: size.height - 34)
    }

    private func spawnSmokeEmitters(at point: CGPoint) {
        frontSmokeEmitter?.removeFromParent()
        frontSmokeEmitter = makeSmokeEmitter(front: true)
        frontSmokeEmitter?.position = point
        if let frontSmokeEmitter {
            smokeFrontNode.addChild(frontSmokeEmitter)
        }

        backSmokeEmitter?.removeFromParent()
        backSmokeEmitter = makeSmokeEmitter(front: false)
        backSmokeEmitter?.position = point
        if let backSmokeEmitter {
            smokeBackNode.addChild(backSmokeEmitter)
        }

        burstRingNode.removeAllActions()
        burstRingNode.position = point
        burstRingNode.setScale(0.34 + (0.08 * smokeScaleFactor))
        burstRingNode.alpha = 0.92
        let ringGrow = SKAction.scale(to: 2.2 + (0.9 * smokeScaleFactor), duration: 0.34)
        ringGrow.timingMode = .easeOut
        let ringFade = SKAction.fadeOut(withDuration: 0.34)
        burstRingNode.run(.group([ringGrow, ringFade]))
    }

    private func configureSummonTexture(for animal: SummonAnimal) {
        let texture = summonTexture(for: animal)
        summonNode.texture = texture

        guard let texture else {
            summonNode.color = UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 0.86)
            summonNode.size = CGSize(width: size.width * 0.16, height: size.width * 0.16)
            updateSmokeScaleFactor()
            return
        }

        let source = texture.size()
        let maxW = max(90, size.width * 0.18)
        let maxH = max(90, size.height * 0.24)
        let fit = min(maxW / source.width, maxH / source.height)
        summonNode.size = CGSize(width: source.width * fit, height: source.height * fit)
        updateSmokeScaleFactor()
    }

    private func updateSmokeScaleFactor() {
        let summonReference = max(120, size.width * 0.20)
        let dominantDimension = max(summonNode.size.width, summonNode.size.height)
        let normalized = dominantDimension / summonReference
        smokeScaleFactor = max(2.2, min(3.4, 1.9 + (normalized * 1.4)))
    }

    private func summonTexture(for animal: SummonAnimal) -> SKTexture? {
        let extensions = ["png", "jpg", "jpeg", "webp"]
        for base in animal.assetNameCandidates {
            for ext in extensions {
                if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "kuchiyose"),
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    return SKTexture(image: image)
                }

                if let url = Bundle.main.url(forResource: base, withExtension: ext),
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    return SKTexture(image: image)
                }
            }
        }
        return nil
    }

    private func makeSmokeEmitter(front: Bool) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let expansion = smokeScaleFactor
        let velocityScale = 0.82 + (expansion * 0.18)
        let spriteScale = 1.10 + (expansion * 0.32)
        let lifetimeScale = 0.95 + (expansion * 0.18)
        let spreadScale = 1.1 + (expansion * 0.45)

        emitter.particleTexture = makeSmokeTexture()
        emitter.particleBirthRate = (front ? 380 : 220) * expansion
        emitter.particleLifetime = (front ? 1.00 : 1.26) * lifetimeScale
        emitter.particleLifetimeRange = 0.42 * (0.90 + (expansion * 0.10))
        emitter.particleSpeed = (front ? 96 : 64) * velocityScale
        emitter.particleSpeedRange = 82 * velocityScale
        emitter.particleScale = (front ? 0.56 : 0.70) * spriteScale
        emitter.particleScaleRange = 0.45 * spriteScale
        emitter.particleScaleSpeed = front ? 0.88 : 0.96
        emitter.particleAlpha = front ? 0.66 : 0.46
        emitter.particleAlphaRange = 0.24
        emitter.particleAlphaSpeed = -0.68
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 2.3
        emitter.particleRotationRange = .pi * 2
        emitter.particlePositionRange = CGVector(dx: (front ? 90 : 74) * spreadScale, dy: (front ? 44 : 36) * spreadScale)
        emitter.yAcceleration = 20 * velocityScale
        emitter.xAcceleration = (front ? 6 : 3) * velocityScale
        emitter.particleBlendMode = .alpha
        emitter.particleColor = front
            ? UIColor(white: 0.98, alpha: 0.94)
            : UIColor(white: 0.84, alpha: 0.62)
        emitter.particleColorBlendFactor = 1.0
        return emitter
    }

    private func makeSmokeTexture() -> SKTexture {
        if let smokeTexture {
            return smokeTexture
        }

        let size = CGSize(width: 52, height: 52)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor.white.withAlphaComponent(0.92).cgColor,
                UIColor(white: 0.95, alpha: 0.72).cgColor,
                UIColor(white: 0.80, alpha: 0.44).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.36, 0.72, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
                return
            }

            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width / 2,
                options: []
            )
        }

        let texture = SKTexture(image: image)
        smokeTexture = texture
        return texture
    }

    private func setState(_ newState: State) {
        state = newState
        stateElapsed = 0
    }

    private func updateDebugLabels() {
        guard debugEnabled else {
            debugStateLabel.text = nil
            debugInfoLabel.text = nil
            return
        }

        debugStateLabel.text = "Kuchiyose state=\(state.rawValue)"
        let progress = state == .idle ? 0 : 4
        debugInfoLabel.text = "progress=\(progress)/4 summon=\(summonAnimal.title)"
    }

    private func easeOut(_ value: TimeInterval) -> CGFloat {
        let t = max(0, min(1, value))
        let g = CGFloat(t)
        return 1.0 - pow(1.0 - g, 3.0)
    }
}

final class PreviewView: UIView {
    private enum BurningAshPhase: String {
        case idle
        case ashFlow
        case spark
        case explosion
        case fadeOut
    }

    private enum RasenganPhase: String {
        case idle
        case charging
        case active
        case thrown
        case impact
    }

    private final class AshParticle {
        let layer: CALayer
        var position: CGPoint
        var velocity: CGVector
        var age: CGFloat = 0
        var lifetime: CGFloat
        var opacity: CGFloat
        var opacityDecay: CGFloat
        var scale: CGFloat
        var scaleGrowth: CGFloat

        init(
            layer: CALayer,
            position: CGPoint,
            velocity: CGVector,
            lifetime: CGFloat,
            opacity: CGFloat,
            opacityDecay: CGFloat,
            scale: CGFloat,
            scaleGrowth: CGFloat
        ) {
            self.layer = layer
            self.position = position
            self.velocity = velocity
            self.lifetime = lifetime
            self.opacity = opacity
            self.opacityDecay = opacityDecay
            self.scale = scale
            self.scaleGrowth = scaleGrowth
        }
    }

    private final class RasenganParticle {
        let layer: CALayer
        var angle: CGFloat
        let rotationMultiplier: CGFloat
        let baseRadius: CGFloat
        let radiusAmplitude: CGFloat
        let radiusFrequency: CGFloat
        let phase: CGFloat
        let distortionSeed: CGFloat
        let alpha: CGFloat

        init(
            layer: CALayer,
            angle: CGFloat,
            rotationMultiplier: CGFloat,
            baseRadius: CGFloat,
            radiusAmplitude: CGFloat,
            radiusFrequency: CGFloat,
            phase: CGFloat,
            distortionSeed: CGFloat,
            alpha: CGFloat
        ) {
            self.layer = layer
            self.angle = angle
            self.rotationMultiplier = rotationMultiplier
            self.baseRadius = baseRadius
            self.radiusAmplitude = radiusAmplitude
            self.radiusFrequency = radiusFrequency
            self.phase = phase
            self.distortionSeed = distortionSeed
            self.alpha = alpha
        }
    }

    private let baseEffectBoost: CGFloat = 1.35
    private let fireballHorizontalBoost: CGFloat = 2.35
    private let fireballVerticalWeight: CGFloat = 0.62
    private let showFaceDebugOverlay = false
    private let showFireballDebugOverlay = false
    private let showBurningAshDebugOverlay = false
    private let showRasenganDebugOverlay = ProcessInfo.processInfo.environment["RASENGAN_DEBUG"] == "1"
    private let showWaterDragonDebugOverlay = ProcessInfo.processInfo.environment["WATER_DRAGON_DEBUG"] == "1"
    private let showKuchiyoseDebugOverlay = ProcessInfo.processInfo.environment["KUCHIYOSE_DEBUG"] == "1"
    private let burningAshMaxParticles = 320
    private var wasLightningActive = false
    private var wasFireballActive = false
    private var wasBurningAshActive = false
    private var wasRasenganActive = false
    private var wasWaterDragonActive = false
    private var wasKuchiyoseActive = false
    private var fireballChargeUntil: CFTimeInterval = 0
    private var burningAshPhase: BurningAshPhase = .idle
    private var burningAshPhaseStartedAt: CFTimeInterval = 0
    private var burningAshLastFrameAt: CFTimeInterval = 0
    private var burningAshDirectionVector = CGVector(dx: 0, dy: -1)
    private var burningAshExplosionBurstDone = false
    private var burningAshParticles: [AshParticle] = []
    private var rasenganPhase: RasenganPhase = .idle
    private var rasenganPhaseStartedAt: CFTimeInterval = 0
    private var rasenganLastFrameAt: CFTimeInterval = 0
    private var rasenganSmoothedPalm: CGPoint?
    private var rasenganPreviousHandPoint: CGPoint?
    private var rasenganVelocityVector: CGVector = .zero
    private var rasenganSmoothedSpeed: CGFloat = 0
    private var rasenganReleasePosition: CGPoint?
    private var rasenganReleaseVelocity: CGVector = .zero
    private var rasenganRotation: CGFloat = 0
    private var rasenganLockedScale: CGFloat = 1.58
    private var rasenganParticles: [RasenganParticle] = []
    private var rasenganWindStyleMode = false
    private var rasenganThrowLockedForCurrentWindCast = false
    private var rasenganTrailPoints: [CGPoint] = []
    private var rasenganImpactPoint: CGPoint?
    private let rasenganThrowThreshold: CGFloat = 980
    private let rasenganThrowVelocityMultiplier: CGFloat = 70
    private let rasenganThrowMinimumVelocity: CGFloat = 420
    private let rasenganThrowTimeout: CFTimeInterval = 1.12
    private let rasenganUseFistHeuristic = false

    private let overlayLayer = CAShapeLayer()
    private let faceDebugLayer = CAShapeLayer()
    private let fireballDebugArrowLayer = CAShapeLayer()
    private let fireballDebugTextLayer = CATextLayer()
    private let flashLayer = CALayer()
    private let auraLayerA = CAEmitterLayer()
    private let auraLayerB = CAEmitterLayer()
    private let fireLayerA = CAEmitterLayer()
    private let fireLayerB = CAEmitterLayer()
    private let lightningLayerA = CAEmitterLayer()
    private let lightningLayerB = CAEmitterLayer()
    private let boltLayerA = CAShapeLayer()
    private let boltLayerB = CAShapeLayer()
    private let streakLayerA = CAShapeLayer()
    private let streakLayerB = CAShapeLayer()
    private let fireballChargeLayer = CAShapeLayer()
    private let fireballLayer = CAEmitterLayer()
    private let burningAshLayer = CAEmitterLayer()
    private let burningAshScreenLayer = CALayer()
    private let burningAshFlashLayer = CALayer()
    private let burningAshParticleContainer = CALayer()
    private let burningAshExplosionLayer = CAEmitterLayer()
    private let burningAshSparkLayer = CAShapeLayer()
    private let burningAshDebugTextLayer = CATextLayer()
    private let rasenganContainerLayer = CALayer()
    private let rasenganGlowLayer = CALayer()
    private let rasenganWhiteAuraLayer = CALayer()
    private let rasenganCoreLayer = CALayer()
    private let rasenganRingLayer = CAShapeLayer()
    private let rasenganOuterRingLayer = CAShapeLayer()
    private let rasenganSwirlLayer = CALayer()
    private let rasenganWindTrailLayer = CAShapeLayer()
    private let rasenganImpactBurstLayer = CAShapeLayer()
    private let rasenganDebugTextLayer = CATextLayer()
    private let waterDragonView = SKView()
    private let waterDragonScene = WaterDragonScene(size: CGSize(width: 2, height: 2))
    private let kuchiyoseView = SKView()
    private let kuchiyoseScene = KuchiyoseScene(size: CGSize(width: 2, height: 2))

    private lazy var burningAshParticleImage = makeAshParticleImage().cgImage
    private lazy var burningAshExplosionParticleImage = makeParticleImage().cgImage
    private lazy var rasenganParticleImage = makeRasenganParticleImage().cgImage

    private let handConnections: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (0, 9), (9, 10), (10, 11), (11, 12),
        (0, 13), (13, 14), (14, 15), (15, 16),
        (0, 17), (17, 18), (18, 19), (19, 20),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupOverlayLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOverlayLayer()
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        flashLayer.frame = bounds
        burningAshScreenLayer.frame = bounds
        burningAshFlashLayer.frame = bounds
        burningAshParticleContainer.frame = bounds
        overlayLayer.frame = bounds
        faceDebugLayer.frame = bounds
        fireballDebugArrowLayer.frame = bounds
        fireballDebugTextLayer.frame = CGRect(x: 10, y: 10, width: max(220, bounds.width - 20), height: 56)
        burningAshDebugTextLayer.frame = CGRect(x: 10, y: 72, width: max(260, bounds.width - 20), height: 64)
        rasenganDebugTextLayer.frame = CGRect(x: 10, y: 140, width: max(260, bounds.width - 20), height: 64)
        rasenganWindTrailLayer.frame = bounds

        waterDragonView.frame = bounds
        waterDragonScene.size = bounds.size
        kuchiyoseView.frame = bounds
        kuchiyoseScene.size = bounds.size
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    private func setupOverlayLayer() {
        flashLayer.frame = bounds
        flashLayer.backgroundColor = UIColor(red: 0.74, green: 0.92, blue: 1.0, alpha: 1.0).cgColor
        flashLayer.opacity = 0
        flashLayer.zPosition = 54
        layer.addSublayer(flashLayer)

        overlayLayer.frame = bounds
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.strokeColor = UIColor.systemGreen.cgColor
        overlayLayer.lineWidth = 2.0
        overlayLayer.lineJoin = .round
        overlayLayer.lineCap = .round
        layer.addSublayer(overlayLayer)

        faceDebugLayer.frame = bounds
        faceDebugLayer.fillColor = UIColor.clear.cgColor
        faceDebugLayer.strokeColor = UIColor.systemPink.withAlphaComponent(0.95).cgColor
        faceDebugLayer.lineWidth = 2.0
        faceDebugLayer.lineJoin = .round
        faceDebugLayer.lineCap = .round
        faceDebugLayer.zPosition = 65
        layer.addSublayer(faceDebugLayer)

        fireballDebugArrowLayer.frame = bounds
        fireballDebugArrowLayer.fillColor = UIColor.clear.cgColor
        fireballDebugArrowLayer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.95).cgColor
        fireballDebugArrowLayer.lineWidth = 2.6
        fireballDebugArrowLayer.lineJoin = .round
        fireballDebugArrowLayer.lineCap = .round
        fireballDebugArrowLayer.zPosition = 66
        layer.addSublayer(fireballDebugArrowLayer)

        fireballDebugTextLayer.contentsScale = UIScreen.main.scale
        fireballDebugTextLayer.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        fireballDebugTextLayer.fontSize = 11
        fireballDebugTextLayer.foregroundColor = UIColor.white.withAlphaComponent(0.92).cgColor
        fireballDebugTextLayer.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        fireballDebugTextLayer.cornerRadius = 8
        fireballDebugTextLayer.alignmentMode = .left
        fireballDebugTextLayer.isWrapped = true
        fireballDebugTextLayer.zPosition = 67
        layer.addSublayer(fireballDebugTextLayer)

        setupAuraLayer(auraLayerA)
        setupAuraLayer(auraLayerB)
        setupFireLayer(fireLayerA)
        setupFireLayer(fireLayerB)
        setupLightningLayer(lightningLayerA)
        setupLightningLayer(lightningLayerB)
        setupBoltLayer(boltLayerA)
        setupBoltLayer(boltLayerB)
        setupStreakLayer(streakLayerA)
        setupStreakLayer(streakLayerB)
        setupFireballChargeLayer(fireballChargeLayer)
        setupFireballLayer(fireballLayer)
        setupBurningAshScreenLayer(burningAshScreenLayer)
        setupBurningAshFlashLayer(burningAshFlashLayer)
        setupBurningAshParticleContainer(burningAshParticleContainer)
        setupBurningAshLayer(burningAshLayer)
        setupBurningAshExplosionLayer(burningAshExplosionLayer)
        setupBurningAshSparkLayer(burningAshSparkLayer)
        setupBurningAshDebugLayer(burningAshDebugTextLayer)
        setupRasenganLayers()
        setupRasenganDebugLayer(rasenganDebugTextLayer)
        setupWaterDragonRenderer()
        setupKuchiyoseRenderer()
    }

    private func setupWaterDragonRenderer() {
        waterDragonView.frame = bounds
        waterDragonView.backgroundColor = .clear
        waterDragonView.allowsTransparency = true
        waterDragonView.ignoresSiblingOrder = true
        waterDragonView.isUserInteractionEnabled = false
        waterDragonView.isHidden = true

        if waterDragonView.superview == nil {
            addSubview(waterDragonView)
        }

        if waterDragonView.scene == nil {
            waterDragonScene.scaleMode = .resizeFill
            waterDragonScene.backgroundColor = .clear
            waterDragonScene.setDebugEnabled(showWaterDragonDebugOverlay)
            waterDragonView.presentScene(waterDragonScene)
        }
    }

    private func setupKuchiyoseRenderer() {
        kuchiyoseView.frame = bounds
        kuchiyoseView.backgroundColor = .clear
        kuchiyoseView.allowsTransparency = true
        kuchiyoseView.ignoresSiblingOrder = true
        kuchiyoseView.isUserInteractionEnabled = false
        kuchiyoseView.isHidden = true

        if kuchiyoseView.superview == nil {
            addSubview(kuchiyoseView)
        }

        if kuchiyoseView.scene == nil {
            kuchiyoseScene.scaleMode = .resizeFill
            kuchiyoseScene.backgroundColor = .clear
            kuchiyoseScene.setDebugEnabled(showKuchiyoseDebugOverlay)
            kuchiyoseView.presentScene(kuchiyoseScene)
        }
    }

    private func setupAuraLayer(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 34, height: 34)
        emitter.renderMode = .additive
        emitter.birthRate = 0
        emitter.zPosition = 40

        let cell = CAEmitterCell()
        cell.name = "aura"
        cell.birthRate = 190
        cell.lifetime = 2.1
        cell.lifetimeRange = 0.8
        cell.velocity = 42
        cell.velocityRange = 30
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi * 0.7
        cell.scale = 0.40
        cell.scaleRange = 0.16
        cell.alphaSpeed = -0.35
        cell.redRange = 0.2
        cell.greenRange = 0.3
        cell.blueRange = 0.08
        cell.color = UIColor.systemOrange.withAlphaComponent(0.5).cgColor
        cell.contents = makeParticleImage().cgImage

        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
    }

    private func setupFireLayer(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 26, height: 26)
        emitter.renderMode = .additive
        emitter.birthRate = 0
        emitter.zPosition = 50

        let cell = CAEmitterCell()
        cell.name = "fire"
        cell.birthRate = 520
        cell.lifetime = 1.3
        cell.lifetimeRange = 0.55
        cell.velocity = 105
        cell.velocityRange = 80
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 2
        cell.scale = 0.24
        cell.scaleRange = 0.12
        cell.alphaSpeed = -0.65
        cell.redRange = 0.15
        cell.greenRange = 0.25
        cell.blueRange = 0.05
        cell.color = UIColor.systemOrange.withAlphaComponent(0.95).cgColor
        cell.contents = makeParticleImage().cgImage

        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
    }

    private func setupLightningLayer(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 20, height: 20)
        emitter.renderMode = .additive
        emitter.birthRate = 0
        emitter.zPosition = 56

        let cell = CAEmitterCell()
        cell.name = "lightning"
        cell.birthRate = 380
        cell.lifetime = 0.28
        cell.lifetimeRange = 0.18
        cell.velocity = 160
        cell.velocityRange = 110
        cell.emissionRange = .pi * 2
        cell.scale = 0.10
        cell.scaleRange = 0.06
        cell.alphaSpeed = -2.7
        cell.color = UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.98).cgColor
        cell.contents = makeLightningParticleImage().cgImage

        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
    }

    private func setupBoltLayer(_ shape: CAShapeLayer) {
        shape.strokeColor = UIColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 0.95).cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 2.8
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.opacity = 0
        shape.zPosition = 58
        layer.addSublayer(shape)
    }

    private func setupStreakLayer(_ shape: CAShapeLayer) {
        shape.strokeColor = UIColor(red: 0.80, green: 0.96, blue: 1.0, alpha: 0.98).cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 1.8
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.opacity = 0
        shape.zPosition = 59
        layer.addSublayer(shape)
    }

    private func setupFireballLayer(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .point
        emitter.emitterSize = CGSize(width: 8, height: 8)
        emitter.renderMode = .additive
        emitter.birthRate = 0
        emitter.zPosition = 60

        let cell = CAEmitterCell()
        cell.name = "fireball"
        cell.birthRate = 2200
        cell.lifetime = 1.5
        cell.lifetimeRange = 0.5
        cell.velocity = 420
        cell.velocityRange = 140
        // Wider cone gives V-shape from the mouth.
        cell.emissionRange = .pi / 5
        cell.scale = 0.45
        cell.scaleRange = 0.20
        // Grow particles as they fly so fire gets larger farther away.
        cell.scaleSpeed = 0.95
        cell.alphaSpeed = -0.95
        cell.yAcceleration = -12
        cell.color = UIColor.systemOrange.withAlphaComponent(0.98).cgColor
        cell.contents = makeParticleImage().cgImage
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
    }

    private func setupFireballChargeLayer(_ shape: CAShapeLayer) {
        shape.strokeColor = UIColor(red: 1.0, green: 0.74, blue: 0.22, alpha: 0.95).cgColor
        shape.fillColor = UIColor(red: 1.0, green: 0.58, blue: 0.10, alpha: 0.20).cgColor
        shape.lineWidth = 2.4
        shape.opacity = 0
        shape.zPosition = 61
        layer.addSublayer(shape)
    }

    private func setupBurningAshScreenLayer(_ layerRef: CALayer) {
        layerRef.frame = bounds
        layerRef.backgroundColor = UIColor(white: 0.36, alpha: 1.0).cgColor
        layerRef.opacity = 0
        layerRef.zPosition = 57
        layer.addSublayer(layerRef)
    }

    private func setupBurningAshFlashLayer(_ layerRef: CALayer) {
        layerRef.frame = bounds
        layerRef.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.32, alpha: 1.0).cgColor
        layerRef.opacity = 0
        layerRef.zPosition = 62.5
        layer.addSublayer(layerRef)
    }

    private func setupBurningAshParticleContainer(_ layerRef: CALayer) {
        layerRef.frame = bounds
        layerRef.masksToBounds = true
        layerRef.zPosition = 58.5
        layer.addSublayer(layerRef)
    }

    private func setupBurningAshLayer(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .point
        emitter.emitterSize = CGSize(width: 8, height: 8)
        emitter.renderMode = .oldestFirst
        emitter.birthRate = 0
        emitter.zPosition = 58

        let cell = CAEmitterCell()
        cell.name = "ash"
        cell.birthRate = 2200
        cell.lifetime = 2.0
        cell.lifetimeRange = 0.8
        cell.velocity = 220
        cell.velocityRange = 120
        cell.emissionRange = .pi / 3
        cell.scale = 0.11
        cell.scaleRange = 0.08
        cell.alphaSpeed = -0.20
        cell.yAcceleration = 24
        cell.color = UIColor(white: 0.80, alpha: 0.95).cgColor
        cell.contents = makeAshParticleImage().cgImage
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
    }

    private func setupBurningAshExplosionLayer(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 26, height: 26)
        emitter.renderMode = .additive
        emitter.birthRate = 0
        emitter.zPosition = 62

        let cell = CAEmitterCell()
        cell.name = "ashExplosion"
        cell.birthRate = 1800
        cell.lifetime = 1.15
        cell.lifetimeRange = 0.45
        cell.velocity = 350
        cell.velocityRange = 190
        cell.emissionRange = .pi * 2
        cell.scale = 0.42
        cell.scaleRange = 0.18
        cell.alphaSpeed = -1.2
        cell.color = UIColor.systemOrange.withAlphaComponent(0.98).cgColor
        cell.contents = makeParticleImage().cgImage
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
    }

    private func setupBurningAshSparkLayer(_ shape: CAShapeLayer) {
        shape.fillColor = UIColor(red: 1.0, green: 0.88, blue: 0.55, alpha: 1.0).cgColor
        shape.strokeColor = UIColor(red: 1.0, green: 0.95, blue: 0.72, alpha: 1.0).cgColor
        shape.lineWidth = 1.2
        shape.opacity = 0
        shape.zPosition = 63
        shape.shadowColor = UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1.0).cgColor
        shape.shadowRadius = 14
        shape.shadowOpacity = 0.92
        shape.shadowOffset = .zero
        layer.addSublayer(shape)
    }

    private func setupBurningAshDebugLayer(_ layerRef: CATextLayer) {
        layerRef.contentsScale = UIScreen.main.scale
        layerRef.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        layerRef.fontSize = 11
        layerRef.foregroundColor = UIColor.white.withAlphaComponent(0.90).cgColor
        layerRef.backgroundColor = UIColor.black.withAlphaComponent(0.42).cgColor
        layerRef.cornerRadius = 8
        layerRef.alignmentMode = .left
        layerRef.isWrapped = true
        layerRef.opacity = 0
        layerRef.zPosition = 67
        layer.addSublayer(layerRef)
    }

    private func setupRasenganLayers() {
        let baseSize: CGFloat = 300
        let center = CGPoint(x: baseSize * 0.5, y: baseSize * 0.5)

        rasenganWindTrailLayer.frame = bounds
        rasenganWindTrailLayer.strokeColor = UIColor(red: 0.86, green: 0.98, blue: 1.0, alpha: 0.95).cgColor
        rasenganWindTrailLayer.fillColor = UIColor.clear.cgColor
        rasenganWindTrailLayer.lineWidth = 3.6
        rasenganWindTrailLayer.lineCap = .round
        rasenganWindTrailLayer.lineJoin = .round
        rasenganWindTrailLayer.opacity = 0
        rasenganWindTrailLayer.zPosition = 63
        layer.addSublayer(rasenganWindTrailLayer)

        rasenganImpactBurstLayer.bounds = CGRect(x: 0, y: 0, width: 260, height: 260)
        rasenganImpactBurstLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        rasenganImpactBurstLayer.path = UIBezierPath(ovalIn: rasenganImpactBurstLayer.bounds.insetBy(dx: 22, dy: 22)).cgPath
        rasenganImpactBurstLayer.fillColor = UIColor(white: 1.0, alpha: 0.82).cgColor
        rasenganImpactBurstLayer.strokeColor = UIColor(red: 0.92, green: 1.0, blue: 1.0, alpha: 0.98).cgColor
        rasenganImpactBurstLayer.lineWidth = 7.2
        rasenganImpactBurstLayer.shadowColor = UIColor(red: 0.66, green: 0.94, blue: 1.0, alpha: 1.0).cgColor
        rasenganImpactBurstLayer.shadowOpacity = 0.98
        rasenganImpactBurstLayer.shadowRadius = 34
        rasenganImpactBurstLayer.shadowOffset = .zero
        rasenganImpactBurstLayer.opacity = 0
        rasenganImpactBurstLayer.zPosition = 68
        layer.addSublayer(rasenganImpactBurstLayer)

        rasenganContainerLayer.bounds = CGRect(x: 0, y: 0, width: baseSize, height: baseSize)
        rasenganContainerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        rasenganContainerLayer.opacity = 0
        rasenganContainerLayer.zPosition = 64
        layer.addSublayer(rasenganContainerLayer)

        rasenganGlowLayer.bounds = CGRect(x: 0, y: 0, width: baseSize * 0.94, height: baseSize * 0.94)
        rasenganGlowLayer.position = center
        rasenganGlowLayer.backgroundColor = UIColor(red: 0.30, green: 0.72, blue: 1.0, alpha: 0.25).cgColor
        rasenganGlowLayer.cornerRadius = (baseSize * 0.94) / 2
        rasenganGlowLayer.shadowColor = UIColor(red: 0.30, green: 0.72, blue: 1.0, alpha: 1.0).cgColor
        rasenganGlowLayer.shadowOpacity = 0.94
        rasenganGlowLayer.shadowRadius = 42
        rasenganGlowLayer.shadowOffset = .zero
        rasenganGlowLayer.opacity = 0
        rasenganContainerLayer.addSublayer(rasenganGlowLayer)

        rasenganWhiteAuraLayer.bounds = CGRect(x: 0, y: 0, width: baseSize * 0.76, height: baseSize * 0.76)
        rasenganWhiteAuraLayer.position = center
        rasenganWhiteAuraLayer.backgroundColor = UIColor(red: 0.84, green: 0.96, blue: 1.0, alpha: 0.34).cgColor
        rasenganWhiteAuraLayer.cornerRadius = (baseSize * 0.76) / 2
        rasenganWhiteAuraLayer.shadowColor = UIColor(red: 0.54, green: 0.88, blue: 1.0, alpha: 1.0).cgColor
        rasenganWhiteAuraLayer.shadowOpacity = 0.96
        rasenganWhiteAuraLayer.shadowRadius = 30
        rasenganWhiteAuraLayer.shadowOffset = .zero
        rasenganWhiteAuraLayer.opacity = 0
        rasenganContainerLayer.addSublayer(rasenganWhiteAuraLayer)

        rasenganSwirlLayer.bounds = rasenganContainerLayer.bounds
        rasenganSwirlLayer.position = center
        rasenganSwirlLayer.opacity = 1
        rasenganSwirlLayer.zPosition = 66
        rasenganContainerLayer.addSublayer(rasenganSwirlLayer)

        rasenganCoreLayer.bounds = CGRect(x: 0, y: 0, width: 150, height: 150)
        rasenganCoreLayer.position = center
        rasenganCoreLayer.cornerRadius = 75
        rasenganCoreLayer.masksToBounds = true
        rasenganCoreLayer.backgroundColor = UIColor(red: 0.80, green: 0.97, blue: 1.0, alpha: 0.94).cgColor
        rasenganCoreLayer.borderWidth = 1.2
        rasenganCoreLayer.borderColor = UIColor(red: 0.56, green: 0.89, blue: 1.0, alpha: 0.90).cgColor
        rasenganCoreLayer.opacity = 0.95
        rasenganCoreLayer.compositingFilter = "screenBlendMode"
        rasenganCoreLayer.shadowColor = UIColor(red: 0.74, green: 0.94, blue: 1.0, alpha: 1.0).cgColor
        rasenganCoreLayer.shadowOpacity = 1
        rasenganCoreLayer.shadowRadius = 16
        rasenganCoreLayer.shadowOffset = .zero
        rasenganContainerLayer.addSublayer(rasenganCoreLayer)

        rasenganRingLayer.bounds = rasenganContainerLayer.bounds
        rasenganRingLayer.position = center
        rasenganRingLayer.path = UIBezierPath(ovalIn: rasenganContainerLayer.bounds.insetBy(dx: 14, dy: 14)).cgPath
        rasenganRingLayer.fillColor = UIColor.clear.cgColor
        rasenganRingLayer.strokeColor = UIColor(red: 0.68, green: 0.94, blue: 1.0, alpha: 0.95).cgColor
        rasenganRingLayer.lineWidth = 2.0
        rasenganRingLayer.opacity = 0
        rasenganRingLayer.zPosition = 67
        rasenganContainerLayer.addSublayer(rasenganRingLayer)

        rasenganOuterRingLayer.bounds = rasenganContainerLayer.bounds
        rasenganOuterRingLayer.position = center
        rasenganOuterRingLayer.path = UIBezierPath(ovalIn: rasenganContainerLayer.bounds.insetBy(dx: 5, dy: 5)).cgPath
        rasenganOuterRingLayer.fillColor = UIColor.clear.cgColor
        rasenganOuterRingLayer.strokeColor = UIColor(red: 0.66, green: 0.92, blue: 1.0, alpha: 0.98).cgColor
        rasenganOuterRingLayer.lineWidth = 2.4
        rasenganOuterRingLayer.lineDashPattern = [10, 7]
        rasenganOuterRingLayer.opacity = 0
        rasenganOuterRingLayer.zPosition = 68
        rasenganContainerLayer.addSublayer(rasenganOuterRingLayer)

        initializeRasenganParticles()
    }

    private func initializeRasenganParticles() {
        rasenganSwirlLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        rasenganParticles.removeAll(keepingCapacity: true)

        let particleCount = 46
        for index in 0..<particleCount {
            let layer = CALayer()
            let baseSize = CGFloat.random(in: 16...28)
            layer.bounds = CGRect(x: 0, y: 0, width: baseSize, height: baseSize)
            layer.position = CGPoint(x: rasenganSwirlLayer.bounds.midX, y: rasenganSwirlLayer.bounds.midY)
            layer.contents = rasenganParticleImage
            layer.contentsGravity = .resizeAspectFill
            layer.opacity = 0
            layer.compositingFilter = "screenBlendMode"
            rasenganSwirlLayer.addSublayer(layer)

            let angle = (CGFloat(index) / CGFloat(particleCount)) * (.pi * 2.0)
            let particle = RasenganParticle(
                layer: layer,
                angle: angle,
                rotationMultiplier: CGFloat.random(in: 1.8...3.6),
                baseRadius: CGFloat.random(in: 34...92),
                radiusAmplitude: CGFloat.random(in: 6...17),
                radiusFrequency: CGFloat.random(in: 4.5...9.5),
                phase: CGFloat.random(in: 0...(.pi * 2.0)),
                distortionSeed: CGFloat.random(in: 0...(.pi * 2.0)),
                alpha: CGFloat.random(in: 0.22...0.72)
            )
            rasenganParticles.append(particle)
        }
    }

    private func setupRasenganDebugLayer(_ layerRef: CATextLayer) {
        layerRef.contentsScale = UIScreen.main.scale
        layerRef.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        layerRef.fontSize = 11
        layerRef.foregroundColor = UIColor.white.withAlphaComponent(0.90).cgColor
        layerRef.backgroundColor = UIColor.black.withAlphaComponent(0.42).cgColor
        layerRef.cornerRadius = 8
        layerRef.alignmentMode = .left
        layerRef.isWrapped = true
        layerRef.opacity = 0
        layerRef.zPosition = 67
        layer.addSublayer(layerRef)
    }

    private func makeRasenganParticleImage() -> UIImage {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor.white.withAlphaComponent(0.92).cgColor,
                UIColor(red: 0.72, green: 0.96, blue: 1.0, alpha: 0.82).cgColor,
                UIColor(red: 0.40, green: 0.76, blue: 1.0, alpha: 0.55).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.33, 0.67, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
                return
            }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width / 2,
                options: []
            )
        }
    }

    private func makeParticleImage() -> UIImage {
        let size = CGSize(width: 46, height: 46)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.systemYellow.withAlphaComponent(0.85).cgColor,
                UIColor.systemOrange.withAlphaComponent(0.65).cgColor,
                UIColor.systemOrange.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.3, 0.62, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
                return
            }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width / 2,
                options: []
            )
        }
    }

    private func makeLightningParticleImage() -> UIImage {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor(red: 0.74, green: 0.92, blue: 1.0, alpha: 0.86).cgColor,
                UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 0.58).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.34, 0.66, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
                return
            }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width / 2,
                options: []
            )
        }
    }

    private func makeAshParticleImage() -> UIImage {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor(white: 0.95, alpha: 0.85).cgColor,
                UIColor(white: 0.72, alpha: 0.55).cgColor,
                UIColor(white: 0.50, alpha: 0.24).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.35, 0.7, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
                return
            }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY),
                endRadius: rect.width / 2,
                options: []
            )
        }
    }

    func updateHands(_ hands: [[CGPoint]]) {
        let path = UIBezierPath()

        for hand in hands {
            for (a, b) in handConnections {
                guard a < hand.count, b < hand.count else { continue }
                let p1 = hand[a]
                let p2 = hand[b]
                guard p1.x >= 0, p1.y >= 0, p2.x >= 0, p2.y >= 0 else { continue }

                let start = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: p1)
                let end = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: p2)
                path.move(to: start)
                path.addLine(to: end)
            }

            for p in hand {
                guard p.x >= 0, p.y >= 0 else { continue }
                let c = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: p)
                path.append(UIBezierPath(ovalIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)))
            }
        }

        overlayLayer.path = path.cgPath
    }

    func updatePreviewConnection(orientation: AVCaptureVideoOrientation, mirrored: Bool) {
        guard let connection = videoPreviewLayer.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = mirrored
        }
    }

    func updateFaceDebug(points: [CGPoint]) {
        guard showFaceDebugOverlay else {
            faceDebugLayer.path = nil
            return
        }

        let path = UIBezierPath()

        for point in points where point.x >= 0 && point.y >= 0 {
            let converted = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: point)
            path.append(UIBezierPath(ovalIn: CGRect(x: converted.x - 4, y: converted.y - 4, width: 8, height: 8)))
        }

        faceDebugLayer.path = path.cgPath
    }

    func updateJutsuEffect(
        hands: [CGPoint],
        scales: [CGFloat],
        mouthPoint: CGPoint?,
        fireballDirectionVector: CGVector?,
        fireballDirectionVector3D: FaceVector3D?,
        fireballMouthOpen: Bool,
        fireballMouthOpenNormalized: CGFloat,
        fireballDepthScale: CGFloat,
        active: Bool,
        jutsu: JutsuType?,
        selectedSummon: SummonAnimal
    ) {
        guard active, let jutsu else {
            rasenganThrowLockedForCurrentWindCast = false
            rasenganWindStyleMode = false
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            setFireVisible(false)
            setLightningVisible(false)
            setFireballVisible(false)
            setBurningAshVisible(false)
            updateRasenganWhenInactive()
            wasLightningActive = false
            wasFireballActive = false
            wasBurningAshActive = false
            setFireballDebugVisible(false)
            return
        }

        if jutsu != .wind {
            rasenganThrowLockedForCurrentWindCast = false
        }

        switch jutsu {
        case .burningAsh:
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            setRasenganVisible(false, hardReset: true)
            wasLightningActive = false
            wasFireballActive = false
            setFireVisible(false)
            setLightningVisible(false)
            setFireballVisible(false)
            updateBurningAsh(
                from: mouthPoint,
                fallbackHands: hands,
                directionVector: fireballDirectionVector
            )
        case .fireball:
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            setRasenganVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            wasLightningActive = false
            setFireVisible(false)
            setLightningVisible(false)
            updateFireball(
                from: mouthPoint,
                fallbackHands: hands,
                directionVector: fireballDirectionVector,
                directionVector3D: fireballDirectionVector3D,
                mouthOpen: fireballMouthOpen,
                mouthOpenNormalized: fireballMouthOpenNormalized,
                depthScaleHint: fireballDepthScale
            )
        case .lightning:
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            setRasenganVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            if !wasLightningActive {
                triggerLightningFlash()
            }
            wasLightningActive = true
            setFireballVisible(false)
            setFireballDebugVisible(false)
            setFireVisible(false)
            updateLightning(hands: hands, scales: scales)
        case .rasengan:
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            wasLightningActive = false
            wasFireballActive = false
            setFireVisible(false)
            setLightningVisible(false)
            setFireballVisible(false)
            setFireballDebugVisible(false)
            updateRasengan(hands: hands, scales: scales, windStyle: false)
        case .wind:
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            wasLightningActive = false
            wasFireballActive = false
            setFireVisible(false)
            setLightningVisible(false)
            setFireballVisible(false)
            setFireballDebugVisible(false)
            updateRasengan(hands: hands, scales: scales, windStyle: true)
        case .waterDragon:
            setKuchiyoseVisible(false, hardReset: true)
            setRasenganVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            wasLightningActive = false
            wasFireballActive = false
            setFireVisible(false)
            setLightningVisible(false)
            setFireballVisible(false)
            setFireballDebugVisible(false)
            updateWaterDragon(hands: hands)
        case .kuchiyose:
            setWaterDragonVisible(false, hardReset: true)
            setRasenganVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            wasLightningActive = false
            wasFireballActive = false
            setFireVisible(false)
            setLightningVisible(false)
            setFireballVisible(false)
            setFireballDebugVisible(false)
            updateKuchiyose(selectedSummon: selectedSummon)
        case .fire:
            setWaterDragonVisible(false, hardReset: true)
            setKuchiyoseVisible(false, hardReset: true)
            setRasenganVisible(false, hardReset: true)
            wasBurningAshActive = false
            setBurningAshVisible(false)
            wasLightningActive = false
            wasFireballActive = false
            setLightningVisible(false)
            setFireballVisible(false)
            setFireballDebugVisible(false)
            updateFire(hands: hands, scales: scales)
        }
    }

    private func updateWaterDragon(hands: [CGPoint]) {
        setWaterDragonVisible(true, hardReset: false)

        guard !wasWaterDragonActive else { return }
        wasWaterDragonActive = true

        let attackRight: Bool
        if hands.count >= 2 {
            attackRight = hands[0].x < hands[1].x
        } else {
            attackRight = Bool.random()
        }

        let direction: WaterDragonScene.AttackDirection = attackRight ? .right : .left
        waterDragonScene.trigger(direction: direction)
    }

    private func updateKuchiyose(selectedSummon: SummonAnimal) {
        setKuchiyoseVisible(true, hardReset: false)

        guard !wasKuchiyoseActive else { return }
        wasKuchiyoseActive = true
        kuchiyoseScene.triggerSummon(animal: selectedSummon)
    }

    private func updateRasengan(hands: [CGPoint], scales: [CGFloat], windStyle: Bool) {
        rasenganWindStyleMode = windStyle

        let now = CACurrentMediaTime()
        let rawDelta = rasenganLastFrameAt > 0 ? now - rasenganLastFrameAt : (1.0 / 60.0)
        rasenganLastFrameAt = now
        let dt = CGFloat(max(1.0 / 180.0, min(1.0 / 20.0, rawDelta)))

        if rasenganPhase == .thrown || rasenganPhase == .impact {
            guard windStyle else {
                setRasenganVisible(false, hardReset: true)
                return
            }
            updateRasenganProjectile(now: now, deltaTime: dt, handPosition: nil, throwTriggered: false)
            return
        }

        if windStyle && rasenganThrowLockedForCurrentWindCast {
            setRasenganVisible(false, hardReset: false)
            return
        }

        guard let source = hands.first else {
            updateRasenganWhenInactive()
            return
        }

        let palm = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: source)

        let previousHand = rasenganPreviousHandPoint ?? palm
        let handVelocity = CGVector(
            dx: palm.x - previousHand.x,
            dy: palm.y - previousHand.y
        )
        rasenganPreviousHandPoint = palm
        rasenganVelocityVector = handVelocity

        let handSpeed = sqrt((handVelocity.dx * handVelocity.dx) + (handVelocity.dy * handVelocity.dy)) / max(0.0001, dt)
        rasenganSmoothedSpeed = (rasenganSmoothedSpeed * 0.72) + (handSpeed * 0.28)

        let handScale = max(0.95, (scales.first ?? 1.0) * 1.08)

        let trackedPalm = trackRasenganPosition(handPosition: palm, velocity: handVelocity)
        rasenganReleasePosition = trackedPalm
        rasenganReleaseVelocity = CGVector(dx: handVelocity.dx * 56.0, dy: handVelocity.dy * 56.0)

        if !wasRasenganActive {
            wasRasenganActive = true
            rasenganLockedScale = max(1.40, min(2.05, handScale * 1.56))
            transitionRasengan(to: .charging, at: now)
        } else if rasenganPhase == .idle {
            rasenganLockedScale = max(1.40, min(2.05, handScale * 1.56))
            transitionRasengan(to: .charging, at: now)
        }

        let hoverPalm = rasenganHoverPoint(from: trackedPalm, handScale: handScale)
        let elapsed = CGFloat(max(0, now - rasenganPhaseStartedAt))
        let speedNormalizationBase: CGFloat = windStyle ? 900.0 : 950.0
        let speedNormalized = min(windStyle ? 1.9 : 1.6, rasenganSmoothedSpeed / speedNormalizationBase)
        let glowBoost = (windStyle ? 0.58 : 0.45) + (speedNormalized * (windStyle ? 0.56 : 0.5))
        let rotationSpeed = (16.0 + (speedNormalized * (windStyle ? 62.0 : 48.0))) * (windStyle ? 1.12 : 1.0)

        switch rasenganPhase {
        case .idle:
            transitionRasengan(to: .charging, at: now)

        case .charging:
            let progress = min(1, elapsed / 0.55)
            let eased = easeOut(progress)
            let baseScale = 0.14 + (0.86 * eased)
            let scale = max(0.08, baseScale * rasenganLockedScale)
            updateRasenganVisual(
                at: hoverPalm,
                scale: scale,
                opacity: 0.18 + (0.82 * eased),
                swirlIntensity: min(1, eased * glowBoost),
                rotationSpeed: rotationSpeed,
                speedNormalized: speedNormalized,
                deltaTime: dt,
                time: CGFloat(now),
                thrown: false,
                windStyle: windStyle
            )
            if progress >= 1 {
                transitionRasengan(to: .active, at: now)
            }

        case .active:
            let scale = rasenganLockedScale
            updateRasenganVisual(
                at: hoverPalm,
                scale: scale,
                opacity: min(1, 0.86 + (0.18 * speedNormalized)),
                swirlIntensity: min(1, glowBoost),
                rotationSpeed: rotationSpeed,
                speedNormalized: speedNormalized,
                deltaTime: dt,
                time: CGFloat(now),
                thrown: false,
                windStyle: windStyle
            )

            if windStyle && shouldTriggerRasenganThrow(speed: rasenganSmoothedSpeed, handScale: handScale) {
                let throwVelocity = CGVector(
                    dx: handVelocity.dx * rasenganThrowVelocityMultiplier,
                    dy: handVelocity.dy * rasenganThrowVelocityMultiplier
                )
                triggerRasenganThrow(from: hoverPalm, velocity: throwVelocity, at: now)
                updateRasenganProjectile(now: now, deltaTime: dt, handPosition: palm, throwTriggered: true)
                return
            }

        case .thrown, .impact:
            updateRasenganProjectile(now: now, deltaTime: dt, handPosition: palm, throwTriggered: false)
            return
        }

        rasenganReleasePosition = hoverPalm
        updateRasenganDebugOverlay(
            phase: rasenganPhase,
            handPosition: palm,
            rasenganPosition: hoverPalm,
            velocity: handVelocity,
            speed: rasenganSmoothedSpeed,
            throwTriggered: false,
            windStyle: windStyle
        )
        setRasenganVisible(true, hardReset: false)
    }

    private func updateRasenganWhenInactive() {
        let now = CACurrentMediaTime()
        let rawDelta = rasenganLastFrameAt > 0 ? now - rasenganLastFrameAt : (1.0 / 60.0)
        rasenganLastFrameAt = now
        let dt = CGFloat(max(1.0 / 180.0, min(1.0 / 20.0, rawDelta)))

        if rasenganPhase == .thrown || rasenganPhase == .impact {
            if rasenganWindStyleMode {
                updateRasenganProjectile(now: now, deltaTime: dt, handPosition: nil, throwTriggered: false)
            } else {
                setRasenganVisible(false, hardReset: true)
            }
            return
        }

        if wasRasenganActive, rasenganPhase == .charging || rasenganPhase == .active {
            wasRasenganActive = false

            guard rasenganWindStyleMode else {
                setRasenganVisible(false, hardReset: true)
                return
            }

            let startPosition = rasenganReleasePosition ?? rasenganContainerLayer.position
            var fallbackVelocity = CGVector(
                dx: rasenganVelocityVector.dx * (rasenganThrowVelocityMultiplier * 0.9),
                dy: rasenganVelocityVector.dy * (rasenganThrowVelocityMultiplier * 0.9)
            )
            let fallbackSpeed = sqrt((fallbackVelocity.dx * fallbackVelocity.dx) + (fallbackVelocity.dy * fallbackVelocity.dy))
            if fallbackSpeed < 30 {
                fallbackVelocity = CGVector(dx: 0, dy: -rasenganThrowMinimumVelocity)
            }
            triggerRasenganThrow(from: startPosition, velocity: fallbackVelocity, at: now)
            updateRasenganProjectile(now: now, deltaTime: dt, handPosition: nil, throwTriggered: false)
            return
        }

        setRasenganVisible(false, hardReset: true)
    }

    private func transitionRasengan(to phase: RasenganPhase, at now: CFTimeInterval) {
        rasenganPhase = phase
        rasenganPhaseStartedAt = now
    }

    private func shouldTriggerRasenganThrow(speed: CGFloat, handScale: CGFloat) -> Bool {
        guard speed > rasenganThrowThreshold else {
            return false
        }
        if !rasenganUseFistHeuristic {
            return true
        }
        return isLikelyHandClosed(handScale: handScale)
    }

    private func isLikelyHandClosed(handScale: CGFloat) -> Bool {
        handScale < 1.06
    }

    private func triggerRasenganThrow(from position: CGPoint, velocity: CGVector, at now: CFTimeInterval) {
        var throwVelocity = velocity
        let speed = sqrt((throwVelocity.dx * throwVelocity.dx) + (throwVelocity.dy * throwVelocity.dy))
        if speed < rasenganThrowMinimumVelocity {
            let direction: CGVector
            if speed > 0.001 {
                direction = CGVector(dx: throwVelocity.dx / speed, dy: throwVelocity.dy / speed)
            } else {
                direction = CGVector(dx: 0, dy: -1)
            }
            throwVelocity = CGVector(
                dx: direction.dx * rasenganThrowMinimumVelocity,
                dy: direction.dy * rasenganThrowMinimumVelocity
            )
        }

        rasenganReleasePosition = position
        rasenganReleaseVelocity = throwVelocity
        rasenganWindStyleMode = true
        rasenganThrowLockedForCurrentWindCast = true
        rasenganTrailPoints.removeAll(keepingCapacity: true)
        rasenganTrailPoints.append(position)
        transitionRasengan(to: .thrown, at: now)
    }

    private func updateRasenganProjectile(
        now: CFTimeInterval,
        deltaTime: CGFloat,
        handPosition: CGPoint?,
        throwTriggered: Bool
    ) {
        guard rasenganWindStyleMode else {
            setRasenganVisible(false, hardReset: true)
            return
        }

        switch rasenganPhase {
        case .thrown:
            guard let current = rasenganReleasePosition else {
                setRasenganVisible(false, hardReset: true)
                return
            }

            let elapsed = now - rasenganPhaseStartedAt
            let frameDecay = pow(0.98, max(1, deltaTime * 60))
            rasenganReleaseVelocity.dx *= frameDecay
            rasenganReleaseVelocity.dy *= frameDecay

            let next = CGPoint(
                x: current.x + (rasenganReleaseVelocity.dx * deltaTime),
                y: current.y + (rasenganReleaseVelocity.dy * deltaTime)
            )
            rasenganReleasePosition = next

            let throwSpeed = sqrt((rasenganReleaseVelocity.dx * rasenganReleaseVelocity.dx) + (rasenganReleaseVelocity.dy * rasenganReleaseVelocity.dy))
            let speedNormalized = min(2.5, throwSpeed / 980.0)

            updateRasenganVisual(
                at: next,
                scale: rasenganLockedScale * (1.06 + (0.16 * speedNormalized)),
                opacity: 1.0,
                swirlIntensity: 1.0,
                rotationSpeed: 44.0 + (speedNormalized * 84.0),
                speedNormalized: speedNormalized,
                deltaTime: deltaTime,
                time: CGFloat(now),
                thrown: true,
                windStyle: true
            )
            updateRasenganDebugOverlay(
                phase: .thrown,
                handPosition: handPosition,
                rasenganPosition: next,
                velocity: rasenganReleaseVelocity,
                speed: throwSpeed,
                throwTriggered: throwTriggered,
                windStyle: true
            )
            setRasenganVisible(true, hardReset: false)

            let margin: CGFloat = 6
            let outOfBounds = next.x < -margin || next.x > bounds.width + margin || next.y < -margin || next.y > bounds.height + margin
            if outOfBounds || elapsed >= rasenganThrowTimeout {
                rasenganImpactPoint = CGPoint(
                    x: min(max(next.x, 0), bounds.width),
                    y: min(max(next.y, 0), bounds.height)
                )
                transitionRasengan(to: .impact, at: now)
            }

        case .impact:
            let impact = rasenganImpactPoint ?? rasenganReleasePosition ?? rasenganContainerLayer.position
            let elapsed = CGFloat(max(0, now - rasenganPhaseStartedAt))
            let progress = min(1, elapsed / 0.34)
            let eased = easeOut(progress)

            updateRasenganVisual(
                at: impact,
                scale: rasenganLockedScale * (1.10 + (1.35 * eased)),
                opacity: 1.0 - progress,
                swirlIntensity: max(0, 1.0 - (progress * 1.35)),
                rotationSpeed: 62 + (78 * (1.0 - progress)),
                speedNormalized: 1.9,
                deltaTime: deltaTime,
                time: CGFloat(now),
                thrown: true,
                windStyle: true
            )

            rasenganImpactBurstLayer.position = impact
            rasenganImpactBurstLayer.opacity = Float(1.0 - progress)
            rasenganImpactBurstLayer.lineWidth = 9.0 - (4.8 * progress)
            rasenganImpactBurstLayer.fillColor = UIColor(white: 1.0, alpha: 0.95 * (1.0 - progress)).cgColor
            rasenganImpactBurstLayer.strokeColor = UIColor(white: 1.0, alpha: 0.98).cgColor
            let impactScale = 0.28 + (4.4 * eased)
            rasenganImpactBurstLayer.transform = CATransform3DMakeScale(impactScale, impactScale, 1)

            flashLayer.backgroundColor = UIColor(white: 1.0, alpha: 1.0).cgColor
            flashLayer.opacity = Float(max(0, 0.42 * (1.0 - progress)))

            updateRasenganDebugOverlay(
                phase: .impact,
                handPosition: handPosition,
                rasenganPosition: impact,
                velocity: rasenganReleaseVelocity,
                speed: sqrt((rasenganReleaseVelocity.dx * rasenganReleaseVelocity.dx) + (rasenganReleaseVelocity.dy * rasenganReleaseVelocity.dy)),
                throwTriggered: false,
                windStyle: true
            )
            setRasenganVisible(true, hardReset: false)

            if progress >= 1 {
                flashLayer.opacity = 0
                setRasenganVisible(false, hardReset: true)
            }

        case .idle, .charging, .active:
            break
        }
    }

    private func trackRasenganPosition(handPosition: CGPoint, velocity: CGVector) -> CGPoint {
        guard let previous = rasenganSmoothedPalm else {
            rasenganSmoothedPalm = handPosition
            return handPosition
        }

        // Predict toward the movement vector, then blend back toward the hand.
        let projected = CGPoint(
            x: previous.x + (velocity.dx * 1.2),
            y: previous.y + (velocity.dy * 1.2)
        )

        let smoothed = CGPoint(
            x: (projected.x * 0.7) + (handPosition.x * 0.3),
            y: (projected.y * 0.7) + (handPosition.y * 0.3)
        )
        rasenganSmoothedPalm = smoothed
        return smoothed
    }

    private func rasenganHoverPoint(from palm: CGPoint, handScale: CGFloat) -> CGPoint {
        let offset = 145 + (40 * max(0, handScale - 1.0))
        return CGPoint(x: palm.x, y: palm.y - offset)
    }

    private func updateRasenganVisual(
        at position: CGPoint,
        scale: CGFloat,
        opacity: CGFloat,
        swirlIntensity: CGFloat,
        rotationSpeed: CGFloat,
        speedNormalized: CGFloat,
        deltaTime: CGFloat,
        time: CGFloat,
        thrown: Bool,
        windStyle: Bool
    ) {
        let clampedScale = max(0.05, scale)
        let clampedOpacity = max(0, min(1, opacity))
        let clampedSwirl = max(0, min(1, swirlIntensity))
        let clampedSpeed = max(0, min(2, speedNormalized))
        let throwBoost: CGFloat = windStyle && thrown ? 0.24 : 0

        rasenganRotation += deltaTime * rotationSpeed
        if rasenganRotation >= .pi * 2 {
            rasenganRotation -= (.pi * 2)
        }

        rasenganContainerLayer.position = position
        rasenganContainerLayer.opacity = Float(clampedOpacity)
        rasenganContainerLayer.transform = CATransform3DMakeScale(clampedScale, clampedScale, 1)

        let swirlRotationFactor: CGFloat
        let ringRotationFactor: CGFloat
        if windStyle {
            swirlRotationFactor = thrown ? 0.86 : 0.48
            ringRotationFactor = thrown ? 0.34 : 0.20
        } else {
            swirlRotationFactor = 0.34
            ringRotationFactor = 0.12
        }

        rasenganSwirlLayer.transform = CATransform3DMakeRotation(rasenganRotation * swirlRotationFactor, 0, 0, 1)
        rasenganRingLayer.transform = CATransform3DMakeRotation(-rasenganRotation * ringRotationFactor, 0, 0, 1)
        rasenganCoreLayer.transform = CATransform3DIdentity
        rasenganCoreLayer.opacity = Float(min(1, 0.68 + (0.24 * clampedSwirl) + (0.20 * clampedSpeed)))

        if windStyle {
            rasenganOuterRingLayer.transform = CATransform3DMakeRotation(rasenganRotation * (thrown ? 1.18 : 0.74), 0, 0, 1)
            rasenganOuterRingLayer.lineDashPhase -= rotationSpeed * (thrown ? 0.90 : 0.34) * deltaTime

            rasenganWhiteAuraLayer.opacity = Float(min(1, 0.28 + (0.46 * clampedSwirl) + (0.40 * clampedSpeed) + throwBoost))
            rasenganWhiteAuraLayer.shadowRadius = 22 + (24 * clampedSwirl) + (28 * clampedSpeed) + (thrown ? 16 : 0)

            rasenganOuterRingLayer.opacity = Float(min(1, 0.30 + (0.50 * clampedSwirl) + (0.38 * clampedSpeed) + throwBoost))
            rasenganOuterRingLayer.lineWidth = 2.2 + (2.0 * clampedSwirl) + (1.8 * clampedSpeed)
        } else {
            rasenganWhiteAuraLayer.opacity = 0
            rasenganOuterRingLayer.opacity = 0
            rasenganOuterRingLayer.transform = CATransform3DIdentity
            rasenganOuterRingLayer.lineDashPhase = 0
        }

        rasenganGlowLayer.opacity = Float(min(1, 0.20 + (0.45 * clampedSwirl) + (0.35 * clampedSpeed) + throwBoost))
        rasenganGlowLayer.shadowRadius = 24 + (26 * clampedSwirl) + (18 * clampedSpeed) + (thrown ? 14 : 0)

        rasenganRingLayer.opacity = Float(min(1, 0.08 + (0.36 * clampedSwirl) + (0.28 * clampedSpeed)))
        rasenganRingLayer.lineWidth = 1.4 + (2.2 * clampedSwirl) + (1.4 * clampedSpeed)

        updateRasenganTrail(for: position, speedNormalized: clampedSpeed, isThrown: thrown, windStyle: windStyle)

        updateRasenganParticles(
            center: CGPoint(x: rasenganContainerLayer.bounds.midX, y: rasenganContainerLayer.bounds.midY),
            swirlIntensity: clampedSwirl,
            speedNormalized: clampedSpeed,
            rotationSpeed: rotationSpeed * (thrown ? 1.32 : (windStyle ? 1.18 : 1.0)),
            deltaTime: deltaTime,
            time: time
        )
    }

    private func updateRasenganTrail(for position: CGPoint, speedNormalized: CGFloat, isThrown: Bool, windStyle: Bool) {
        guard windStyle else {
            if !rasenganTrailPoints.isEmpty {
                rasenganTrailPoints.removeAll(keepingCapacity: true)
            }
            rasenganWindTrailLayer.path = nil
            rasenganWindTrailLayer.opacity = 0
            return
        }

        rasenganTrailPoints.append(position)
        let maxPoints = isThrown ? 22 : 8
        if rasenganTrailPoints.count > maxPoints {
            rasenganTrailPoints.removeFirst(rasenganTrailPoints.count - maxPoints)
        }

        guard rasenganTrailPoints.count >= 2 else {
            rasenganWindTrailLayer.path = nil
            rasenganWindTrailLayer.opacity = 0
            return
        }

        let path = UIBezierPath()
        path.move(to: rasenganTrailPoints[0])
        for point in rasenganTrailPoints.dropFirst() {
            path.addLine(to: point)
        }
        rasenganWindTrailLayer.path = path.cgPath

        let baseOpacity = isThrown ? 0.56 : 0.20
        let opacityBoost = isThrown ? 0.34 : 0.16
        rasenganWindTrailLayer.opacity = Float(min(1, baseOpacity + (speedNormalized * opacityBoost)))
        rasenganWindTrailLayer.lineWidth = isThrown
            ? (4.3 + (speedNormalized * 2.9))
            : (2.2 + (speedNormalized * 1.1))
    }

    private func updateRasenganParticles(
        center: CGPoint,
        swirlIntensity: CGFloat,
        speedNormalized: CGFloat,
        rotationSpeed: CGFloat,
        deltaTime: CGFloat,
        time: CGFloat
    ) {
        if rasenganParticles.isEmpty {
            initializeRasenganParticles()
        }

        let distortionAmount = (0.8 + (speedNormalized * 4.2)) * max(0.2, swirlIntensity)

        for particle in rasenganParticles {
            particle.angle += rotationSpeed * particle.rotationMultiplier * deltaTime
            if particle.angle > .pi * 2 {
                particle.angle -= (.pi * 2)
            }

            let oscillation = sin((time * particle.radiusFrequency) + particle.phase) * particle.radiusAmplitude
            let speedRadiusBoost = speedNormalized * 6.0
            let radius = max(8, particle.baseRadius + oscillation + speedRadiusBoost)

            let distortionX = sin((time * 13.0) + particle.distortionSeed) * distortionAmount
            let distortionY = cos((time * 11.0) + (particle.distortionSeed * 1.27)) * distortionAmount

            let orbitX = cos(particle.angle) * radius
            let orbitY = sin(particle.angle) * (radius * 0.74)
            let position = CGPoint(
                x: center.x + orbitX + distortionX,
                y: center.y + orbitY + distortionY
            )

            particle.layer.position = position

            let pulse = 0.86 + (0.22 * sin((time * 8.8) + particle.phase))
            let scale = max(0.25, pulse + (0.28 * swirlIntensity) + (0.24 * speedNormalized))
            particle.layer.transform = CATransform3DMakeScale(scale, scale, 1)
            particle.layer.opacity = Float(min(1, max(0.10, particle.alpha + (0.30 * swirlIntensity) + (0.24 * speedNormalized))))
        }
    }

    private func updateRasenganDebugOverlay(
        phase: RasenganPhase,
        handPosition: CGPoint?,
        rasenganPosition: CGPoint?,
        velocity: CGVector,
        speed: CGFloat,
        throwTriggered: Bool,
        windStyle: Bool
    ) {
        guard showRasenganDebugOverlay else {
            rasenganDebugTextLayer.opacity = 0
            rasenganDebugTextLayer.string = nil
            return
        }

        let throwLabel = throwTriggered ? "TRIGGER" : "no"
        let gateLabel = rasenganUseFistHeuristic ? "fist" : "speed"
        let styleLabel = windStyle ? "wind" : "base"

        if let handPosition, let rasenganPosition {
            rasenganDebugTextLayer.string = String(
                format: "state=%@ style=%@ throw=%@ speed=%.1f thr=%.0f gate=%@ vel=(%.1f, %.1f)\nhand=(%.1f, %.1f) ras=(%.1f, %.1f)",
                phase.rawValue,
                styleLabel,
                throwLabel,
                speed,
                rasenganThrowThreshold,
                gateLabel,
                velocity.dx,
                velocity.dy,
                handPosition.x,
                handPosition.y,
                rasenganPosition.x,
                rasenganPosition.y
            )
        } else if let rasenganPosition {
            rasenganDebugTextLayer.string = String(
                format: "state=%@ style=%@ throw=%@ speed=%.1f thr=%.0f gate=%@ vel=(%.1f, %.1f)\nhand=(-,-) ras=(%.1f, %.1f)",
                phase.rawValue,
                styleLabel,
                throwLabel,
                speed,
                rasenganThrowThreshold,
                gateLabel,
                velocity.dx,
                velocity.dy,
                rasenganPosition.x,
                rasenganPosition.y
            )
        } else {
            rasenganDebugTextLayer.string = String(
                format: "state=%@ style=%@ throw=%@ speed=%.1f thr=%.0f gate=%@ vel=(%.1f, %.1f)\nhand=(-,-) ras=(-,-)",
                phase.rawValue,
                styleLabel,
                throwLabel,
                speed,
                rasenganThrowThreshold,
                gateLabel,
                velocity.dx,
                velocity.dy
            )
        }
        rasenganDebugTextLayer.opacity = 1
    }

    private func updateBurningAsh(
        from mouthPoint: CGPoint?,
        fallbackHands: [CGPoint],
        directionVector: CGVector?
    ) {
        let source = mouthPoint ?? fallbackHands.first
        guard let source else {
            setBurningAshVisible(false)
            return
        }

        let mouth = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: source)
        let now = CACurrentMediaTime()

        if !wasBurningAshActive {
            wasBurningAshActive = true
            burningAshParticles.removeAll(keepingCapacity: true)
            burningAshExplosionBurstDone = false
            burningAshScreenLayer.opacity = 0
            burningAshFlashLayer.opacity = 0
            burningAshSparkLayer.opacity = 0
            transitionBurningAsh(to: .ashFlow, at: now)
            burningAshLastFrameAt = now
        }

        let rawDelta = burningAshLastFrameAt > 0 ? now - burningAshLastFrameAt : (1.0 / 60.0)
        burningAshLastFrameAt = now
        let dt = CGFloat(max(1.0 / 180.0, min(1.0 / 20.0, rawDelta)))

        let ashFlowDuration: CGFloat = 2.35
        let ashToSparkDelay: CGFloat = 0.22
        let sparkDuration: CGFloat = 0.30
        let explosionDuration: CGFloat = 0.72
        let fadeOutDuration: CGFloat = 1.05

        let flowDirection = normalizedDirection(directionVector)
        burningAshDirectionVector = flowDirection

        let elapsed = CGFloat(max(0, now - burningAshPhaseStartedAt))
        switch burningAshPhase {
        case .idle:
            transitionBurningAsh(to: .ashFlow, at: now)

        case .ashFlow:
            let clampedBuildProgress = min(1, elapsed / ashFlowDuration)
            let eased = easeOut(clampedBuildProgress)

            // Start as a concentrated mouth sprout, matching fireball launch language.
            updateBurningAshSproutEmitter(at: mouth, direction: flowDirection, intensity: eased)

            let spawnRate = 8 + (24 * eased)
            let spawnCount = max(1, Int(spawnRate * dt * 60.0))

            spawnAshParticles(
                count: spawnCount,
                source: mouth,
                direction: flowDirection,
                spread: .pi / 5.6,
                speedRange: 30...84,
                jitterRadius: 10,
                scaleRange: 0.42...1.05,
                lifetimeRange: 1.2...2.8,
                opacityRange: 0.26...0.58,
                growthRange: 0.18...0.42,
                decayRange: 0.22...0.44,
                warm: false
            )

            burningAshScreenLayer.opacity = Float(min(0.70, 0.12 + (0.58 * eased)))
            burningAshFlashLayer.opacity = 0
            burningAshSparkLayer.opacity = 0

            if elapsed >= (ashFlowDuration + ashToSparkDelay) {
                transitionBurningAsh(to: .spark, at: now)
            }

        case .spark:
            burningAshLayer.birthRate = 0
            let sparkProgress = min(1, elapsed / sparkDuration)
            updateBurningAshSpark(at: mouth, progress: easeInOut(sparkProgress))

            spawnAshParticles(
                count: max(1, Int(4 * dt * 60.0)),
                source: mouth,
                direction: flowDirection,
                spread: .pi / 8,
                speedRange: 45...92,
                jitterRadius: 6,
                scaleRange: 0.34...0.78,
                lifetimeRange: 0.6...1.2,
                opacityRange: 0.38...0.72,
                growthRange: 0.35...0.65,
                decayRange: 0.40...0.80,
                warm: true
            )

            if sparkProgress >= 1.0 {
                triggerBurningAshExplosion(at: mouth, direction: flowDirection)
                transitionBurningAsh(to: .explosion, at: now)
            }

        case .explosion:
            burningAshLayer.birthRate = 0
            let progress = min(1, elapsed / explosionDuration)
            let linearFalloff = max(0, 1 - progress)
            let burstRate = 16 + Int(34 * linearFalloff)

            spawnAshParticles(
                count: max(2, Int(CGFloat(burstRate) * dt * 60.0)),
                source: mouth,
                direction: flowDirection,
                spread: .pi,
                speedRange: 180...430,
                jitterRadius: 16,
                scaleRange: 0.62...1.48,
                lifetimeRange: 0.52...1.35,
                opacityRange: 0.52...0.98,
                growthRange: 0.74...1.45,
                decayRange: 0.60...1.10,
                warm: true
            )

            burningAshScreenLayer.opacity = Float(max(0.20, 0.66 * (1.0 - (0.72 * progress))))
            burningAshFlashLayer.opacity = Float(max(0, 0.72 * linearFalloff))
            burningAshSparkLayer.opacity = Float(max(0, 1.0 - (1.9 * progress)))

            if progress >= 1.0 {
                transitionBurningAsh(to: .fadeOut, at: now)
            }

        case .fadeOut:
            burningAshLayer.birthRate = 0
            let progress = min(1, elapsed / fadeOutDuration)
            burningAshScreenLayer.opacity = Float(max(0, 0.30 * (1.0 - progress)))
            burningAshFlashLayer.opacity = 0
            burningAshSparkLayer.opacity = Float(max(0, 0.24 * (1.0 - progress)))

            if progress >= 1.0, burningAshParticles.isEmpty {
                transitionBurningAsh(to: .idle, at: now)
            }
        }

        let drag: CGFloat
        switch burningAshPhase {
        case .ashFlow: drag = 0.08
        case .spark: drag = 0.06
        case .explosion: drag = 0.012
        case .fadeOut: drag = 0.16
        case .idle: drag = 0.22
        }

        updateBurningAshParticles(deltaTime: dt, drag: drag)
        updateBurningAshDebugOverlay(phase: burningAshPhase, direction: flowDirection)
        setBurningAshVisible(true)
    }

    private func transitionBurningAsh(to phase: BurningAshPhase, at now: CFTimeInterval) {
        burningAshPhase = phase
        burningAshPhaseStartedAt = now
    }

    private func updateBurningAshSproutEmitter(at mouth: CGPoint, direction: CGVector, intensity: CGFloat) {
        let t = max(0, min(1, intensity))
        let emissionLongitude = atan2(direction.dy, direction.dx)

        burningAshLayer.emitterPosition = mouth
        burningAshLayer.emitterSize = CGSize(width: 6, height: 6)
        burningAshLayer.birthRate = 1
        burningAshLayer.setValue(2600 + (1200 * t), forKeyPath: "emitterCells.ash.birthRate")
        burningAshLayer.setValue(260 + (120 * t), forKeyPath: "emitterCells.ash.velocity")
        burningAshLayer.setValue(110 + (70 * t), forKeyPath: "emitterCells.ash.velocityRange")
        burningAshLayer.setValue(Double.pi / 7.4, forKeyPath: "emitterCells.ash.emissionRange")
        burningAshLayer.setValue(emissionLongitude, forKeyPath: "emitterCells.ash.emissionLongitude")
        burningAshLayer.setValue(0.14 + (0.04 * t), forKeyPath: "emitterCells.ash.scale")
        burningAshLayer.setValue(-0.28, forKeyPath: "emitterCells.ash.alphaSpeed")
        burningAshLayer.setValue(direction.dx * 30.0, forKeyPath: "emitterCells.ash.xAcceleration")
        burningAshLayer.setValue(direction.dy * 30.0, forKeyPath: "emitterCells.ash.yAcceleration")
    }

    private func normalizedDirection(_ vector: CGVector?) -> CGVector {
        let input = vector ?? CGVector(dx: 0, dy: -1)
        let length = sqrt((input.dx * input.dx) + (input.dy * input.dy))
        if length > 1e-6 {
            return CGVector(dx: input.dx / length, dy: input.dy / length)
        }
        return CGVector(dx: 0, dy: -1)
    }

    private func spawnAshParticles(
        count: Int,
        source: CGPoint,
        direction: CGVector,
        spread: CGFloat,
        speedRange: ClosedRange<CGFloat>,
        jitterRadius: CGFloat,
        scaleRange: ClosedRange<CGFloat>,
        lifetimeRange: ClosedRange<CGFloat>,
        opacityRange: ClosedRange<CGFloat>,
        growthRange: ClosedRange<CGFloat>,
        decayRange: ClosedRange<CGFloat>,
        warm: Bool
    ) {
        guard count > 0 else { return }

        let baseAngle = atan2(direction.dy, direction.dx)

        for _ in 0..<count {
            guard burningAshParticles.count < burningAshMaxParticles else { break }

            let angle = baseAngle + CGFloat.random(in: -spread...spread)
            let speed = CGFloat.random(in: speedRange)
            let jitter = CGPoint(
                x: CGFloat.random(in: -jitterRadius...jitterRadius),
                y: CGFloat.random(in: -jitterRadius...jitterRadius)
            )

            let velocity = CGVector(
                dx: (cos(angle) * speed) + CGFloat.random(in: -12...12),
                dy: (sin(angle) * speed) + CGFloat.random(in: -12...12)
            )

            let layer = CALayer()
            let size: CGFloat = warm ? 20 : 16
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layer.position = CGPoint(x: source.x + jitter.x, y: source.y + jitter.y)
            layer.contents = warm ? burningAshExplosionParticleImage : burningAshParticleImage
            layer.opacity = Float(CGFloat.random(in: opacityRange))
            layer.compositingFilter = "screenBlendMode"
            layer.shadowColor = (warm
                ? UIColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1.0)
                : UIColor(white: 0.4, alpha: 1.0)
            ).cgColor
            layer.shadowOffset = .zero
            layer.shadowOpacity = warm ? 0.78 : 0.34
            layer.shadowRadius = warm ? 10 : 6

            let opacity = CGFloat(layer.opacity)
            let particle = AshParticle(
                layer: layer,
                position: layer.position,
                velocity: velocity,
                lifetime: CGFloat.random(in: lifetimeRange),
                opacity: opacity,
                opacityDecay: CGFloat.random(in: decayRange),
                scale: CGFloat.random(in: scaleRange),
                scaleGrowth: CGFloat.random(in: growthRange)
            )
            particle.layer.transform = CATransform3DMakeScale(particle.scale, particle.scale, 1)

            burningAshParticleContainer.addSublayer(layer)
            burningAshParticles.append(particle)
        }
    }

    private func triggerBurningAshExplosion(at mouth: CGPoint, direction: CGVector) {
        guard !burningAshExplosionBurstDone else { return }
        burningAshExplosionBurstDone = true
        igniteAshParticlesToFire()

        for particle in burningAshParticles {
            var radial = CGVector(dx: particle.position.x - mouth.x, dy: particle.position.y - mouth.y)
            let radialLength = sqrt((radial.dx * radial.dx) + (radial.dy * radial.dy))
            if radialLength > 1e-6 {
                radial.dx /= radialLength
                radial.dy /= radialLength
            } else {
                radial = CGVector(dx: CGFloat.random(in: -1...1), dy: CGFloat.random(in: -1...1))
                let fallbackLength = sqrt((radial.dx * radial.dx) + (radial.dy * radial.dy))
                if fallbackLength > 1e-6 {
                    radial.dx /= fallbackLength
                    radial.dy /= fallbackLength
                }
            }

            var biased = CGVector(
                dx: (radial.dx * 0.56) + (direction.dx * 0.44),
                dy: (radial.dy * 0.56) + (direction.dy * 0.44)
            )
            let biasedLength = sqrt((biased.dx * biased.dx) + (biased.dy * biased.dy))
            if biasedLength > 1e-6 {
                biased.dx /= biasedLength
                biased.dy /= biasedLength
            }

            let currentSpeed = max(90, sqrt((particle.velocity.dx * particle.velocity.dx) + (particle.velocity.dy * particle.velocity.dy)))
            let boost = CGFloat.random(in: 4.2...6.4)
            particle.velocity = CGVector(
                dx: (biased.dx * currentSpeed * boost) + CGFloat.random(in: -55...55),
                dy: (biased.dy * currentSpeed * boost) + CGFloat.random(in: -55...55)
            )
            particle.opacityDecay += CGFloat.random(in: 0.45...0.85)
            particle.scaleGrowth += CGFloat.random(in: 0.60...1.20)
        }

        spawnAshParticles(
            count: 120,
            source: mouth,
            direction: direction,
            spread: .pi,
            speedRange: 240...520,
            jitterRadius: 20,
            scaleRange: 0.70...1.60,
            lifetimeRange: 0.55...1.40,
            opacityRange: 0.62...1.0,
            growthRange: 0.90...1.60,
            decayRange: 0.75...1.28,
            warm: true
        )

        let shockwaveRadius: CGFloat = 18
        let shockwaveRect = CGRect(
            x: mouth.x - shockwaveRadius,
            y: mouth.y - shockwaveRadius,
            width: shockwaveRadius * 2,
            height: shockwaveRadius * 2
        )
        burningAshSparkLayer.path = UIBezierPath(ovalIn: shockwaveRect).cgPath
        burningAshSparkLayer.lineWidth = 5.2
        burningAshSparkLayer.fillColor = UIColor(red: 1.0, green: 0.74, blue: 0.28, alpha: 0.28).cgColor
        burningAshSparkLayer.strokeColor = UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1.0).cgColor
        burningAshSparkLayer.opacity = 1.0

        let shockwaveScale = CABasicAnimation(keyPath: "transform.scale")
        shockwaveScale.fromValue = 0.58
        shockwaveScale.toValue = 2.8

        let shockwaveOpacity = CABasicAnimation(keyPath: "opacity")
        shockwaveOpacity.fromValue = 1.0
        shockwaveOpacity.toValue = 0.0

        let shockwaveLineWidth = CABasicAnimation(keyPath: "lineWidth")
        shockwaveLineWidth.fromValue = 5.2
        shockwaveLineWidth.toValue = 0.9

        let shockwaveGroup = CAAnimationGroup()
        shockwaveGroup.animations = [shockwaveScale, shockwaveOpacity, shockwaveLineWidth]
        shockwaveGroup.duration = 0.42
        shockwaveGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shockwaveGroup.fillMode = .forwards
        shockwaveGroup.isRemovedOnCompletion = true
        burningAshSparkLayer.add(shockwaveGroup, forKey: "burningAshShockwave")

        burningAshFlashLayer.opacity = 1.0
        let flashFade = CABasicAnimation(keyPath: "opacity")
        flashFade.fromValue = 1.0
        flashFade.toValue = 0.0
        flashFade.duration = 0.32
        flashFade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        burningAshFlashLayer.add(flashFade, forKey: "burningAshFlash")

        burningAshScreenLayer.opacity = max(burningAshScreenLayer.opacity, 0.74)
    }

    private func igniteAshParticlesToFire() {
        guard !burningAshParticles.isEmpty else { return }

        for particle in burningAshParticles {
            particle.layer.contents = burningAshExplosionParticleImage
            particle.layer.shadowColor = UIColor(red: 1.0, green: 0.58, blue: 0.22, alpha: 1.0).cgColor
            particle.layer.shadowOpacity = 0.88
            particle.layer.shadowRadius = 12

            particle.opacity = min(1.0, particle.opacity + 0.18)
            particle.opacityDecay += CGFloat.random(in: 0.16...0.32)
            particle.scale = max(0.62, particle.scale)
            particle.scaleGrowth += CGFloat.random(in: 0.24...0.52)
        }
    }

    private func updateBurningAshSpark(at point: CGPoint, progress: CGFloat) {
        let radius = 6 + (22 * progress)
        let sparkRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        burningAshSparkLayer.path = UIBezierPath(ovalIn: sparkRect).cgPath
        burningAshSparkLayer.lineWidth = 1.2 + (1.8 * progress)
        burningAshSparkLayer.opacity = Float(max(0.0, 1.0 - (0.18 * progress)))
        burningAshSparkLayer.fillColor = UIColor(
            red: 1.0,
            green: 0.76 + (0.18 * (1.0 - progress)),
            blue: 0.32,
            alpha: 1.0
        ).cgColor
    }

    private func updateBurningAshParticles(deltaTime: CGFloat, drag: CGFloat) {
        guard !burningAshParticles.isEmpty else { return }

        let damping = max(0.0, 1.0 - (drag * deltaTime))

        for idx in burningAshParticles.indices.reversed() {
            let particle = burningAshParticles[idx]

            particle.velocity.dx *= damping
            particle.velocity.dy *= damping
            particle.position.x += particle.velocity.dx * deltaTime
            particle.position.y += particle.velocity.dy * deltaTime
            particle.age += deltaTime
            particle.opacity = max(0.0, particle.opacity - (particle.opacityDecay * deltaTime))
            particle.scale += particle.scaleGrowth * deltaTime

            if particle.age >= particle.lifetime || particle.opacity <= 0.01 {
                particle.layer.removeFromSuperlayer()
                burningAshParticles.remove(at: idx)
                continue
            }

            particle.layer.position = particle.position
            particle.layer.opacity = Float(particle.opacity)
            particle.layer.transform = CATransform3DMakeScale(particle.scale, particle.scale, 1)
        }
    }

    private func clearBurningAshParticles() {
        for particle in burningAshParticles {
            particle.layer.removeFromSuperlayer()
        }
        burningAshParticles.removeAll(keepingCapacity: true)
    }

    private func updateBurningAshDebugOverlay(phase: BurningAshPhase, direction: CGVector) {
        guard showBurningAshDebugOverlay else {
            burningAshDebugTextLayer.opacity = 0
            burningAshDebugTextLayer.string = nil
            return
        }

        burningAshDebugTextLayer.string = String(
            format: "state=%@\nparticles=%d dir=(%.2f, %.2f)",
            phase.rawValue,
            burningAshParticles.count,
            direction.dx,
            direction.dy
        )
        burningAshDebugTextLayer.opacity = 1
    }

    private func easeOut(_ value: CGFloat) -> CGFloat {
        let t = max(0, min(1, value))
        return 1.0 - pow(1.0 - t, 3.0)
    }

    private func easeInOut(_ value: CGFloat) -> CGFloat {
        let t = max(0, min(1, value))
        if t < 0.5 {
            return 2.0 * t * t
        }
        return 1.0 - pow(-2.0 * t + 2.0, 2.0) * 0.5
    }

    private func updateFireball(
        from mouthPoint: CGPoint?,
        fallbackHands: [CGPoint],
        directionVector: CGVector?,
        directionVector3D: FaceVector3D?,
        mouthOpen: Bool,
        mouthOpenNormalized: CGFloat,
        depthScaleHint: CGFloat
    ) {
        let source = mouthPoint ?? fallbackHands.first
        guard let source else {
            setFireballVisible(false)
            setFireballDebugVisible(false)
            return
        }

        let mouth = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: source)
        let now = CACurrentMediaTime()

        let fallback3D = FaceVector3D(
            x: directionVector?.dx ?? 0,
            y: directionVector?.dy ?? -1,
            z: 0
        )
        let raw3D = directionVector3D ?? fallback3D
        let rawLength = sqrt((raw3D.x * raw3D.x) + (raw3D.y * raw3D.y) + (raw3D.z * raw3D.z))
        let vx: CGFloat
        let vy: CGFloat
        let vz: CGFloat
        if rawLength > 1e-6 {
            vx = raw3D.x / rawLength
            vy = raw3D.y / rawLength
            vz = raw3D.z / rawLength
        } else {
            vx = 0
            vy = -1
            vz = 0
        }

        let shouldSpawn = mouthOpen && vz < 0
        if !shouldSpawn {
            setFireballVisible(false)
            updateFireballDebugOverlay(
                mouth: mouth,
                vx: vx,
                vy: vy,
                vz: vz,
                mouthOpen: mouthOpen,
                mouthOpenNormalized: mouthOpenNormalized,
                depthScale: max(0.6, depthScaleHint)
            )
            return
        }

        // Increase left/right sensitivity so head turn produces a flatter, more horizontal fireball.
        var tunedVX = vx * fireballHorizontalBoost
        var tunedVY = vy * fireballVerticalWeight
        let tunedLength = sqrt((tunedVX * tunedVX) + (tunedVY * tunedVY))
        if tunedLength > 1e-6 {
            tunedVX /= tunedLength
            tunedVY /= tunedLength
        } else {
            tunedVX = 0
            tunedVY = -1
        }

        let emissionLongitude = atan2(tunedVY, tunedVX)

        if !wasFireballActive {
            wasFireballActive = true
            fireballChargeUntil = now + 0.12
        }

        if now < fireballChargeUntil {
            // Short pre-burst charge on the mouth.
            let t = CGFloat(max(0, min(1, (now - (fireballChargeUntil - 0.12)) / 0.12)))
            let r = 32 + (58 * t)
            fireballChargeLayer.path = UIBezierPath(ovalIn: CGRect(x: mouth.x - r, y: mouth.y - r, width: 2 * r, height: 2 * r)).cgPath
            fireballChargeLayer.opacity = Float(0.35 + 0.45 * t)
            fireballLayer.birthRate = 0
            return
        }

        fireballChargeLayer.opacity = 0

        fireballLayer.emitterPosition = mouth
        // Keep source narrow at mouth so cone expands outward.
        fireballLayer.emitterSize = CGSize(width: 6, height: 6)

        let towardScreen = max(0, -vz)
        let awayFromScreen = max(0, vz)
        let depthScale = max(0.6, depthScaleHint, (1.0 + (towardScreen * 0.5)) - (awayFromScreen * 0.35))
        let opacityBoost = towardScreen * 0.3

        fireballLayer.setValue(3000, forKeyPath: "emitterCells.fireball.birthRate")
        fireballLayer.setValue(500, forKeyPath: "emitterCells.fireball.velocity")
        fireballLayer.setValue(0.58 * depthScale, forKeyPath: "emitterCells.fireball.scale")
        fireballLayer.setValue(1.15 * depthScale, forKeyPath: "emitterCells.fireball.scaleSpeed")
        fireballLayer.setValue(Double.pi / 4.6, forKeyPath: "emitterCells.fireball.emissionRange")
        fireballLayer.setValue(emissionLongitude, forKeyPath: "emitterCells.fireball.emissionLongitude")
        fireballLayer.setValue(tunedVX * 22.0, forKeyPath: "emitterCells.fireball.xAcceleration")
        fireballLayer.setValue(tunedVY * 22.0, forKeyPath: "emitterCells.fireball.yAcceleration")
        fireballLayer.opacity = Float(min(1.0, 0.78 + opacityBoost))

        updateFireballDebugOverlay(
            mouth: mouth,
            vx: tunedVX,
            vy: tunedVY,
            vz: vz,
            mouthOpen: mouthOpen,
            mouthOpenNormalized: mouthOpenNormalized,
            depthScale: depthScale
        )

        setFireballVisible(true)
    }

    private func updateFireballDebugOverlay(
        mouth: CGPoint,
        vx: CGFloat,
        vy: CGFloat,
        vz: CGFloat,
        mouthOpen: Bool,
        mouthOpenNormalized: CGFloat,
        depthScale: CGFloat
    ) {
        guard showFireballDebugOverlay else {
            setFireballDebugVisible(false)
            return
        }

        let directionColor = mouthOpen && vz < 0 ? UIColor.systemGreen : UIColor.systemRed
        fireballDebugArrowLayer.strokeColor = directionColor.withAlphaComponent(0.95).cgColor

        let arrowLength: CGFloat = 96
        let tip = CGPoint(x: mouth.x + (vx * arrowLength), y: mouth.y + (vy * arrowLength))
        let path = UIBezierPath()
        path.move(to: mouth)
        path.addLine(to: tip)

        let arrowHeadLength: CGFloat = 12
        let angle = atan2(tip.y - mouth.y, tip.x - mouth.x)
        let leftWing = CGPoint(
            x: tip.x - (cos(angle - (.pi / 6.0)) * arrowHeadLength),
            y: tip.y - (sin(angle - (.pi / 6.0)) * arrowHeadLength)
        )
        let rightWing = CGPoint(
            x: tip.x - (cos(angle + (.pi / 6.0)) * arrowHeadLength),
            y: tip.y - (sin(angle + (.pi / 6.0)) * arrowHeadLength)
        )
        path.move(to: tip)
        path.addLine(to: leftWing)
        path.move(to: tip)
        path.addLine(to: rightWing)

        fireballDebugArrowLayer.path = path.cgPath
        fireballDebugTextLayer.string = String(
            format: "v=(%.2f, %.2f, %.2f)\nmouth_open=%@ (%.3f) depth_scale=%.2f",
            vx,
            vy,
            vz,
            mouthOpen ? "true" : "false",
            mouthOpenNormalized,
            depthScale
        )
        setFireballDebugVisible(true)
    }

    private func updateFire(hands: [CGPoint], scales: [CGFloat]) {
        setFireVisible(true)

        let pointA = hands.indices.contains(0) ? hands[0] : CGPoint(x: 0.5, y: 0.5)
        let pointB = hands.indices.contains(1) ? hands[1] : pointA

        let a = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: pointA)
        let b = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: pointB)

        auraLayerA.emitterPosition = a
        auraLayerB.emitterPosition = b
        fireLayerA.emitterPosition = a
        fireLayerB.emitterPosition = b

        let sA = max(1.0, (scales.indices.contains(0) ? scales[0] : 1.0) * baseEffectBoost)
        let sB = max(1.0, (scales.indices.contains(1) ? scales[1] : sA) * baseEffectBoost)

        tuneAuraLayer(auraLayerA, scale: sA)
        tuneAuraLayer(auraLayerB, scale: sB)
        tuneFireLayer(fireLayerA, scale: sA)
        tuneFireLayer(fireLayerB, scale: sB)

        auraLayerA.birthRate = 1
        auraLayerB.birthRate = 1
        fireLayerA.birthRate = 1
        fireLayerB.birthRate = 1
    }

    private func updateLightning(hands: [CGPoint], scales: [CGFloat]) {
        let pointA = hands.indices.contains(0) ? hands[0] : CGPoint(x: 0.5, y: 0.5)
        let pointB = hands.indices.contains(1) ? hands[1] : pointA

        let a = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: pointA)
        let b = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: pointB)

        let sA = max(1.0, (scales.indices.contains(0) ? scales[0] : 1.0) * baseEffectBoost)
        let sB = max(1.0, (scales.indices.contains(1) ? scales[1] : sA) * baseEffectBoost)

        // Render lightning on only one hand (dominant by scale).
        let useFirstHand = sA >= sB
        let center = useFirstHand ? a : b
        let scale = useFirstHand ? sA : sB

        // Strong, fast pulse for chidori-like intensity.
        let pulse = 1.0 + 0.45 * (0.5 + 0.5 * sin(CGFloat(CACurrentMediaTime() * 22.0)))
        let pulseScale = scale * pulse
        let coreScale = pulseScale * 1.55

        // Keep energy centered on palm with a larger core.
        lightningLayerA.emitterPosition = center
        lightningLayerA.emitterSize = CGSize(width: 38 * coreScale, height: 38 * coreScale)
        lightningLayerA.setValue(760 * coreScale, forKeyPath: "emitterCells.lightning.birthRate")
        lightningLayerA.setValue(280 * coreScale, forKeyPath: "emitterCells.lightning.velocity")
        lightningLayerA.setValue(0.17 * coreScale, forKeyPath: "emitterCells.lightning.scale")

        boltLayerA.path = makeLightningBoltPath(center: center, scale: coreScale).cgPath
        boltLayerA.lineWidth = 3.4 * pulse
        boltLayerA.opacity = Float.random(in: 0.82...1.0)

        // Screen-reaching electric streaks that shoot from the palm.
        streakLayerA.path = makeScreenStreakPath(from: center, spread: 0.18).cgPath
        streakLayerB.path = makeScreenStreakPath(from: center, spread: 0.32).cgPath
        streakLayerA.lineWidth = 2.0 * pulse
        streakLayerB.lineWidth = 1.6 * pulse
        streakLayerA.opacity = Float.random(in: 0.55...0.95)
        streakLayerB.opacity = Float.random(in: 0.45...0.85)

        // Keep the second lightning layer hidden so effect stays on one hand only.
        lightningLayerB.birthRate = 0
        boltLayerB.opacity = 0

        setLightningVisible(true)
    }

    private func triggerLightningFlash() {
        flashLayer.removeAllAnimations()
        flashLayer.opacity = 0.26

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.26
        fade.toValue = 0.0
        fade.duration = 0.18
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flashLayer.add(fade, forKey: "lightningFlash")
        flashLayer.opacity = 0.0
    }

    private func makeLightningBoltPath(center: CGPoint, scale: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let length = 48 * scale
        let steps = 6
        var current = CGPoint(x: center.x, y: center.y - length * 0.5)
        path.move(to: current)

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let y = center.y - length * 0.5 + (length * t)
            let jitter = CGFloat.random(in: -10...10) * scale
            let x = center.x + jitter
            current = CGPoint(x: x, y: y)
            path.addLine(to: current)
        }

        return path
    }

    private func makeScreenStreakPath(from center: CGPoint, spread: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: center)

        let targetX = center.x < bounds.midX ? bounds.maxX + 40 : -40
        let baseY = center.y + CGFloat.random(in: -bounds.height * spread...bounds.height * spread)
        let ctrl1 = CGPoint(
            x: center.x + (targetX - center.x) * 0.35,
            y: center.y + CGFloat.random(in: -80...80)
        )
        let ctrl2 = CGPoint(
            x: center.x + (targetX - center.x) * 0.70,
            y: baseY + CGFloat.random(in: -100...100)
        )
        let end = CGPoint(x: targetX, y: baseY)
        path.addCurve(to: end, controlPoint1: ctrl1, controlPoint2: ctrl2)
        return path
    }

    private func setFireVisible(_ visible: Bool) {
        auraLayerA.birthRate = visible ? 1 : 0
        auraLayerB.birthRate = visible ? 1 : 0
        fireLayerA.birthRate = visible ? 1 : 0
        fireLayerB.birthRate = visible ? 1 : 0
    }

    private func setWaterDragonVisible(_ visible: Bool, hardReset: Bool) {
        waterDragonView.isHidden = !visible
        if !visible {
            if hardReset {
                waterDragonScene.resetEffect()
            }
            wasWaterDragonActive = false
        }
    }

    private func setKuchiyoseVisible(_ visible: Bool, hardReset: Bool) {
        kuchiyoseView.isHidden = !visible
        if !visible {
            if hardReset {
                kuchiyoseScene.resetEffect()
            }
            wasKuchiyoseActive = false
        }
    }

    private func setLightningVisible(_ visible: Bool) {
        lightningLayerA.birthRate = visible ? 1 : 0
        lightningLayerB.birthRate = 0
        boltLayerA.opacity = visible ? boltLayerA.opacity : 0
        boltLayerB.opacity = 0
        streakLayerA.opacity = visible ? streakLayerA.opacity : 0
        streakLayerB.opacity = visible ? streakLayerB.opacity : 0
    }

    private func setFireballVisible(_ visible: Bool) {
        fireballLayer.birthRate = visible ? 1 : 0
        fireballChargeLayer.opacity = visible ? fireballChargeLayer.opacity : 0
        if !visible {
            fireballChargeUntil = 0
            wasFireballActive = false
            fireballLayer.opacity = 1.0
        }
    }

    private func setFireballDebugVisible(_ visible: Bool) {
        fireballDebugArrowLayer.opacity = visible ? 1.0 : 0.0
        fireballDebugTextLayer.opacity = visible ? 1.0 : 0.0
        if !visible {
            fireballDebugArrowLayer.path = nil
            fireballDebugTextLayer.string = nil
        }
    }

    private func setRasenganVisible(_ visible: Bool, hardReset: Bool) {
        rasenganContainerLayer.opacity = visible ? rasenganContainerLayer.opacity : 0
        rasenganWindTrailLayer.opacity = visible ? rasenganWindTrailLayer.opacity : 0
        rasenganImpactBurstLayer.opacity = visible ? rasenganImpactBurstLayer.opacity : 0

        if !visible {
            rasenganDebugTextLayer.opacity = 0
            rasenganDebugTextLayer.string = nil

            if hardReset {
                transitionRasengan(to: .idle, at: CACurrentMediaTime())
                rasenganLastFrameAt = 0
                rasenganSmoothedPalm = nil
                rasenganPreviousHandPoint = nil
                rasenganVelocityVector = .zero
                rasenganSmoothedSpeed = 0
                rasenganReleasePosition = nil
                rasenganReleaseVelocity = .zero
                rasenganTrailPoints.removeAll(keepingCapacity: true)
                rasenganImpactPoint = nil
                rasenganRotation = 0
                rasenganLockedScale = 1.58
                rasenganWindStyleMode = false
                wasRasenganActive = false
                rasenganContainerLayer.transform = CATransform3DIdentity
                rasenganGlowLayer.opacity = 0
                rasenganWhiteAuraLayer.opacity = 0
                rasenganRingLayer.opacity = 0
                rasenganOuterRingLayer.opacity = 0
                rasenganRingLayer.transform = CATransform3DIdentity
                rasenganOuterRingLayer.transform = CATransform3DIdentity
                rasenganOuterRingLayer.lineDashPhase = 0
                rasenganSwirlLayer.transform = CATransform3DIdentity
                rasenganCoreLayer.transform = CATransform3DIdentity
                rasenganWindTrailLayer.path = nil
                rasenganWindTrailLayer.opacity = 0
                rasenganImpactBurstLayer.transform = CATransform3DIdentity
                rasenganImpactBurstLayer.fillColor = UIColor(white: 1.0, alpha: 0.82).cgColor
                rasenganImpactBurstLayer.opacity = 0
                flashLayer.opacity = 0
                for particle in rasenganParticles {
                    particle.layer.opacity = 0
                }
            }
        }
    }

    private func setBurningAshVisible(_ visible: Bool) {
        burningAshParticleContainer.opacity = visible ? 1 : 0
        if !visible {
            burningAshLayer.birthRate = 0
            burningAshExplosionLayer.birthRate = 0
            burningAshScreenLayer.opacity = 0
            burningAshFlashLayer.opacity = 0
            burningAshSparkLayer.opacity = 0
            burningAshDebugTextLayer.opacity = 0
            burningAshDebugTextLayer.string = nil
            transitionBurningAsh(to: .idle, at: CACurrentMediaTime())
            burningAshLastFrameAt = 0
            burningAshDirectionVector = CGVector(dx: 0, dy: -1)
            burningAshExplosionBurstDone = false
            clearBurningAshParticles()
            wasBurningAshActive = false
        }
    }

    private func tuneAuraLayer(_ layer: CAEmitterLayer, scale: CGFloat) {
        layer.emitterSize = CGSize(width: 34 * scale, height: 34 * scale)
        layer.setValue(190 * scale, forKeyPath: "emitterCells.aura.birthRate")
        layer.setValue(42 * scale, forKeyPath: "emitterCells.aura.velocity")
        layer.setValue(0.40 * scale, forKeyPath: "emitterCells.aura.scale")
    }

    private func tuneFireLayer(_ layer: CAEmitterLayer, scale: CGFloat) {
        layer.emitterSize = CGSize(width: 26 * scale, height: 26 * scale)
        layer.setValue(520 * scale, forKeyPath: "emitterCells.fire.birthRate")
        layer.setValue(105 * scale, forKeyPath: "emitterCells.fire.velocity")
        layer.setValue(0.24 * scale, forKeyPath: "emitterCells.fire.scale")
    }
}
