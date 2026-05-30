//
//  HomeTabView.swift
//  rezka-player
//

#if os(tvOS)
import SwiftUI

struct HomeTabView: View {
    let categories: [CategoryList]

    @StateObject private var searchViewModel = MediaSearchContentViewModel(search: "")
    @State private var searchText: String = ""

    var body: some View {
        TabView {
            MediaHistoryView()
                .tabItem {
                    Label("Watching", systemImage: "play.circle")
                }
            ForEach(categories, id: \.type) { category in
                tabContent(for: category)
                    .tabItem {
                        Label(tabTitle(for: category), systemImage: category.iconName)
                    }
                    .tag(category.type)
            }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }

    @ViewBuilder
    private func tabContent(for category: CategoryList) -> some View {
        if category.type == .search {
            NavigationStack {
                MediaSearchContentView()
                    .environmentObject(searchViewModel)
                    .searchable(text: $searchText, placement: .automatic, prompt: Text("Search"))
            }
            .onChange(of: searchText) { newText in
                Task { await searchViewModel.updateSearch(text: newText) }
            }
        } else {
            CategoryContentHost(category: category)
        }
    }

    private func tabTitle(for cat: CategoryList) -> String {
        if cat.type == .search { return "Search" }
        return cat.name
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

#endif
