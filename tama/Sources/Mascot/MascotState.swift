import Foundation

/// The different animation states for the mascot.
/// Each state maps to an animation name in the faces.riv Rive file.
enum MascotState: String, CaseIterable {
    /// Default — mascot is idle, gently breathing/blinking.
    case idle
    /// User is typing in the prompt field.
    case typing
    /// Prompt submitted, waiting for AI response.
    case waiting
    /// AI response is streaming in.
    case responding
    /// Mascot is thinking/concerned.
    case thinking
    /// Mascot is happy/pleased.
    case happy
}
