import Darwin
import Foundation

/// Süreç listesi ve süreç başına CPU/bellek.
///
/// **Neden `ps` çağırıyoruz.** İlk uygulama libproc kullanıyordu; ölçüldüğünde
/// makinedeki 666 sürecin yalnızca 371'ini gördüğü çıktı. `proc_pidinfo` başka
/// bir kullanıcının süreci için — WindowServer, coreaudiod, kernel_task — sıfır
/// döner. `/bin/ps` bunları gösterebiliyor çünkü hem setuid root hem de
/// `com.apple.system-task-ports.read` özel yetkisini taşıyor; o yetki Apple'a
/// ait, imzalansak da alamayız. Eksik tablo, "ne yiyor" sorusunun cevabını tam
/// da en sık suçlu olan sistem süreçlerinde kaybederdi.
///
/// Maliyet: kart açıkken üç saniyede bir süreç. Saniyede bir ölçülen CPU, bellek,
/// disk ve ağ bunun dışında, mach arayüzleriyle ve süreç doğurmadan alınıyor.
final class ProcessTable {

    private struct CPUTime {
        /// Sürecin doğduğundan beri harcadığı toplam CPU saniyesi.
        var seconds: Double
        var sampledAt: Date
    }

    private var previous: [Int32: CPUTime] = [:]

    /// Çalışan tüm süreçler. İlk çağrıda tüm CPU yüzdeleri sıfırdır: fark
    /// alınacak önceki örnek henüz yoktur.
    func snapshot() -> [ProcessRow] {
        guard let output = runPS() else { return [] }

        let now = Date()
        var seen: [Int32: CPUTime] = [:]
        var rows: [ProcessRow] = []

        for line in output.split(separator: "\n") {
            guard let row = parse(line, now: now, seen: &seen) else { continue }
            rows.append(row)
        }

        // Kapanmış süreçler fark tablosunda birikmesin.
        previous = seen
        return rows
    }

    func reset() { previous = [:] }

    // MARK: Çalıştırma

    /// `ps`in kendi `%cpu` sütunu kullanılmıyor: macOS'ta o sütun sürecin ömrü
    /// boyunca aldığı ORTALAMADIR, anlık yük değil. Uzun süredir açık bir
    /// uygulama bir dakikadır boş dursa bile yüksek görünür. Bunun yerine
    /// biriken CPU süresi okunup iki örnek arasındaki fark alınıyor.
    private func runPS() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pid=,rss=,cputime=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        // Boru okunmadan beklenirse büyük çıktıda kilitlenir: önce oku, sonra bekle.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Ayrıştırma

    private func parse(_ line: Substring, now: Date, seen: inout [Int32: CPUTime]) -> ProcessRow? {
        // Komut yolu boşluk içerebildiği için yalnızca ilk üç alan bölünür.
        let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard fields.count == 4,
              let pid = Int32(fields[0]),
              let residentKB = UInt64(fields[1]),
              let cpuSeconds = seconds(fromCPUTime: fields[2])
        else { return nil }

        seen[pid] = CPUTime(seconds: cpuSeconds, sampledAt: now)

        var cpu = 0.0
        if let was = previous[pid] {
            let elapsed = now.timeIntervalSince(was.sampledAt)
            if elapsed > 0, cpuSeconds >= was.seconds {
                cpu = (cpuSeconds - was.seconds) / elapsed
            }
        }

        let path = fields[3].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let name = path.contains("/") ? String(path.split(separator: "/").last ?? "") : path

        return ProcessRow(pid: pid,
                          name: name,
                          cpu: cpu,
                          memory: residentKB * 1024)
    }

    /// `ps` biçimi: `[[gg-]ss:]dd:ss.ss` — alanlar sondan başa sabit anlamda.
    private func seconds(fromCPUTime field: Substring) -> Double? {
        var days = 0.0
        var rest = field
        if let dash = rest.firstIndex(of: "-") {
            guard let value = Double(rest[rest.startIndex..<dash]) else { return nil }
            days = value
            rest = rest[rest.index(after: dash)...]
        }
        var total = 0.0
        for part in rest.split(separator: ":") {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return days * 86_400 + total
    }
}
