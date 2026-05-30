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

    final class Coordinator {
        var viewModel: DetailedMediaItemViewModel?
        weak var avController: AVPlayerViewController?
        var lastStreamURL: String = ""
        var audioOptions: [(option: AVMediaSelectionOption, name: String, isSelected: Bool)] = []
#if !os(macOS)
        fileprivate var endObserver: NSObjectProtocol?
#endif

        init(viewModel: DetailedMediaItemViewModel?) {
            self.viewModel = viewModel
        }

#if !os(macOS)
        deinit {
            if let observer = endObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        @MainActor
        func swapSource(to urlString: String) {
            guard !urlString.isEmpty,
                  let url = URL(string: urlString),
                  urlString != lastStreamURL,
                  let player = avController?.player else { return }

            lastStreamURL = urlString

            let resumeAt = player.currentTime()
            let wasPlaying = player.rate > 0

            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if wasPlaying { player.play() }
            }

            rebuildMenus()
            Task { @MainActor [weak self] in
                await self?.refreshAudioOptions()
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
            guard let vm = viewModel, vm.hasNextEpisode else { return }
            do {
                let advanced = try await vm.advanceToNextEpisode()
                guard advanced,
                      !vm.stream.isEmpty,
                      let url = URL(string: vm.stream),
                      let player = avController?.player else { return }

                lastStreamURL = vm.stream
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.play()
                }

                observePlaybackEnd()
                rebuildMenus()
                await refreshAudioOptions()
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
                } else {
                    audioOptions = []
                }
            } catch {
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
                            self.swapSource(to: vm.stream)
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
                    UIAction(
                        title: name,
                        state: id == viewModel.currentTranslation ? .on : .off
                    ) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self, let vm = self.viewModel else { return }
                            try? await vm.setCurrentTranslation(id: id)
                            self.swapSource(to: vm.stream)
                            self.rebuildMenus()
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

    private func initialPlayer() -> AVPlayer? {
        guard let url = videoURL else { return nil }
        return AVPlayer(url: url)
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

        if let player = initialPlayer() {
            controller.player = player
            context.coordinator.lastStreamURL = videoURL?.absoluteString ?? ""

            if let vm = viewModel,
               let entry = WatchHistoryViewModel.shared.entry(for: vm.media),
               entry.currentTime > 0 {
                let resumeTime = CMTime(seconds: entry.currentTime, preferredTimescale: 600)
                player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.play()
                }
            } else {
                player.play()
            }
        } else {
            print("⚠️ PlayerViewController: no video URL — skipping playback.")
        }

        context.coordinator.avController = controller
        context.coordinator.viewModel = viewModel
        Task { @MainActor [weak coordinator = context.coordinator] in
            guard let coordinator = coordinator else { return }
            coordinator.observePlaybackEnd()
            coordinator.rebuildMenus()
            await coordinator.refreshAudioOptions()
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
                    context.coordinator.swapSource(to: newURL)
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
                translationId: vm.currentTranslation
            )
        }
#endif
    }
}
