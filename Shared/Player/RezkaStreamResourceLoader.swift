//
//  RezkaStreamResourceLoader.swift
//  rezka-player
//
//  `AVURLAssetHTTPHeaderFieldsKey` only reliably applies to the very first
//  request AVFoundation makes for an asset. On real hardware, HLS playback
//  (manifest + sub-playlists + segments) runs through a separate pipeline
//  that does not carry those headers along — so CDNs that require a
//  matching Referer/User-Agent (like rezka's) 404 every request past the
//  first, even though the exact same asset loads fine in the Simulator's
//  more lenient path.
//
//  This delegate works around that by disguising every https(s) URL under
//  a private scheme so AVFoundation always routes the request back to us,
//  and — for playlists — rewriting every embedded URL (segment refs,
//  EXT-X-MEDIA / EXT-X-KEY URI= attributes, variant streams) to the same
//  private scheme so the headers keep applying all the way down the chain.
//
//  Playlists (.m3u8) are fully proxied here — fetched, rewritten, and
//  handed back as data — because we need their text to rewrite the URLs
//  inside them. Segments are NOT: handing MPEG-TS segment bytes back
//  through a custom-scheme resource loader fails outright on real hardware
//  (AVPlayerItem.errorLog() reports CoreMediaErrorDomain -12881, comment
//  "custom url not redirect"). AVFoundation expects segment requests to
//  come back as a *redirect* to the real URL instead — so for anything
//  that isn't a playlist, this responds with `loadingRequest.redirect` (a
//  URLRequest carrying our headers) and lets AVFoundation's native
//  pipeline do the actual fetch, which is also what handles their range
//  requests correctly.
//
//  rezka's CDN tokens are single-use: a URL only serves its 200 once, and
//  404s on any repeat — and AVFoundation can (and does, more aggressively
//  on real hardware) issue more than one AVAssetResourceLoadingRequest for
//  the same playlist (a content-info probe, a byte-range data request,
//  our own diagnostic loadMediaSelectionGroup() call...). So a playlist
//  URL is fetched over the network at most once: the full body is cached
//  (already scheme-rewritten, so a later cache hit still routes segment
//  requests back through us) and every loadingRequest for it — whatever
//  offset/length it asks for — is served by slicing the single cached
//  buffer, never by hitting the network again.
//

import AVFoundation

