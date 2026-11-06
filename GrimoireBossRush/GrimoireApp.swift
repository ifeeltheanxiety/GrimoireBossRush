import SwiftUI
import SpriteKit

@main
struct GrimoireApp: App {
    @StateObject private var state = GameState()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: GameState
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state.screen {
            case .menu: MenuView()
            case .character: CharacterView()
            case .settings: SettingsView()
            case .story: StoryView(lines: Story.demonKnight)
            case .battle: BattleView()
            case .result(let r): ResultView(result: r)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: state.screen)
    }
}

// MARK: - Shared UI

let voidPurple = Color(red: 0.65, green: 0.35, blue: 1)
let titleGradient = LinearGradient(colors: [.white, Color(red: 0.8, green: 0.7, blue: 1), Color(red: 0.55, green: 0.3, blue: 0.95)],
                                   startPoint: .top, endPoint: .bottom)

extension Font {
    static func fantasy(_ size: CGFloat) -> Font { .custom("Copperplate-Bold", size: size) }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GameButton: View {
    let title: String
    var width: CGFloat = 250
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Art.view("ui_panel").resizable()
                Text(title)
                    .font(.fantasy(width * 0.075))
                    .foregroundStyle(titleGradient)
                    .shadow(color: voidPurple, radius: 6)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, width * 0.1)
            }
            .frame(width: width, height: width * 140 / 720)
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// Daniel assembled from the same part textures the battle rig uses.
struct DanielPortrait: View {
    var demon = false
    @State private var t = false
    var body: some View {
        ZStack {
            if demon { part("daniel_wings").scaleEffect(t ? 1.0 : 0.95, anchor: UnitPoint(x: 0.51, y: 0.38)) }
            part("daniel_cape").rotationEffect(.degrees(t ? 2 : -1), anchor: UnitPoint(x: 232 / 512, y: 232 / 768))
            part("daniel_body")
            part("daniel_head").rotationEffect(.degrees(t ? -1.5 : 0.5), anchor: UnitPoint(x: 262 / 512, y: 205 / 768))
            if demon { part("daniel_eyes").blendMode(.plusLighter) }
            ZStack {
                part("daniel_sword_glow").blendMode(.plusLighter).opacity(t ? 1 : 0.4)
                part("daniel_arm")
            }
            .rotationEffect(.degrees(t ? -4 : 2), anchor: UnitPoint(x: 302 / 512, y: 248 / 768))
        }
        .aspectRatio(512 / 768, contentMode: .fit)
        .scaleEffect(y: t ? 1.01 : 1, anchor: .bottom)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { t = true } }
    }
    private func part(_ n: String) -> some View { Art.view(n).resizable().aspectRatio(contentMode: .fit) }
}

final class AmbientScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        let smoke = FX.emitter("fx_smoke", rate: 10, life: 4, speed: 30, scale: 1.4, color: UIColor(red: 0.25, green: 0.08, blue: 0.45, alpha: 1))
        smoke.position = CGPoint(x: size.width * 0.3, y: -20)
        smoke.particlePositionRange = CGVector(dx: size.width * 0.6, dy: 10)
        smoke.emissionAngle = .pi / 2; smoke.emissionAngleRange = 0.5
        smoke.particleAlpha = 0.35; smoke.particleAlphaSpeed = -0.08; smoke.particleScaleSpeed = 0.2
        smoke.particleBlendMode = .alpha
        smoke.advanceSimulationTime(4)
        addChild(smoke)
        let motes = FX.emitter("fx_spark", rate: 18, life: 5, speed: 22, scale: 0.2, color: UIColor(red: 0.75, green: 0.5, blue: 1, alpha: 1))
        motes.position = CGPoint(x: size.width / 2, y: size.height * 0.3)
        motes.particlePositionRange = CGVector(dx: size.width, dy: size.height * 0.6)
        motes.emissionAngle = .pi / 2; motes.emissionAngleRange = 1
        motes.particleAlphaSpeed = -0.15; motes.particleScaleSpeed = 0
        motes.advanceSimulationTime(5)
        addChild(motes)
    }
}

