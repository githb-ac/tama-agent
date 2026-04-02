import AppKit
import Carbon.HIToolbox
import os

/// Manages the floating prompt panel lifecycle and global hotkey registration.
@MainActor
final class PromptPanelController {
    static let shared = PromptPanelController()
    private let logger = Logger(subsystem: "com.unstablemind.tamagotchai", category: "hotkey")

    private var panel: FloatingPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var conversationHistory: [[String: Any]] = []
    private lazy var agentLoop = AgentLoop(
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
    )

    // MARK: - Public

    /// Registers the global hotkey.
    /// Default shortcut: ⌥ + Space (Option + Space).
    func register(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey)
    ) {
        registerCarbonHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    /// Unregisters the hotkey and cleans up.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Toggles the panel visibility.
    func toggle() {
        if let panel, panel.isVisible {
            panel.dismiss()
        } else {
            showPanel()
        }
    }

    // MARK: - Panel

    private func showPanel() {
        if panel == nil {
            let newPanel = FloatingPanel()
            newPanel.onSubmit = { [weak self] text in
                self?.handleSubmit(text)
            }
            newPanel.onTextChanged = { [weak newPanel] text in
                if text.isEmpty {
                    newPanel?.mascot.setState(.idle)
                } else {
                    newPanel?.mascot.notifyKeystroke()
                }
            }
            panel = newPanel
        }

        conversationHistory = []
        panel?.present()
    }

    private func handleSubmit(_ text: String) {
        panel?.mascot.setState(.waiting)

        guard ClaudeService.shared.isLoggedIn else {
            panel?.mascot.setState(.idle)
            panel?.showResponse(
                "Not logged in to Claude. Use the menu bar → Login to Claude."
            )
            return
        }

        conversationHistory.append(["role": "user", "content": text])

        // Bridge AgentLoop events into an AsyncThrowingStream for the panel
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: String.self
        )

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let updatedHistory = try await agentLoop.run(
                    messages: conversationHistory,
                    systemPrompt: agentSystemPrompt,
                    onEvent: { [weak self] event in
                        switch event {
                        case let .textDelta(delta):
                            // Hide tool indicator once text resumes after a tool
                            DispatchQueue.main.async {
                                self?.panel?.hideToolIndicator()
                            }
                            continuation.yield(delta)
                        case let .toolStart(name, _):
                            // Insert a line break so text before the tool
                            // doesn't merge with text after it
                            continuation.yield("\n\n")
                            DispatchQueue.main.async {
                                self?.panel?.showToolIndicator(name: name)
                            }
                        case .toolResult:
                            break
                        case .turnComplete:
                            DispatchQueue.main.async {
                                self?.panel?.hideToolIndicator()
                            }
                            continuation.finish()
                        case let .error(msg):
                            DispatchQueue.main.async {
                                self?.panel?.hideToolIndicator()
                            }
                            continuation.yield("\n⚠️ \(msg)\n")
                        }
                    }
                )
                conversationHistory = updatedHistory
            } catch {
                continuation.finish(throwing: error)
            }
        }

        Task { @MainActor [weak self] in
            guard let self, let panel else { return }

            do {
                _ = try await panel.streamResponse(stream)
            } catch {
                conversationHistory.removeLast()
                panel.showResponse(
                    "Error: \(error.localizedDescription)"
                )
                panel.mascot.setState(.idle)
            }
        }
    }

    private var agentSystemPrompt: String {
        let cwd = FileManager.default
            .homeDirectoryForCurrentUser.path
        return """
        you have access to tools for working with the user's computer. \
        you can run shell commands (bash), read/write/edit files, \
        search code (grep/find), list directories (ls), and fetch web \
        pages. working directory: \(cwd)
        """
    }

    // MARK: - Carbon Hot Key

    private func registerCarbonHotKey(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("TGCH"),
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                Task { @MainActor in
                    PromptPanelController.shared.toggle()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard handlerResult == noErr else {
            logger.error("Failed to install hotkey handler")
            return
        }

        let registerResult = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerResult != noErr {
            logger.error("Failed to register hotkey")
        }
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
