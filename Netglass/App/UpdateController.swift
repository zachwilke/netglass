import Combine
import Foundation
import Sparkle
import SwiftUI

/// Sparkle 2 host. The feed lives on GitHub Releases; automatic checks stay
/// off until a real EdDSA public key replaces the Info.plist placeholder.
final class SparkleFeedDelegate: NSObject, SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateController.feedURL.absoluteString
    }
}

@MainActor
final class UpdateController {
    static let shared = UpdateController()

    static let feedURL = URL(string: "https://github.com/zachwilke/netglass/releases/latest/download/appcast.xml")!

    nonisolated static var publicKeyConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("REPLACE") { return false }
        return true
    }

    let controller: SPUStandardUpdaterController
    private let feedDelegate = SparkleFeedDelegate()

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: UpdateController.publicKeyConfigured,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates && UpdateController.publicKeyConfigured
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value && UpdateController.publicKeyConfigured
            }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var model: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.model = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!model.canCheckForUpdates)
    }
}
