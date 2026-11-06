import SwiftUI
import SpriteKit
import UIKit

/// Loads art from the bundle (works for loose PNGs whether Xcode flattens the Art folder or not).
enum Art {
    private static var images: [String: UIImage] = [:]
    private static var textures: [String: SKTexture] = [:]

    static func image(_ name: String) -> UIImage {
        if let i = images[name] { return i }
        let img = UIImage(named: name)
            ?? Bundle.main.path(forResource: name, ofType: "png", inDirectory: "Art").flatMap(UIImage.init(contentsOfFile:))
            ?? UIImage()
        images[name] = img
        return img
    }

    static func tex(_ name: String) -> SKTexture {
        if let t = textures[name] { return t }
        let t = SKTexture(image: image(name))
        textures[name] = t
        return t
    }

    static func view(_ name: String) -> Image { Image(uiImage: image(name)) }
}

struct SaveData: Codable {
    var level = 1
    var exp = 0
    var gold = 0
    var wins = 0
    var skillLv = [1, 1, 1]
    var shake = true
    var haptics = true

    var expToNext: Int { 80 + level * 40 }
    var maxHP: CGFloat { CGFloat(420 + (level - 1) * 45) }
    var attack: CGFloat { CGFloat(22 + (level - 1) * 4) }
    var defense: CGFloat { CGFloat(6 + (level - 1) * 2) }
    var maxMana: CGFloat { CGFloat(100 + (level - 1) * 8) }
    func skillMult(_ i: Int) -> CGFloat { 1 + CGFloat(skillLv[i] - 1) * 0.15 }
    func upgradeCost(_ i: Int) -> Int { 100 * skillLv[i] }
}

struct BattleResult: Equatable {
    var won: Bool
    var exp: Int
    var gold: Int
    var levelUp: Bool
    var seconds: Int
}

enum Screen: Equatable {
    case menu, character, settings, story, battle, result(BattleResult)
}

struct StoryLine { let speaker: String; let text: String }

enum Story {
    static let demonKnight: [StoryLine] = [
        StoryLine(speaker: "", text: "Ten years ago the sky cracked open. Since then, demons walk among the ruins of humanity."),
        StoryLine(speaker: "DANIEL", text: "The grimoire is warm again... It only does that when something strong is near."),
        StoryLine(speaker: "GRIMOIRE", text: "Bearer of the Void. The Demon Knight guards the gate ahead. It remembers the one who wrote me."),
        StoryLine(speaker: "DEMON KNIGHT", text: "That book... So the void chose a human this time. I will tear it from your corpse."),
        StoryLine(speaker: "DANIEL", text: "Then come. I need answers, and you're standing in the way.")
    ]
}

final class GameState: ObservableObject {
    @Published var screen: Screen = .menu
    @Published var p: SaveData { didSet { save() } }
    private static let key = "grimoire.progress.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let pr = try? JSONDecoder().decode(SaveData.self, from: d) {
            p = pr
        } else {
            p = SaveData()
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func finishBattle(won: Bool, time: TimeInterval) {
        var exp = won ? 140 + max(0, 90 - Int(time)) : 30
        let gold = won ? 160 + p.level * 20 : 15
        p.gold += gold
        var up = false
        var pr = p
        pr.exp += exp
        while pr.exp >= pr.expToNext {
            pr.exp -= pr.expToNext
            pr.level += 1
            up = true
        }
        if won { pr.wins += 1 }
        p = pr
        exp = max(exp, 0)
        screen = .result(BattleResult(won: won, exp: exp, gold: gold, levelUp: up, seconds: Int(time)))
    }

    func upgrade(_ i: Int) {
        let c = p.upgradeCost(i)
        guard p.gold >= c, p.skillLv[i] < 10 else { return }
        p.gold -= c
        p.skillLv[i] += 1
    }

    func reset() { p = SaveData() }
}
