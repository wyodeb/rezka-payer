//
//  MediaSearchView.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 16.08.2022.
//

import SwiftUI

struct MediaSearchView: View {
    @StateObject private var viewModel = MediaSearchContentViewModel(search: "")

    var body: some View {
        MediaSearchContentView()
            .environmentObject(viewModel)
    }
}

struct MediaSearchContentView: View {
    @EnvironmentObject var viewModel: MediaSearchContentViewModel
    
    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared
    
    @State private var scrollViewHeight = CGFloat.infinity
    @Namespace private var scrollViewNameSpace
    
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40)
    ]

    var body: some View {
        Group {
            NavigationView {
                ScrollView {
                    if let elements = viewModel.subCategories {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 22) {
                                ForEach(elements) { element in
                                    Button {
                                        // currently disabled - subcategory switching not wired for search
                                    } label: {
                                        PillChip(
                                            icon: element == viewModel.selectedSubCategory ? "checkmark" : nil,
                                            title: element.name,
                                            isSelected: element == viewModel.selectedSubCategory
                                        )
                                    }
                                    .buttonStyle(PillButtonStyle(isSelected: element == viewModel.selectedSubCategory))
                                }
                            }
                            .padding(.horizontal, 60)
                            .padding(.top, 24)
                            .padding(.bottom, 36)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(viewModel.newMedias) { media in
                            NavigationLink {
                                DetailedMediaItemView(viewModel: DetailedMediaItemViewModel(media: media), bookmarkViewModel: bookmarkViewModel)
                            } label: {
                                MediaItemViewView(media: media, bookmarkViewModel: bookmarkViewModel)
                                    .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                            }
#if os(tvOS)
                            .buttonStyle(.card)
#else
                            .buttonStyle(.bordered)
#endif
                            .contextMenu {
                                Button {
                                    bookmarkViewModel.toggleBookmark(for: media)
                                } label: {
                                    Text(bookmarkViewModel.bookMarkTitle(for: media))
                                }
                            }
                        }
                    }
                    .padding()

                    if !viewModel.newMedias.isEmpty {
                        Color.clear
                            .frame(height: 1)
                            .onAppear { loadMoreTask() }
                    }
                }
            }
            .overlay(overlayView)
            .task {
                refreshTask()
            }
#if os(macOS)
            .frame(maxWidth: 1024, maxHeight: 1024)
#endif
        }
    }
    
    @ViewBuilder
    private var overlayView: some View {
        switch viewModel.phase {
        case .fetching:
            progress
        case .fetchingNextPage:
            progress
        case .success(let medias) where medias.isEmpty:
            EmptyPlaceholderView(text: "No Medias", image: nil)
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
            await viewModel.searchMedias()
        }
    }
    
    private func loadMoreTask() {
        Task {
            await viewModel.loadMore()
        }
    }
}

struct MediaSearchView_Previews: PreviewProvider {
    static var previews: some View {
        MediaSearchView()
    }
}
