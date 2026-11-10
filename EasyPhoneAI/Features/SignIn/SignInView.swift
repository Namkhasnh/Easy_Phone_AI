import SwiftUI

/// S01 Sign-in (UI_SCREENS S01). Shown by RootView while `AppState.session == .signedOut`.
/// Google only, no Apple button in the thesis build (D-283).
struct SignInView: View {
    @State private var viewModel: SignInViewModel

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                // S01 app icon 96pt: `appLogo` = the AppIcon art (light + dark), a separate image set
                // because SwiftUI cannot load the AppIcon set.
                Image(.appLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)

                Text("signIn.title")
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("signIn.tagline")
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)

                Text("signIn.reason")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Space.screenPadding)
            .padding(.top, Tokens.Space.sectionGap)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background(Tokens.Colors.bg)
        .onChange(of: viewModel.message) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(
                String(localized: String.LocalizationValue(message.key))
            ).post()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Tokens.Space.m) {
            if let message = viewModel.message {
                Label {
                    Text(LocalizedStringKey(message.key))
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // TODO(spec): Google "G" mark — no licensed asset in the project yet; text-only button for now.
            PrimaryButton("signIn.google", isLoading: viewModel.isSigningIn) {
                Task { await viewModel.signIn() }
            }

            Text("signIn.legal")
                .font(Tokens.Fonts.caption)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .tint(Tokens.Colors.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { _ in
                    // TODO(spec): 1G.6 opens the in-app Terms / Privacy text (D-284); no-op until then.
                    .handled
                })
        }
        .padding(.horizontal, Tokens.Space.screenPadding)
        .padding(.vertical, Tokens.Space.m)
        .background(Tokens.Colors.bg)
    }
}

// MARK: - Previews (mocks only, D-206; "Dữ liệu mẫu" badge, D-189)

private struct SignInPreview: View {
    @State private var viewModel: SignInViewModel
    private let tapOnAppear: Bool

    init(auth: MockAuthService, tapOnAppear: Bool = false) {
        _viewModel = State(initialValue: SignInViewModel(auth: auth))
        self.tapOnAppear = tapOnAppear
    }

    var body: some View {
        SignInView(viewModel: viewModel)
            .overlay(alignment: .topTrailing) { DemoDataBadge().padding() }
            .task { if tapOnAppear { await viewModel.signIn() } }
    }
}

#Preview("Mặc định") {
    SignInPreview(auth: MockAuthService())
}

#Preview("Lỗi") {
    SignInPreview(auth: MockAuthService(signInResult: .failure(ServiceError.framework(code: AuthErrorCode.signInFailed))),
                  tapOnAppear: true)
}

#Preview("AX5") {
    SignInPreview(auth: MockAuthService())
        .dynamicTypeSize(.accessibility5)
}

#Preview("Tối") {
    SignInPreview(auth: MockAuthService())
        .preferredColorScheme(.dark)
}
