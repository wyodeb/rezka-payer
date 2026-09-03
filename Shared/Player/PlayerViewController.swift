//
//  PlayerViewController.swift
//  rezka-player
//
//  Created by vitalii on 01.11.2022.
//

import AVKit
import SwiftUI

#if os(macOS)
typealias Representable = NSViewControllerRepresentable
typealias ViewControllerType = NSViewController
#else
typealias Representable = UIViewControllerRepresentable
typealias ViewControllerType = AVPlayerViewController
#endif

struct PlayerViewController: Representable {
    typealias NSViewControllerType = ViewControllerType

    var videoURL: URL?
    var viewModel: DetailedMediaItemViewModel?

    @MainActor
    final class Coordinator: Sendable {
        var viewModel: DetailedMediaItemViewModel?
        weak var avController: AVPlayerViewController?
        var lastStreamURL: String = ""
        var audioOptions: [(option: AVMediaSelectionOption, name: String, isSelected: Bool)] = []
#if !os(macOS)
        fileprivate var endObserver: NSObjectProtocol?
        fileprivate var failObserver: NSObjectProtocol?
        fileprivate var statusObserver: NSKeyValueObservation?
        /// AVAssetResourceLoader holds its delegate weakly — this keeps it alive
        /// for as long as the asset that's using it is in play.
        fileprivate var resourceLoaderDelegate: RezkaStreamResourceLoader?

        /// Mirror-fallback state: rezka hands back several CDN mirrors per quality
        /// (`voidcrystal.org`, `stream.voidboost.one`, ...) and any one of their
        /// signed tokens can be dead for a given title even though the others work.
        /// `play(quality:resumeAt:autoplay:)` walks this queue, and once every
        /// mirror of the current quality has failed, drops to the next lower
        /// quality and tries its mirrors too.
        private var mirrorQueue: [String] = []
        private var mirrorIndex = 0
        private var fallbackQuality: Media.Quality = .unknown
        private var pendingResumeAt: CMTime = .zero
        private var pendingAutoplay = true
        /// Whether this playback attempt has already retried with the signed-in
        /// account's cookies stripped after every quality/mirror failed logged in —
        /// tried last, not first, so registered-only perks like 4K stay available.
        private var triedAnonymousFallback = false
#endif

        init(viewModel: DetailedMediaItemViewModel?) {
            self.viewModel = viewModel
        }

        /// Builds a player item with the Referer/User-Agent headers the CDN requires.
        ///
        /// rezka's stream URLs are plain progressive MP4 (mirrors(_:) always picks that
        /// form now, never the `:hls:manifest.m3u8` one — see StreamMedia.mirrors). For a
        /// single file, `AVURLAssetHTTPHeaderFieldsKey` is exactly what it's meant for and
        /// lets AVFoundation handle the entire progressive download/range-request/buffering
        /// pipeline natively, with none of the per-chunk indirection the custom
        /// RezkaStreamResourceLoader adds — that indirection is only there to solve HLS's
        /// many-separate-resources header problem (see that file's header comment), which
        /// doesn't apply to one file, and was measurably slower for higher-bitrate content
        /// on real hardware. Kept as a fallback for the off chance a `.m3u8` URL is ever
        /// selected again.
        @MainActor
        func makeStreamPlayerItem(url: URL) -> AVPlayerItem {
            let headers: [String: String] = [
                ApiConstants.userAgentKey: ApiConstants.userAgent,
                "Referer": RezkaConstantsApi.server + "/"
            ]

            guard url.absoluteString.contains("m3u8") else {
                let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let item = AVPlayerItem(asset: asset)
                // Real hardware's more constrained memory/CPU (vs. the Simulator running
                // on a Mac) makes AVFoundation buffer more conservatively by default,
                // which shows up as choppier playback at higher bitrates even over an
                // otherwise-identical native path. Read further ahead to smooth that out.
                item.preferredForwardBufferDuration = 15
                return item
            }

            let delegate = RezkaStreamResourceLoader(headers: headers)
#if !os(macOS)
            resourceLoaderDelegate = delegate
#endif

            let disguisedURL = RezkaStreamResourceLoader.disguise(url)
            let asset = AVURLAsset(url: disguisedURL)
            asset.resourceLoader.setDelegate(delegate, queue: DispatchQueue(label: "rezka.resourceloader"))

            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 15
            return item
        }

#if !os(macOS)
        deinit {
            if let observer = endObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = failObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        @MainActor
        func observePlaybackFailures() {
            statusObserver?.invalidate()
            if let observer = failObserver {
                NotificationCenter.default.removeObserver(observer)
                failObserver = nil
            }
            guard let item = avController?.player?.currentItem else { return }

            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                if item.status == .readyToPlay {
                    // Deliberately deferred until here rather than probed at item-creation
                    // time: forcing AVFoundation to enumerate media selection groups
                    // up front makes it fetch every audio rendition's own sub-manifest
                    // immediately, racing extra requests against the main video load at
                    // the worst possible moment. Every failure we were chasing carried
                    // AVErrorFailedDependenciesKey=(MediaSelectionArray, ...) — waiting
                    // for a confirmed-successful load first removes that as a variable.
                    Task { @MainActor in
                        await self?.refreshAudioOptions()
                    }
                    return
                }
                guard item.status == .failed else { return }
                print("⚠️ AVPlayerItem failed to load: \(item.error?.localizedDescription ?? "unknown error")")
                var underlying = (item.error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError
                var depth = 0
                while let current = underlying {
                    print("⚠️ Underlying error [\(depth)]: \(current)")
                    underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
                    depth += 1
                }
                if let events = item.errorLog()?.events, !events.isEmpty {
                    for event in events {
                        print("⚠️ ErrorLog: statusCode=\(event.errorStatusCode) domain=\(event.errorDomain) comment=\(event.errorComment ?? "nil") uri=\(event.uri ?? "nil") server=\(event.serverAddress ?? "nil")")
                    }
                } else {
                    print("⚠️ ErrorLog: no events")
                }
                Task { @MainActor in
                    self?.handleStreamFailure()
                }
            }

            failObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                print("⚠️ AVPlayerItem failed to play to end: \(error?.localizedDescription ?? "unknown error")")
            }
        }

