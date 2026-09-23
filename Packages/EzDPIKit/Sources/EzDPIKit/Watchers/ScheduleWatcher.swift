import Foundation

/// Zaman kurallarının yeniden değerlendirilmesi için düzenli tetikleyici.
/// Dakika hassasiyeti yeterli, 30 saniyede bir bakmak fazlasıyla yakın.
@MainActor
final class ScheduleWatcher {
    private var timer: Timer?

    func start(onTick: @escaping () -> Void) {
        timer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor in onTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Şu anki dakika (gece yarısından itibaren) ve haftanın günü (1=Pazar).
    static func now() -> (minute: Int, weekday: Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute, .weekday], from: Date())
        return ((comps.hour ?? 0) * 60 + (comps.minute ?? 0), comps.weekday ?? 1)
    }

    /// Gece yarısını aşan aralıkları da doğru değerlendirir (23:00 - 02:00 gibi).
    static func inRange(start: Int, end: Int, now: Int) -> Bool {
        start <= end ? (now >= start && now < end) : (now >= start || now < end)
    }
}