struct Backdrop: View {
    var name = "bg_menu"
    var dim: Double = 0
    @State private var scene: AmbientScene = {
        let s = AmbientScene(size: CGSize(width: 900, height: 420))
        s.scaleMode = .resizeFill
        return s
    }()
    var body: some View {
        ZStack {
            Art.view(name).resizable().scaledToFill()
            Color.black.opacity(dim)
            SpriteView(scene: scene, options: [.allowsTransparency]).allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Menu

struct MenuView: View {
    @EnvironmentObject var state: GameState
    @State private var glow = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Backdrop()
                HStack(spacing: 0) {
                    ZStack {
                        Circle().fill(voidPurple.opacity(glow ? 0.35 : 0.15)).blur(radius: 50).frame(width: geo.size.height * 0.8)
                        DanielPortrait().frame(height: geo.size.height * 1.05)
                    }
                    .frame(width: geo.size.width * 0.45)
                    .offset(y: geo.size.height * 0.08)
                    VStack(spacing: 10) {
                        Text("GRIMOIRE")
                            .font(.fantasy(min(64, geo.size.width * 0.075)))
                            .foregroundStyle(titleGradient)
                            .shadow(color: voidPurple.opacity(0.9), radius: glow ? 18 : 8)
                        Text("BOSS RUSH")
                            .font(.fantasy(20)).tracking(10)
                            .foregroundColor(Color(red: 1, green: 0.55, blue: 0.5))
                            .shadow(color: .red, radius: 6)
                        Spacer().frame(height: 14)
                        GameButton(title: "START BATTLE") { state.screen = .story }
                        GameButton(title: "CHARACTER") { state.screen = .character }
                        GameButton(title: "SETTINGS") { state.screen = .settings }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true } }
    }
}

// MARK: - Character

struct CharacterView: View {
    @EnvironmentObject var state: GameState
    var body: some View {
        let p = state.p
        GeometryReader { geo in
            ZStack {
                Backdrop(dim: 0.45)
                HStack(spacing: 20) {
                    DanielPortrait().frame(height: geo.size.height * 0.95).frame(width: geo.size.width * 0.32)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DANIEL").font(.fantasy(30)).foregroundStyle(titleGradient)
                        Text("Bearer of the Void Grimoire").font(.system(size: 12, weight: .medium, design: .serif)).foregroundColor(.gray)
                        HStack(spacing: 18) {
                            stat("LEVEL", "\(p.level)")
                            stat("EXP", "\(p.exp)/\(p.expToNext)")
                            stat("GOLD", "\(p.gold)")
                        }
                        HStack(spacing: 18) {
                            stat("HP", "\(Int(p.maxHP))"); stat("ATTACK", "\(Int(p.attack))")
                            stat("DEFENSE", "\(Int(p.defense))"); stat("MANA", "\(Int(p.maxMana))")
                        }
                        Text("VOID ARTS").font(.fantasy(14)).foregroundColor(voidPurple).padding(.top, 6)
                        ForEach(0..<3, id: \.self) { i in
                            HStack {
                                Art.view(BattleScene.skills[i].tex).resizable().frame(width: 34, height: 34)
                                Text("\(BattleScene.skills[i].name)  Lv.\(p.skillLv[i])").font(.fantasy(14)).foregroundColor(.white)
                                Spacer()
                                GameButton(title: p.skillLv[i] >= 10 ? "MAX" : "UPGRADE \(p.upgradeCost(i))G", width: 170,
                                           enabled: p.gold >= p.upgradeCost(i) && p.skillLv[i] < 10) { state.upgrade(i) }
                            }
                        }
                        GameButton(title: "BACK", width: 170) { state.screen = .menu }.padding(.top, 4)
                    }
                    .frame(maxWidth: 480)
                }
                .padding(.horizontal, 30)
            }
        }
    }
    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            Text(v).font(.fantasy(17)).foregroundColor(.white)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: GameState
    @State private var confirmReset = false
    var body: some View {
        ZStack {
            Backdrop(dim: 0.5)
            VStack(spacing: 10) {
                Text("SETTINGS").font(.fantasy(34)).foregroundStyle(titleGradient).shadow(color: voidPurple, radius: 8)
                GameButton(title: "SCREEN SHAKE: \(state.p.shake ? "ON" : "OFF")", width: 300) { state.p.shake.toggle() }
                GameButton(title: "VIBRATION: \(state.p.haptics ? "ON" : "OFF")", width: 300) { state.p.haptics.toggle() }
                GameButton(title: confirmReset ? "TAP AGAIN TO ERASE" : "RESET PROGRESS", width: 300) {
                    if confirmReset { state.reset(); confirmReset = false } else { confirmReset = true }
                }
                GameButton(title: "BACK", width: 200) { state.screen = .menu }
            }
        }
    }
}

// MARK: - Story

struct StoryView: View {
    @EnvironmentObject var state: GameState
    let lines: [StoryLine]
    @State private var index = 0
    @State private var shown = 0

