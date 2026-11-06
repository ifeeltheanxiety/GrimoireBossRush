import SpriteKit

/// Cut-out character rig. Every part texture shares one canvas, so parts line up automatically;
/// `pivot` (canvas pixels) is the rotation point of a part.
final class Rig: SKNode {
    let pose = SKNode()
    let canvas: CGSize
    let feet: CGPoint
    let k: CGFloat
    private(set) var parts: [String: SKSpriteNode] = [:]
    private var pivots: [String: CGPoint] = [:]

    init(canvas: CGSize, feet: CGPoint, height: CGFloat, top: CGFloat) {
        self.canvas = canvas
        self.feet = feet
        self.k = height / (feet.y - top)
        super.init()
        addChild(pose)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func local(_ px: CGPoint) -> CGPoint { CGPoint(x: (px.x - feet.x) * k, y: (feet.y - px.y) * k) }

    @discardableResult
    func add(_ tex: String, z: CGFloat, pivot: CGPoint? = nil, parent: String? = nil, blend: SKBlendMode = .alpha) -> SKSpriteNode {
        let pv = pivot ?? feet
        let s = SKSpriteNode(texture: Art.tex(tex))
        s.size = CGSize(width: canvas.width * k, height: canvas.height * k)
        s.anchorPoint = CGPoint(x: pv.x / canvas.width, y: 1 - pv.y / canvas.height)
        s.zPosition = z
        s.blendMode = blend
        if let pn = parent, let ps = parts[pn], let pp = pivots[pn] {
            let a = local(pv), b = local(pp)
            s.position = CGPoint(x: a.x - b.x, y: a.y - b.y)
            ps.addChild(s)
        } else {
            s.position = local(pv)
            pose.addChild(s)
        }
        parts[tex] = s
        pivots[tex] = pv
        return s
    }

    func part(_ name: String) -> SKSpriteNode { parts[name]! }

    /// Ghost copy of the current pose, used for after-images.
    func ghost(color: UIColor) -> SKNode {
        let g = pose.copy() as! SKNode
        g.enumerateChildNodes(withName: "//*") { n, _ in
            n.removeAllActions()
            if let s = n as? SKSpriteNode { s.color = color; s.colorBlendFactor = 1; s.blendMode = .add }
        }
        g.removeAllActions()
        g.alpha = 0.55
        return g
    }
}

class Fighter: SKNode {
    let rig: Rig
    let shadow = SKSpriteNode(texture: Art.tex("fx_shadow"))
    var maxHP: CGFloat
    var hp: CGFloat
    var busy = false
    var airborne = false
    var alive: Bool { hp > 0 }
    var facing: CGFloat = 1 { didSet { rig.pose.xScale = facing } }
    let bodyHeight: CGFloat

    init(rig: Rig, hp: CGFloat, shadowWidth: CGFloat) {
        self.rig = rig
        self.maxHP = hp
        self.hp = hp
        self.bodyHeight = (rig.feet.y - 60) * rig.k
        super.init()
        shadow.size = CGSize(width: shadowWidth, height: shadowWidth * 0.28)
        shadow.alpha = 0.75
        shadow.zPosition = -10
        addChild(shadow)
        addChild(rig)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func flash(_ color: UIColor = .white) {
        for s in rig.parts.values where s.blendMode == .alpha {
            s.removeAction(forKey: "flash")
            s.run(.sequence([.colorize(with: color, colorBlendFactor: 0.85, duration: 0.03),
                             .colorize(withColorBlendFactor: 0, duration: 0.16)]), withKey: "flash")
        }
    }
}

final class Daniel: Fighter {
    let wings: SKSpriteNode, eyes: SKSpriteNode, swordGlow: SKSpriteNode
    let aura: SKEmitterNode

