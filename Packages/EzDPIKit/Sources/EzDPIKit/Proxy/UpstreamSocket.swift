import Foundation

/// The outbound half of a session, on a plain BSD socket.
///
/// Deliberately not `NWConnection`. Network.framework applies the **system**
/// proxy configuration to the connections it makes — and Kalfa's system proxy
/// points at this very engine, so every upstream connection was handed straight
/// back to us and sat there until it timed out. Every request through the
/// engine hung, while the engine looked perfectly healthy in the log.
///
/// Measured on this machine with the system proxy on: `NWConnection` to a
/// hostname times out, `NWConnection` to a literal IP times out as well (the
/// proxy applies either way), and a POSIX socket connects immediately. The
/// framework offers `nw_parameters_set_prefer_no_proxy` for exactly this, but
/// only in C, and `NWParameters` cannot be bridged to the C type from Swift.
///
/// A socket has no opinion about proxies, and it also gives finer control over
/// when bytes are handed to the kernel — which is the whole point of the engine.
final class UpstreamSocket {

    private let queue: DispatchQueue
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var closed = false

    /// Incoming bytes from the server.
    var onData: ((Data) -> Void)?
    /// The far end went away.
    var onClose: (() -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    // MARK: Connect

    /// Resolves and connects without blocking the queue. `ready(false)` means
    /// the caller should give up on this session.
    func connect(host: String, port: UInt16, timeout: TimeInterval = 10, ready: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { return ready(false) }

            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var info: UnsafeMutablePointer<addrinfo>?
            // Handles both a name and a literal address, so a rule that resolved
            // over DoH can hand us the IP it got.
            guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
                return ready(false)
            }
            defer { freeaddrinfo(info) }

            let socketFD = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
            guard socketFD >= 0 else { return ready(false) }

            // Separate writes must reach the wire separately; Nagle would glue
            // the fragments back together and undo the whole exercise.
            var on: Int32 = 1
            setsockopt(socketFD, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
            // Writing to a socket the far end closed raises SIGPIPE and kills
            // the app; ask for EPIPE instead.
            setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(socketFD, F_SETFL, fcntl(socketFD, F_GETFL, 0) | O_NONBLOCK)

            let result = Darwin.connect(socketFD, first.pointee.ai_addr, first.pointee.ai_addrlen)
            if result == 0 {
                self.fd = socketFD
                self.startReading()
                return ready(true)
            }
            guard errno == EINPROGRESS else {
                Darwin.close(socketFD)
                return ready(false)
            }

            // Non-blocking connect finishes when the socket becomes writable;
            // SO_ERROR says whether it finished well.
            var settled = false
            let source = DispatchSource.makeWriteSource(fileDescriptor: socketFD, queue: self.queue)
            source.setEventHandler { [weak self] in
                guard let self, !settled else { return }
                settled = true
                source.cancel()
                self.writeSource = nil

                var error: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &length)
                guard error == 0 else {
                    Darwin.close(socketFD)
                    return ready(false)
                }
                self.fd = socketFD
                self.startReading()
                ready(true)
            }
            self.writeSource = source
            source.resume()

            self.queue.asyncAfter(deadline: .now() + timeout) {
                guard !settled else { return }
                settled = true
                source.cancel()
                self.writeSource = nil
                Darwin.close(socketFD)
                ready(false)
            }
        }
    }

    // MARK: Read

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(self.fd, &buffer, buffer.count)
            if count > 0 {
                self.onData?(Data(buffer[0..<count]))
            } else if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
                self.close()
            }
        }
        readSource = source
        source.resume()
    }

    // MARK: Write

    /// Hands one piece to the kernel and calls back when it is all gone.
    ///
    /// The caller sends fragments one at a time, waiting for each — queuing them
    /// together would let them leave as a single segment.
    func send(_ data: Data, then: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var remaining = data
            while !remaining.isEmpty {
                let written = remaining.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return write(self.fd, base, raw.count)
                }
                if written > 0 {
                    remaining = remaining.dropFirst(written)
                } else if written < 0 && (errno == EAGAIN || errno == EINTR) {
                    // The send buffer is full; let it drain rather than spin.
                    usleep(1_000)
                } else {
                    return self.close()
                }
            }
            then()
        }
    }

    // MARK: Teardown

    func close() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        readSource = nil
        writeSource?.cancel()
        writeSource = nil
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        onClose?()
        onClose = nil
        onData = nil
    }
}
