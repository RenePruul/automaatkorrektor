import AutomaatkorrektorCore

let testLanguageConfiguration = LanguageCheckConfiguration(
  validatedServiceBaseURL: "http://127.0.0.1:8000"
)

private struct TestLanguageConfigurationProvider: LanguageCheckConfiguring {
  func currentConfiguration() -> LanguageCheckConfiguration {
    testLanguageConfiguration
  }
}

extension LanguageCheckUseCase {
  init(
    selectionReader: any SelectionReading,
    languageDetector: any LanguageDetecting
  ) {
    self.init(
      configurationProvider: TestLanguageConfigurationProvider(),
      selectionReader: selectionReader,
      languageDetector: languageDetector
    )
  }
}
