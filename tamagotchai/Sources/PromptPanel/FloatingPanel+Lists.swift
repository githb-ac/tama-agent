import AppKit

// Session list, tool list, and text-change tracking extracted from FloatingPanel
// to keep the main file under the SwiftLint file_length threshold.
extension FloatingPanel {
    // MARK: - Session List

    /// Shows the session history list with grouped sessions, or an empty state message.
    func showSessionList(_ groups: [(label: String, sessions: [ChatSession])], emptyMessage: String? = nil) {
        // If tab bar is already visible we're switching tabs — use instant swap to prevent jitter
        let alreadyVisible = !sessionListView.isHidden || !tabBarContainer.isHidden

        // Hide tool list if switching back from Tools tab
        toolListView.isHidden = true
        toolListHeightConstraint?.constant = 0

        // Reset response area so it doesn't ghost behind the session list
        responseScrollView.isHidden = true
        responseHeightConstraint?.constant = 0
        reachedMaxHeight = false
        lastTargetHeight = 0
        rawMarkdown = ""
        pendingMarkdown = ""
        displayedMarkdown = ""
        conversationAttributed = NSMutableAttributedString()
        conversationBaseLength = 0
        responseTextView.textStorage?.setAttributedString(NSAttributedString())
        responseTextView.removeAllCopyButtons()

        sessionListView.reload(groups: groups, emptyMessage: emptyMessage)

        // Calculate target height based on content
        let listTargetHeight: CGFloat
        if groups.isEmpty {
            listTargetHeight = 80
        } else {
            let rowHeight: CGFloat = 44
            let headerHeight: CGFloat = 28
            let padding: CGFloat = 12
            let totalItems = groups.reduce(0) { $0 + $1.sessions.count }
            let totalHeaders = groups.count
            let contentHeight = CGFloat(totalItems) * rowHeight + CGFloat(totalHeaders) * headerHeight + padding
            listTargetHeight = min(contentHeight, responseMaxHeight - tabBarHeight)
        }

        // Only reset height to 0 when first showing the list — not on tab switches
        if !alreadyVisible {
            sessionListHeightConstraint?.constant = 0
        }
        dividerContainer.isHidden = false
        tabBarContainer.isHidden = false
        sessionListView.isHidden = false
        dividerContainer.alphaValue = 1
        tabBarContainer.alphaValue = 1
        sessionListView.alphaValue = 1

        let newPanelHeight = inputHeight + 1 + tabBarHeight + listTargetHeight
        let newOriginY = topY - newPanelHeight
        let newFrame = NSRect(
            x: frame.origin.x,
            y: newOriginY,
            width: panelWidth,
            height: newPanelHeight
        )

        if alreadyVisible {
            // Instant swap for tab switches — no animation prevents vertical jitter
            sessionListHeightConstraint?.constant = listTargetHeight
            setFrame(newFrame, display: true)
            positionMascotOverSpacer()
            sessionListView.scrollToTop()
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                self.sessionListHeightConstraint?.animator().constant = listTargetHeight
                self.animator().setFrame(newFrame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated { [weak self] in
                    self?.positionMascotOverSpacer()
                    self?.sessionListView.scrollToTop()
                }
            }
        }

        invalidateShadow()
        makeFirstResponder(inputField)
    }

