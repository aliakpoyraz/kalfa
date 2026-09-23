import Combine
import Foundation

/// Bakım işlemlerini sırayla çalıştırır ve sonucu bildirir.
@MainActor
public final class OptimizeService: ObservableObject {

    public static let shared = OptimizeService()

    /// Şu an çalışan işlem; yoksa nil.
    @Published public private(set) var running: Optimizer.Task?
    /// İşlem kimliği -> son sonuç.
    @Published public private(set) var results: [String: Result<Void, Error>] = [:]

    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.optimize", qos: .userInitiated)

    private init() {}

    public var tasks: [Optimizer.Task] { Optimizer.all }

    public func succeeded(_ task: Optimizer.Task) -> Bool {
        if case .success = results[task.id] { return true }
        return false
    }

    public func failure(_ task: Optimizer.Task) -> String? {
        if case .failure(let error) = results[task.id] { return error.localizedDescription }
        return nil
    }

    public func run(_ task: Optimizer.Task) {
        guard running == nil else { return }
        running = task
        results[task.id] = nil

        queue.async { [weak self] in
            let outcome: Result<Void, Error>
            do {
                try Optimizer.run(task)
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            Task { @MainActor [weak self] in
                self?.results[task.id] = outcome
                self?.running = nil
            }
        }
    }
}
