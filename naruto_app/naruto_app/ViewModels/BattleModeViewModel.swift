import CoreGraphics
import Combine
import Foundation

@MainActor
final class BattleModeViewModel: ObservableObject {
    enum State: String {
        case idle
        case enemyAttack
        case playerDefend
        case playerAttack
        case roundEnd
        case gameOver
    }

    struct Projectile: Identifiable {
        let id = UUID()
        let jutsu: JutsuType
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var damage: Int
    }

    struct EnemyProjectile: Identifiable {
        let id = UUID()
        let jutsu: JutsuType
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var age: TimeInterval = 0
        var lifetime: TimeInterval
        var wobbleSeed: CGFloat
    }

    struct FloatingFeedback: Identifiable {
        let id = UUID()
        var text: String
        var colorHex: UInt32
        var position: CGPoint
        var age: TimeInterval = 0
        var lifetime: TimeInterval = 1.0
    }

    struct ImpactBurst: Identifiable {
        let id = UUID()
        var position: CGPoint
        var colorHex: UInt32
        var age: TimeInterval = 0
        var lifetime: TimeInterval = 0.45
        var maxRadius: CGFloat = 46
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var round: Int = 1
    @Published private(set) var playerHP: Int = 100
    @Published private(set) var sasukeHP: Int
    @Published private(set) var sasukeHPMax: Int
    @Published private(set) var chakra: Int = 100
    @Published private(set) var activeEnemyJutsu: JutsuType?
    @Published private(set) var phaseTimeRemaining: TimeInterval = 0
    @Published private(set) var phaseDuration: TimeInterval = 1
    @Published private(set) var feedbackText: String = ""
    @Published private(set) var projectiles: [Projectile] = []
    @Published private(set) var enemyProjectiles: [EnemyProjectile] = []
    @Published private(set) var floatingFeedbacks: [FloatingFeedback] = []
    @Published private(set) var impactBursts: [ImpactBurst] = []
    @Published private(set) var comboCount: Int = 0
    @Published private(set) var sasukeHitFlash = false
    @Published private(set) var playerHitPulse: Int = 0
    @Published private(set) var playerWon = false

    private(set) var battleEnded = false
    private var defendSucceeded = false
    private var arenaSize: CGSize = .zero
    private var lastAcceptedAttackAt: Date = .distantPast
    private var lastAcceptedAttackJutsu: JutsuType?
    private var lastComboAt: Date = .distantPast
    private var enemyProjectileSpawnAccumulator: TimeInterval = 0
    private let enemyAttackPool: [JutsuType] = [.lightning, .fireball, .burningAsh]
    private let comboChainWindow: TimeInterval = 4.0

    /// Right-edge strip the player occupies; enemy projectiles that cross it
    /// during the defend phase deal chip damage.
    private var playerZoneX: CGFloat {
        max(0, arenaSize.width * 0.90)
    }

    init(initialSasukeHP: Int) {
        let clamped = max(60, min(300, initialSasukeHP))
        sasukeHP = clamped
        sasukeHPMax = clamped
    }

