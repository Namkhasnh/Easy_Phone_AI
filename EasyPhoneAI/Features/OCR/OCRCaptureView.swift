import PhotosUI
import SwiftUI

/// S09 Photo capture (UI_SCREENS S09) step 1: tips card `ocr.tips` + `ocr.oneImageNote`, confirmation dialog
/// "Chụp ảnh" / "Chọn ảnh có sẵn" / "Hủy". After a photo: thumbnail + "Chụp lại" (reading comes with 1D.3).
struct OCRCaptureView: View {
    @State var viewModel: OCRCaptureViewModel
    @State private var libraryItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                tipsCard
                if let data = viewModel.imageData, let image = CameraPicker.thumbnail(data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                        .accessibilityHidden(true)
                }
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Colors.bg)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Tokens.Space.m) {
                if viewModel.mode == .captured {
                    SecondaryButton("ocr.retake", systemImage: "camera") { viewModel.retake() }
                } else {
                    PrimaryButton("home.camera") { viewModel.showsSourceDialog = true }
                }
            }
            .padding(Tokens.Space.screenPadding)
            .background(Tokens.Colors.bg)
        }
        .navigationTitle(Text("home.camera"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Text("home.camera"), isPresented: $viewModel.showsSourceDialog, titleVisibility: .hidden) {
            if viewModel.cameraAvailable {
                Button("ocr.source.camera") { viewModel.chooseCamera() }
            }
            Button("ocr.source.library") { viewModel.chooseLibrary() }
            Button("common.cancel", role: .cancel) {
                if viewModel.mode == .choosing { dismiss() }
            }
        }
        .photosPicker(isPresented: $viewModel.showsLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { viewModel.received(data) }
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $viewModel.showsCamera) {
            CameraPicker(onPhoto: { viewModel.received($0) }, onCancel: { viewModel.showsCamera = false })
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
