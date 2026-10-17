// MetalCapabilities.swift: what the Metal backend has proven it can run, and
// whether it is fit to run it right now. `RenderDispatcher` reads both: an
// op goes to Metal only when it is in `supported` and the backend is `healthy`.
// Invariants: `supported` only ever grows, and `fail` keeps it (so a status
// note can still say what would run on a working device); `healthy` and
// `lastError` move together, `fail` setting both and `recover` clearing both;
// `effectiveSupports` is empty while not healthy.

/// The Metal backend's capability and health state, as routing will see it.
public struct MetalCapabilities: Equatable, Sendable {
    /// The op families the backend has proven by parity against the CPU.
    /// `RenderDispatcher` sends an op to Metal only when it is here, and
    /// every other op to the CPU. Grows one family per slice; `fail` does not shrink it.
    public private(set) var supported: Set<RenderOp>

    /// False after a device loss or command-buffer error, until `recover()`.
    /// An unhealthy backend is to be routed around: `RenderDispatcher`
    /// sends every op, supported or not, to the CPU.
    public private(set) var healthy: Bool

    /// The reason of the last `fail`, nil while healthy. Shown in the
    /// rendering status note so the user can see why the GPU is off.
    public private(set) var lastError: String?

    /// What the backend reports as its `supports`: `supported` while healthy,
    /// and nothing while not, so `RenderDispatcher` sends every op to the
    /// CPU after a device loss until `recover()`.
    public var effectiveSupports: Set<RenderOp> {
        healthy ? supported : []
    }

    /// A healthy backend that supports nothing yet, with no error.
    public init() {
        supported = []
        healthy = true
        lastError = nil
    }

    /// Marks `op` as proven: `RenderDispatcher` may send it to Metal while
    /// the backend is healthy. Enabling an op twice is the same as once.
    public mutating func enable(_ op: RenderOp) {
        supported.insert(op)
    }

    /// Records a device loss or command-buffer error: the backend turns
    /// unhealthy with `reason` as `lastError`, so `RenderDispatcher` sends
    /// everything to the CPU. `supported` is kept, so the status note can say
    /// what would run once the backend recovers.
    public mutating func fail(_ reason: String) {
        healthy = false
        lastError = reason
    }

    /// Called once the backend has a working command queue again: it is
    /// healthy with no error, and `supported` is as it was before the failure.
    public mutating func recover() {
        healthy = true
        lastError = nil
    }
}
