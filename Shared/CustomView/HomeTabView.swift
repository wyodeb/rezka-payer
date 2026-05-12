//
//  HomeTabView.swift
//  rezka-player
//

#if os(tvOS)
import SwiftUI

struct HomeTabView: View {
    let categories: [CategoryList]

    @StateObject private var searchViewModel = MediaSearchContentViewModel(search: "")

    @State private var selection: Int = 0
    @State private var searchText: String = ""
    @FocusState private var focusedTab: Int?

    private enum Tab {
        case category(CategoryList)
        case settings
    }

    private var tabs: [Tab] {
        var t: [Tab] = categories.map { .category($0) }
        t.append(.settings)
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            content
        }
        .onChange(of: searchText) { _ in
            Task { await searchViewModel.updateSearch(text: searchText) }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                tabItem(at: idx, tab: tab)
            }
            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func tabItem(at index: Int, tab: Tab) -> some View {
        switch tab {
        case .category(let cat) where cat.type == .search:
            SearchTabPill(
                text: $searchText,
                isSelected: selection == index,
                outerFocus: $focusedTab,
                myValue: index
            )
            .onChange(of: focusedTab) { newValue in
                if newValue == index { selection = index }
            }
        case .category(let cat):
            Button {
                selection = index
            } label: {
                TabPillLabel(title: cat.name, icon: cat.iconName)
            }
            .buttonStyle(TabPillStyle(isSelected: selection == index))
            .focused($focusedTab, equals: index)
            .onChange(of: focusedTab) { newValue in
                if newValue == index { selection = index }
            }
        case .settings:
            Button {
                selection = index
            } label: {
                TabPillLabel(title: "Settings", icon: "gearshape")
            }
            .buttonStyle(TabPillStyle(isSelected: selection == index))
            .focused($focusedTab, equals: index)
            .onChange(of: focusedTab) { newValue in
                if newValue == index { selection = index }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let tab = tabs[safe: selection] ?? .settings
        switch tab {
        case .category(let cat) where cat.type == .search:
            MediaSearchContentView()
                .environmentObject(searchViewModel)
                .id("search")
        case .category(let cat):
            CategoryContentHost(category: cat)
                .id(cat.type)
        case .settings:
            SettingsView()
                .id("settings")
        }
    }
}

// MARK: - Stable per-category host

private struct CategoryContentHost: View {
    @StateObject private var viewModel: MediaContentViewModel

    init(category: CategoryList) {
        _viewModel = StateObject(
            wrappedValue: MediaContentViewModel(category: category.type, subCategories: category.items)
        )
    }

    var body: some View {
        MediaContentView()
            .environmentObject(viewModel)
    }
}

// MARK: - Tab pills

private struct TabPillLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TabPillStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabPillBody(isSelected: isSelected, configuration: configuration)
    }

    struct TabPillBody: View {
        let isSelected: Bool
        let configuration: TabPillStyle.Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .foregroundStyle(foreground)
                .background(Capsule(style: .continuous).fill(background))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isFocused ? .clear : RezkaPalette.surfaceStroke, lineWidth: 1)
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .shadow(color: isFocused ? .black.opacity(0.55) : .clear,
                        radius: isFocused ? 14 : 0,
                        x: 0, y: isFocused ? 8 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var foreground: Color {
            if isFocused { return RezkaPalette.onLight }
            if isSelected { return RezkaPalette.primaryText }
            return RezkaPalette.secondaryText
        }

        private var background: AnyShapeStyle {
            if isFocused { return AnyShapeStyle(Color.white) }
            if isSelected { return AnyShapeStyle(RezkaPalette.surface) }
            return AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - Search tab pill (morphing)

private struct SearchTabPill<Value: Hashable>: View {
    @Binding var text: String
    let isSelected: Bool
    @FocusState.Binding var outerFocus: Value?
    let myValue: Value

    private var isFocused: Bool { outerFocus == myValue }
    private var isExpanded: Bool { !text.isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))

            ZStack(alignment: .leading) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .submitLabel(.search)
                    .focused($outerFocus, equals: myValue)
                    .opacity(0.02)

                Text(text)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(foreground)
                    .allowsHitTesting(false)
            }
            .frame(width: isExpanded ? 520 : 90, alignment: .leading)

            if isExpanded && !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(foreground.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .foregroundStyle(foreground)
        .background(Capsule(style: .continuous).fill(background))
        .overlay(
            Capsule(style: .continuous)
                .stroke(isFocused ? .clear : RezkaPalette.surfaceStroke, lineWidth: 1)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(color: isFocused ? .black.opacity(0.55) : .clear,
                radius: isFocused ? 14 : 0,
                x: 0, y: isFocused ? 8 : 0)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
    }

    private var foreground: Color {
        if isFocused { return RezkaPalette.onLight }
        if isSelected { return RezkaPalette.primaryText }
        return RezkaPalette.secondaryText
    }

    private var background: AnyShapeStyle {
        if isFocused { return AnyShapeStyle(Color.white) }
        if isSelected { return AnyShapeStyle(RezkaPalette.surface) }
        return AnyShapeStyle(Color.clear)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
