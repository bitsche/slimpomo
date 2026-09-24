import Foundation

enum BreakMessages {
    /// Things that fit in a chair, for the 5-minute break.
    static let five = [
        "Unclench your jaw and soften your face",
        "Roll your shoulders and let them drop",
        "Close your eyes and count three breaths",
        "Stretch your neck gently from side to side",
        "Shake out your hands and wrists",
        "Rest your eyes on something far away",
        "Put both feet flat on the floor",
        "Let your arms hang loose for a moment",
        "Loosen your grip and rest your hands",
        "Take one longer breath out than in",
        "Sit back and let your breath settle",
        "Wiggle your toes and relax your feet",
        "Notice five things you can see right now",
        "Look out of the window and relax",
        "Give your eyes a break from the display",
        "Smile at nothing in particular",
        "Listen for the quietest sound in the room",
        "Drink a few sips of water",
        "Soften your brow and unfocus your eyes",
        "Do nothing at all for the rest of this break",
    ]

    /// A short errand away from the chair, for the 10-minute break.
    static let ten = [
        "Stand up and stretch for a moment",
        "Get a glass of water",
        "Make a cup of tea",
        "Walk to another room and back",
        "Step away from the screen for a bit",
        "Tidy one small thing nearby",
        "Look at the sky for a few seconds",
        "Take a slow walk around the room",
        "Open a window and take a breath of air",
        "Look at a plant, a photo, or the daylight",
        "Wash your hands and come back slowly",
        "Refill your glass and drink it away from the desk",
        "Stretch your back and shake out your legs",
        "Make a small snack",
        "Walk to the kitchen and back",
        "Air the room and stand by the window",
        "Put something away that has been sitting out",
        "Step into another room and stay there a minute",
        "Roll out your wrists, then your ankles",
        "Drink some water before you sit down again",
    ]

    /// Enough time to leave, for the 15-minute break.
    static let fifteen = [
        "Take a short walk",
        "Walk around the block if you can",
        "Step outside and look at the sky",
        "Make tea and drink it away from your desk",
        "Have a small snack somewhere else",
        "Walk up and down the stairs slowly",
        "Leave the screen and read a page of something else",
        "Tidy one corner of the room",
        "Go outside and walk to the end of the street",
        "Sit by a window in another room",
        "Take the long way to get a glass of water",
        "Do a longer stretch on the floor",
        "Open the door and get a few minutes of air",
        "Walk to the farthest room and back twice",
        "Prepare something small to eat",
        "Look at daylight from somewhere that is not your chair",
        "Take a short walk and come back when you are ready",
        "Water a plant, then stay away from the desk a little longer",
        "Message someone, then stand up while you wait",
        "Do nothing at all, somewhere that is not your chair",
    ]

    static func pick(breakDuration: TimeInterval, avoiding previous: String? = nil) -> String {
        let pool = pool(for: breakDuration)
        let choices = pool.filter { $0 != previous }
        return (choices.isEmpty ? pool : choices).randomElement() ?? pool[0]
    }

    private static func pool(for breakDuration: TimeInterval) -> [String] {
        let minutes = Int((breakDuration / 60).rounded())
        if minutes >= 13 {
            return fifteen
        }
        if minutes >= 8 {
            return ten
        }
        return five
    }
}
