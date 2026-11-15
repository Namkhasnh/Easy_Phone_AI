import SwiftUI

/// S10 Source image (UI_SCREENS S10): full-screen black, image fit, the field's box outlined 3pt `warning` with the
/// rest dimmed, pinch-zoom. Top "Đóng"; bottom caption "Thông tin “{fieldLabel}” được lấy từ vùng này.".
struct SourceImageView: View {
    @State var viewModel: SourceImageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    static let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = viewModel.image {
                photo(image)
            } else if !viewModel.didLoad {
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("source.title")
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("common.close") { dismiss() }
                    .font(Tokens.Fonts.button)
                    .foregroundStyle(.white)
                    .frame(minWidth: Tokens.Size.tapTargetMin, minHeight: Tokens.Size.tapTargetMin)
            }
            .padding(.horizontal, Tokens.Space.screenPadding)
            .padding(.vertical, Tokens.Space.s)
            .background(.black.opacity(0.6))
        }
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: viewModel.caption)
                .font(Tokens.Fonts.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Space.screenPadding)
                .background(.black.opacity(0.6))
                .accessibilityLabel(Text(verbatim: viewModel.accessibilityText))
        }
        .task { await viewModel.load() }
        .accessibilityIdentifier("screen.S10")
    }

    /// Image + overlay zoom together; drag only while zoomed in.
    private func photo(_ image: CGImage) -> some View {
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        return Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let rect = viewModel.highlight(in: geo.size) {
                        // Dim everything outside the box (even-odd fill), then the 3pt `warning` outline.
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addRect(rect)
                        }
                        .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                        Rectangle()
                            .strokeBorder(Tokens.Colors.warning, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(Self.maxScale, max(1, lastScale * $0.magnification)) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale == 1 { offset = .zero; lastOffset = .zero }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .accessibilityHidden(true)                                   // the caption carries the meaning
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

#Preview("S10 no image") {
    SourceImageView(viewModel: SourceImageViewModel(imagePath: nil, images: MockImageStore(),
                                                    box: NormalizedRect(x: 0.1, y: 0.6, width: 0.8, height: 0.1),
                                                    fieldLabel: "Ngày giờ", spanText: "9:30 ngày 14/11/2026"))
}
