# Native Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver a runnable macOS openSketch prototype with a genuine vector document, basic editing, durable local saving, and measurable evidence for the next stage.

**Architecture:** A Swift package separates a value-based OpenSketchCore from an AppKit/SwiftUI OpenSketchUI target and a small executable. Rendering, hit testing, and selection use the same local transforms. An explicit editing transaction groups a gesture into one undo entry; the native document package stores versioned JSON, never rasterized vector truth.

**Tech Stack:** Swift 6 language mode, macOS 15 deployment target, Foundation, Core Graphics, AppKit, SwiftUI, Swift Testing, system tools only.

## Global Constraints

- Product and repository name: `openSketch`.
- macOS native first; macOS 15+ deployment target. Actual runtime validation is on the available Apple silicon Mac, not a claim of macOS 15 runtime acceptance.
- Work only in this repository on `feat/native-prototype`; preserve adjacent Compositor and user files.
- No third-party source or package dependency in this prototype. Do not copy Sketch assets or application internals.
- Persist editable vector values with stable UUIDs, ordered children, local bounds, rotation, visibility, lock, style and text.
- Native extension: `.opensketch`, a document package containing `document.json`, format identifier `org.opensketch.document`, version 1.
- Sketch support is metadata inspection only, clearly labeled; no claim of editable import or lossless round trip.
- User-facing prototype UI is Simplified Chinese, with stable English accessibility identifiers and stored IDs.
- Build a local `build/openSketch.app`; do not install in `/Applications` or push.
- Core state/file/geometry regressions require behavior tests. Visual UI wiring is verified by build and real GUI interaction.

## Task 1: Vector model, geometry, history and native persistence

**Files:** `Package.swift`, `Sources/OpenSketchCore/{DocumentModel,DocumentOperations,SceneGeometry,DocumentHistory,DocumentCodec,SketchMetadata}.swift`, `Tests/OpenSketchCoreTests/*.swift`, `docs/development/core-api.md`.

**Interfaces:** Public `DesignDocument`, `DesignPage`, `DesignNode`, `NodeKind`, `RGBAColor`, `VectorPath`, `PathCommand`; `SceneGeometry.localTransform(for:)`, `worldTransform(id:in:)`, `hitTest(_:in:)`; `DocumentHistory`; `DocumentCodec.encode/decode/save/load`; `SketchMetadata.decode(_:)`. The core API document must give exact final signatures for the UI task.

The document starts with one page. Nodes support frame, group, rectangle, ellipse, text and path; text/path remain values. Transform is translation by node frame followed by rotation around its center. Frames clip children when `clipsContent` is true. Hit testing respects ancestor visibility, locking and clipping. Traversal is bottom-to-top, selection searches top-to-bottom and returns the deepest eligible node.

- [ ] Write behavior tests for nested rotation and hit testing using hand-derived coordinates, clipping, hidden/locked ancestors and z order.
- [ ] Test undo grouping, cancellation, redo preservation on no-op, and dirty state when undoing to a saved revision.
- [ ] Test save/reopen preserving node UUID, children, path controls and Chinese/emoji text; reject newer versions, duplicate IDs, non-finite geometry and malformed content without overwriting an existing valid file.
- [ ] Test metadata from a minimal literal Sketch 196 JSON fixture. The fields `version`, `appVersion`, `build`, and `compatibilityVersion` must remain separate.
- [ ] Run `swift test` to establish missing-feature failures, implement, then obtain a passing suite.

Representative regression shape (adapt initializer spelling consistently in the final API):

```swift
@Test func rejectsNewerDocumentWithoutReplacingCurrentFile() throws {
    let original = DesignDocument.blank()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".opensketch")
    defer { try? FileManager.default.removeItem(at: url) }
    try DocumentCodec.save(original, to: url)
    var future = original
    future.version = 99
    #expect(throws: (any Error).self) { try DocumentCodec.save(future, to: url) }
    #expect(try DocumentCodec.load(from: url) == original)
}
```

