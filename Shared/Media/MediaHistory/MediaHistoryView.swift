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
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 28)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                RezkaBackground()
                if viewModel.entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 56))
                            .foregroundStyle(RezkaPalette.tertiaryText)
                        Text("Nothing here yet")
                            .font(.title3)
                            .foregroundStyle(RezkaPalette.secondaryText)
                        Text("Movies and series you start watching will appear here.")
                            .font(.callout)
                            .foregroundStyle(RezkaPalette.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(viewModel.entries) { entry in
                                NavigationLink {
                                    DetailedMediaItemView(
                                        viewModel: DetailedMediaItemViewModel(media: entry.media),
                                        bookmarkViewModel: bookmarkViewModel
                                    )
                                } label: {
                                    WatchHistoryCard(entry: entry)
                                }
#if os(tvOS)
                                .buttonStyle(.card)
#endif
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.remove(media: entry.media)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(40)
                    }
                }
            }
            .navigationTitle("Watching")
        }
    }
}

private struct WatchHistoryCard: View {
    let entry: WatchHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                CacheAsyncImage(url: entry.media.coverURL) { phase in
                    phase.view
                        .scaledToFill()
                }
                .frame(height: 220)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.media.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let ep = entry.episodeLabel {
                            Text(ep)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Text(entry.timeLeftFormatted)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(14)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(RezkaPalette.surface)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * entry.progress)
                }
            }
            .frame(height: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RezkaPalette.surfaceStroke, lineWidth: 1)
        )
    }
}

struct MediaHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        MediaHistoryView()
    }
}
