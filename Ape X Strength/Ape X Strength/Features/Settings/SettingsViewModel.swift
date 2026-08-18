import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { service.save(settings) }
    }
    private let service: any SettingsService

    init(service: any SettingsService) {
        self.service = service
        settings = service.load()
    }
}