    /// Hides the session list, tool list, and tab bar.
    func hideSessionList() {
        guard !suppressHideSessionList else { return }

        let sessionListVisible = !sessionListView.isHidden
        let toolListVisible = !toolListView.isHidden
        let tabBarVisible = !tabBarContainer.isHidden

        guard sessionListVisible || toolListVisible || tabBarVisible else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if sessionListVisible { self.sessionListView.animator().alphaValue = 0 }
            if toolListVisible { self.toolListView.animator().alphaValue = 0 }
            if tabBarVisible { self.tabBarContainer.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                sessionListView.isHidden = true
                sessionListHeightConstraint?.constant = 0
                toolListView.isHidden = true
                toolListHeightConstraint?.constant = 0

                // If the response area is now showing (error or streaming response),
                // keep the tab bar visible — don't collapse it.
                guard responseScrollView.isHidden else {
                    invalidateShadow()
                    return
                }

                tabBarContainer.isHidden = true
                // Reset tab to "Chats" for next open
                tabBar.selectTab(0, animated: false)
                // Reset tools state
                hideToolList()
                // Collapse the divider too
                if responseScrollView.isHidden {
                    dividerContainer.isHidden = true
                    let panelFrame = NSRect(
                        x: frame.origin.x,
                        y: topY - inputHeight,
                        width: panelWidth,
                        height: inputHeight
                    )
                    setFrame(panelFrame, display: true)
                    positionMascotOverSpacer()
                }
                invalidateShadow()
            }
        }
    }

    // MARK: - Text change tracking

    func controlTextDidChange(_: Notification) {
        let text = inputField.stringValue
        if isToolsMode {
            if isInsideTool {
                activeTool?.filterContent(query: text)
            } else {
                onToolSearchChanged?(text)
            }
        } else {
            onTextChanged?(text)
        }
    }

    // MARK: - Tool List

    /// Shows the tool list (called when Tools tab is selected).
    func showToolList(tools: [PanelTool]) {
        // If tab bar is already visible we're switching tabs — use instant swap to prevent jitter
        let isTabSwitch = !tabBarContainer.isHidden

        isToolsMode = true
        isInsideTool = false
        activeTool = nil

        // Hide session list and response area
        sessionListView.isHidden = true
        sessionListHeightConstraint?.constant = 0
        responseScrollView.isHidden = true
        responseHeightConstraint?.constant = 0

        // Remove any pushed tool view
        if let activeToolView {
            activeToolView.removeFromSuperview()
            activeToolHeightConstraint = nil
            self.activeToolView = nil
        }

        // Update input field
        inputField.placeholderString = "Search tools..."
        inputField.stringValue = ""

        // Reload tool list
        toolListView.reload(tools: tools)

        let listTargetHeight: CGFloat = min(toolListView.contentHeight, responseMaxHeight - tabBarHeight)

        if !isTabSwitch {
            toolListHeightConstraint?.constant = 0
        }
        dividerContainer.isHidden = false
        tabBarContainer.isHidden = false
        toolListView.isHidden = false
        dividerContainer.alphaValue = 1
        tabBarContainer.alphaValue = 1
        toolListView.alphaValue = 1

        let newPanelHeight = inputHeight + 1 + tabBarHeight + listTargetHeight
        let newOriginY = topY - newPanelHeight
        let newFrame = NSRect(
            x: frame.origin.x,
            y: newOriginY,
            width: panelWidth,
            height: newPanelHeight
        )

        if isTabSwitch {
            // Instant swap for tab switches — no animation prevents vertical jitter
            toolListHeightConstraint?.constant = listTargetHeight
            setFrame(newFrame, display: true)
            positionMascotOverSpacer()
            toolListView.scrollToTop()
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                self.toolListHeightConstraint?.animator().constant = listTargetHeight
                self.animator().setFrame(newFrame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated { [weak self] in
                    self?.positionMascotOverSpacer()
                    self?.toolListView.scrollToTop()
                }
            }
        }

        invalidateShadow()
        makeFirstResponder(inputField)
    }

    /// Lightweight filter — only reloads the tool list data without touching the input field or frame.
    func filterToolList(tools: [PanelTool]) {
        toolListView.reload(tools: tools)
        toolListView.scrollToTop()
    }

    /// Hides the tool list (called when switching away from Tools tab).
    func hideToolList() {
        isToolsMode = false
        isInsideTool = false
        activeTool = nil

        // Remove any pushed tool view
        if let activeToolView {
            mainStack.removeArrangedSubview(activeToolView)
            activeToolView.removeFromSuperview()
            activeToolHeightConstraint = nil
            self.activeToolView = nil
        }

        toolListView.isHidden = true
        toolListHeightConstraint?.constant = 0
    }

    /// Pushes a tool's content view, replacing the tool list.
    func pushToolView(tool: PanelTool) {
        isInsideTool = true
        activeTool = tool
        inputField.placeholderString = tool.searchPlaceholder
        inputField.stringValue = ""

        // Hide the tool list
        toolListView.isHidden = true
        toolListHeightConstraint?.constant = 0

        // Create and insert the tool's view
        let view = tool.makeView()
        view.translatesAutoresizingMaskIntoConstraints = false
        activeToolView = view

        // Insert tool view in the mainStack where the tool list was
        let toolListIndex = mainStack.arrangedSubviews.firstIndex(of: toolListView) ?? 3
        mainStack.insertArrangedSubview(view, at: toolListIndex + 1)

        let targetHeight = responseMaxHeight - tabBarHeight
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: targetHeight)
        heightConstraint.isActive = true
        activeToolHeightConstraint = heightConstraint

        let newPanelHeight = inputHeight + 1 + tabBarHeight + targetHeight
        let newOriginY = topY - newPanelHeight
        let newFrame = NSRect(
            x: frame.origin.x,
            y: newOriginY,
            width: panelWidth,
            height: newPanelHeight
        )

        // Instant swap — panel is already expanded from the tool list
        setFrame(newFrame, display: true)
        positionMascotOverSpacer()
        invalidateShadow()
        makeFirstResponder(inputField)
    }

    /// Pops back from a tool's drilled-in view to the tool list.
    func popToolView() {
        guard isInsideTool else { return }

        // Remove the active tool view
        if let activeToolView {
            mainStack.removeArrangedSubview(activeToolView)
            activeToolView.removeFromSuperview()
            activeToolHeightConstraint = nil
            self.activeToolView = nil
        }

        isInsideTool = false
        activeTool = nil

        // Re-show the tool list
        showToolList(tools: PanelToolRegistry.shared.search(query: ""))
    }
}