        /// Starts (or restarts) playback at `quality`, walking every CDN mirror the
        /// site offered for it before giving up on that quality — see the mirrorQueue
        /// doc comment above.
        @MainActor
        func play(quality: Media.Quality, resumeAt: CMTime, autoplay: Bool) {
            guard let vm = viewModel else { return }
            let mirrors = vm.streamMirrors(startingAt: quality)
            guard !mirrors.isEmpty else {
                print("⚠️ No mirrors available for quality \(quality.rawValue)")
                return
            }

            fallbackQuality = quality
            mirrorQueue = mirrors
            mirrorIndex = 0
            pendingResumeAt = resumeAt
            pendingAutoplay = autoplay
            triedAnonymousFallback = false
            lastStreamURL = mirrors[0]
            loadCurrentMirror()
        }

        /// Re-plays whatever the view model's current quality/translation/episode
        /// points at, resuming from the player's current position. Used whenever the
        /// view model's stream selection changes out from under an already-playing item.
        @MainActor
        func playCurrentViewModelStream() {
            guard let vm = viewModel, let player = avController?.player else { return }
            play(quality: vm.currentQuality, resumeAt: player.currentTime(), autoplay: player.rate > 0)
        }

        @MainActor
        private func loadCurrentMirror() {
            guard mirrorIndex < mirrorQueue.count,
                  let url = URL(string: mirrorQueue[mirrorIndex]),
                  let player = avController?.player else { return }

            let item = makeStreamPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.seek(to: pendingResumeAt, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard let self, self.pendingAutoplay else { return }
                player.play()
            }

            observePlaybackEnd()
            observePlaybackFailures()
            rebuildMenus()
            // refreshAudioOptions() is triggered from observePlaybackFailures() once the
            // item reaches .readyToPlay, not proactively here — see that comment.
        }

