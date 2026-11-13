import MapKit
import SwiftUI

/// S13 Places (UI_SCREENS S13): search field · results (name + address, ≥ 72pt) · map preview card (200pt, one marker)
/// with "Lưu địa điểm" / "Chỉ đường" · "Địa điểm đã lưu" (house / briefcase / mappin).
struct PlacesView: View {
    @State var viewModel: PlacesViewModel
    @Environment(Router.self) private var router
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text("places.title")
                    .font(Tokens.Fonts.display)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                searchField
                if let place = viewModel.selected { previewCard(place) }
                if viewModel.isSearching { ProgressView().frame(maxWidth: .infinity) }
                if viewModel.showsNoResults {
                    Text("places.noResults")
                        .font(Tokens.Fonts.body)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(viewModel.results) { place in
                    Button { viewModel.select(place) } label: {
                        PlaceRow(symbol: "mappin.circle", title: place.name, subtitle: place.address,
                                 selected: viewModel.selected == place)
                    }
                    .buttonStyle(.plain)
                }
                savedSection
            }
            .padding(Tokens.Space.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dismissesKeyboard($searchFocused)
        .background(Tokens.Colors.bg)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadSaved() }
        .onChange(of: viewModel.reviewDraftId) { _, id in
            guard let id else { return }
            viewModel.didOpenReview()
            router.push(.review(id))
        }
        .accessibilityIdentifier("screen.S13")
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Tokens.Colors.textSecondary)
                .accessibilityHidden(true)
            TextField("places.search", text: $viewModel.query)
                .font(Tokens.Fonts.fieldValue)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { Task { await viewModel.search() } }
        }
        .padding(Tokens.Space.m)
        .frame(minHeight: Tokens.Size.buttonMinHeight)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    /// 200pt map with one marker + Primary "Lưu địa điểm" + Secondary "Chỉ đường".
    private func previewCard(_ place: PlaceResult) -> some View {
        let center = CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 800, longitudinalMeters: 800))) {
                Marker(place.name, coordinate: center)
            }
            .id(place.id)                                                // recenter when another result is picked
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .accessibilityHidden(true)                                   // name + address below say the same
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: place.name)
                    .font(Tokens.Fonts.title)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text(verbatim: place.address)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            PrimaryButton("places.save") { viewModel.save() }
            SecondaryButton("places.directions", systemImage: "arrow.triangle.turn.up.right.diamond") { viewModel.directions() }
        }
        .padding(Tokens.Space.l)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("places.saved.title")
                .font(Tokens.Fonts.title)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if viewModel.saved.isEmpty {
                Text("places.saved.empty")
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.saved) { row in
                // TODO(spec): S13 does not say what a saved row does; it opens the preview (then "Chỉ đường").
                Button { viewModel.select(row.place) } label: {
                    PlaceRow(symbol: row.symbol, title: row.title, subtitle: row.place.address,
                             selected: viewModel.selected == row.place)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Tokens.Space.l)
    }
}

private struct PlaceRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Tokens.Colors.primary)
                .frame(width: Tokens.Size.tapTargetMin)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: title)
                    .font(Tokens.Fonts.fieldValue)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text(verbatim: subtitle)
                    .font(Tokens.Fonts.body)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Tokens.Colors.primary).accessibilityHidden(true)
            }
        }
        .padding(Tokens.Space.m)
        .frame(minHeight: 72)
        .background(Tokens.Colors.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Previews (mock data, "Dữ liệu mẫu", D-189)

@MainActor
private func placesPreviewModel() -> PlacesViewModel {
    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()
    local.save(SavedPlace(label: "home", name: "Nhà", address: "12 Lê Lợi, Quận 1", latitude: 10.7769, longitude: 106.7009))
    let places = MockPlacesService([PlaceResult(name: "Chợ Bến Thành", address: "Lê Lợi, Quận 1, TP.HCM",
                                                coordinate: Coordinate(latitude: 10.772461, longitude: 106.698055))])
    return PlacesViewModel(places: places, localData: local, engine: TaskEngine(repository: repo))
}

private struct PlacesPreview: View {
    var body: some View {
        NavigationStack {
            PlacesView(viewModel: placesPreviewModel())
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DemoDataBadge() } }
        }
        .environment(Router())
    }
}

#Preview("Light") { PlacesPreview() }
#Preview("Dark, AX5") { PlacesPreview().preferredColorScheme(.dark).dynamicTypeSize(.accessibility5) }
