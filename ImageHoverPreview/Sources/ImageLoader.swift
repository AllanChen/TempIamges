import AppKit

class ImageLoader {
    private let imageCache = NSCache<NSString, NSImage>()
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB
    private let maxImageDimension: CGFloat = 2048

    init() {
        imageCache.totalCostLimit = maxCacheSize
    }

    func loadImages(from urls: [URL], completion: @escaping ([NSImage?]) -> Void) {
        guard !urls.isEmpty else {
            completion([])
            return
        }
        var results: [NSImage?] = Array(repeating: nil, count: urls.count)
        let lock = NSLock()
        let group = DispatchGroup()
        for (i, url) in urls.enumerated() {
            group.enter()
            loadImage(from: url) { image in
                lock.lock()
                results[i] = image
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(results)
        }
    }

    func loadImage(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = url.absoluteString as NSString

        // Check cache first
        if let cached = imageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        if url.isFileURL {
            loadLocalImage(from: url, cacheKey: cacheKey, completion: completion)
        } else {
            loadRemoteImage(from: url, cacheKey: cacheKey, completion: completion)
        }
    }

    private func loadLocalImage(from url: URL, cacheKey: NSString, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = NSImage(contentsOf: url) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let resized = self?.resizeImage(image, maxDimension: 400) ?? image

            // Cache with cost (approximate bytes)
            let cost = Int(resized.size.width * resized.size.height * 4)
            self?.imageCache.setObject(resized, forKey: cacheKey, cost: cost)

            DispatchQueue.main.async {
                completion(resized)
            }
        }
    }

    private func loadRemoteImage(from url: URL, cacheKey: NSString, completion: @escaping (NSImage?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3

        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            guard let image = NSImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let resized = self.resizeImage(image, maxDimension: 400)

            // Cache with cost
            let cost = Int(resized.size.width * resized.size.height * 4)
            self.imageCache.setObject(resized, forKey: cacheKey, cost: cost)

            DispatchQueue.main.async {
                completion(resized)
            }
        }

        task.resume()
    }

    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let originalSize = image.size

        guard originalSize.width > maxDimension || originalSize.height > maxDimension else {
            return image
        }

        let ratio: CGFloat
        if originalSize.width > originalSize.height {
            ratio = maxDimension / originalSize.width
        } else {
            ratio = maxDimension / originalSize.height
        }

        let newWidth = originalSize.width * ratio
        let newHeight = originalSize.height * ratio

        let newImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        newImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)

        newImage.unlockFocus()

        return newImage
    }

    func clearCache() {
        imageCache.removeAllObjects()
    }
}