    init(height: CGFloat, hp: CGFloat) {
        let r = Rig(canvas: CGSize(width: 512, height: 768), feet: CGPoint(x: 262, y: 740), height: height, top: 60)
        wings = r.add("daniel_wings", z: -2, pivot: CGPoint(x: 262, y: 290))
        r.add("daniel_cape", z: -1, pivot: CGPoint(x: 232, y: 232))
        r.add("daniel_body", z: 0)
        r.add("daniel_head", z: 1, pivot: CGPoint(x: 262, y: 205))
        eyes = r.add("daniel_eyes", z: 0.5, pivot: CGPoint(x: 262, y: 205), parent: "daniel_head", blend: .add)
        r.add("daniel_arm", z: 3, pivot: CGPoint(x: 302, y: 248))
        swordGlow = r.add("daniel_sword_glow", z: -0.5, pivot: CGPoint(x: 302, y: 248), parent: "daniel_arm", blend: .add)
        aura = FX.emitter("fx_smoke", rate: 0, life: 0.9, speed: 50, scale: 0.5, color: UIColor(red: 0.35, green: 0.1, blue: 0.6, alpha: 1))
        super.init(rig: r, hp: hp, shadowWidth: height * 0.55)
        wings.setScale(0.01); wings.alpha = 0
        eyes.alpha = 0
        swordGlow.alpha = 0.35
        aura.position = CGPoint(x: 0, y: height * 0.45)
        aura.particlePositionRange = CGVector(dx: height * 0.4, dy: height * 0.8)
        aura.emissionAngle = .pi / 2
        aura.particleBlendMode = .alpha
        aura.targetNode = nil
        aura.zPosition = -3
        addChild(aura)
        idle()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    var arm: SKSpriteNode { rig.part("daniel_arm") }
    var head: SKSpriteNode { rig.part("daniel_head") }
    var cape: SKSpriteNode { rig.part("daniel_cape") }

    func idle() {
        rig.pose.removeAction(forKey: "breath")
        rig.pose.run(.repeatForever(.sequence([.scaleY(to: 1.015, duration: 0.9), .scaleY(to: 1.0, duration: 0.9)])), withKey: "breath")
        head.run(.repeatForever(.sequence([.rotate(toAngle: 0.03, duration: 1.2), .rotate(toAngle: -0.01, duration: 1.2)])), withKey: "idle")
        cape.run(.repeatForever(.sequence([.rotate(toAngle: -0.05, duration: 1.1), .rotate(toAngle: 0.02, duration: 1.1)])), withKey: "idle")
        swordGlow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.8), .fadeAlpha(to: 0.25, duration: 0.8)])), withKey: "pulse")
    }

    /// Lean / bob while running.
    func setRunning(_ on: Bool) {
        if on {
            rig.pose.zRotation = -0.09 * facing
            guard rig.pose.action(forKey: "run") == nil else { return }
            rig.pose.run(.repeatForever(.sequence([.moveTo(y: 4, duration: 0.14), .moveTo(y: 0, duration: 0.14)])), withKey: "run")
            cape.run(.rotate(toAngle: -0.22, duration: 0.15))
        } else if rig.pose.action(forKey: "run") != nil {
            rig.pose.removeAction(forKey: "run")
            rig.pose.zRotation = 0
            rig.pose.position = .zero
            cape.run(.rotate(toAngle: 0, duration: 0.25))
        }
    }

    /// Overhead slash: wind-up then fast swing. `strike` fires at the moment of impact.
    func swing(windup: TimeInterval = 0.08, strike: @escaping () -> Void) -> TimeInterval {
        arm.removeAction(forKey: "atk")
        arm.run(.sequence([
            .rotate(toAngle: 2.1, duration: windup, shortestUnitArc: true),
            .rotate(toAngle: -0.55, duration: 0.07, shortestUnitArc: false),
            .run(strike),
            .wait(forDuration: 0.1),
            .rotate(toAngle: 0, duration: 0.14)
        ]), withKey: "atk")
        return windup + 0.07 + 0.12
    }

    func cast(duration: TimeInterval) {
        arm.removeAction(forKey: "atk")
        arm.run(.sequence([.rotate(toAngle: 1.3, duration: 0.12), .wait(forDuration: duration), .rotate(toAngle: 0, duration: 0.2)]), withKey: "atk")
        head.run(.sequence([.rotate(toAngle: 0.12, duration: 0.12), .wait(forDuration: duration), .rotate(toAngle: 0, duration: 0.2)]))
    }

    func setDemon(_ on: Bool) {
        if on {
            wings.run(.group([.scale(to: 1, duration: 0.5), .fadeAlpha(to: 0.95, duration: 0.3)]))
            wings.run(.repeatForever(.sequence([.scaleY(to: 0.92, duration: 0.35), .scaleY(to: 1.0, duration: 0.35)])), withKey: "flap")
            eyes.run(.fadeIn(withDuration: 0.2))
            swordGlow.removeAction(forKey: "pulse")
            swordGlow.run(.repeatForever(.sequence([.fadeAlpha(to: 1, duration: 0.15), .fadeAlpha(to: 0.75, duration: 0.15)])), withKey: "pulse")
            swordGlow.run(.scale(to: 1.15, duration: 0.3))
            aura.particleBirthRate = 45
        } else {
            wings.removeAction(forKey: "flap")
            wings.run(.group([.scale(to: 0.01, duration: 0.35), .fadeOut(withDuration: 0.3)]))
            eyes.run(.fadeOut(withDuration: 0.3))
            swordGlow.run(.scale(to: 1, duration: 0.3))
            aura.particleBirthRate = 0
            idle()
        }
    }

    func die() {
        arm.removeAllActions()
        rig.run(.sequence([.group([.rotate(byAngle: 1.4 * facing, duration: 0.5), .moveBy(x: -30 * facing, y: 0, duration: 0.5)]),
                           .fadeAlpha(to: 0.4, duration: 0.8)]))
    }
}

