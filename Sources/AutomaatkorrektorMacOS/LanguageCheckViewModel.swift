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

  private let useCase: LanguageCheckUseCase
  private var generation = 0

  init(useCase: LanguageCheckUseCase) {
    self.useCase = useCase
  }

  func check() async {
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
    } catch is CancellationError {
      // Cancellation is intentionally silent.
    } catch {
      guard checkGeneration == generation else { return }
      state = .failed(.invalidResponse)
    }
  }

  func dismiss() async {
    generation += 1
    await useCase.cancel()
    state = .waiting
  }
}
