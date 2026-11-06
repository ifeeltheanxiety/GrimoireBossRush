# GRIMOIRE: BOSS RUSH — v0.1 (первый играбельный бой)

Swift · SwiftUI · SpriteKit · iOS 16+ · landscape · офлайн · сохранение в UserDefaults.

## Запуск
1. Нужен Mac с **Xcode 16+** (проект использует папку-синхронизацию Xcode 16).
2. Открыть `GrimoireBossRush.xcodeproj` → Target → Signing → выбрать свою Team.
3. Запустить на iPhone или симуляторе (Cmd+R).

## Файлы
| Файл | Что внутри |
|---|---|
| `GrimoireApp.swift` | App, меню, персонаж, настройки, сюжетная сцена, экран битвы/паузы, победа/поражение |
| `BattleScene.swift` | Бой: управление, HUD, способности, Demon Form, ИИ босса, урон, эффекты |
| `Actors.swift` | Риг персонажей (cut-out анимация), Daniel, Demon Knight, частицы |
| `GameData.swift` | Прогресс, уровни, золото, улучшения, сюжет, загрузка арта |
| `Art/` | Все текстуры (PNG) |
| `tools/make_art.py` | Генератор текущих placeholder-текстур |

## Управление
Джойстик слева (плавающий) · ATTACK (удержание = комбо из 3 ударов) · VOID SLASH · BLACK HOLE · ABYSSAL STORM · DODGE (неуязвимость) · DEMON FORM (когда заполнена фиолетовая шкала ярости).

## Замена арта (важно)
Текущий арт — стилизованный cel-shaded placeholder, сгенерированный кодом. Для настоящей anime-графики замените PNG **с теми же именами и размерами холста**. Каждая часть персонажа рисуется на ОБЩЕМ холсте в своей позиции — тогда всё встаёт на место без правок кода.

| Файл | Холст | Содержимое / точка вращения (px) |
|---|---|---|
| daniel_cape | 512×768 | плащ, вращение у плеч (232,232) |
| daniel_body | 512×768 | торс, ноги, задняя рука, эмблема гримуара; ступни (262,740) |
| daniel_head | 512×768 | голова + волосы, шея (262,205) |
| daniel_eyes | 512×768 | только фиолетовое свечение глаз |
| daniel_arm | 512×768 | передняя рука + чёрный меч, плечо (302,248) |
| daniel_sword_glow | 512×768 | фиолетовое свечение клинка |
| daniel_wings | 512×768 | демонические крылья, центр (262,290) |
| knight_body | 768×1024 | Demon Knight без правой руки; ступни (384,1000) |
| knight_arm | 768×1024 | рука + огненный меч, плечо (476,318) |
| bg_arena / bg_menu | 1792×828 | фоны; пол начинается на 56% высоты |
| btn_* | 256×256 | круглые кнопки способностей |
| ui_panel 720×140, ui_bar_frame 1024×80, ui_joy_base 320, ui_joy_knob 160 | | интерфейс |

Персонажи смотрят **вправо**, фон прозрачный. Пример промпта для генератора изображений:
*"Full body anime fantasy knight, young man 25 years old, messy black hair, serious grey-violet eyes, black magic knight armor and long dark cape, purple glowing grimoire sigil on chest, black sword, side 3/4 view facing right, cel shading, dark fantasy, rim light violet, transparent background"* — затем разрезать на части по таблице.

## Дальше (v0.2)
Босс 2 — ABYSS LORD (2 фазы), звук/музыка, экран выбора босса.