    var body: some View {
        let line = lines[index]
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Backdrop(name: "bg_arena", dim: 0.35)
                HStack(alignment: .bottom) {
                    DanielPortrait().frame(height: geo.size.height * 0.95)
                        .opacity(line.speaker == "DANIEL" ? 1 : 0.55)
                        .offset(x: -20, y: geo.size.height * 0.15)
                    Spacer()
                    Art.view("knight_full").resizable().aspectRatio(contentMode: .fit)
                        .scaleEffect(x: -1, y: 1)
                        .frame(height: geo.size.height * 1.05)
                        .opacity(line.speaker == "DEMON KNIGHT" ? 1 : 0.55)
                        .offset(x: 20, y: geo.size.height * 0.15)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !line.speaker.isEmpty {
                        Text(line.speaker).font(.fantasy(18))
                            .foregroundColor(line.speaker == "DEMON KNIGHT" ? Color(red: 1, green: 0.45, blue: 0.4) : voidPurple)
                    }
                    Text(String(line.text.prefix(shown)))
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                }
                .padding(.horizontal, 34).padding(.vertical, 16)
                .background(Art.view("ui_panel").resizable())
                .frame(maxWidth: 720)
                .padding(.bottom, 14)
                VStack {
                    HStack {
                        Spacer()
                        GameButton(title: "SKIP", width: 120) { state.screen = .battle }
                    }
                    Spacer()
                }
                .padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture { advance() }
        }
        .task(id: index) {
            shown = 0
            let n = lines[index].text.count
            while shown < n {
                try? await Task.sleep(nanoseconds: 22_000_000)
                shown += 1
            }
        }
    }

    private func advance() {
        if shown < lines[index].text.count { shown = lines[index].text.count; return }
        if index + 1 < lines.count { index += 1 } else { state.screen = .battle }
    }
}

// MARK: - Battle

struct BattleView: View {
    @EnvironmentObject var state: GameState
    @State private var scene: BattleScene?
    @State private var paused = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60).ignoresSafeArea()
                }
                VStack {
                    Button { paused = true; scene?.setPaused(true) } label: {
                        Art.view("ui_joy_knob").resizable().frame(width: 40, height: 40)
                            .overlay(Text("II").font(.fantasy(14)).foregroundColor(.white))
                    }
                    .buttonStyle(PressStyle())
                    Spacer()
                }
                .padding(.top, 6)
                if paused {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 10) {
                        Text("PAUSED").font(.fantasy(34)).foregroundStyle(titleGradient)
                        GameButton(title: "RESUME") { paused = false; scene?.setPaused(false) }
                        GameButton(title: "RETREAT") { state.screen = .menu }
                    }
                }
            }
            .onAppear {
                guard scene == nil else { return }
                let ins = geo.safeAreaInsets
                let full = CGSize(width: geo.size.width + ins.leading + ins.trailing, height: geo.size.height + ins.top + ins.bottom)
                let s = BattleScene(size: full, progress: state.p,
                                    safe: UIEdgeInsets(top: ins.top, left: ins.leading, bottom: ins.bottom, right: ins.trailing))
                let st = state
                s.onFinish = { won, t in DispatchQueue.main.async { st.finishBattle(won: won, time: t) } }
                scene = s
            }
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @EnvironmentObject var state: GameState
    let result: BattleResult
    @State private var appear = false
    var body: some View {
        ZStack {
            Backdrop(name: result.won ? "bg_menu" : "bg_arena", dim: 0.5)
            HStack(spacing: 30) {
                if result.won {
                    DanielPortrait(demon: true).frame(height: 330)
                } else {
                    Art.view("knight_full").resizable().aspectRatio(contentMode: .fit).scaleEffect(x: -1, y: 1).frame(height: 330)
                }
                VStack(spacing: 10) {
                    Text(result.won ? "VICTORY" : "DEFEAT")
                        .font(.fantasy(60))
                        .foregroundStyle(result.won ? titleGradient
                                         : LinearGradient(colors: [.white, .red], startPoint: .top, endPoint: .bottom))
                        .shadow(color: result.won ? voidPurple : .red, radius: 14)
                        .scaleEffect(appear ? 1 : 1.6).opacity(appear ? 1 : 0)
                    Text(result.won ? "The Demon Knight falls. The grimoire whispers a name: ABYSS LORD."
                                    : "The void recedes... Rise again, Daniel.")
                        .font(.system(size: 14, weight: .medium, design: .serif)).foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                    HStack(spacing: 24) {
                        reward("EXP", "+\(result.exp)")
                        reward("GOLD", "+\(result.gold)")
                        reward("TIME", "\(result.seconds)s")
                    }
                    if result.levelUp {
                        Text("LEVEL UP!  Lv.\(state.p.level)").font(.fantasy(22)).foregroundColor(Color(red: 1, green: 0.85, blue: 0.4))
                    }
                    HStack {
                        GameButton(title: "FIGHT AGAIN", width: 200) { state.screen = .battle }
                        GameButton(title: "MENU", width: 200) { state.screen = .menu }
                    }
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true } }
    }
    private func reward(_ k: String, _ v: String) -> some View {
        VStack {
            Text(k).font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            Text(v).font(.fantasy(22)).foregroundColor(.white)
        }
    }
}
