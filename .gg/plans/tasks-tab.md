# Tasks Tab Feature

## Overview
Add a "Tasks" tab (between Routines and Tools) that shows task lists as sessions. Each task list has a title and checklist items that can be toggled manually or by the agent via a new `task` tool.

## Architecture

### Data Model — `tamagotchai/Sources/Tasks/TaskItem.swift`
- `TaskItem`: `Codable, Identifiable` — `id: UUID`, `title: String`, `isCompleted: Bool`
- `TaskList`: `Codable, Identifiable` — `id: UUID`, `title: String`, `items: [TaskItem]`, `createdAt: Date`, `updatedAt: Date`, `moodIcon: String`

### Persistence — `tamagotchai/Sources/Tasks/TaskStore.swift`
- `@MainActor final class TaskStore` — singleton like `SessionStore`
- Stores as JSON files in `~/Library/Application Support/Tamagotchai/tasks/`
- Methods: `loadAll()`, `save(taskList:)`, `delete(id:)`, `taskList(for:)`, `allTaskListsGroupedByDate()`
- Logging: category `"tasks"`

### Task List Detail View — `tamagotchai/Sources/Tasks/TaskDetailView.swift`
- `final class TaskDetailView: NSView` — scrollable list of checkbox rows
- Each row: checkbox (NSButton) + label (NSTextField)
- Toggling a checkbox updates the `TaskItem.isCompleted` and saves via `TaskStore`
- Callbacks: `onToggleItem: ((UUID, UUID, Bool) -> Void)?` (taskListId, itemId, newState)

### Tasks List View — `tamagotchai/Sources/Tasks/TaskListView.swift`
- Reuses the same pattern as `SessionListView` — grouped by date, shows task list titles with mood icons
- Callbacks: `onSelectTaskList`, `onDeleteTaskList`

### Agent Tool — `tamagotchai/Sources/AI/Tools/TaskTool.swift`
- Tool name: `"task"`
- Operations via `action` parameter:
  - `"create"` — requires `title: String`, `items: [String]` → creates a new TaskList
  - `"update"` — requires `title: String` (to find the list), optional `add_items: [String]`, `remove_items: [String]`, `check_items: [String]`, `uncheck_items: [String]`
  - `"delete"` — requires `title: String`, optional `items: [String]` (delete specific items; if omitted, deletes entire list)
- Returns JSON success/error response
- Registered in `ToolRegistry.defaultRegistry()`

### Tab Integration

**`SessionListView.swift` line 4** — Add `.tasks` case:
```swift
enum SessionTab: Int {
    case chats = 0
    case reminders = 1
    case routines = 2
    case tasks = 3
    case tools = 4
}
```

**`FloatingPanel.swift` line 147** — Update tab labels:
```swift
labels: ["Chats", "Reminders", "Routines", "Tasks", "Tools"]
```

**`FloatingPanel.swift`** — Add:
- `lazy var taskListView: TaskListView` (like `sessionListView`)
- `var taskListHeightConstraint: NSLayoutConstraint?`
- `var taskDetailView: TaskDetailView?` + height constraint
- `var isTasksMode: Bool`
- Callbacks: `onSelectTaskList`, `onDeleteTaskList`
- Add `taskListView` to `mainStack` (after `toolListView`, before `responseScrollView`)

**`FloatingPanel+Lists.swift`** — Add:
- `showTaskList(_ groups:emptyMessage:)` — mirrors `showSessionList`
- `hideTaskList()` — mirrors `hideToolList`  
- `showTaskDetail(taskList:)` — pushes the detail view replacing the task list
- `popTaskDetail()` — pops back to task list
- Update `showSessionList` to hide taskListView
- Update `showToolList` to hide taskListView
- Update `hideSessionList` to also hide taskListView and reset tab index to 0

**`PromptPanelController.swift`** — Update:
- `handleTabChanged` — add `.tasks` case that calls `showTaskList`
- Wire up `onSelectTaskList` and `onDeleteTaskList` callbacks in `ensurePanel()`
- Handle ESC from task detail (pop back to task list)

**`FloatingPanel.swift` sendEvent** — Handle ESC from task detail view (similar to tool drill-in)

## Files Changed
- **New**: `tamagotchai/Sources/Tasks/TaskItem.swift`
- **New**: `tamagotchai/Sources/Tasks/TaskStore.swift`
- **New**: `tamagotchai/Sources/Tasks/TaskListView.swift`
- **New**: `tamagotchai/Sources/Tasks/TaskDetailView.swift`
- **New**: `tamagotchai/Sources/AI/Tools/TaskTool.swift`
- **Modified**: `tamagotchai/Sources/PromptPanel/SessionListView.swift` (SessionTab enum)
- **Modified**: `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` (tab labels, new views, callbacks)
- **Modified**: `tamagotchai/Sources/PromptPanel/FloatingPanel+Lists.swift` (show/hide task list)
- **Modified**: `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` (tab handling, callbacks)
- **Modified**: `tamagotchai/Sources/AI/Tools/AgentTool.swift` (register TaskTool)

## Risks
- Adding a 5th tab may crowd the tab bar — PaddedTabButton uses 12px horizontal padding which should accommodate it
- Task detail view ESC handling needs to coexist with existing escape logic (tool drill-in, session back, interrupt)

## Verification
- Build: `xcodegen generate && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build`
- Lint: `swiftlint lint --config .swiftlint.yml`
- Format: `swiftformat --lint --config .swiftformat tamagotchai/Sources`

## Steps
1. Create `tamagotchai/Sources/Tasks/TaskItem.swift` with `TaskItem` and `TaskList` model types
2. Create `tamagotchai/Sources/Tasks/TaskStore.swift` with singleton persistence store for task lists
3. Create `tamagotchai/Sources/Tasks/TaskListView.swift` — grouped list view matching SessionListView pattern
4. Create `tamagotchai/Sources/Tasks/TaskDetailView.swift` — checkbox list detail view for a single task list
5. Create `tamagotchai/Sources/AI/Tools/TaskTool.swift` — agent tool with create/update/delete actions
6. Register `TaskTool` in `ToolRegistry.defaultRegistry()` in `tamagotchai/Sources/AI/Tools/AgentTool.swift`
7. Update `SessionTab` enum in `SessionListView.swift` to add `.tasks = 3` and shift `.tools = 4`
8. Update `FloatingPanel.swift` — add tab label "Tasks", add taskListView/taskDetailView properties, callbacks, mainStack integration, and ESC handling
9. Update `FloatingPanel+Lists.swift` — add `showTaskList`, `hideTaskList`, `showTaskDetail`, `popTaskDetail` methods; update existing show/hide methods to handle task views
10. Update `PromptPanelController.swift` — handle `.tasks` tab in `handleTabChanged`, wire up task list callbacks in `ensurePanel()`
11. Run `xcodegen generate` and build to verify compilation
12. Run swiftlint and swiftformat to ensure code quality
