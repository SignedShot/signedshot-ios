//
//  OnboardingView.swift
//  ExampleApp
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    registerPage.tag(0)
                    sessionPage.tag(1)
                    capturePage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Spacer().frame(height: 32)

                // Bottom button
                Button(action: {
                    if currentPage < 2 {
                        withAnimation { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                }) {
                    Text(currentPage < 2 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.green)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)

                if currentPage < 2 {
                    Button("Skip") {
                        hasCompletedOnboarding = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.bottom, 24)
                } else {
                    Spacer().frame(height: 48)
                }
            }
        }
    }

    // MARK: - Pages

    private var registerPage: some View {
        VStack(spacing: 24) {
            Spacer()

            stepBadge("Step 1")

            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Register your device")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Tap **Register Device** to link this device to SignedShot. This is a one-time setup that gives your device a unique identity for signing photos.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private var sessionPage: some View {
        VStack(spacing: 24) {
            Spacer()

            stepBadge("Step 2")

            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Start a capture session")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Before each photo, tap **Start Session**. Sessions expire after 5 minutes as a security measure to prevent replay attacks.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private var capturePage: some View {
        VStack(spacing: 24) {
            Spacer()

            stepBadge("Step 3")

            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Capture & verify")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Take a photo with the capture button. Your photo and its cryptographic proof are saved to **Files → SignedShot**. Verify with the CLI or the API.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Helpers

    private func stepBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.white.opacity(0.15))
            .cornerRadius(12)
    }
}

#Preview {
    OnboardingView()
}
