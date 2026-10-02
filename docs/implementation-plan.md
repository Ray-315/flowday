# FlowDay native client implementation plan

**Goal:** Build the first usable native FlowDay client from the supplied PRD and mockups.

**Architecture:** Flutter shared domain and persistence, adaptive desktop/mobile presentation. Windows is the locally verified target; Android, iOS, macOS and Linux share the source. External identity, synchronization, model execution and remote reminder delivery require a later service integration and are not simulated as connected.

**Tech stack:** Flutter stable, Dart, Flutter widgets and tests, local JSON file repository through path_provider.

## Files and steps

- [x] Bootstrap `pubspec.yaml`, `analysis_options.yaml`, native platform runners and scripts. Disable Flutter telemetry. Run `flutter doctor -v` and resolve dependencies. Windows plugin junctions handle absent symlink privilege.
- [x] Implement and test `lib/domain/models.dart`, `lib/domain/store.dart` and `lib/data/repository.dart`. Tests cover single/multiple block completion, AND/OR and skipped predecessors, cycle-safe project moves, persistence and invalid imports.
- [x] Implement `lib/main.dart`, `lib/ui/theme.dart`, `lib/ui/app.dart` and page widgets. Preserve the sidebar, blue actions, pastel calendar blocks and detail panel from the mockups. At narrow widths use a drawer and full-width editor.
- [x] Implement the first usable local page set. Exact implemented operations and remaining PRD scope are recorded in `docs/implementation-status.md`; timeline currently shares agenda presentation, and notification delivery is not connected.
- [x] Add widget tests for navigation, task creation and narrow-screen layout. Domain tests, `flutter analyze`, 41 tests and Windows release build passed.
- [x] Write `README.md` and a precise implementation status matrix. Keep the original PRD and all source mockups unchanged.

## Acceptance boundaries

This is the first native implementation increment, not a claim that the complete V1 service product is shipped. Keep unavailable integrations out of enabled controls; document missing account auth, remote notifications, cloud sync, AI, Apple and course import explicitly. Use empty real data on first launch; optional example data must be an explicit action.

## Verification scenarios

1. Create a project and task; schedule one block; completing it completes the task.
2. Schedule two blocks; completing both accumulates actual time but does not auto-complete the task.
3. AND requires every predecessor; OR requires one; skipped satisfies dependency; graph loops do not execute automatically.
4. Create, edit, delete, restore and restart; saved data survives. Import invalid JSON without overwriting the existing state.
5. Navigate every page at desktop and 390-pixel mobile width without overflow.
