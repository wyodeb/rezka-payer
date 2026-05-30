//
//  MediaContentView.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 16.08.2022.
//

import SwiftUI

struct MediaContentView: View {
    @EnvironmentObject var viewModel: MediaContentViewModel
    
    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared
    
    @State private var scrollViewHeight = CGFloat.infinity
    @Namespace private var scrollViewNameSpace
    
    @State private var isLoading = true
    @State private var didTriggerLoadMore = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40)
    ]

    var body: some View {
        ZStack {
            RezkaBackground()
            NavigationView {
                ScrollView {
                    if let elements = viewModel.subCategories {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 22) {
                                ForEach(elements) { element in
                                    Button {
                                        Task { await viewModel.setSubCategory(element) }
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
                            .onAppear {
                                guard !didTriggerLoadMore else { return }
                                didTriggerLoadMore = true
                                loadMoreTask()
                            }
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
            await viewModel.loadMedias()
        }
    }
    
    private func loadMoreTask() {
        Task {
            await viewModel.loadMore()
        }
    }
}

struct MediaNewContentView_Previews: PreviewProvider {
    static var previews: some View {
        MediaContentView()
            .environmentObject(MediaContentViewModel())
    }
}