Use finite bounds and explicit count/depth/data limits before accepting files. Save validates first and uses Foundation atomic package replacement. Root owns orchestration; implementation must not edit app files or adjacent projects.

## Task 2: Native application and editing workflow

**Files:** Extend `Package.swift`; add `Sources/OpenSketchUI/` (EditorSession, CanvasView, CanvasRenderer, TextLayout, EditorRootView, LayersSidebar, InspectorView, AppController, Exporter, SketchFileInspector), `Sources/openSketchApp/main.swift`, `Resources/Info.plist`, `scripts/build.sh`, `Tests/OpenSketchUITests/`.

**Consumes:** Task 1 public API and `docs/development/core-api.md`. **Produces:** `openSketch` executable, `build/openSketch.app`, `scripts/build.sh [debug|release]`, UI actions callable from native menus.

- [ ] Create a single-document native window with custom AppKit canvas and SwiftUI sidebars; new/open/save/save-as, unsaved-close/new/open guard, app activation and file-open integration.
- [ ] Provide select, frame, rectangle, ellipse and text tools; click or drag creates objects; Shift multi-selection; drag moves; selection handles resize; inspector edits position, size, rotation, fill/stroke, corner radius and text typography.
- [ ] Provide layer visibility/lock, delete, duplicate, page add/switch, keyboard shortcuts and native clipboard copy/paste; children and locked ancestors must retain correct behavior.
- [ ] Implement anchored zoom, scroll pan, zoom-to-fit, 100%, canvas grid and visible selection. Clear input affordances and readable empty state; include an optional self-authored example document.
- [ ] Inline text editing uses NSTextView; draw/export measure through the same layout service. Preserve Unicode content and allow missing-font fallback. Handle edit commit/cancel before document lifecycle changes.
- [ ] Use one undo transaction per drag and text edit. Escape cancels a drag without dirtying a clean document. Menu validation updates for undo/redo/selection.
- [ ] Export selected frame or page content to PNG and PDF through the shared renderer. Reject oversized output before allocation; show errors without changing the source document.
- [ ] Inspect `.sketch` metadata via a bounded system ZIP read or equally bounded native reader; never extract arbitrary entries or overwrite the input. Display observed version and explicit metadata-only support.
- [ ] Add targeted tests for text layout/export, gesture/dirty-state integration and safe file inspection. First establish failure, then verify `swift test`.
- [ ] Bundle with a shell script that supports invocation from any directory and paths containing spaces. Use `swift build`, an Info.plist registering `.opensketch`, and ad-hoc signing for local launch.

Interaction acceptance sequence:

```text
New -> draw rectangle -> move -> resize -> Undo -> Redo
Text -> enter 中文 + emoji -> commit -> save .opensketch -> reopen
Change fill -> export PNG/PDF -> confirm visible output
Escape during move -> original position and dirty state restored
Open Sketch inspection -> show 196 and metadata-only explanation
Close edited document -> Cancel preserves the current document
```

## Task 3: Verification, review and delivery evidence

**Files:** `README.md`, `THIRD_PARTY_NOTICES.md`, `docs/development/2026-11-06-prototype-acceptance.md`, `.gitignore` if required by generated tooling.

- [ ] Run the focused tests and a Release build; validate the application Info.plist and `codesign --verify --deep --strict`.
- [ ] Launch the built bundle, inspect the actual window and perform the acceptance sequence above with new local fixtures.
- [ ] Measure a deterministic 1,000/10,000-node geometry workload in Release and report method/device/results; do not present it as GUI frame rate.
- [ ] Review the full implementation for correctness, file safety, shared transform/text behavior and unsupported-feature claims; resolve important findings.
- [ ] Update README with actual capabilities, exact build/test/open commands and known limits. Record which acceptance steps actually ran.
- [ ] Verify `git diff --check`, exact staged file scope, unchanged Compositor and clean local commits. Leave the feature branch available for subsequent work.

The milestone is a working initial prototype. Component instances, Stack solving, pen/node UI, complete SVG interoperability, Sketch editable import, automatic recovery, real-time collaboration and production signing remain separate milestones.
