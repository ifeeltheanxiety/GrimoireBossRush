import SpriteKit
import UIKit

// MARK: - HUD pieces

final class SkillButton: SKNode {
    let r: CGFloat
    private let icon: SKSpriteNode
    private let shade = SKSpriteNode(texture: Art.tex("ui_shade"))
    private let glow = SKSpriteNode(texture: Art.tex("fx_glow"))
    private let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")

    init(_ tex: String, radius: CGFloat, glowColor: UIColor = UIColor(red: 0.7, green: 0.3, blue: 1, alpha: 1)) {
        r = radius
        icon = SKSpriteNode(texture: Art.tex(tex))
        super.init()
        icon.size = CGSize(width: radius * 2.2, height: radius * 2.2)
        shade.size = CGSize(width: radius * 1.75, height: radius * 1.75)
        shade.alpha = 0
        glow.size = CGSize(width: radius * 4, height: radius * 4)
        glow.color = glowColor; glow.colorBlendFactor = 1; glow.blendMode = .add; glow.alpha = 0
        label.fontSize = radius * 0.7
        label.verticalAlignmentMode = .center
        label.fontColor = .white
        [glow, icon, shade, label].forEach(addChild)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func set(cooldown: CGFloat, usable: Bool, highlight: Bool = false) {
        shade.alpha = cooldown > 0 ? 0.7 : (usable ? 0 : 0.45)
        label.text = cooldown > 0 ? "\(Int(ceil(cooldown)))" : ""
        let g: CGFloat = highlight ? 0.55 + 0.35 * sin(CGFloat(CACurrentMediaTime()) * 6) : 0
        glow.alpha = g
    }

    func press() {
        icon.run(.sequence([.scale(to: 0.86, duration: 0.05), .scale(to: 1, duration: 0.12)]))
    }

    func deny() {
        run(.sequence([.moveBy(x: 4, y: 0, duration: 0.03), .moveBy(x: -8, y: 0, duration: 0.05), .moveBy(x: 4, y: 0, duration: 0.03)]))
    }
}

final class Bar: SKNode {
    private let fill: SKSpriteNode
    private let trail = SKSpriteNode(texture: Art.tex("ui_fill_white"))

    init(_ tex: String, width: CGFloat, height: CGFloat) {
        fill = SKSpriteNode(texture: Art.tex(tex))
        super.init()
        let frame = SKSpriteNode(texture: Art.tex("ui_bar_frame"))
        frame.size = CGSize(width: width, height: height)
        let inner = CGSize(width: width * 0.92, height: height * 0.46)
        for s in [trail, fill] {
            s.anchorPoint = CGPoint(x: 0, y: 0.5)
            s.size = inner
            s.position = CGPoint(x: -inner.width / 2, y: 0)
        }
        trail.alpha = 0.8
        [frame, trail, fill].forEach(addChild)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func set(_ ratio: CGFloat, dt: CGFloat) {
        let r = max(0, min(1, ratio))
        fill.xScale = r
        trail.xScale = trail.xScale > r ? max(r, trail.xScale - dt * 0.6) : r
    }
}

final class Wave {
    let node: SKSpriteNode
    let vx: CGFloat
    let fromPlayer: Bool
    var hit = false
    init(node: SKSpriteNode, vx: CGFloat, fromPlayer: Bool) { self.node = node; self.vx = vx; self.fromPlayer = fromPlayer }
}

// MARK: - Battle

final class BattleScene: SKScene {
    var onFinish: ((Bool, TimeInterval) -> Void)?

    private let prog: SaveData
    private let safe: UIEdgeInsets
    private let world = SKNode()
    private let hud = SKNode()
    private var player: Daniel!
    private var boss: DemonKnight!

    private var floorLo: CGFloat = 0, floorHi: CGFloat = 0, xLo: CGFloat = 0, xHi: CGFloat = 0
    private var mana: CGFloat = 0, rage: CGFloat = 0
    private var cd: [CGFloat] = [0, 0, 0]
    private var dodgeCD: CGFloat = 0, demonTime: CGFloat = 0, invuln: CGFloat = 0, lock: CGFloat = 0
    private var combo = 0, comboTimer: CGFloat = 0
    private var lastTime: TimeInterval = 0, elapsed: TimeInterval = 0
    private var started = false, over = false, frozen = false
    private var bossThink: CGFloat = 1.2, bossFreeze: CGFloat = 0
    private var waves: [Wave] = []
    private var hole: SKNode?
    private var storm: SKNode?

    private var hpBar: Bar!, manaBar: Bar!, rageBar: Bar!, bossBar: Bar!
    private let joyBase = SKSpriteNode(texture: Art.tex("ui_joy_base"))
    private let joyKnob = SKSpriteNode(texture: Art.tex("ui_joy_knob"))
    private var joyHome = CGPoint.zero
    private var joyTouch: UITouch?, attackTouch: UITouch?
    private var joyVec = CGVector.zero
    private var btns: [String: SkillButton] = [:]
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticHeavy = UIImpactFeedbackGenerator(style: .heavy)

    static let skills: [(name: String, tex: String, cost: CGFloat, cd: CGFloat)] = [
        ("VOID SLASH", "btn_slash", 20, 3.5), ("BLACK HOLE", "btn_hole", 35, 9), ("ABYSSAL STORM", "btn_storm", 55, 15)
    ]
    static let demonDuration: CGFloat = 15
    private let violet = UIColor(red: 0.62, green: 0.32, blue: 1, alpha: 1)
    private let fireColor = UIColor(red: 1, green: 0.45, blue: 0.12, alpha: 1)

    private var demon: Bool { demonTime > 0 }
    private var canAct: Bool { started && !over && player.alive && lock <= 0 }

    init(size: CGSize, progress: SaveData, safe: UIEdgeInsets) {
        self.prog = progress
        self.safe = safe
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func setPaused(_ p: Bool) {
        frozen = p
        isPaused = p
        if p { joyTouch = nil; attackTouch = nil; joyVec = .zero }
    }

    // MARK: Setup

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        guard player == nil else { return }
        addChild(world)
        hud.zPosition = 5000
        addChild(hud)
        buildArena()
        buildHUD()
        intro()
    }