        /// Called when the currently-loading item fails outright (`.status == .failed`).
        /// Tries the next mirror of the same quality first; once those are exhausted,
        /// drops to the next lower quality and tries its mirrors too.
        @MainActor
        private func handleStreamFailure() {
            mirrorIndex += 1
            if mirrorIndex < mirrorQueue.count {
                print("ℹ️ Mirror failed — trying mirror \(mirrorIndex + 1)/\(mirrorQueue.count) of \(fallbackQuality.rawValue)")
                loadCurrentMirror()
                return
            }

            if let vm = viewModel, let lowerQuality = vm.nextLowerQuality(after: fallbackQuality) {
                print("ℹ️ All mirrors of \(fallbackQuality.rawValue) failed — falling back to \(lowerQuality.rawValue)")
                vm.setQuality(lowerQuality)
                play(quality: lowerQuality, resumeAt: pendingResumeAt, autoplay: pendingAutoplay)
                return
            }

            guard let vm = viewModel, !triedAnonymousFallback else {
                print("⚠️ All mirrors exhausted for \(fallbackQuality.rawValue) and no lower quality left — giving up.")
                return
            }

            // Every quality/mirror combination from the logged-in fetch failed. A
            // signed-in, non-premium account can get CDN-rejected where an anonymous
            // request for the same content works (see RezkaMediaApi.streamRequest) —
            // this was deliberately not tried first so registered-only perks like 4K
            // stay available whenever the logged-in fetch does work.
            triedAnonymousFallback = true
            let resumeAt = pendingResumeAt
            let autoplay = pendingAutoplay
            Task { @MainActor [weak self] in
                print("ℹ️ Retrying stream fetch anonymously (logged-in fetch exhausted every quality/mirror)...")
                guard let self, await vm.refetchStreamAnonymously() else {
                    print("⚠️ Anonymous retry also produced no playable stream — giving up.")
                    return
                }
                self.play(quality: vm.currentQuality, resumeAt: resumeAt, autoplay: autoplay)
            }
        }

        @MainActor
        func observePlaybackEnd() {
            if let observer = endObserver {
                NotificationCenter.default.removeObserver(observer)
                endObserver = nil
            }
            guard let item = avController?.player?.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.advanceAndPlayNext()
                }
            }
        }

        @MainActor
        private func advanceAndPlayNext() async {
            guard let vm = viewModel else { return }

            if !vm.hasNextEpisode {
                WatchHistoryViewModel.shared.remove(media: vm.media)
                return
            }

            do {
                let advanced = try await vm.advanceToNextEpisode()
                guard advanced, !vm.streamMirrors().isEmpty else { return }

                WatchHistoryViewModel.shared.advanceEpisode(
                    media: vm.media,
                    season: vm.currentSeason ?? 1,
                    episode: vm.currentEpisode ?? 1,
                    translationId: vm.currentTranslation
                )

                play(quality: vm.currentQuality, resumeAt: .zero, autoplay: true)
            } catch {
                print("⚠️ Failed to advance to next episode: \(error)")
            }
        }

        @MainActor
        func refreshAudioOptions() async {
            guard let item = avController?.player?.currentItem else {
                audioOptions = []
                rebuildMenus()
                return
            }
            do {
                if let group = try await item.asset.loadMediaSelectionGroup(for: .audible) {
                    let current = item.currentMediaSelection.selectedMediaOption(in: group)
                    audioOptions = group.options.enumerated().map { index, option in
                        let displayName = Self.displayName(for: option, fallbackIndex: index)
                        return (option, displayName, option == current)
                    }
                    print("ℹ️ Audio group: allowsEmptySelection=\(group.allowsEmptySelection) optionCount=\(group.options.count)")
                    for (i, option) in group.options.enumerated() {
                        print("ℹ️ Audio option[\(i)]: displayName=\"\(option.displayName(with: .current))\" lang=\(option.extendedLanguageTag ?? "nil") mediaType=\(option.mediaType.rawValue) commonMetadata=\(option.commonMetadata.map { "\($0.commonKey?.rawValue ?? "?")=\($0.stringValue ?? "?")" })")
                    }
                } else {
                    print("ℹ️ Audio group: nil (asset exposes no selectable audible group)")
                    audioOptions = []
                }
            } catch {
                print("⚠️ Failed to load audio media selection group: \(error)")
                audioOptions = []
            }
            rebuildMenus()
        }

        private static func displayName(for option: AVMediaSelectionOption, fallbackIndex: Int) -> String {
            let displayLocale = Locale.current
            let name = option.displayName(with: displayLocale)
            if !name.isEmpty { return name }
            if let langCode = option.extendedLanguageTag,
               let pretty = displayLocale.localizedString(forIdentifier: langCode), !pretty.isEmpty {
                return pretty
            }
            return "Track \(fallbackIndex + 1)"
        }

        @MainActor
        func rebuildMenus() {
            guard let avController = avController, let viewModel = viewModel else { return }
            avController.transportBarCustomMenuItems = buildMenuItems(for: viewModel)
        }

        @MainActor
        private func buildMenuItems(for viewModel: DetailedMediaItemViewModel) -> [UIMenuElement] {
            var elements: [UIMenuElement] = []

            if let qualities = viewModel.streams?.qualities, !qualities.isEmpty {
                let actions = qualities.map { quality in
                    UIAction(
                        title: quality.rawValue,
                        state: quality == viewModel.currentQuality ? .on : .off
                    ) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self, let vm = self.viewModel else { return }
                            vm.setQuality(quality)
                            self.playCurrentViewModelStream()
                        }
                    }
                }
                elements.append(
                    UIMenu(
                        title: "Quality",
                        image: UIImage(systemName: "speedometer"),
                        children: actions
                    )
                )
            }

            let translations = viewModel.translations
            if translations.count > 1 {
                let actions = translations.map { (id, name) in
                    let title = viewModel.isPremiumTranslation(id) ? "\(name) 🔒" : name
                    return UIAction(
                        title: title,
                        state: id == viewModel.currentTranslation ? .on : .off
                    ) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self, let vm = self.viewModel else { return }
                            try? await vm.setCurrentTranslation(id: id)
                            self.playCurrentViewModelStream()
                        }
                    }
                }
                elements.append(
                    UIMenu(
                        title: "Soundtrack",
                        image: UIImage(systemName: "speaker.wave.2"),
                        children: actions
                    )
                )
            }

            if audioOptions.count > 1 {
                let actions = audioOptions.map { entry in
                    UIAction(title: entry.name, state: entry.isSelected ? .on : .off) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self,
                                  let item = self.avController?.player?.currentItem else { return }
                            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                                item.select(entry.option, in: group)
                                await self.refreshAudioOptions()
                            }
                        }
                    }
                }
                elements.append(
                    UIMenu(
                        title: "Audio Track",
                        image: UIImage(systemName: "waveform"),
                        children: actions
                    )
                )
            }

            return elements
        }
