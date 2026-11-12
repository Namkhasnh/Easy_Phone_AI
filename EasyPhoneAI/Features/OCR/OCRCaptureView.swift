import PhotosUI
import SwiftUI

/// S09 Photo capture (UI_SCREENS S09) step 1: hero + tips card `ocr.tips` + `ocr.oneImageNote`, Primary "Chụp ảnh"
/// (hidden without a camera) + Secondary "Chọn ảnh có sẵn"; back button = "Hủy". After a photo: thumbnail + "Chụp lại".
// TODO(decision): UI_SCREENS S09 says a confirmation dialog; owner 2026-11-12 found it ugly → two buttons (DOC-43).
struct OCRCaptureView: View {
    @State var viewModel: OCRCaptureViewModel
    @State private var libraryItem: PhotosPickerItem?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                if let data = viewModel.imageData, let image = CameraPicker.thumbnail(data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                        .accessibilityHidden(true)
                } else {
                    // Owner 2026-11-12: the iOS dialog covered the tips and left the screen empty → hero + 2 buttons.
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: Tokens.Size.iconHero * 1.6))
                        .foregroundStyle(Tokens.Colors.primary)
                        .padding(.top, Tokens.Space.xl)
                        .accessibilityHidden(true)
                    Text("home.camera")
                        .font(Tokens.Fonts.display)
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if viewModel.saveFailed {
                    Banner(message: UserMessage(key: "ocr.noText.body"), style: .warning)
                }
                tipsCard
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Tokens.Space.m) {
                if viewModel.mode == .captured {
                    SecondaryButton("ocr.retake", systemImage: "arrow.counterclockwise") { Task { await viewModel.retake() } }
                } else {
                    if viewModel.cameraAvailable {
                        PrimaryButton("ocr.source.camera") { viewModel.chooseCamera() }
                    }
                    SecondaryButton("ocr.source.library", systemImage: "photo.on.rectangle") { viewModel.chooseLibrary() }
                }
            }
            .padding(Tokens.Space.screenPadding)
            .background(Tokens.Colors.bg)
        }
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $viewModel.showsLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.received(data, fromCamera: false)
                }
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $viewModel.showsCamera) {
            CameraPicker(onPhoto: { data in Task { await viewModel.received(data, fromCamera: true) } },
                         onCancel: { viewModel.showsCamera = false })
                .ignoresSafeArea()
        }
        .sheet(item: $viewModel.pendingPermission) { pending in
            PermissionSheet(pending: pending,
                            onAllow: { Task { await viewModel.allowPermission() } },
                            onOpenSettings: {
                                viewModel.dismissPermission()
                                // = UIApplication.openSettingsURLString, without importing UIKit (D-014)
                                if let url = URL(string: "app-settings:") { openURL(url) }
                            },
                            onLater: { viewModel.dismissPermission() },
                            onFallback: { viewModel.useLibraryInstead() })
        }
        .accessibilityIdentifier("screen.S09")
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Label {
                Text("ocr.tips").fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb").accessibilityHidden(true)
            }
            .font(Tokens.Fonts.body)
            .foregroundStyle(Tokens.Colors.textPrimary)
            Text("ocr.oneImageNote")
                .font(Tokens.Fonts.body)
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        OCRCaptureView(viewModel: OCRCaptureViewModel(permissions: MockPermissionManager(), cameraAvailable: true))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
    }
}
