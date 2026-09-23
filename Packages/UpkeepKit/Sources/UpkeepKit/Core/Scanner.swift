import Darwin
import Foundation

/// Disk yürüyüşü.
///
/// `FileManager.enumerator` yerine `opendir`/`readdir` + `fstatat`: sayım
/// yüz binlerce girdide dönüyor ve her girdi için `URL` kurup `resourceValues`
/// sormak taramayı dakikalara çıkarıyor. `fstatat` dizin tanıtıcısı üzerinden
/// çalışır, yol birleştirme maliyeti de kalkar.
public final class Scanner: @unchecked Sendable {

    /// İlerleme bildirimi bu aralıktan sık gönderilmez. Her dosyada yayımlamak
    /// arayüzü saniyede on binlerce kez uyandırır; tarama kendisi yavaşlar.
    private let reportInterval = 0.2
    /// Sayaçlar bu kadar dosyada bir paylaşılan toplama aktarılır. Dosya başına
    /// kilit almak bir milyonluk ağaçta bir milyon kilit demekti ve paralel
    /// yürüyüşte iş parçacıkları o kilitte sıraya giriyordu.
    private let flushEvery = 512

    /// Tek bir alt ağacın yerel sayacı. Paylaşılan duruma toplu aktarılır.
    private struct LocalCount {
        var files = 0
        var bytes: UInt64 = 0
        var lastPath = ""

        var isEmpty: Bool { files == 0 }
        mutating func reset() { files = 0; bytes = 0 }
    }

    private let lock = NSLock()
    private var cancelled = false
    private var progress = ScanProgress()
    private var lastReport = Date.distantPast
    /// Aynı fiziksel dosyaya birden çok sert bağ varsa boyut bir kez sayılır.
    /// Sayılmazsa `/Applications` içindeki bağlar toplamı şişirir.
    private var seenInodes = Set<InodeKey>()

    private struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Kökü tarar. Çağıran iş parçacığını bloklar — arka planda çağrılmalı.
    ///
    /// - Parameter onProgress: ana iş parçacığında çağrılmaz; çağıran kendi
    ///   sıçramasını yapar.
    public func scan(root: String, onProgress: @escaping @Sendable (ScanProgress) -> Void) -> DiskNode {
        lock.lock()
        cancelled = false
        progress = ScanProgress()
        seenInodes = []
        lock.unlock()

        let node = scanRoot(root, onProgress: onProgress)

        lock.lock()
        progress.isFinished = true
        let final = progress
        lock.unlock()
        onProgress(final)
        return node
    }

    /// Kökün doğrudan çocuklarını paralel yürür.
    ///
    /// Alt ağaçlar birbirinden bağımsız: her biri kendi düğümünü kurar,
    /// paylaşılan tek şey sert bağ kümesi ve ilerleme sayacı — ikisi de
    /// kilitli ve artık toplu güncelleniyor. Ev dizini taraması tek iş
    /// parçacığında 25 saniye sürüyordu.
    private func scanRoot(_ root: String, onProgress: @escaping @Sendable (ScanProgress) -> Void) -> DiskNode {
        let name = (root as NSString).lastPathComponent
        let node = DiskNode(name: name.isEmpty ? root : name, path: root, isDirectory: true)
        guard !isCancelled, Safety.mayScan(root) else { return node }

        var directories: [String] = []
        var local = LocalCount()
        readEntries(in: root, into: node, directories: &directories, local: &local, onProgress: onProgress)
        flush(&local, onProgress: onProgress)

        guard !directories.isEmpty else { return node }

        var results = [DiskNode?](repeating: nil, count: directories.count)
        // Her yineleme yalnızca kendi indisine yazar; dizi paylaşılsa da
        // iki iş parçacığı aynı hücreye dokunmaz.
        results.withUnsafeMutableBufferPointer { buffer in
            let slot = buffer
            DispatchQueue.concurrentPerform(iterations: directories.count) { index in
                guard !self.isCancelled else { return }
                slot[index] = self.walk(path: directories[index], onProgress: onProgress)
            }
        }

        for child in results.compactMap({ $0 }) {
            node.children.append(child)
            node.size &+= child.size
            node.fileCount += child.fileCount
        }
        return node
    }

    // MARK: Yürüyüş

    private func walk(path: String, onProgress: @escaping @Sendable (ScanProgress) -> Void) -> DiskNode {
        let name = (path as NSString).lastPathComponent
        let node = DiskNode(name: name.isEmpty ? path : name, path: path, isDirectory: true)
        guard !isCancelled, Safety.mayScan(path) else { return node }

        var directories: [String] = []
        var local = LocalCount()
        readEntries(in: path, into: node, directories: &directories, local: &local, onProgress: onProgress)

        for childPath in directories {
            if isCancelled { break }
            let child = walk(path: childPath, onProgress: onProgress)
            node.children.append(child)
            node.size &+= child.size
            node.fileCount += child.fileCount
        }

        flush(&local, onProgress: onProgress)
        return node
    }

    /// Bir dizinin girdilerini okur: dosyaları düğüme ekler, alt dizinleri
    /// çağırana bırakır.
    private func readEntries(in path: String,
                             into node: DiskNode,
                             directories: inout [String],
                             local: inout LocalCount,
                             onProgress: @escaping @Sendable (ScanProgress) -> Void) {
        guard let directory = opendir(path) else { return }
        defer { closedir(directory) }
        let descriptor = dirfd(directory)

        while let entry = readdir(directory) {
            if isCancelled { return }

            var raw = entry.pointee.d_name
            let entryName = withUnsafePointer(to: &raw) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            guard entryName != ".", entryName != ".." else { continue }

            var status = stat()
            // Sembolik bağ TAKİP EDİLMEZ: `/var` gibi bağlar aynı ağacı ikinci
            // kez saydırır, kötü kurulmuş bir bağ ise sonsuz döngü yapar.
            guard fstatat(descriptor, entryName, &status, AT_SYMLINK_NOFOLLOW) == 0 else { continue }

            let childPath = path.hasSuffix("/") ? path + entryName : path + "/" + entryName

            if (status.st_mode & S_IFMT) == S_IFDIR {
                directories.append(childPath)
                continue
            }
            guard (status.st_mode & S_IFMT) == S_IFREG else { continue }

            // Görünen boyut değil, diskte tutulan blok sayısı.
            let bytes = UInt64(max(status.st_blocks, 0)) * 512
            if status.st_nlink > 1 {
                let key = InodeKey(device: status.st_dev, inode: status.st_ino)
                lock.lock()
                let isNew = seenInodes.insert(key).inserted
                lock.unlock()
                guard isNew else { continue }
            }

            let child = DiskNode(name: entryName, path: childPath, isDirectory: false, size: bytes)
            node.children.append(child)
            node.size &+= bytes
            node.fileCount += 1

            local.files += 1
            local.bytes &+= bytes
            local.lastPath = childPath
            if local.files >= flushEvery { flush(&local, onProgress: onProgress) }
        }
    }

    /// Yerel sayacı paylaşılan ilerlemeye aktarır ve zamanı gelmişse yayımlar.
    private func flush(_ local: inout LocalCount, onProgress: @escaping @Sendable (ScanProgress) -> Void) {
        guard !local.isEmpty else { return }

        lock.lock()
        progress.scannedFiles += local.files
        progress.scannedBytes &+= local.bytes
        progress.currentPath = local.lastPath
        let now = Date()
        let due = now.timeIntervalSince(lastReport) >= reportInterval
        if due { lastReport = now }
        let snapshot = progress
        lock.unlock()

        local.reset()
        if due { onProgress(snapshot) }
    }
}
