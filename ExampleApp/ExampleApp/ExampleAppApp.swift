//
//  ExampleAppApp.swift
//  ExampleApp
//
//  Created by Felippe Costa on 24/01/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAppCheck

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

      // Set up App Check with App Attest provider (for real devices)
      let providerFactory = SignedShotAppCheckProviderFactory()
      AppCheck.setAppCheckProviderFactory(providerFactory)

      // Initialize Firebase
      FirebaseApp.configure()

      return true
  }
}

// App Check provider factory - renamed to avoid conflict with protocol
class SignedShotAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
      #if targetEnvironment(simulator)
      // Use debug provider for simulator
      return AppCheckDebugProvider(app: app)
      #else
      // Use App Attest for real devices
      return AppAttestProvider(app: app)
      #endif
  }
}

@main
struct ExampleAppApp: App {
  // Register app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  var body: some Scene {
      WindowGroup {
          ContentView()
      }
  }
}