#endif
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSViewController(context: Context) -> NSViewControllerType {
        return makeViewController(context: context)
    }

    func makeUIViewController(context: Context) -> NSViewControllerType {
        return makeViewController(context: context)
    }

    func makeViewController(context: Context) -> NSViewControllerType {
#if os(macOS)
        //TODO: add player to macOS
        let controller = NSViewController()
#else
        let controller = AVPlayerViewController()
        controller.modalPresentationStyle = .fullScreen
        controller.player = AVPlayer()

        context.coordinator.avController = controller
        context.coordinator.viewModel = viewModel

        if let vm = viewModel, !vm.streamMirrors().isEmpty {
            let resumeSeconds = WatchHistoryViewModel.shared.entry(for: vm.media)?.currentTime ?? 0
            let resumeTime = resumeSeconds > 0 ? CMTime(seconds: resumeSeconds, preferredTimescale: 600) : .zero
            context.coordinator.play(quality: vm.currentQuality, resumeAt: resumeTime, autoplay: true)
        } else {
            print("⚠️ PlayerViewController: no video URL — skipping playback.")
            context.coordinator.rebuildMenus()
        }
#endif
        return controller
    }

    func updateNSViewController(_ playerController: NSViewControllerType, context: Context) {}

    func updateUIViewController(_ playerController: NSViewControllerType, context: Context) {
#if !os(macOS)
        context.coordinator.viewModel = viewModel
        if let vm = viewModel {
            let newURL = vm.stream
            if !newURL.isEmpty && newURL != context.coordinator.lastStreamURL {
                Task { @MainActor in
                    context.coordinator.playCurrentViewModelStream()
                }
            } else {
                Task { @MainActor in
                    context.coordinator.rebuildMenus()
                }
            }
        }
#endif
    }

    static func dismantleUIViewController(_ playerController: NSViewControllerType, coordinator: Coordinator) {
#if !os(macOS)
        guard let player = coordinator.avController?.player,
              let vm = coordinator.viewModel else { return }
        let currentTime = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard currentTime.isFinite, duration.isFinite, duration > 0 else { return }
        Task { @MainActor in
            WatchHistoryViewModel.shared.update(
                media: vm.media,
                currentTime: currentTime,
                duration: duration,
                season: vm.currentSeason,
                episode: vm.currentEpisode,
                translationId: vm.currentTranslation,
                nextEpisodeTarget: vm.nextEpisodeIdentifier
            )
        }
#endif
    }
}
