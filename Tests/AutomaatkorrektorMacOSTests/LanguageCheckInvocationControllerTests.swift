import AutomaatkorrektorCore
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Language check invocation focus safety")
struct LanguageCheckInvocationControllerTests {
  @Test("menu feedback remains nonactivating before selected text capture")
  func menuInvocationDoesNotStealFocus() async {
    let events = InvocationEvents()
    let fixture = makeFixture(events: events)

    await fixture.controller.openMenu().value
    await fixture.controller.checkFromMenu().value

    #expect(events.values == [.presentedWithoutActivation, .capturedSelection])
    #expect(fixture.presentation.keyWindowRequestCount == 0)
    #expect(fixture.presentation.applicationActivationRequestCount == 0)
  }

  @Test("shortcut feedback remains nonactivating before selected text capture")
  func shortcutInvocationDoesNotStealFocus() async {
    let events = InvocationEvents()
    let fixture = makeFixture(events: events)

    await fixture.controller.checkFromShortcut().value

    #expect(events.values == [.presentedWithoutActivation, .capturedSelection])
    #expect(fixture.presentation.keyWindowRequestCount == 0)
    #expect(fixture.presentation.applicationActivationRequestCount == 0)
  }

  private func makeFixture(events: InvocationEvents) -> (
    controller: LanguageCheckInvocationController,
    presentation: InvocationPresentationSpy
  ) {
    let presentation = InvocationPresentationSpy(events: events)
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: InvocationSelectionReader(events: events),
        languageDetector: InvocationDetector()
      ),
      accessibilityPermission: InvocationPermissionController()
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: InvocationTerminator()
    )
    return (
      LanguageCheckInvocationController(
        lifecycle: lifecycle,
        presentation: presentation
      ),
      presentation
    )
  }
}

@MainActor
private final class InvocationEvents {
  enum Event: Equatable {
    case presentedWithoutActivation
    case capturedSelection
  }

  private(set) var values: [Event] = []

  func append(_ event: Event) {
    values.append(event)
  }
}

@MainActor
private final class InvocationPresentationSpy: LanguageCheckFeedbackPresenting {
  private let events: InvocationEvents
  private(set) var isPresented = false
  private(set) var keyWindowRequestCount = 0
  private(set) var applicationActivationRequestCount = 0

  init(events: InvocationEvents) {
    self.events = events
  }

  func presentWithoutActivation() {
    isPresented = true
    events.append(.presentedWithoutActivation)
  }

  func dismiss() {
    isPresented = false
  }
}

private struct InvocationSelectionReader: SelectionReading {
  let events: InvocationEvents

  func readSelectedText() async throws -> SelectedText {
    await events.append(.capturedSelection)
    return SelectedText("Tere maailm")
  }
}

private struct InvocationDetector: LanguageDetecting {
  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    .estonian
  }
}

private final class InvocationPermissionController: AccessibilityPermissionControlling {
  func checkPermission() -> Bool { true }
  func openSettings() {}
}

@MainActor
private final class InvocationTerminator: ApplicationTerminating {
  func terminate() {}
}
