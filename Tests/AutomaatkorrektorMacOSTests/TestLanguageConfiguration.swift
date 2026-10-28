import AutomaatkorrektorCore

let testLanguageConfiguration = LanguageCheckConfiguration(
  endpoint: .default
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