    var sasukeHitbox: CGRect {
        guard arenaSize.width > 10, arenaSize.height > 10 else { return .zero }
        let width = max(100, arenaSize.width * 0.24)
        let height = max(170, arenaSize.height * 0.56)
        let x = arenaSize.width * 0.03
        let y = arenaSize.height * 0.30
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var defendTargetJutsu: JutsuType? {
        guard state == .playerDefend, let activeEnemyJutsu else { return nil }
        return counterJutsu(for: activeEnemyJutsu)
    }

    func startBattle() {
        battleEnded = false
        playerWon = false
        state = .idle
        round = 1
        playerHP = 100
        sasukeHP = sasukeHPMax
        chakra = 100
        comboCount = 0
        lastComboAt = .distantPast
        projectiles.removeAll(keepingCapacity: true)
        enemyProjectiles.removeAll(keepingCapacity: true)
        impactBursts.removeAll(keepingCapacity: true)
        enemyProjectileSpawnAccumulator = 0
        floatingFeedbacks.removeAll(keepingCapacity: true)
        feedbackText = "Prepare for battle"
        beginEnemyAttack()
    }

    func updateArenaSize(_ size: CGSize) {
        arenaSize = size
    }

    func tick(deltaTime: TimeInterval) {
        guard !battleEnded else { return }

        if phaseTimeRemaining > 0 {
            phaseTimeRemaining = max(0, phaseTimeRemaining - deltaTime)
        }

        updateProjectiles(deltaTime: deltaTime)
        updateEnemyProjectiles(deltaTime: deltaTime)
        updateFloatingFeedbacks(deltaTime: deltaTime)
        updateImpactBursts(deltaTime: deltaTime)

        if state == .playerDefend, let enemyJutsu = activeEnemyJutsu {
            enemyProjectileSpawnAccumulator += deltaTime
            let interval = enemySpawnInterval(for: enemyJutsu)
            while enemyProjectileSpawnAccumulator >= interval {
                enemyProjectileSpawnAccumulator -= interval
                let burstCount = enemyJutsu == .lightning ? 2 : 1
                spawnEnemyProjectileBurst(for: enemyJutsu, count: burstCount)
            }
        } else {
            enemyProjectileSpawnAccumulator = 0
        }

        switch state {
        case .enemyAttack where phaseTimeRemaining <= 0:
            startPlayerDefendPhase()
        case .playerDefend where phaseTimeRemaining <= 0:
            completeDefendPhase()
            startPlayerAttackPhase()
        case .playerAttack where phaseTimeRemaining <= 0:
            startRoundEnd()
        case .roundEnd where phaseTimeRemaining <= 0:
            beginEnemyAttack()
        default:
            break
        }
    }

    func registerPlayerJutsuTrigger(_ jutsu: JutsuType?) {
        guard let jutsu, !battleEnded else { return }

        switch state {
        case .playerDefend:
            handleDefendInput(jutsu)
        case .playerAttack:
            handleAttackInput(jutsu)
        default:
            break
        }
    }

    private func beginEnemyAttack() {
        guard !battleEnded else { return }
        state = .enemyAttack
        defendSucceeded = false
        activeEnemyJutsu = enemyAttackPool.randomElement() ?? .lightning
        phaseTimeRemaining = 1.5
        phaseDuration = 1.5
        feedbackText = "Sasuke uses \(activeEnemyJutsu?.title ?? "Attack")"

        addFloatingFeedback(
            text: activeEnemyJutsu?.title ?? "Attack",
            colorHex: 0xFF5A5A,
            position: CGPoint(x: sasukeHitbox.midX > 0 ? sasukeHitbox.midX : 120, y: sasukeHitbox.minY > 0 ? sasukeHitbox.minY + 24 : 220),
            lifetime: 1.2
        )

        if let activeEnemyJutsu {
            spawnEnemyProjectileBurst(for: activeEnemyJutsu, count: activeEnemyJutsu == .burningAsh ? 3 : 2)
        }
    }

    private func startPlayerDefendPhase() {
        state = .playerDefend
        phaseTimeRemaining = max(6.0, 10.0 - Double(round - 1) * 0.5)
        phaseDuration = phaseTimeRemaining
        enemyProjectileSpawnAccumulator = 0
        if let activeEnemyJutsu {
            let counter = counterJutsu(for: activeEnemyJutsu)
            feedbackText = "Defend now. Counter with \(counter.title)"
        } else {
            feedbackText = "Defend now. Follow the counter signs"
        }
    }

    private func completeDefendPhase() {
        guard state == .playerDefend else { return }

        if defendSucceeded {
            feedbackText = "Defense successful"
            return
        }

        applyPlayerDamage(min(30, 18 + (round - 1) * 2), reason: "Failed defense")
    }

    private func startPlayerAttackPhase() {
        guard !battleEnded else { return }
        state = .playerAttack
        phaseTimeRemaining = 10.0
        phaseDuration = phaseTimeRemaining
        comboCount = 0
        lastComboAt = .distantPast
        enemyProjectiles.removeAll(keepingCapacity: true)
        enemyProjectileSpawnAccumulator = 0
        feedbackText = "Counter-attack now"
    }

    private func startRoundEnd() {
        guard !battleEnded else { return }
        state = .roundEnd
        phaseTimeRemaining = 1.6
        phaseDuration = 1.6
        round += 1
        chakra = min(100, chakra + 15)
        enemyProjectiles.removeAll(keepingCapacity: true)
        enemyProjectileSpawnAccumulator = 0
        feedbackText = "Round \(round - 1) complete. Chakra +15"
        addFloatingFeedback(
            text: "+15 chakra",
            colorHex: 0x66D6FF,
            position: CGPoint(x: max(40, arenaSize.width * 0.64), y: 78),
            lifetime: 1.0
        )
    }

    private func enemySourcePoint() -> CGPoint {
        guard !sasukeHitbox.isEmpty else {
            return CGPoint(x: max(80, arenaSize.width * 0.18), y: max(140, arenaSize.height * 0.38))
        }
        return CGPoint(
            x: sasukeHitbox.maxX + 10,
            y: sasukeHitbox.minY + (sasukeHitbox.height * 0.22)
        )
    }

    private func enemySpawnInterval(for jutsu: JutsuType) -> TimeInterval {
        let base: TimeInterval
        switch jutsu {
        case .lightning:
            base = 0.42
        case .burningAsh:
            base = 0.60
        case .fireball:
            base = 0.68
        default:
            base = 0.62
        }
        // Each round tightens the barrage by 8%, floored so it stays fair.
        return max(0.26, base * pow(0.92, Double(round - 1)))
    }

    private func spawnEnemyProjectileBurst(for jutsu: JutsuType, count: Int = 1) {
        let source = enemySourcePoint()
        let spawnCount: Int
        switch jutsu {
        case .burningAsh:
            spawnCount = max(3, count * 2)
        case .lightning:
            spawnCount = max(2, count)
        default:
            spawnCount = max(1, count)
        }

        for _ in 0..<spawnCount {
            let projectile: EnemyProjectile
            switch jutsu {
            case .lightning:
                projectile = EnemyProjectile(
                    jutsu: jutsu,
                    position: source,
                    velocity: CGVector(
                        dx: CGFloat.random(in: 580...720),
                        dy: CGFloat.random(in: -40...40)
                    ),
                    radius: CGFloat.random(in: 8...11),
                    age: 0,
                    lifetime: 0.82,
                    wobbleSeed: CGFloat.random(in: 0...(.pi * 2))
                )
            case .burningAsh:
                projectile = EnemyProjectile(
                    jutsu: jutsu,
                    position: source,
                    velocity: CGVector(
                        dx: CGFloat.random(in: 280...360),
                        dy: CGFloat.random(in: -70...70)
                    ),
                    radius: CGFloat.random(in: 9...14),
                    age: 0,
                    lifetime: 1.65,
                    wobbleSeed: CGFloat.random(in: 0...(.pi * 2))
                )
            case .fireball:
                projectile = EnemyProjectile(
                    jutsu: jutsu,
                    position: source,
                    velocity: CGVector(
                        dx: CGFloat.random(in: 360...460),
                        dy: CGFloat.random(in: -48...48)
                    ),
                    radius: CGFloat.random(in: 14...20),
                    age: 0,
                    lifetime: 1.45,
                    wobbleSeed: CGFloat.random(in: 0...(.pi * 2))
                )
            default:
                projectile = EnemyProjectile(
                    jutsu: jutsu,
                    position: source,
                    velocity: CGVector(dx: 340, dy: 0),
                    radius: 12,
                    age: 0,
                    lifetime: 1.2,
                    wobbleSeed: 0
                )
            }

            enemyProjectiles.append(projectile)
        }
    }

    private func handleDefendInput(_ jutsu: JutsuType) {
        guard let enemyJutsu = activeEnemyJutsu else { return }
        let target = counterJutsu(for: enemyJutsu)

        if jutsu == target {
            defendSucceeded = true
            let isPerfect = (phaseDuration - phaseTimeRemaining) <= 3.0
            if isPerfect {
                chakra = min(100, chakra + 10)
                feedbackText = "PERFECT BLOCK! +10 chakra"
            } else {
                feedbackText = "Blocked \(enemyJutsu.title)"
            }
            addFloatingFeedback(
                text: isPerfect ? "PERFECT BLOCK" : "BLOCK",
                colorHex: isPerfect ? 0xFFE066 : 0x66FF99,
                position: CGPoint(x: max(80, arenaSize.width * 0.70), y: max(120, arenaSize.height * 0.36)),
                lifetime: isPerfect ? 1.2 : 0.9
            )
            addImpactBurst(
                at: CGPoint(x: max(80, arenaSize.width * 0.78), y: max(140, arenaSize.height * 0.42)),
                colorHex: isPerfect ? 0xFFE066 : 0x66FF99,
                maxRadius: isPerfect ? 90 : 60
            )
            Haptics.defenseSuccess()
            startPlayerAttackPhase()
        } else {
            feedbackText = "Use \(target.title) to counter"
        }
    }

    private func counterJutsu(for enemyJutsu: JutsuType) -> JutsuType {
        switch enemyJutsu {
        case .fireball, .burningAsh:
            return .waterDragon
        case .lightning:
            return .rasengan
        default:
            return enemyJutsu
        }
    }

    private func handleAttackInput(_ jutsu: JutsuType) {
        let now = Date()
        if jutsu == lastAcceptedAttackJutsu, now.timeIntervalSince(lastAcceptedAttackAt) < 0.55 {
            return
        }
        lastAcceptedAttackAt = now
        lastAcceptedAttackJutsu = jutsu

        let profile = attackProfile(for: jutsu)
        guard chakra >= profile.chakraCost else {
            feedbackText = "Not enough chakra for \(jutsu.title)"
            addFloatingFeedback(
                text: "No chakra",
                colorHex: 0xFFCC66,
                position: CGPoint(x: max(40, arenaSize.width * 0.66), y: max(90, arenaSize.height * 0.78)),
                lifetime: 0.8
            )
            return
        }

        if now.timeIntervalSince(lastComboAt) <= comboChainWindow, comboCount >= 1 {
            comboCount += 1
        } else {
            comboCount = 1
        }
        lastComboAt = now
        let comboMultiplier = 1.0 + 0.3 * Double(min(comboCount - 1, 2))
        let comboDamage = Int((Double(profile.damage) * comboMultiplier).rounded())

        chakra -= profile.chakraCost
        feedbackText = comboCount >= 2 ? "\(jutsu.title) — COMBO x\(comboCount)!" : "\(jutsu.title) launched"
        if comboCount >= 2 {
            addFloatingFeedback(
                text: "COMBO x\(comboCount)",
                colorHex: 0xFFB84D,
                position: CGPoint(x: max(60, arenaSize.width * 0.52), y: max(90, arenaSize.height * 0.24)),
                lifetime: 0.9
            )
        }

        let spawn = CGPoint(
            x: max(120, arenaSize.width * 0.72),
            y: max(120, arenaSize.height * 0.56)
        )

        let speedX: CGFloat = -(420 + CGFloat(comboDamage * 4))
        let projectile = Projectile(
            jutsu: jutsu,
            position: spawn,
            velocity: CGVector(dx: speedX, dy: CGFloat.random(in: -12...12)),
            radius: profile.projectileRadius,
            damage: comboDamage
        )
        projectiles.append(projectile)

        addFloatingFeedback(
            text: "-\(profile.chakraCost) chakra",
            colorHex: 0x7EC8FF,
            position: CGPoint(x: spawn.x, y: spawn.y - 48),
            lifetime: 0.9
        )
    }

    private func updateProjectiles(deltaTime: TimeInterval) {
        guard !projectiles.isEmpty else { return }

        for idx in projectiles.indices.reversed() {
            var projectile = projectiles[idx]
            projectile.position.x += projectile.velocity.dx * deltaTime
            projectile.position.y += projectile.velocity.dy * deltaTime

            let projectileRect = CGRect(
                x: projectile.position.x - projectile.radius,
                y: projectile.position.y - projectile.radius,
                width: projectile.radius * 2,
                height: projectile.radius * 2
            )

            if projectileRect.intersects(sasukeHitbox), !sasukeHitbox.isEmpty {
                applyDamageToSasuke(projectile.damage, sourceJutsu: projectile.jutsu, at: projectile.position)
                projectiles.remove(at: idx)
                continue
            }

            let outOfBounds = projectile.position.x < -60 || projectile.position.x > arenaSize.width + 60 || projectile.position.y < -60 || projectile.position.y > arenaSize.height + 60
            if outOfBounds {
                projectiles.remove(at: idx)
            } else {
                projectiles[idx] = projectile
            }
        }
    }

    private func updateEnemyProjectiles(deltaTime: TimeInterval) {
        guard !enemyProjectiles.isEmpty else { return }

        for idx in enemyProjectiles.indices.reversed() {
            var projectile = enemyProjectiles[idx]
            projectile.age += deltaTime

            let wobble = sin(CGFloat(projectile.age * 8) + projectile.wobbleSeed) * (projectile.jutsu == .lightning ? 9 : 5)
            projectile.position.x += projectile.velocity.dx * deltaTime
            projectile.position.y += (projectile.velocity.dy * deltaTime) + (wobble * CGFloat(deltaTime))

            if state == .playerDefend, !defendSucceeded, arenaSize.width > 10, projectile.position.x >= playerZoneX {
                let chip = min(8, 3 + (round - 1) / 2 + (projectile.jutsu == .fireball ? 2 : 0))
                applyPlayerDamage(chip, reason: "Hit by \(projectile.jutsu.title)")
                addImpactBurst(
                    at: projectile.position,
                    colorHex: 0xFF6A6A,
                    maxRadius: 40
                )
                enemyProjectiles.remove(at: idx)
                continue
            }

            let outOfBounds = projectile.position.x < -80 || projectile.position.x > arenaSize.width + 120 || projectile.position.y < -80 || projectile.position.y > arenaSize.height + 120
            if outOfBounds || projectile.age >= projectile.lifetime {
                enemyProjectiles.remove(at: idx)
            } else {
                enemyProjectiles[idx] = projectile
            }
        }
    }

    private func updateFloatingFeedbacks(deltaTime: TimeInterval) {
        guard !floatingFeedbacks.isEmpty else { return }

        for idx in floatingFeedbacks.indices.reversed() {
            floatingFeedbacks[idx].age += deltaTime
            floatingFeedbacks[idx].position.y -= CGFloat(24 * deltaTime)
            if floatingFeedbacks[idx].age >= floatingFeedbacks[idx].lifetime {
                floatingFeedbacks.remove(at: idx)
            }
        }
    }

    private func applyDamageToSasuke(_ damage: Int, sourceJutsu: JutsuType, at impactPoint: CGPoint) {
        sasukeHP = max(0, sasukeHP - damage)
        feedbackText = "\(sourceJutsu.title) hit Sasuke for \(damage)"
        Haptics.enemyHit()
        addImpactBurst(at: impactPoint, colorHex: 0xFFB84D, maxRadius: 70)
        flashSasuke()
        addFloatingFeedback(
            text: "-\(damage)",
            colorHex: 0xFF8F8F,
            position: CGPoint(x: max(impactPoint.x, sasukeHitbox.minX + 20), y: max(impactPoint.y, sasukeHitbox.minY + 18)),
            lifetime: 1.0
        )

        if sasukeHP <= 0 {
            battleEnded = true
            playerWon = true
            state = .gameOver
            enemyProjectiles.removeAll(keepingCapacity: true)
            phaseTimeRemaining = 0
            feedbackText = "Sasuke defeated — Victory!"
        }
    }

    private func applyPlayerDamage(_ damage: Int, reason: String) {
        playerHP = max(0, playerHP - damage)
        feedbackText = "\(reason): -\(damage) HP"
        Haptics.playerHit()
        playerHitPulse += 1

        addFloatingFeedback(
            text: "-\(damage)",
            colorHex: 0xFF6A6A,
            position: CGPoint(x: max(120, arenaSize.width * 0.75), y: max(150, arenaSize.height * 0.34)),
            lifetime: 1.0
        )

        if playerHP <= 0 {
            battleEnded = true
            state = .gameOver
            enemyProjectiles.removeAll(keepingCapacity: true)
            phaseTimeRemaining = 0
            feedbackText = "You were defeated"
        }
    }

    private func addFloatingFeedback(text: String, colorHex: UInt32, position: CGPoint, lifetime: TimeInterval) {
        floatingFeedbacks.append(
            FloatingFeedback(
                text: text,
                colorHex: colorHex,
                position: position,
                age: 0,
                lifetime: lifetime
            )
        )
    }

    private func updateImpactBursts(deltaTime: TimeInterval) {
        guard !impactBursts.isEmpty else { return }
        for idx in impactBursts.indices.reversed() {
            impactBursts[idx].age += deltaTime
            if impactBursts[idx].age >= impactBursts[idx].lifetime {
                impactBursts.remove(at: idx)
            }
        }
    }

    private func addImpactBurst(at position: CGPoint, colorHex: UInt32, maxRadius: CGFloat) {
        impactBursts.append(ImpactBurst(position: position, colorHex: colorHex, maxRadius: maxRadius))
    }

    private func flashSasuke() {
        sasukeHitFlash = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            self?.sasukeHitFlash = false
        }
    }

    private func attackProfile(for jutsu: JutsuType) -> (chakraCost: Int, damage: Int, projectileRadius: CGFloat) {
        switch jutsu {
        case .rasengan:
            return (28, 30, 24)
        case .lightning:
            return (16, 25, 20)
        case .wind:
            return (30, 40, 28)
        default:
            return (10, 15, 18)
        }
    }
}