final class DemonKnight: Fighter {
    let fire: SKEmitterNode
    let eyeGlow = SKSpriteNode(texture: Art.tex("fx_glow"))
    var speedMult: CGFloat = 1
    var stagger: CGFloat = 0

    init(height: CGFloat, hp: CGFloat) {
        let r = Rig(canvas: CGSize(width: 768, height: 1024), feet: CGPoint(x: 384, y: 1000), height: height, top: 60)
        r.add("knight_body", z: 0)
        let arm = r.add("knight_arm", z: 2, pivot: CGPoint(x: 476, y: 318))
        fire = FX.emitter("fx_spark", rate: 70, life: 0.6, speed: 40, scale: 0.35, color: UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 1))
        super.init(rig: r, hp: hp, shadowWidth: height * 0.6)
        let shoulder = r.local(CGPoint(x: 476, y: 318))
        let mid = r.local(CGPoint(x: 650, y: 713))
        let tip = r.local(CGPoint(x: 731, y: 829))
        fire.position = CGPoint(x: mid.x - shoulder.x, y: mid.y - shoulder.y)
        fire.zRotation = atan2(tip.y - mid.y, tip.x - mid.x)
        fire.particlePositionRange = CGVector(dx: hypot(tip.x - mid.x, tip.y - mid.y) * 2, dy: 8)
        fire.emissionAngle = .pi / 2
        fire.yAcceleration = 60
        arm.addChild(fire)
        eyeGlow.size = CGSize(width: 90 * r.k * 2, height: 40 * r.k * 2)
        eyeGlow.color = .red; eyeGlow.colorBlendFactor = 1; eyeGlow.blendMode = .add
        eyeGlow.position = r.local(CGPoint(x: 432, y: 232))
        eyeGlow.zPosition = 5
        r.pose.addChild(eyeGlow)
        eyeGlow.run(.repeatForever(.sequence([.fadeAlpha(to: 1, duration: 0.6), .fadeAlpha(to: 0.4, duration: 0.6)])))
        r.pose.run(.repeatForever(.sequence([.scaleY(to: 1.02, duration: 1.1), .scaleY(to: 1, duration: 1.1)])))
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    var arm: SKSpriteNode { rig.part("knight_arm") }

    func walk(_ on: Bool) {
        if on {
            guard rig.action(forKey: "walk") == nil else { return }
            rig.run(.repeatForever(.sequence([.moveTo(y: 5, duration: 0.25), .moveTo(y: 0, duration: 0.25)])), withKey: "walk")
        } else {
            rig.removeAction(forKey: "walk"); rig.position = .zero
        }
    }

    func raise(_ t: TimeInterval) -> SKAction {
        .run { [weak self] in
            self?.arm.run(.rotate(toAngle: 2.3, duration: t))
            self?.eyeGlow.run(.sequence([.scale(to: 1.8, duration: t), .scale(to: 1, duration: 0.2)]))
        }
    }

    func slam() -> SKAction {
        .run { [weak self] in
            self?.arm.run(.sequence([.rotate(toAngle: -0.5, duration: 0.09), .wait(forDuration: 0.35), .rotate(toAngle: 0, duration: 0.3)]))
        }
    }

    func resetPose() {
        arm.removeAllActions()
        arm.run(.rotate(toAngle: 0, duration: 0.2))
        rig.pose.position = .zero
        rig.pose.run(.scaleY(to: 1, duration: 0.1))
    }
}

enum FX {
    static func emitter(_ tex: String, rate: CGFloat, life: CGFloat, speed: CGFloat, scale: CGFloat, color: UIColor) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Art.tex(tex)
        e.particleBirthRate = rate
        e.particleLifetime = life
        e.particleLifetimeRange = life * 0.4
        e.particleSpeed = speed
        e.particleSpeedRange = abs(speed) * 0.6
        e.emissionAngleRange = .pi * 2
        e.particleScale = scale
        e.particleScaleRange = scale * 0.5
        e.particleScaleSpeed = -scale / life * 0.6
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -0.9 / life
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.particleRotationRange = .pi * 2
        return e
    }

    static func burst(_ tex: String, count: Int, life: CGFloat, speed: CGFloat, scale: CGFloat, color: UIColor) -> SKEmitterNode {
        let e = emitter(tex, rate: CGFloat(count) * 20, life: life, speed: speed, scale: scale, color: color)
        e.numParticlesToEmit = count
        e.run(.sequence([.wait(forDuration: TimeInterval(life) * 1.6 + 0.1), .removeFromParent()]))
        return e
    }

    static func sprite(_ tex: String, size: CGSize, color: UIColor? = nil, blend: SKBlendMode = .add) -> SKSpriteNode {
        let s = SKSpriteNode(texture: Art.tex(tex))
        s.size = size
        s.blendMode = blend
        if let c = color { s.color = c; s.colorBlendFactor = 1 }
        return s
    }
}
