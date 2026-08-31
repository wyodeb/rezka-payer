//
//  MediaItemViewView.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 18.08.2022.
//

import SwiftUI

struct MediaItemViewView: View {
#if os(iOS)
    static let coverSize = CGSize(width: 200, height: 300)
#elseif os(macOS)
    static let coverSize = CGSize(width: 300, height: 500)
#else
    static let coverSize = CGSize(width: 400, height: 600)
#endif

    let media: Media
    @StateObject var bookmarkViewModel: MediaBookmarksViewModel

    /// Watch progress (0...1). When set, a thin progress bar is drawn at the
    /// bottom of the card and, if `episodeLabelOverride` is also set, that
    /// replaces the generic series-info chip — used by the Watching tab so
    /// its cards share this exact layout instead of a bespoke one.
    var progress: Double? = nil
    var episodeLabelOverride: String? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                CacheAsyncImage(url: media.coverURL) { phase in
                    phase.view
                        .scaledToFill()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.45),
                        .black.opacity(0.92)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            media.category.icon
                                .font(.caption.weight(.semibold))
                            Text(media.category.text)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(
                            Capsule()
                                .fill(media.category.color.opacity(0.85))
                        )
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        )

                        if let episodeLabelOverride {
                            Text(episodeLabelOverride)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.18), lineWidth: 1)
                                )
                        } else if media.isSeries, let seriesInfo = media.seriesInfo {
                            Text(seriesInfo)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.18), lineWidth: 1)
                                )
                        }

                        Spacer(minLength: 0)

                        if bookmarkViewModel.isBookmarked(for: media) {
                            Image(systemName: "bookmark.fill")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    Text(media.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)

                    if !media.descriptionShort.isEmpty {
                        Text(media.descriptionShort)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }

                    if let progress {
                        GeometryReader { barProxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule().fill(Color.white)
                                    .frame(width: barProxy.size.width * max(0, min(progress, 1)))
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: RezkaTheme.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RezkaTheme.cardCorner, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 14)
        }
    }
}

struct MediaItemViewView_Previews: PreviewProvider {
    static var previews: some View {
        MediaItemViewView(media: Media.previewData.first!, bookmarkViewModel: MediaBookmarksViewModel.shared)
    }
}