final class RezkaStreamResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    private static let privateScheme = "rezka-stream"

    private let headers: [String: String]
    private let session = URLSession(configuration: .default)
    private let lock = NSLock()

    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var cache: [URL: Data] = [:]
    private var failed: [URL: Error] = [:]
    private var waiters: [URL: [AVAssetResourceLoadingRequest]] = [:]
    private var inFlight: Set<URL> = []

    init(headers: [String: String]) {
        self.headers = headers
    }

    /// Rewrite an http(s) URL onto our private scheme so AVFoundation hands loading back to
    /// us, carrying the real URL — base64-encoded — as a query parameter rather than as
    /// the disguised path or in plain text anywhere in the string.
    ///
    /// rezka's manifest URLs look like `.../file.mp4:hls:manifest.m3u8`. Real tvOS
    /// hardware's asset-type sniffer appears to scan the *entire* URL string — not just
    /// the path — for a recognizable media extension: even after moving the real URL into
    /// a plain (percent-encoded) query value, the literal substring "mp4" survived intact
    /// (percent-encoding only escapes reserved characters, not letters/digits), and
    /// AVFoundation fired its own native request for a bare, truncated `.mp4` URL that was
    /// never a real resource — bypassing our delegate, and 404ing uncontrolled. Base64
    /// encoding the real URL leaves no such literal substring anywhere for it to find.
    static func disguise(_ url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return url }

        let isPlaylist = url.absoluteString.contains("m3u8")
        let encoded = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents()
        components.scheme = privateScheme
        components.host = "proxy"
        components.path = isPlaylist ? "/passthrough.m3u8" : "/passthrough.bin"
        components.queryItems = [URLQueryItem(name: "u", value: encoded)]
        return components.url ?? url
    }

    private static func reveal(_ url: URL) -> URL? {
        guard url.scheme == privateScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "u" })?.value else {
            return nil
        }

        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let real = String(data: data, encoding: .utf8) else {
            return nil
        }
        return URL(string: real)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requestedURL = loadingRequest.request.url,
              let realURL = Self.reveal(requestedURL) else {
            loadingRequest.finishLoading(with: DataError.generate(for: .rezkaConstantsApi, error: .bad))
            return false
        }

        let isPlaylist = realURL.absoluteString.contains("m3u8")

        guard isPlaylist else {
            var redirect = URLRequest(url: realURL)
            for (key, value) in headers {
                redirect.setValue(value, forHTTPHeaderField: key)
            }
            loadingRequest.redirect = redirect
            loadingRequest.response = HTTPURLResponse(url: requestedURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)
            loadingRequest.finishLoading()
            return true
        }

        lock.lock()
        if let cached = cache[realURL] {
            lock.unlock()
            respond(loadingRequest: loadingRequest, data: cached, isPlaylist: isPlaylist)
            return true
        }
        if let error = failed[realURL] {
            lock.unlock()
            if !loadingRequest.isCancelled { loadingRequest.finishLoading(with: error) }
            return true
        }
        if inFlight.contains(realURL) {
            waiters[realURL, default: []].append(loadingRequest)
            lock.unlock()
            return true
        }
        inFlight.insert(realURL)
        lock.unlock()

        var request = URLRequest(url: realURL)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            self?.handleFetch(realURL: realURL, isPlaylist: isPlaylist, primary: loadingRequest, data: data, response: response, error: error)
        }
        lock.lock()
        tasks[ObjectIdentifier(loadingRequest)] = task
        lock.unlock()
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        lock.lock()
        let task = tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))
        for (url, list) in waiters {
            waiters[url] = list.filter { $0 !== loadingRequest }
        }
        lock.unlock()
        task?.cancel()
    }

    private func handleFetch(realURL: URL, isPlaylist: Bool, primary: AVAssetResourceLoadingRequest, data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        tasks.removeValue(forKey: ObjectIdentifier(primary))
        inFlight.remove(realURL)
        let queuedWaiters = waiters.removeValue(forKey: realURL) ?? []
        lock.unlock()

        let resolvedError: Error? = {
            if let error { return error }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodySnippet = data.flatMap { String(data: $0.prefix(500), encoding: .utf8) } ?? "<no body>"
                print("⚠️ CDN response for \(realURL.absoluteString):")
                print("⚠️   status=\(http.statusCode) headers=\(http.allHeaderFields)")
                print("⚠️   body=\(bodySnippet)")
                return NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorBadServerResponse,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) loading \(realURL.absoluteString)"]
                )
            }
            if data == nil { return DataError.generate(for: .rezkaConstantsApi, error: .empty) }
            return nil
        }()

        if let resolvedError {
            lock.lock()
            failed[realURL] = resolvedError
            lock.unlock()
            if !primary.isCancelled { primary.finishLoading(with: resolvedError) }
            for waiter in queuedWaiters where !waiter.isCancelled {
                waiter.finishLoading(with: resolvedError)
            }
            return
        }

        var payload = data!
        if isPlaylist, let text = String(data: payload, encoding: .utf8) {
            payload = Self.rewritingReferences(in: text, baseURL: realURL).data(using: .utf8) ?? payload
        }

        lock.lock()
        cache[realURL] = payload
        lock.unlock()

        respond(loadingRequest: primary, data: payload, isPlaylist: isPlaylist)
        for waiter in queuedWaiters {
            respond(loadingRequest: waiter, data: payload, isPlaylist: isPlaylist)
        }
    }

    /// Serves a loadingRequest entirely out of an already-fetched, already scheme-rewritten buffer —
    /// answers its content-info fields and/or slices out whatever byte range its dataRequest wants.
    private func respond(loadingRequest: AVAssetResourceLoadingRequest, data: Data, isPlaylist: Bool) {
        guard !loadingRequest.isCancelled else { return }

        if let infoRequest = loadingRequest.contentInformationRequest {
            infoRequest.contentType = isPlaylist ? "public.m3u-playlist" : "public.data"
            infoRequest.contentLength = Int64(data.count)
            infoRequest.isByteRangeAccessSupported = true
        }

        if let dataRequest = loadingRequest.dataRequest {
            let start = Int(dataRequest.currentOffset)
            if start >= 0 && start <= data.count {
                let end = dataRequest.requestsAllDataToEndOfResource
                    ? data.count
                    : min(start + dataRequest.requestedLength, data.count)
                if end > start {
                    dataRequest.respond(with: data.subdata(in: start..<end))
                }
            }
        }

        loadingRequest.finishLoading()
    }

    /// Rewrites every URL reference in the playlist text — bare segment/sub-playlist
    /// lines *and* `URI="..."` attributes inside tags like EXT-X-MEDIA / EXT-X-KEY /
    /// EXT-X-STREAM-INF — onto our private scheme.
    ///
    /// References here are commonly relative (e.g. just `seg-1-v1-a1.ts`), not full
    /// URLs. Handing those back untouched would leave AVFoundation to resolve them
    /// itself against our disguised base URL — and standard relative-URL resolution
    /// drops the base's query string when substituting a path, which is exactly
    /// where the real URL lives. So every reference, relative or absolute, is
    /// resolved against the *real* `baseURL` and disguised here, before AVFoundation
    /// ever sees it — nothing is left for it to resolve on its own.
    private static func rewritingReferences(in text: String, baseURL: URL) -> String {
        let withRewrittenAttributes = rewriteURIAttributes(in: text, baseURL: baseURL)
        return withRewrittenAttributes
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return line }
                return resolveAndDisguise(trimmed, relativeTo: baseURL) ?? line
            }
            .joined(separator: "\n")
    }

    private static func rewriteURIAttributes(in text: String, baseURL: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: "URI=\"([^\"]+)\"") else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastEnd = 0
        for match in matches {
            let full = match.range
            let group = match.range(at: 1)
            result += nsText.substring(with: NSRange(location: lastEnd, length: full.location - lastEnd))
            let raw = nsText.substring(with: group)
            let rewritten = resolveAndDisguise(raw, relativeTo: baseURL) ?? raw
            result += "URI=\"\(rewritten)\""
            lastEnd = full.location + full.length
        }
        result += nsText.substring(from: lastEnd)
        return result
    }

    private static func resolveAndDisguise(_ reference: String, relativeTo base: URL) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL else { return nil }
        return disguise(resolved).absoluteString
    }
}
