import Foundation

// Separate from Perception/Observation: cancelling an owned observer must never mutate a value or
// register a synthetic access in an enclosing UI tracker.
@_spi(OwnedObservation)
public final class SharedObservationSource: @unchecked Sendable {
  private struct Observer {
    var keyPaths: Set<AnyKeyPath>
    var onChange: @Sendable () -> Void
  }
  private let lock = NSLock()
  private var observers: [UUID: Observer] = [:]

  init() {}

  public func subscribe(
    to keyPaths: Set<AnyKeyPath>,
    onChange: @escaping @Sendable () -> Void
  ) -> SharedSubscription {
    let id = UUID()
    lock.lock()
    observers[id] = Observer(keyPaths: keyPaths, onChange: onChange)
    lock.unlock()
    return SharedSubscription { [self] in
      lock.lock()
      observers.removeValue(forKey: id)
      lock.unlock()
    }
  }

  func access(_ keyPath: AnyKeyPath) {
    SharedAccessScope.current?.onAccess(self, keyPath)
  }

  func willSet(_ keyPath: AnyKeyPath) {
    lock.lock()
    let callbacks = observers.values.filter { $0.keyPaths.contains(keyPath) }.map(\.onChange)
    lock.unlock()
    for callback in callbacks { callback() }
  }

  /// Captures synchronous Shared/SharedReader accesses without installing any Apple tracking.
  /// The caller owns subscriptions and decides how nested access lists are combined.
  public static func collect<T>(
    _ apply: () throws -> T,
    onAccess: @escaping (SharedObservationSource, AnyKeyPath) -> Void
  ) rethrows -> T {
    let previous = SharedAccessScope.current
    SharedAccessScope.current = SharedAccessScope(onAccess: onAccess)
    defer { SharedAccessScope.current = previous }
    return try apply()
  }
}

private final class SharedAccessScope {
  let onAccess: (SharedObservationSource, AnyKeyPath) -> Void

  init(onAccess: @escaping (SharedObservationSource, AnyKeyPath) -> Void) {
    self.onAccess = onAccess
  }

  #if os(WASI)
    // WASI is single-threaded.
    nonisolated(unsafe) static var current: SharedAccessScope?
  #else
    private static let key = "co.pointfree.Sharing.OwnedObservation.accessScope"
    static var current: SharedAccessScope? {
      get { Thread.current.threadDictionary[key] as? SharedAccessScope }
      set { Thread.current.threadDictionary[key] = newValue }
    }
  #endif
}
