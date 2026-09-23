import Foundation

enum BreakMessages {
    static let all = [
        "Maybe time for some breathing exercise",
        "Look out of the window and relax",
        "Roll your shoulders and let them drop",
        "Stand up and stretch for a moment",
        "Get a glass of water",
        "Rest your eyes on something far away",
        "Take a slow walk around the room",
        "Unclench your jaw and soften your face",
        "Step away from the screen for a bit",
        "Notice five things you can see right now",
        "Shake out your hands and wrists",
        "Open a window and take a breath of air",
        "Sit back and let your breath settle",
        "Look at the sky for a few seconds",
        "Make a cup of tea",
        "Wiggle your toes and relax your feet",
        "Put both feet flat on the floor",
        "Close your eyes and count three breaths",
        "Stretch your neck gently from side to side",
        "Tidy one small thing nearby",
        "Smile at nothing in particular",
        "Let your arms hang loose for a moment",
        "Listen for the quietest sound in the room",
        "Drink some water before you sit down again",
        "Look at a plant, a photo, or the daylight",
        "Loosen your grip and rest your hands",
        "Take one longer breath out than in",
        "Walk to another room and back",
        "Give your eyes a break from the display",
        "Do nothing at all for the rest of this break",
    ]

    static func pick() -> String {
        all.randomElement() ?? all[0]
    }
}
