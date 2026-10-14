# Owned observation bridge

This fork adds the `OwnedObservation` SPI for Wuhu's TCA2 fork. `SharedObservationSource.collect`
collects synchronous `Shared` and `SharedReader` accesses (both boxed and persistent references).
`subscribe(to:onChange:)` returns a cancellable `SharedSubscription`. Cancellation only removes
that subscription: it never mutates observable state or registers a synthetic Apple dependency.
The source retains active callbacks; subscription owners must cancel or release their tokens.

This SPI deliberately does not provide a generic Swift Observation replacement. The TCA caller
combines nested access lists, deduplicates source/key-path pairs, owns one-shot subscriptions and
cancels all of them on the first notification or when the feature is remounted/dismounted.
Collection is thread-local and synchronous; async work does not inherit its access scope.

Normal Perception/Observation access and mutation forwarding remains unchanged. Notifications
follow Sharing's existing scheduling, including dispatch to the main queue for off-main mutations.
Callbacks are invoked outside the source's lock, allowing cancellation from a callback.

Integration regressions live in TCA's `ObservationOwnershipTests`: nested SharedReader tracking,
one-shot cancellation and callback release, boxed and persistent sources, actual Shared-driven
151-remount retention (live environments stay 1/1/1), and enclosing Apple tracker behavior. TCA's
existing Shared-backed on-change/on-mount fixtures must also pass. Upstream Shared public API,
platform floors, package manifests and Perception implementation are unchanged.
