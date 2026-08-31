//
//  MediaHistoryView.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 16.08.2022.
//

import SwiftUI

struct MediaHistoryView: View {
    @StateObject private var viewModel = WatchHistoryViewModel.shared
    @StateObject private var bookmarkViewModel = MediaBookmarksViewModel.shared

    private let columns = [
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                RezkaBackground()
                if viewModel.entries.isEmpty {
                    EmptyPlaceholderView(
                        text: "Nothing here yet",
                        image: Image(systemName: "play.circle"),
                        caption: "Movies and series you start watching will appear here."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(viewModel.entries) { entry in
                                VStack(spacing: 14) {
                                    NavigationLink {
                                        DetailedMediaItemView(
                                            viewModel: DetailedMediaItemViewModel(media: entry.media),
                                            bookmarkViewModel: bookmarkViewModel
                                        )
                                    } label: {
                                        MediaItemViewView(
                                            media: entry.media,
                                            bookmarkViewModel: bookmarkViewModel,
                                            progress: entry.progress,
                                            episodeLabelOverride: entry.episodeLabel
                                        )
                                        .frame(width: MediaItemViewView.coverSize.width, height: MediaItemViewView.coverSize.height)
                                    }
#if os(tvOS)
                                    .buttonStyle(.card)
#else
                                    .buttonStyle(.bordered)
#endif
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            viewModel.remove(media: entry.media)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }

                                    Button {
                                        viewModel.remove(media: entry.media)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    .buttonStyle(PillButtonStyle(isDestructive: true))
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Watching")
        }
        .task {
            await viewModel.syncFromRemote()
        }
    }
}

struct MediaHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        MediaHistoryView()
    }
}
