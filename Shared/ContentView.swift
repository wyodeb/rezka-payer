//
//  ContentView.swift
//  Shared
//
//  Created by Vitalii Parovishnyk on 16.08.2022.
//

import SwiftUI

struct ContentView: View {
    private struct K {
        static var name = ""
        static var icon = "sparkles.tv"
    }
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var historyViewModel = WatchHistoryViewModel.shared
    
    @State var selectedCategory: CategoryList?
    
    @State var selectedItem: SubCategoryList?
    
    @State var pathCategory = NavigationPath()
    @State var pathColor    = NavigationPath()
    
    @State var sideBarVisibility = NavigationSplitViewVisibility.automatic
    @State var showToolbar = true
    @State private var showSettings = false
    
    var body: some View {
#if os(tvOS)
        ZStack {
            RezkaBackground()
            switch viewModel.phase {
            case .fetching, .fetchingNextPage:
                RezkaProgress()
            case .failure(let error):
                TabView {
                    RetryView(text: error.localizedDescription, retryAction: refreshTask)
                        .tabItem { Label("Home", systemImage: "house") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            default:
                HomeTabView(categories: viewModel.categories)
            }
        }
        .fullScreenCover(item: $historyViewModel.pendingDeepLinkMedia) { media in
            NavigationStack {
                DetailedMediaItemView(
                    viewModel: DetailedMediaItemViewModel(media: media),
                    bookmarkViewModel: MediaBookmarksViewModel.shared
                )
            }
        }
        .task { refreshTask() }
#else
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView(columnVisibility: $sideBarVisibility) {
                    List(viewModel.categories, selection: $selectedCategory) { category in
                        CategoryListView(item: category)
                    }
                    .navigationSplitViewColumnWidth(200)
                    .navigationTitle(K.name)
                } content: {
                    CategoryView(horizontalSizeClass: horizontalSizeClass, category: selectedCategory, selection: $selectedItem)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
                } detail: {
                    selectedItem?.detailsView
                }
                .navigationSplitViewStyle(.prominentDetail)
                .toolbar {
                    EmptyView()
                }
            } else {
                NavigationSplitView(columnVisibility: $sideBarVisibility) {
                    List(viewModel.categories, selection: $selectedCategory) { category in
                        NavigationLink(value: category) {
                            Text(category.name)
                        }
                    }
                    .navigationTitle(K.name)
                } detail: {
                    NavigationStack {
                        CategoryView(horizontalSizeClass: horizontalSizeClass, category: selectedCategory, selection: $selectedItem)
                    }
                }
            }
        }
        .overlay(overlayView)
        .toolbar {
            ToolbarItem {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .task {
            refreshTask()
            
        }
#if os(macOS)
        .frame(minWidth: 640, idealWidth: 1024, minHeight: 480, idealHeight: 768)
#endif
#endif
    }
    
    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            progress
        case .fetchingNextPage:
            progress
        case .success(let categories) where categories.isEmpty:
            EmptyPlaceholderView(text: "no categories", image: nil)
        case .failure(let error):
            RetryView(text: error.localizedDescription, retryAction: refreshTask)
        default: EmptyView()
        }
    }
    
    @ViewBuilder
    private var progress: some View {
        RezkaProgress()
    }
    
    private func refreshTask() {
        Task {
            await viewModel.load()
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
