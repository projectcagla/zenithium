//
//  ZenithiumApp.swift
//  Zenithium
//
//  The entry point. Spec §10: background task registration at launch, and the composition
//  root built once.
//

import SwiftUI
import SwiftData

@main
struct ZenithiumApp: App {

    @State private var dependencies: AppDependencies?
    @State private var launchError: ZenithiumError?

    var body: some Scene {
        WindowGroup {
            Group {
                if let dependencies {
                    RootView(dependencies: dependencies)
                        .modelContainer(dependencies.modelContainer)
                        .task { await dependencies.start() }
                } else if let launchError {
                    // §5.6 in spirit: a container that will not open is a recoverable state
                    // with an explanation, not a crash on a black screen.
                    ErrorStateView(error: launchError) {
                        await buildDependencies()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ZenithiumColor.background.ignoresSafeArea())
                } else {
                    ZenithiumColor.background.ignoresSafeArea()
                }
            }
            .preferredColorScheme(.dark)
            .task { await buildDependencies() }
        }
    }

    @MainActor
    private func buildDependencies() async {
        guard dependencies == nil else { return }
        do {
            let built = try AppDependencies.live()
            // Registration must happen before the app finishes launching, which is why it is
            // here rather than inside `start()`.
            built.scheduler.register()
            dependencies = built
            launchError = nil
        } catch let error as ZenithiumError {
            ZenithiumLog.orchestration.error("Launch failed")
            launchError = error
        } catch {
            launchError = .persistenceUnavailable(detail: String(describing: error))
        }
    }
}
