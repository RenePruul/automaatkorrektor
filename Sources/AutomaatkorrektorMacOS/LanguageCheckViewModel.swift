import AutomaatkorrektorCore
import Combine

enum LanguageCheckPresentationState: Sendable, Equatable {
  case waiting
  case checking
  case verdict(LanguageVerdict)
  case blocked(LanguageCheckBlock)
  case failed(LanguageCheckFailure)
}

struct LanguageCheckPresentation: Sendable, Equatable {
  let title: String
  let detail: String
  let symbol: String
  let tone: Tone

  enum Tone: Sendable, Equatable {
    case accent
    case progress
    case success
    case caution
    case failure
  }
}

struct LanguageCheckConsentPresentation: Sendable, Equatable {
  let origin: LanguageServiceOrigin

  var explanation: String {
    "Valitud tekst saadetakse teenuse \(origin.displayValue) operaatorile."
  }

  let warning =
    "Kasuta ainult usaldusväärset teenust. Ära saada paroole, saladusi ega tundlikke isikuandmeid."
}

private let readyPresentation = LanguageCheckPresentation(
  title: "Programm on tööks valmis",
  detail: "Vali tekst ja käivita eesti keele kontroll.",
  symbol: "checkmark.circle.fill",
  tone: .success
)

extension LanguageCheckPresentationState {
  var presentation: LanguageCheckPresentation {
    switch self {
    case .waiting:
      LanguageCheckPresentation(
        title: "Ootan valikut",
        detail: "Vali tekst ja käivita eesti keele kontroll.",
        symbol: "text.magnifyingglass",
        tone: .accent
      )
    case .checking:
      LanguageCheckPresentation(
        title: "Kontrollin keelt",
        detail: "Valitud teksti keel tuvastatakse…",
        symbol: "hourglass",
        tone: .progress
      )
    case .verdict(.estonian):
      LanguageCheckPresentation(
        title: "Eesti keel",
        detail: "Valitud tekst on eesti keeles.",
        symbol: "checkmark.circle.fill",
        tone: .success
      )
    case .verdict(.notEstonian):
      LanguageCheckPresentation(
        title: "Muu keel",
        detail: "Valitud tekst ei ole eesti keeles.",
        symbol: "xmark.circle.fill",
        tone: .caution
      )
    case .verdict(.uncertain):
      LanguageCheckPresentation(
        title: "Ebakindel",
        detail: "Keele tuvastamiseks ei ole piisavalt kindlust.",
        symbol: "questionmark.circle.fill",
        tone: .caution
      )
    case .blocked(.accessibilityPermissionRequired):
      LanguageCheckPresentation(
        title: "Accessibility-luba puudub",
        detail: "Valitud teksti lugemiseks on vaja Accessibility-luba.",
        symbol: "lock.trianglebadge.exclamationmark",
        tone: .failure
      )
    case .blocked(.unsupportedTextField):
      LanguageCheckPresentation(
        title: "Tekstivälja ei toetata",
        detail: "Vali tekst toetatud tekstiväljal.",
        symbol: "nosign",
        tone: .caution
      )
    case .blocked(.noSelection):
      LanguageCheckPresentation(
        title: "Teksti pole valitud",
        detail: "Vali kontrollimiseks tekst.",
        symbol: "selection.pin.in.out",
        tone: .caution
      )
    case .blocked(.languageCheckConsentRequired(let origin)):
      LanguageCheckPresentation(
        title: "Kaugteenus vajab luba",
        detail: """
          Valitud teksti saatmiseks teenusele \(origin.displayValue) on vaja sinu nõusolekut.
          """,
        symbol: "network.badge.shield.half.filled",
        tone: .caution
      )
    case .failed:
      LanguageCheckPresentation(
        title: "Kontroll ebaõnnestus",
        detail: "Keeletuvastuse teenusega tekkis probleem.",
        symbol: "wifi.exclamationmark",
        tone: .failure
      )
    }
  }
}

@MainActor
final class LanguageCheckViewModel: ObservableObject {
  @Published private(set) var state: LanguageCheckPresentationState = .waiting
  @Published private(set) var showsAccessibilityInstructions = false