    private func buildArena() {
        let bg = SKSpriteNode(texture: Art.tex("bg_arena"))
        let s = max(size.width / 1792, size.height / 828)
        bg.size = CGSize(width: 1792 * s, height: 828 * s)
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bg.zPosition = -1000
        world.addChild(bg)
        floorHi = size.height / 2 - 0.06 * bg.size.height - 8
        floorLo = max(26, size.height * 0.07)
        xLo = safe.left + 40
        xHi = size.width - safe.right - 40

        let embers = FX.emitter("fx_spark", rate: 14, life: 4, speed: 30, scale: 0.18, color: fireColor)
        embers.position = CGPoint(x: size.width / 2, y: 0)
        embers.particlePositionRange = CGVector(dx: size.width, dy: 20)
        embers.emissionAngle = .pi / 2; embers.emissionAngleRange = 0.6
        embers.yAcceleration = 8; embers.particleAlphaSpeed = -0.2; embers.particleScaleSpeed = 0
        embers.zPosition = 2500
        embers.advanceSimulationTime(4)
        world.addChild(embers)
        let fog = FX.emitter("fx_smoke", rate: 2, life: 9, speed: 14, scale: 3.2, color: UIColor(red: 0.5, green: 0.15, blue: 0.2, alpha: 1))
        fog.position = CGPoint(x: size.width / 2, y: floorHi)
        fog.particlePositionRange = CGVector(dx: size.width, dy: 30)
        fog.emissionAngle = 0; fog.emissionAngleRange = 0.3
        fog.particleAlpha = 0.12; fog.particleAlphaSpeed = -0.012; fog.particleScaleSpeed = 0
        fog.particleBlendMode = .alpha
        fog.zPosition = -500
        fog.advanceSimulationTime(9)
        world.addChild(fog)

        let midY = (floorLo + floorHi) / 2
        player = Daniel(height: size.height * 0.40, hp: prog.maxHP)
        player.position = CGPoint(x: xLo + 110, y: midY)
        boss = DemonKnight(height: size.height * 0.56, hp: 3200)
        boss.position = CGPoint(x: xHi - 110, y: midY)
        boss.facing = -1
        world.addChild(player)
        world.addChild(boss)
        mana = prog.maxMana
        place(player); place(boss)
    }

    private func buildHUD() {
        let L = max(safe.left, 14) + 8, T = size.height - 14
        let name = label("DANIEL  Lv.\(prog.level)", 13, font: "Copperplate-Bold")
        name.horizontalAlignmentMode = .left
        name.position = CGPoint(x: L + 4, y: T - 8)
        hud.addChild(name)
        hpBar = Bar("ui_fill_hp", width: 250, height: 26); hpBar.position = CGPoint(x: L + 125, y: T - 30)
        manaBar = Bar("ui_fill_mana", width: 210, height: 20); manaBar.position = CGPoint(x: L + 105, y: T - 50)
        rageBar = Bar("ui_fill_rage", width: 170, height: 17); rageBar.position = CGPoint(x: L + 85, y: T - 67)
        [hpBar, manaBar, rageBar].forEach { hud.addChild($0!) }

        let R = size.width - max(safe.right, 14) - 8
        let bw = min(380, size.width * 0.4)
        bossBar = Bar("ui_fill_boss", width: bw, height: 28); bossBar.position = CGPoint(x: R - bw / 2, y: T - 30)
        hud.addChild(bossBar)
        let bn = label("DEMON KNIGHT", 14, font: "Copperplate-Bold")
        bn.fontColor = UIColor(red: 1, green: 0.75, blue: 0.7, alpha: 1)
        bn.horizontalAlignmentMode = .right
        bn.position = CGPoint(x: R - 6, y: T - 8)
        hud.addChild(bn)

        joyHome = CGPoint(x: max(safe.left, 20) + 85, y: 82)
        joyBase.size = CGSize(width: 124, height: 124); joyBase.alpha = 0.75
        joyKnob.size = CGSize(width: 62, height: 62)
        joyBase.position = joyHome; joyKnob.position = joyHome
        hud.addChild(joyBase); hud.addChild(joyKnob)

        let A = CGPoint(x: size.width - max(safe.right, 16) - 70, y: 74)
        func polar(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
            CGPoint(x: A.x + r * cos(deg * .pi / 180), y: A.y + r * sin(deg * .pi / 180))
        }
        let defs: [(String, String, CGFloat, CGPoint)] = [
            ("attack", "btn_attack", 44, A),
            ("s0", "btn_slash", 30, polar(100, 168)),
            ("s1", "btn_hole", 30, polar(100, 124)),
            ("s2", "btn_storm", 30, polar(100, 80)),
            ("dodge", "btn_dodge", 30, CGPoint(x: A.x - 180, y: A.y - 18)),
            ("demon", "btn_demon", 30, CGPoint(x: L + 36, y: T - 112))
        ]
        for (key, tex, r, p) in defs {
            let b = SkillButton(tex, radius: r)
            b.position = p
            hud.addChild(b)
            btns[key] = b
        }
    }

