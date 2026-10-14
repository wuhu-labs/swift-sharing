import Testing

@_spi(OwnedObservation) @testable import Sharing

struct OwnedObservationTests {
  @Test func cancellingReleasesReentrantCaptureOutsideTokenLock() {
    let source = SharedObservationSource()
    let probe = CancellationProbe()
    weak var witness: ReentrantCancellation?
    let subscription: SharedSubscription
    do {
      let capture = ReentrantCancellation(probe: probe)
      witness = capture
      subscription = source.subscribe(to: [\Int.self]) {
        withExtendedLifetime(capture) {}
      }
      capture.subscription.withLock { $0 = subscription }
    }
    #expect(witness != nil)
    subscription.cancel()
    #expect(witness == nil)
    #expect(probe.didDeinit.withLock { $0 })
    subscription.cancel()
  }
}

private final class ReentrantCancellation: Sendable {
  let subscription = Mutex<SharedSubscription?>(nil)
  let probe: CancellationProbe

  init(probe: CancellationProbe) {
    self.probe = probe
  }

  deinit {
    subscription.withLock { $0 }?.cancel()
    probe.didDeinit.withLock { $0 = true }
  }
}

private final class CancellationProbe: Sendable {
  let didDeinit = Mutex(false)
}