  private let useCase: LanguageCheckUseCase
  private let accessibilityPermission: any AccessibilityPermissionControlling
  private let languageCheckConsent: LanguageCheckConsentStore?
  private var hasAccessibilityPermission: Bool?
  private var generation = 0

  init(
    useCase: LanguageCheckUseCase,
    accessibilityPermission: any AccessibilityPermissionControlling,
    languageCheckConsent: LanguageCheckConsentStore? = nil
  ) {
    self.useCase = useCase
    self.accessibilityPermission = accessibilityPermission
    self.languageCheckConsent = languageCheckConsent
  }

  var visiblePresentation: LanguageCheckPresentation {
    if state == .waiting, hasAccessibilityPermission == true {
      return readyPresentation
    }
    return state.presentation
  }

  var showsRetryAction: Bool {
    state == .failed(.unavailableService)
  }

  func retryUnavailableService() async {
    guard showsRetryAction else { return }
    await check()
  }

  var pendingConsentOrigin: LanguageServiceOrigin? {
    guard case .blocked(.languageCheckConsentRequired(let origin)) = state else {
      return nil
    }
    return origin
  }

  var languageCheckConsentPresentation: LanguageCheckConsentPresentation? {
    pendingConsentOrigin.map(LanguageCheckConsentPresentation.init(origin:))
  }

  func grantLanguageCheckConsent() async {
    guard let origin = pendingConsentOrigin, let languageCheckConsent else { return }
    languageCheckConsent.grantConsent(for: origin)
    state = .waiting
    await check()
  }

  func declineLanguageCheckConsent() {
    guard pendingConsentOrigin != nil else { return }
    generation += 1
    state = .waiting
  }

  func check() async {
    guard accessibilityPermission.checkPermission() else {
      await applyMissingAccessibilityPermission()
      return
    }
    hasAccessibilityPermission = true
    showsAccessibilityInstructions = false
    generation += 1
    let checkGeneration = generation
    state = .checking

    do {
      let verdict = try await useCase.check()
      guard checkGeneration == generation else { return }
      state = .verdict(verdict)
    } catch let block as LanguageCheckBlock {
      guard checkGeneration == generation else { return }
      state = .blocked(block)
    } catch let failure as LanguageCheckFailure {
      guard checkGeneration == generation else { return }
      state = .failed(failure)
    } catch let accessibilityError as AccessibilitySelectionError {
      guard checkGeneration == generation else { return }
      state = Self.presentationState(for: accessibilityError)
    } catch is CancellationError {
      // Cancellation is intentionally silent.
    } catch {
      guard checkGeneration == generation else { return }
      state = .failed(.invalidResponse)
    }
  }

  func refreshAccessibilityPermission() async {
    if accessibilityPermission.checkPermission() {
      hasAccessibilityPermission = true
      showsAccessibilityInstructions = false
      if state == .blocked(.accessibilityPermissionRequired) {
        state = .waiting
      }
    } else {
      await applyMissingAccessibilityPermission()
    }
  }

  func openAccessibilitySettings() {
    accessibilityPermission.openSettings()
    showsAccessibilityInstructions = true
  }

  func dismiss() async {
    generation += 1
    await useCase.cancel()
    state = .waiting
  }

  private func applyMissingAccessibilityPermission() async {
    hasAccessibilityPermission = false
    generation += 1
    await useCase.cancel()
    state = .blocked(.accessibilityPermissionRequired)
  }

  private static func presentationState(
    for error: AccessibilitySelectionError
  ) -> LanguageCheckPresentationState {
    switch error {
    case .permissionRequired:
      .blocked(.accessibilityPermissionRequired)
    case .noSelection:
      .blocked(.noSelection)
    case .selectionTooLarge:
      .failed(.selectionTooLarge)
    case .protectedContent, .unsupportedTextField, .readOnly, .invalidSelection,
      .focusChanged, .noFocusedControl, .unsupportedApplication, .unknown:
      .blocked(.unsupportedTextField)
    case .targetUnavailable:
      .failed(.invalidInput)
    }
  }
}