    private func intro() {
        banner("DEMON KNIGHT", color: UIColor(red: 1, green: 0.4, blue: 0.3, alpha: 1), size: 34, y: size.height * 0.6)
        run(.sequence([.wait(forDuration: 1.3), .run { [weak self] in
            guard let self else { return }
            self.banner("FIGHT!", color: .white, size: 46, y: self.size.height * 0.55)
            self.started = true
        }]))
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if let hit = btns.first(where: { hypot($0.value.position.x - p.x, $0.value.position.y - p.y) < $0.value.r * 1.3 }) {
                hit.value.press()
                if hit.key == "attack" { attackTouch = t }
                handle(hit.key)
            } else if joyTouch == nil && p.x < size.width * 0.45 && p.y < size.height * 0.6 {
                joyTouch = t
                joyBase.position = p; joyKnob.position = p
                joyBase.alpha = 1
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let jt = joyTouch, touches.contains(jt) else { return }
        let p = jt.location(in: self)
        var v = CGVector(dx: p.x - joyBase.position.x, dy: p.y - joyBase.position.y)
        let len = hypot(v.dx, v.dy), maxR: CGFloat = 52
        if len > maxR { v = CGVector(dx: v.dx / len * maxR, dy: v.dy / len * maxR) }
        joyKnob.position = CGPoint(x: joyBase.position.x + v.dx, y: joyBase.position.y + v.dy)
        joyVec = CGVector(dx: v.dx / maxR, dy: v.dy / maxR)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === joyTouch {
                joyTouch = nil; joyVec = .zero
                joyBase.position = joyHome; joyKnob.position = joyHome; joyBase.alpha = 0.75
            }
            if t === attackTouch { attackTouch = nil }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }

    private func handle(_ key: String) {
        switch key {
        case "attack": basicAttack()
        case "s0": skill(0)
        case "s1": skill(1)
        case "s2": skill(2)
        case "dodge": dodge()
        case "demon": transform()
        default: break
        }
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 30))
        lastTime = currentTime
        if frozen { return }
        defer { updateHUD(dt) }
        guard started else { return }
        if !over { elapsed += TimeInterval(dt) }
        for i in 0..<3 { cd[i] = max(0, cd[i] - dt) }
        dodgeCD = max(0, dodgeCD - dt); invuln = max(0, invuln - dt); lock = max(0, lock - dt)
        comboTimer -= dt
        if comboTimer <= 0 { combo = 0 }
        if demonTime > 0 && lock <= 0 {
            demonTime -= dt
            if demonTime <= 0 { endDemon() }
        }
        mana = min(prog.maxMana, mana + dt * (demon ? 14 : 7))
        if attackTouch != nil && canAct { basicAttack() }
        updatePlayer(dt)
        updateBoss(dt)
        updateWaves(dt)
    }

    private func updatePlayer(_ dt: CGFloat) {
        guard player.alive && !over else { player.setRunning(false); return }
        let m = hypot(joyVec.dx, joyVec.dy)
        if lock <= 0 && m > 0.15 {
            let sp: CGFloat = demon ? 240 : 200
            player.position.x += joyVec.dx * sp * dt
            player.position.y += joyVec.dy * sp * 0.65 * dt
            if abs(joyVec.dx) > 0.1 { player.facing = joyVec.dx > 0 ? 1 : -1 }
            player.setRunning(true)
        } else {
            player.setRunning(false)
            if lock <= 0 { face(player, boss) }
        }
        place(player)
    }

    private func updateWaves(_ dt: CGFloat) {
        for w in waves where w.node.parent != nil {
            w.node.position.x += w.vx * dt
            let p = w.node.position
            if !w.hit {
                if w.fromPlayer, boss.alive, abs(boss.position.x - p.x) < 55, abs(boss.position.y - p.y) < 50 {
                    w.hit = true
                    damageBoss(0.9, rageGain: 0, at: chest(boss))
                } else if !w.fromPlayer, abs(player.position.x - p.x) < 42, abs(player.position.y - p.y) < 30, invuln <= 0, player.alive {
                    w.hit = true
                    hurtPlayer(34)
                    w.node.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
                }
            }
            if p.x < -150 || p.x > size.width + 150 { w.node.removeFromParent() }
        }
        waves.removeAll { $0.node.parent == nil }
    }

    // MARK: Helpers

    private func depth(_ y: CGFloat) -> CGFloat { 1.05 - (y - floorLo) / max(1, floorHi - floorLo) * 0.18 }

    private func place(_ f: Fighter) {
        f.position.x = min(max(f.position.x, xLo), xHi)
        f.position.y = min(max(f.position.y, floorLo), floorHi)
        f.setScale(depth(f.position.y))
        f.zPosition = 1000 - f.position.y
    }

    private func face(_ f: Fighter, _ target: Fighter) { f.facing = target.position.x >= f.position.x ? 1 : -1 }

    private func chest(_ f: Fighter) -> CGPoint {
        CGPoint(x: f.position.x, y: f.position.y + f.bodyHeight * 0.55 * f.xScale)
    }

    private func inReach(_ a: Fighter, _ b: Fighter, reach: CGFloat, depth d: CGFloat) -> Bool {
        let dx = (b.position.x - a.position.x) * a.facing
        return dx > -30 && dx < reach && abs(b.position.y - a.position.y) < d
    }

