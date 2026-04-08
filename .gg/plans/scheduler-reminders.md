# Scheduler & Reminders System for Tamagotchai

## Overview

Port the reminder/routine scheduling system from pocket-agent into tamagotchai as native Swift. The agent gets tools to create reminders (simple notifications) and routines (LLM-triggered tasks), list them, and delete them. A background scheduler polls for due jobs and fires macOS notifications or re-invokes the agent loop.

## Architecture

### Storage
- **JSON file** in `~/Library/Application Support/Tamagotchai/schedules.json` — follows the existing pattern from `ClaudeCredentials.swift` (line 44-50). No new dependencies needed.
- `Codable` structs for `ScheduledJob` persisted as an array.

### Components

1. **`ScheduleStore`** (`tamagotchai/Sources/Scheduler/ScheduleStore.swift`)
   - Singleton, `@MainActor`
   - CRUD operations on `ScheduledJob` array
   - JSON file persistence (load/save)
   - `Timer` polling every 30s for due jobs
   - On due: reminders → macOS notification; routines → invoke agent loop

2. **`ScheduleParser`** (`tamagotchai/Sources/Scheduler/ScheduleParser.swift`)
   - Port of pocket-agent's `cron.ts` `parseSchedule()` + `parseDateTime()` + `calculateNextRun()`
   - Supports: bare durations ("30m"), "every 2h", "tomorrow 3pm", "in 10 minutes", cron expressions

3. **`CreateReminderTool`** (`tamagotchai/Sources/AI/Tools/CreateReminderTool.swift`)
   - Agent tool: name, schedule, message → creates a `ScheduledJob` with `jobType: .reminder`

4. **`CreateRoutineTool`** (`tamagotchai/Sources/AI/Tools/CreateRoutineTool.swift`)
   - Agent tool: name, schedule, prompt → creates a `ScheduledJob` with `jobType: .routine`

5. **`ListSchedulesTool`** (`tamagotchai/Sources/AI/Tools/ListSchedulesTool.swift`)
   - Lists all active schedules with next run times

6. **`DeleteScheduleTool`** (`tamagotchai/Sources/AI/Tools/DeleteScheduleTool.swift`)
   - Deletes a schedule by name

### Data Model

```swift
struct ScheduledJob: Codable, Identifiable {
    let id: UUID
    var name: String
    var jobType: JobType           // .reminder or .routine
    var scheduleType: ScheduleType // .at, .every, .cron
    var schedule: String?          // cron expression (for .cron type)
    var runAt: Date?               // absolute time (for .at type)
    var intervalSeconds: Int?      // interval (for .every type)
    var prompt: String             // message (reminder) or LLM prompt (routine)
    var nextRunAt: Date?
    var deleteAfterRun: Bool       // true for one-shot (.at type)
    var enabled: Bool
    var createdAt: Date
    
    enum JobType: String, Codable { case reminder, routine }
    enum ScheduleType: String, Codable { case at, every, cron }
}
```

### Notification Delivery

- **Reminders**: `UNUserNotificationCenter` → macOS banner notification with the message. Also show in the panel if open.
- **Routines**: Create a fresh `AgentLoop`, run the prompt, show response in panel + notification.
- Request notification authorization on app launch in `AppDelegate.applicationDidFinishLaunching`.

### Integration Points

- **`ToolRegistry.defaultRegistry()`** (AgentTool.swift:55-67): Add the 4 new tools
- **`AppDelegate.applicationDidFinishLaunching`** (TamagotchaiApp.swift:51): Start `ScheduleStore.shared` timer, request notification permissions
- **`AppDelegate.applicationWillTerminate`** (TamagotchaiApp.swift:59): Stop scheduler
- **System prompt** (PromptPanelController.swift:320-326): Mention reminder/routine capabilities
- **CLAUDE.md**: Update project structure, add new categories to logging table

### Risks & Mitigations

- **App not running**: Menu bar app is typically always running — acceptable. No daemon needed.
- **Timer drift**: 30s polling is sufficient for reminders (same approach as pocket-agent). Exact-to-the-second precision is not expected.
- **Concurrent access**: `@MainActor` on `ScheduleStore` avoids races. Tools call into it on main actor.
- **Routine execution**: Routines need the agent loop but NOT the panel. Create a headless `AgentLoop` that only sends notification with the result.

## Steps

1. Create `tamagotchai/Sources/Scheduler/ScheduleParser.swift` — port schedule parsing from pocket-agent's `cron.ts`: `parseSchedule()`, `parseDateTime()`, `calculateNextRun()`, `matchesCronField()` as pure Swift functions. Support bare durations ("30m", "2h"), "every 2h", "tomorrow 3pm", "in 10 minutes", and 5-field cron expressions.
2. Create `tamagotchai/Sources/Scheduler/ScheduleStore.swift` — `@MainActor` singleton with `ScheduledJob` Codable model, JSON file persistence in Application Support, CRUD methods (add/list/delete), a 30-second `Timer` that checks for due jobs, fires `UNUserNotificationCenter` notifications for reminders, and runs a headless `AgentLoop` for routines. Use `os.Logger` with category "scheduler".
3. Create `tamagotchai/Sources/AI/Tools/CreateReminderTool.swift` — agent tool conforming to `AgentTool` protocol: name "create_reminder", takes name/schedule/reminder params, calls `ScheduleStore.shared.addJob()` with `.reminder` type, returns JSON result. Follow existing tool patterns (BashTool.swift style).
4. Create `tamagotchai/Sources/AI/Tools/CreateRoutineTool.swift` — agent tool: name "create_routine", takes name/schedule/prompt params, calls `ScheduleStore.shared.addJob()` with `.routine` type, returns JSON result.
5. Create `tamagotchai/Sources/AI/Tools/ListSchedulesTool.swift` — agent tool: name "list_schedules", no required params, returns all scheduled jobs as JSON with name, type, schedule description, next run time, and enabled status.
6. Create `tamagotchai/Sources/AI/Tools/DeleteScheduleTool.swift` — agent tool: name "delete_schedule", takes name param, calls `ScheduleStore.shared.deleteJob()`, returns success/failure JSON.
7. Register all 4 new tools in `ToolRegistry.defaultRegistry()` in `tamagotchai/Sources/AI/Tools/AgentTool.swift` (add CreateReminderTool, CreateRoutineTool, ListSchedulesTool, DeleteScheduleTool to the tools array).
8. In `tamagotchai/Sources/TamagotchaiApp.swift` `AppDelegate.applicationDidFinishLaunching`: request `UNUserNotificationCenter` notification authorization, start `ScheduleStore.shared`, and set up `UNUserNotificationCenterDelegate`. In `applicationWillTerminate`: stop the scheduler.
9. Update system prompts in `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` to mention reminder and routine capabilities so the agent knows to use them.
10. Update `CLAUDE.md` project structure to include the new `Scheduler/` directory and tool files, add "scheduler" logging category, and add the new tool categories to the logging table.
11. Build the project with `xcodegen generate && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` and fix any compilation errors.