    private func label(_ text: String, _ size: CGFloat, font: String = "AvenirNext-HeavyItalic") -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font)
        l.text = text
        l.fontSize = size
        l.verticalAlignmentMode = .center
        return l
    }

    private func banner(_ text: String, color: UIColor, size s: CGFloat, y: CGFloat) {
        let shadow = label(text, s, font: "Copperplate-Bold")
        shadow.fontColor = UIColor(red: 0.3, green: 0.05, blue: 0.5, alpha: 0.9)
        shadow.position = CGPoint(x: 2, y: -3)
        let l = label(text, s, font: "Copperplate-Bold")
        l.fontColor = color
        let node = SKNode()
        node.addChild(shadow); node.addChild(l)
        node.position = CGPoint(x: size.width / 2, y: y)
        node.setScale(1.6); node.alpha = 0
        hud.addChild(node)
        node.run(.sequence([.group([.fadeIn(withDuration: 0.12), .scale(to: 1, duration: 0.15)]), .wait(forDuration: 0.9),
                            .group([.fadeOut(withDuration: 0.35), .moveBy(x: 0, y: 14, duration: 0.35)]), .removeFromParent()]))
    }

    private func number(_ v: Int, at p: CGPoint, color: UIColor, big: Bool) {
        let fs: CGFloat = big ? 30 : 21
        let sh = label("\(v)", fs); sh.fontColor = .black; sh.position = CGPoint(x: 2, y: -2)
        let l = label("\(v)", fs); l.fontColor = color
        let n = SKNode()
        n.addChild(sh); n.addChild(l)
        n.position = CGPoint(x: p.x + CGFloat.random(in: -18...18), y: p.y + 30)
        n.zPosition = 3000
        n.setScale(0.5)
        world.addChild(n)
        n.run(.sequence([.group([.scale(to: big ? 1.3 : 1, duration: 0.08), .moveBy(x: 0, y: 16, duration: 0.08)]),
                         .group([.moveBy(x: 0, y: 34, duration: 0.6), .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.25)])]),
                         .removeFromParent()]))
    }

    private func spark(at p: CGPoint, color: UIColor, scale: CGFloat = 1) {
        let star = FX.sprite("fx_star", size: CGSize(width: 90 * scale, height: 90 * scale), color: color)
        star.position = p; star.zPosition = 2900; star.setScale(0.3)
        star.zRotation = CGFloat.random(in: 0...CGFloat.pi)
        world.addChild(star)
        star.run(.sequence([.group([.scale(to: 1.2, duration: 0.12), .fadeOut(withDuration: 0.16)]), .removeFromParent()]))
        let b = FX.burst("fx_spark", count: Int(16 * scale), life: 0.35, speed: 220 * scale, scale: 0.35, color: color)
        b.position = p; b.zPosition = 2901
        world.addChild(b)
    }

    private func shake(_ amount: CGFloat) {
        guard prog.shake, amount > 0 else { return }
        var seq: [SKAction] = []
        var a = amount
        for _ in 0..<6 {
            seq.append(.moveTo(x: .random(in: -a...a), duration: 0.025))
            seq.append(.moveTo(y: .random(in: -a...a) * 0.6, duration: 0.025))
            a *= 0.7
        }
        seq.append(.move(to: .zero, duration: 0.03))
        world.removeAction(forKey: "shake")
        world.run(.sequence(seq), withKey: "shake")
    }

    private func haptic(_ heavy: Bool) {
        guard prog.haptics else { return }
        heavy ? hapticHeavy.impactOccurred() : hapticLight.impactOccurred()
    }

    private func ghosts(_ n: Int, every: TimeInterval, color: UIColor) {
        let make = SKAction.run { [weak self] in
            guard let self else { return }
            let holder = SKNode()
            holder.position = self.player.position
            holder.setScale(self.player.xScale)
            holder.zPosition = self.player.zPosition - 1
            holder.addChild(self.player.rig.ghost(color: color))
            self.world.addChild(holder)
            holder.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
        run(.repeat(.sequence([make, .wait(forDuration: every)]), count: n))
    }

    /// Sparks sucked toward `center` (black hole / transformation charge).
    private func inward(into node: SKNode, center: CGPoint, radius: ClosedRange<CGFloat>, count: Int, color: UIColor) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(CGFloat.pi * 2)), r = CGFloat.random(in: radius)
            let p = FX.sprite("fx_spark", size: CGSize(width: 14, height: 14), color: color)
            p.position = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.7)
            node.addChild(p)
            p.run(.sequence([.group([.move(to: center, duration: 0.35), .scale(to: 0.3, duration: 0.35)]), .removeFromParent()]))
        }
    }

    private func flashScreen(_ color: UIColor, alpha: CGFloat, duration: TimeInterval) {
        let f = SKSpriteNode(color: color, size: CGSize(width: size.width * 1.2, height: size.height * 1.2))
        f.position = CGPoint(x: size.width / 2, y: size.height / 2)
        f.zPosition = -1
        f.alpha = alpha
        f.blendMode = .add
        hud.addChild(f)
        f.run(.sequence([.fadeOut(withDuration: duration), .removeFromParent()]))
    }

    // MARK: Damage

    private func damageBoss(_ mult: CGFloat, skill: Int? = nil, rageGain: CGFloat, manaGain: CGFloat = 0,
                            shake s: CGFloat = 0, knock: CGFloat = 0, at p: CGPoint? = nil) {
        guard boss.alive, !over else { return }
        let skillMult: CGFloat = skill.map { prog.skillMult($0) } ?? 1
        let formMult: CGFloat = demon ? 1.6 : 1
        var d: CGFloat = prog.attack * mult * skillMult * formMult
        d *= CGFloat.random(in: 0.9...1.1)
        let crit = CGFloat.random(in: 0...1) < 0.12
        if crit { d *= 1.6 }
        boss.hp = max(0, boss.hp - d)
        boss.flash(demon ? UIColor(red: 0.8, green: 0.5, blue: 1, alpha: 1) : .white)
        let pt = p ?? chest(boss)
        number(Int(d), at: CGPoint(x: pt.x, y: pt.y + 30), color: crit ? UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
               : (demon ? UIColor(red: 0.85, green: 0.6, blue: 1, alpha: 1) : .white), big: crit)
        spark(at: pt, color: demon ? violet : UIColor(red: 0.85, green: 0.75, blue: 1, alpha: 1), scale: crit ? 1.3 : 1)
        if !demon { rage = min(100, rage + rageGain) }
        mana = min(prog.maxMana, mana + manaGain)
        shake(s + (crit ? 3 : 0))
        haptic(s > 6)
        if knock > 0 && !boss.airborne && !boss.busy { boss.position.x += knock * (boss.position.x >= player.position.x ? 1 : -1) }
        boss.stagger += d
        if boss.hp <= 0 {
            bossDied()
        } else if boss.stagger > 420 && !boss.airborne {
            staggerBoss()
        }
    }

    private func hurtPlayer(_ raw: CGFloat) {
        guard player.alive, invuln <= 0, !over else { return }
        var d: CGFloat = max(1, raw - prog.defense) * CGFloat.random(in: 0.9...1.1)
        if demon { d *= 0.75 }
        player.hp = max(0, player.hp - d)
        player.flash(UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
        number(Int(d), at: chest(player), color: UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1), big: false)
        spark(at: chest(player), color: fireColor, scale: 0.8)
        shake(7)
        haptic(true)
        if !demon { rage = min(100, rage + d * 0.35) }
        invuln = 0.45
        let dir: CGFloat = player.position.x >= boss.position.x ? 1 : -1
        player.run(.moveBy(x: 26 * dir, y: 0, duration: 0.12))
        if player.hp <= 0 { playerDied() }
    }

    // MARK: Player actions

    private func aimFacing() {
        if abs(joyVec.dx) > 0.2 { player.facing = joyVec.dx > 0 ? 1 : -1 } else { face(player, boss) }
    }

    private func basicAttack() {
        guard canAct else { return }
        aimFacing()
        combo = combo % 3 + 1
        comboTimer = 0.75
        let fin = combo == 3
        lock = fin ? 0.4 : 0.28
        player.run(.moveBy(x: (fin ? 30 : 12) * player.facing, y: 0, duration: 0.1))
        _ = player.swing(windup: fin ? 0.12 : 0.07) { [weak self] in self?.basicHit(fin) }
    }

    private func basicHit(_ fin: Bool) {
        guard !over else { return }
        let s = FX.sprite("fx_slash", size: CGSize(width: fin ? 190 : 140, height: fin ? 100 : 74),
                          color: demon ? violet : UIColor(red: 0.8, green: 0.7, blue: 1, alpha: 1))
        let sc = player.xScale
        s.position = CGPoint(x: player.position.x + 55 * sc * player.facing, y: player.position.y + player.bodyHeight * 0.45 * sc)
        s.xScale = player.facing * sc
        s.zRotation = (combo == 2 ? -0.35 : 0.25) * player.facing
        s.zPosition = player.zPosition + 2
        s.alpha = 0
        world.addChild(s)
        s.run(.sequence([.group([.fadeIn(withDuration: 0.03), .scaleY(to: sc * 1.15, duration: 0.08)]), .fadeOut(withDuration: 0.16), .removeFromParent()]))
        if inReach(player, boss, reach: 125 * sc + 30, depth: 55) {
            damageBoss(fin ? 1.6 : 1, rageGain: fin ? 9 : 6, manaGain: 4, shake: fin ? 6 : 2, knock: fin ? 16 : 5)
        }
        if demon {
            let w = FX.sprite("fx_slash", size: CGSize(width: 120, height: 60), color: violet)
            w.zRotation = .pi / 2 * -player.facing
            w.position = CGPoint(x: player.position.x + 50 * player.facing, y: player.position.y + player.bodyHeight * 0.4 * sc)
            w.zPosition = 2800
            world.addChild(w)
            waves.append(Wave(node: w, vx: 520 * player.facing, fromPlayer: true))
        }
    }

    private func skill(_ i: Int) {
        let s = Self.skills[i]
        guard canAct, cd[i] <= 0, mana >= s.cost else { btns["s\(i)"]?.deny(); return }
        mana -= s.cost
        cd[i] = s.cd
        banner(s.name, color: UIColor(red: 0.85, green: 0.7, blue: 1, alpha: 1), size: 24, y: size.height * 0.7)
        switch i {
        case 0: voidSlash()
        case 1: blackHole()
        default: abyssalStorm()
        }
    }

    private func voidSlash() {
        aimFacing()
        lock = 0.45
        invuln = max(invuln, 0.35)
        let start = player.position
        let endX = min(max(start.x + 230 * player.facing, xLo), xHi)
        let y = player.position.y
        ghosts(6, every: 0.03, color: violet)
        _ = player.swing(windup: 0.05) { }
        player.run(.sequence([.wait(forDuration: 0.05), .moveTo(x: endX, duration: 0.12)]))
        run(.sequence([.wait(forDuration: 0.17), .run { [weak self] in
            guard let self, !self.over else { return }
            let len = abs(endX - start.x) + 120
            let sc = self.player.xScale
            let trail = FX.sprite("fx_slash", size: CGSize(width: len, height: 120 * sc), color: self.violet)
            trail.position = CGPoint(x: (start.x + endX) / 2, y: y + self.player.bodyHeight * 0.4 * sc)
            trail.xScale = self.player.facing
            trail.zPosition = 2800
            self.world.addChild(trail)
            trail.run(.sequence([.scaleY(to: 1.3, duration: 0.1), .wait(forDuration: 0.15), .group([.fadeOut(withDuration: 0.3), .scaleY(to: 0.1, duration: 0.3)]), .removeFromParent()]))
            let lo = min(start.x, endX) - 60, hi = max(start.x, endX) + 70
            if self.boss.position.x > lo && self.boss.position.x < hi && abs(self.boss.position.y - y) < 70 {
                self.damageBoss(2.4, skill: 0, rageGain: 10, shake: 8, knock: 10)
                self.run(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
                    guard let self else { return }
                    self.damageBoss(1.0, skill: 0, rageGain: 4, shake: 4)
                }]))
            }
        }]))
    }

    private func blackHole() {
        aimFacing()
        lock = 0.4
        player.cast(duration: 0.3)
        let dx = boss.position.x - player.position.x
        var target = CGPoint(x: player.position.x + 200 * player.facing, y: player.position.y)
        if abs(dx) < 400 { target = boss.position }
        target.x = min(max(target.x, xLo), xHi)
        let node = SKNode()
        node.position = target
        node.zPosition = 2700
        world.addChild(node)
        hole = node
        let lift = boss.bodyHeight * 0.45
        let dark = FX.sprite("fx_glow", size: CGSize(width: 300, height: 300), color: .black, blend: .alpha)
        dark.alpha = 0.7; dark.position.y = lift
        let ring = FX.sprite("fx_ring", size: CGSize(width: 200, height: 200), color: violet)
        ring.position.y = lift
        ring.run(.repeatForever(.sequence([.group([.scale(to: 0.4, duration: 0.4), .fadeAlpha(to: 0.9, duration: 0.2)]), .scale(to: 1.1, duration: 0), .fadeAlpha(to: 0, duration: 0)])))
        let orb = FX.sprite("fx_orb", size: CGSize(width: 150, height: 150), blend: .alpha)
        orb.position.y = lift
        orb.setScale(0.05)
        orb.run(.scale(to: 1, duration: 0.3))
        orb.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.8)))
        [dark, ring, orb].forEach(node.addChild)
        let pull = SKAction.run { [weak node, weak self] in
            guard let node, let self else { return }
            self.inward(into: node, center: CGPoint(x: 0, y: lift), radius: 90...160, count: 3, color: self.violet)
        }
        node.run(.repeatForever(.sequence([pull, .wait(forDuration: 0.04)])), withKey: "pull")
        var ticks: [SKAction] = []
        for _ in 0..<10 {
            ticks.append(.wait(forDuration: 0.25))
            ticks.append(.run { [weak self, weak node] in
                guard let self, let node else { return }
                if hypot(self.boss.position.x - node.position.x, (self.boss.position.y - node.position.y) * 2) < 150 {
                    self.damageBoss(0.32, skill: 1, rageGain: 2, at: CGPoint(x: node.position.x, y: node.position.y + lift))
                }
            })
        }
        ticks.append(.run { [weak self, weak node] in
            guard let self, let node else { return }
            node.removeAction(forKey: "pull")
            orb.run(.group([.scale(to: 2.2, duration: 0.25), .fadeOut(withDuration: 0.25)]))
            dark.run(.fadeOut(withDuration: 0.3)); ring.run(.fadeOut(withDuration: 0.1))
            self.spark(at: CGPoint(x: node.position.x, y: node.position.y + lift), color: self.violet, scale: 2)
            self.flashScreen(self.violet, alpha: 0.35, duration: 0.3)
            if hypot(self.boss.position.x - node.position.x, (self.boss.position.y - node.position.y) * 2) < 170 {
                self.damageBoss(1.8, skill: 1, rageGain: 8, shake: 9)
            }
            if self.hole === node { self.hole = nil }
        })
        ticks.append(.wait(forDuration: 0.4))
        ticks.append(.removeFromParent())
        node.run(.sequence(ticks))
    }

    private func abyssalStorm() {
        aimFacing()
        lock = 0.6
        player.cast(duration: 0.5)
        storm?.removeFromParent()
        let node = SKNode()
        node.position = boss.position
        world.addChild(node)
        storm = node
        boss.speedMult = 0.35
        let h = boss.bodyHeight
        for (i, sc) in [(0, 1.0), (1, 0.7)] as [(Int, CGFloat)] {
            let v = FX.sprite("fx_vortex", size: CGSize(width: 300 * sc, height: 300 * sc), color: i == 0 ? violet : .white)
            v.yScale = 0.38
            let spin: CGFloat = i == 0 ? -1 : 1
            v.alpha = 0
            v.run(.fadeAlpha(to: i == 0 ? 0.95 : 0.6, duration: 0.25))
            v.run(.repeatForever(.rotate(byAngle: spin * CGFloat.pi * 2, duration: i == 0 ? 0.5 : 0.35)))
            node.addChild(v)
        }
        let column = FX.emitter("fx_smoke", rate: 90, life: 0.9, speed: 40, scale: 0.8, color: UIColor(red: 0.4, green: 0.12, blue: 0.75, alpha: 1))
        column.particlePositionRange = CGVector(dx: 120, dy: 10)
        column.emissionAngle = .pi / 2; column.emissionAngleRange = 0.4
        column.yAcceleration = h * 2.2
        column.particleBlendMode = .add
        node.addChild(column)
        let sparks = FX.emitter("fx_spark", rate: 60, life: 0.7, speed: 160, scale: 0.3, color: violet)
        sparks.position.y = h * 0.5
        sparks.particlePositionRange = CGVector(dx: 140, dy: h)
        node.addChild(sparks)

        var seq: [SKAction] = []
        for _ in 0..<9 {
            seq.append(.wait(forDuration: 0.22))
            seq.append(.run { [weak self, weak node] in
                guard let self, let node else { return }
                let cut = FX.sprite("fx_slash", size: CGSize(width: 160, height: 60), color: .white)
                cut.position = CGPoint(x: CGFloat.random(in: -50...50), y: CGFloat.random(in: (h * 0.2)...(h * 0.9)))
                cut.zRotation = CGFloat.random(in: 0...(CGFloat.pi * 2))
                cut.zPosition = 10
                node.addChild(cut)
                cut.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                self.damageBoss(0.55, skill: 2, rageGain: 3, shake: 2)
            })
        }
        seq.append(.run { [weak self, weak node] in
            guard let self, let node else { return }
            column.particleBirthRate = 0; sparks.particleBirthRate = 0
            for c in node.children where c is SKSpriteNode { c.run(.group([.scale(by: 1.8, duration: 0.3), .fadeOut(withDuration: 0.3)])) }
            self.spark(at: CGPoint(x: node.position.x, y: node.position.y + h * 0.5), color: self.violet, scale: 2.4)
            self.flashScreen(self.violet, alpha: 0.5, duration: 0.4)
            self.damageBoss(2.8, skill: 2, rageGain: 12, shake: 14)
            self.boss.speedMult = 1
            if self.storm === node { self.storm = nil }
        })
        seq.append(.wait(forDuration: 1.0))
        seq.append(.removeFromParent())
        node.run(.sequence(seq))
    }

    private func dodge() {
        guard started, !over, player.alive, dodgeCD <= 0 else { return }
        dodgeCD = 0.75
        invuln = max(invuln, 0.4)
        lock = 0.24
        player.arm.removeAction(forKey: "atk")
        player.arm.run(.rotate(toAngle: 0, duration: 0.1))
        let m = hypot(joyVec.dx, joyVec.dy)
        let dir = m > 0.2 ? CGVector(dx: joyVec.dx / m, dy: joyVec.dy / m) : CGVector(dx: -player.facing, dy: 0)
        let target = CGPoint(x: player.position.x + dir.dx * 150, y: player.position.y + dir.dy * 90)
        let move = SKAction.move(to: target, duration: 0.22)
        move.timingMode = .easeOut
        player.run(move)
        ghosts(5, every: 0.04, color: UIColor(red: 0.5, green: 0.7, blue: 1, alpha: 1))
        let dust = FX.burst("fx_smoke", count: 8, life: 0.5, speed: 60, scale: 0.4, color: UIColor(white: 0.5, alpha: 1))
        dust.particleBlendMode = .alpha
        dust.position = player.position; dust.zPosition = player.zPosition - 2
        world.addChild(dust)
    }

    private func transform() {
        guard canAct, rage >= 100, !demon else { btns["demon"]?.deny(); return }
        demonTime = Self.demonDuration
        lock = 1.15
        invuln = 1.6
        bossFreeze = 1.2
        boss.isPaused = true
        player.setRunning(false)
        let veil = SKSpriteNode(color: .black, size: CGSize(width: size.width * 1.2, height: size.height * 1.2))
        veil.position = CGPoint(x: size.width / 2, y: size.height / 2)
        veil.zPosition = -400; veil.alpha = 0
        world.addChild(veil)
        veil.run(.sequence([.fadeAlpha(to: 0.65, duration: 0.25), .wait(forDuration: 0.7), .fadeOut(withDuration: 0.4), .removeFromParent()]))
        let c = chest(player)
        let charge = SKNode()
        charge.position = c
        charge.zPosition = 3000
        world.addChild(charge)
        charge.run(.repeatForever(.sequence([.run { [weak self, weak charge] in
            guard let self, let charge else { return }
            self.inward(into: charge, center: .zero, radius: 110...200, count: 4, color: self.violet)
        }, .wait(forDuration: 0.03)])), withKey: "pull")
        player.rig.pose.run(.sequence([.moveBy(x: 0, y: 18, duration: 0.6), .moveBy(x: 0, y: -18, duration: 0.2)]))
        run(.sequence([.wait(forDuration: 0.75), .run { [weak self] in
            guard let self else { return }
            charge.removeAction(forKey: "pull")
            charge.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
            self.player.setDemon(true)
            self.flashScreen(UIColor(red: 0.7, green: 0.4, blue: 1, alpha: 1), alpha: 0.9, duration: 0.5)
            let wave = FX.sprite("fx_ring", size: CGSize(width: 80, height: 80), color: self.violet)
            wave.position = c; wave.zPosition = 3000
            self.world.addChild(wave)
            wave.run(.sequence([.group([.scale(to: 9, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
            self.spark(at: c, color: self.violet, scale: 2.5)
            self.banner("DEMON FORM", color: UIColor(red: 0.85, green: 0.55, blue: 1, alpha: 1), size: 38, y: self.size.height * 0.62)
            self.shake(14)
            self.haptic(true)
            if hypot(self.boss.position.x - self.player.position.x, self.boss.position.y - self.player.position.y) < 160 {
                self.damageBoss(1.5, rageGain: 0, shake: 4, knock: 40)
            }
        }, .wait(forDuration: 0.45), .run { [weak self] in
            self?.boss.isPaused = false
        }]))
    }

    private func endDemon() {
        demonTime = 0
        rage = 0
        player.setDemon(false)
        banner("FORM RELEASED", color: UIColor(white: 0.85, alpha: 1), size: 18, y: size.height * 0.66)
    }

    // MARK: Boss AI

    private func updateBoss(_ dt: CGFloat) {
        guard boss.alive, !over else { boss.walk(false); return }
        if let s = storm { s.position = boss.position; s.zPosition = boss.zPosition + 5 }
        if bossFreeze > 0 { bossFreeze -= dt; return }
        if let h = hole, !boss.airborne {
            let dx = h.position.x - boss.position.x, dy = h.position.y - boss.position.y
            let d = max(1, hypot(dx, dy))
            if d > 6 { boss.position.x += dx / d * 120 * dt; boss.position.y += dy / d * 120 * dt }
        }
        if !boss.airborne { place(boss) }
        guard !boss.busy else { return }
        face(boss, player)
        let p2 = boss.hp < boss.maxHP * 0.5
        let dx = player.position.x - boss.position.x, dy = player.position.y - boss.position.y
        let dist = abs(dx)
        bossThink -= dt
        if bossThink > 0 || !player.alive {
            if (dist > 140 || abs(dy) > 25) && player.alive {
                let sp = 70 * boss.speedMult * (p2 ? 1.35 : 1)
                let d = max(1, hypot(dx, dy * 2))
                boss.position.x += dx / d * sp * dt
                boss.position.y += dy * 2 / d * sp * dt
                boss.walk(true)
            } else {
                boss.walk(false)
            }
            return
        }
        boss.walk(false)
        let r = CGFloat.random(in: 0...1)
        if dist < 190 && abs(dy) < 60 {
            r < 0.7 ? swingAttack(p2) : leapAttack(p2)
        } else {
            if r < 0.5 { fireWave(p2) } else if r < 0.85 { leapAttack(p2) } else { bossThink = 0.8 }
        }
    }

    private func bossAct(_ seq: [SKAction], recover: TimeInterval, p2: Bool) {
        boss.busy = true
        boss.run(.sequence(seq + [.wait(forDuration: recover), .run { [weak self] in
            self?.boss.busy = false
            self?.bossThink = p2 ? 0.8 : 1.4
        }]), withKey: "ai")
    }

    private func telegraph() -> SKAction {
        .run { [weak self] in
            guard let self else { return }
            let g = FX.sprite("fx_glow", size: CGSize(width: 70, height: 70), color: .red)
            g.position = CGPoint(x: 0, y: self.boss.bodyHeight * 0.85)
            g.zPosition = 20
            self.boss.addChild(g)
            g.run(.sequence([.scale(to: 2, duration: 0.25), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
    }

    private func swingAttack(_ p2: Bool) {
        func one(_ windup: TimeInterval) -> [SKAction] {
            [boss.raise(windup), telegraph(), .wait(forDuration: windup), .run { [weak self] in
                guard let self else { return }
                self.boss.run(.moveBy(x: 30 * self.boss.facing, y: 0, duration: 0.1))
            }, boss.slam(), .wait(forDuration: 0.06), .run { [weak self] in
                guard let self else { return }
                let sc = self.boss.xScale
                let s = FX.sprite("fx_slash", size: CGSize(width: 230 * sc, height: 120 * sc), color: self.fireColor)
                s.position = CGPoint(x: self.boss.position.x + 90 * sc * self.boss.facing, y: self.boss.position.y + self.boss.bodyHeight * 0.4 * sc)
                s.xScale = self.boss.facing
                s.zRotation = -0.4 * self.boss.facing
                s.zPosition = 2800
                self.world.addChild(s)
                s.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
                self.shake(4)
                if self.inReach(self.boss, self.player, reach: 190 * sc, depth: 60) { self.hurtPlayer(44) }
            }, .wait(forDuration: 0.4)]
        }
        bossAct(p2 ? one(0.5) + one(0.3) : one(0.55), recover: 0.7, p2: p2)
    }

    private func fireWave(_ p2: Bool) {
        let rows: [CGFloat] = p2 ? [-50, 0, 50] : [0]
        bossAct([boss.raise(0.45), telegraph(), .wait(forDuration: 0.45), boss.slam(), .wait(forDuration: 0.06), .run { [weak self] in
            guard let self else { return }
            self.shake(4)
            for off in rows {
                let y = min(max(self.player.position.y + off, self.floorLo), self.floorHi)
                let f = FX.sprite("fx_flame", size: CGSize(width: 110, height: 70), blend: .add)
                f.anchorPoint = CGPoint(x: 0.5, y: 0.05)
                f.position = CGPoint(x: self.boss.position.x + 80 * self.boss.facing, y: y)
                f.zPosition = 1000 - y + 1
                f.run(.repeatForever(.sequence([.scaleY(to: 1.25, duration: 0.1), .scaleY(to: 0.9, duration: 0.1)])))
                let trail = FX.emitter("fx_spark", rate: 50, life: 0.5, speed: 40, scale: 0.3, color: self.fireColor)
                trail.emissionAngle = .pi / 2
                trail.targetNode = self.world
                f.addChild(trail)
                self.world.addChild(f)
                self.waves.append(Wave(node: f, vx: 340 * self.boss.facing, fromPlayer: false))
            }
        }, .wait(forDuration: 0.4)], recover: 0.6, p2: p2)
    }

    private func leapAttack(_ p2: Bool) {
        let target = CGPoint(x: min(max(player.position.x, xLo), xHi), y: min(max(player.position.y, floorLo), floorHi))
        let ring = FX.sprite("fx_ring", size: CGSize(width: 300, height: 110), color: .red)
        ring.position = target
        ring.zPosition = -200
        ring.alpha = 0
        world.addChild(ring)
        ring.run(.sequence([.fadeAlpha(to: 0.9, duration: 0.2), .repeat(.sequence([.fadeAlpha(to: 0.4, duration: 0.12), .fadeAlpha(to: 0.9, duration: 0.12)]), count: 5), .removeFromParent()]))
        let flight: TimeInterval = p2 ? 0.5 : 0.6
        let move = SKAction.move(to: target, duration: flight)
        move.timingMode = .easeInEaseOut
        let jumpH = size.height * 0.35
        bossAct([
            .run { [weak self] in self?.boss.rig.pose.run(.scaleY(to: 0.88, duration: 0.3)) },
            boss.raise(0.4), .wait(forDuration: 0.35),
            .run { [weak self] in
                guard let self else { return }
                self.boss.airborne = true
                let up = SKAction.moveBy(x: 0, y: jumpH, duration: flight * 0.55); up.timingMode = .easeOut
                let down = SKAction.moveBy(x: 0, y: -jumpH, duration: flight * 0.45); down.timingMode = .easeIn
                self.boss.rig.run(.sequence([up, down]))
                self.boss.rig.pose.run(.scaleY(to: 1, duration: 0.1))
                self.boss.zPosition = 1500
            },
            move,
            boss.slam(),
            .run { [weak self] in
                guard let self else { return }
                self.boss.airborne = false
                self.boss.rig.position = .zero
                ring.removeFromParent()
                self.place(self.boss)
                self.shake(13)
                self.haptic(true)
                let burst = FX.burst("fx_spark", count: 60, life: 0.6, speed: 320, scale: 0.5, color: self.fireColor)
                burst.position = target; burst.zPosition = 2800
                self.world.addChild(burst)
                let shock = FX.sprite("fx_ring", size: CGSize(width: 120, height: 44), color: self.fireColor)
                shock.position = target; shock.zPosition = 2799
                self.world.addChild(shock)
                shock.run(.sequence([.group([.scale(to: 3, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
                let dx = (self.player.position.x - target.x) / 150, dy = (self.player.position.y - target.y) / 60
                if dx * dx + dy * dy < 1 { self.hurtPlayer(56) }
            },
            .wait(forDuration: 0.3)
        ], recover: 0.8, p2: p2)
    }

    private func staggerBoss() {
        boss.stagger = 0
        boss.removeAction(forKey: "ai")
        boss.resetPose()
        boss.busy = true
        banner("BREAK!", color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), size: 26, y: size.height * 0.72)
        boss.rig.pose.run(.sequence([.rotate(toAngle: 0.12, duration: 0.1), .wait(forDuration: 0.9), .rotate(toAngle: 0, duration: 0.2)]))
        boss.run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in
            self?.boss.busy = false
            self?.bossThink = 0.5
        }]), withKey: "ai")
    }

    // MARK: End

    private func bossDied() {
        over = true
        boss.removeAction(forKey: "ai")
        boss.resetPose()
        boss.fire.particleBirthRate = 0
        hole?.removeFromParent(); storm?.removeFromParent()
        speed = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.speed = 1 }
        flashScreen(.white, alpha: 0.8, duration: 0.6)
        shake(16)
        haptic(true)
        let c = chest(boss)
        for i in 0..<5 {
            run(.sequence([.wait(forDuration: Double(i) * 0.12), .run { [weak self] in
                self?.spark(at: CGPoint(x: c.x + CGFloat.random(in: -50...50), y: c.y + CGFloat.random(in: -60...60)),
                            color: i % 2 == 0 ? (self?.fireColor ?? .orange) : .white, scale: 1.8)
            }]))
        }
        for s in boss.rig.parts.values { s.run(.colorize(with: .white, colorBlendFactor: 1, duration: 0.4)) }
        boss.run(.sequence([.wait(forDuration: 0.4), .group([.fadeOut(withDuration: 0.8), .scaleX(to: boss.xScale * 1.15, duration: 0.8)]), .removeFromParent()]))
        run(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
            guard let self else { return }
            self.banner("VICTORY", color: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), size: 52, y: self.size.height * 0.6)
        }, .wait(forDuration: 1.6), .run { [weak self] in
            guard let self else { return }
            self.onFinish?(true, self.elapsed)
        }]))
    }

    private func playerDied() {
        over = true
        player.die()
        if demon { player.setDemon(false) }
        boss.removeAction(forKey: "ai")
        boss.resetPose()
        boss.walk(false)
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in
            guard let self else { return }
            self.banner("DEFEAT", color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), size: 52, y: self.size.height * 0.6)
        }, .wait(forDuration: 1.8), .run { [weak self] in
            guard let self else { return }
            self.onFinish?(false, self.elapsed)
        }]))
    }

    // MARK: HUD

    private func updateHUD(_ dt: CGFloat) {
        guard hpBar != nil else { return }
        hpBar.set(player.hp / player.maxHP, dt: dt)
        manaBar.set(mana / prog.maxMana, dt: dt)
        rageBar.set(demon ? demonTime / Self.demonDuration : rage / 100, dt: dt)
        bossBar.set(boss.hp / boss.maxHP, dt: dt)
        for i in 0..<3 { btns["s\(i)"]?.set(cooldown: cd[i], usable: mana >= Self.skills[i].cost) }
        btns["dodge"]?.set(cooldown: dodgeCD, usable: true)
        btns["attack"]?.set(cooldown: 0, usable: true)
        btns["demon"]?.set(cooldown: 0, usable: rage >= 100 || demon, highlight: rage >= 100 && !demon)
    }
}
