// MetalBackend+Warmup.swift: the background pipeline compile (metal-backend MB-17, the packet's First launch
// row). `startingInBackground` returns at once with every family enabled at init held in
// `capabilities.compiling`, so `supports` lacks it and its ops throw `unsupported(<family>)` (a dispatcher
// draws them on the CPU), then compiles each family's built-in pipelines on a dispatch queue, never the
// caller's. Invariants: a build runs with the lock free and only the memo write takes it; a pipeline already
// memoised (an op that compiled it on first use) is kept; a family leaves `compiling` once all of its
// pipelines are memoised, or once its compile failed, which marks the backend failed with
// "compile <family>: ..." as a failed probe does, so after `recover` the family compiles on first use.
// The plain `init` keeps compiling on first use, under the lock.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// A backend on `device` whose built-in pipelines compile on `queue`: it returns without waiting, with
    /// `supports` empty and `capabilities.compiling` holding every family `init` enables; each family joins
    /// `supports` as its pipelines land. A failed compile marks the backend failed (`isHealthy` false,
    /// `capabilities.lastError` "compile <family>: ..."); nothing crashes. Throws as `init` does.
    public static func startingInBackground(device: any MTLDevice, cacheURL: URL?,
                                            queue: DispatchQueue = .global(qos: .userInitiated)) throws -> MetalBackend {
        let backend = try MetalBackend(device: device, cacheURL: cacheURL)
        let families = backend.withCapabilities { capabilities -> Set<RenderOp> in
            capabilities.startCompiling(capabilities.supported)
            return capabilities.supported
        }
        queue.async { backend.compileBuiltIns(families) }
        return backend
    }

    /// Every built-in pipeline `op` runs, key and MSL: blur's include unsharp's mask and resample's scatter
    /// kernel, and each composite family has one kernel per blend mode in it (`compositeKernel(for:)`).
    static func builtInPipelines(for op: RenderOp) -> [(key: PipelineKey, source: String)] {
        switch op {
        case .display: return [(DisplayShader.key, DisplayShader.source), (DisplayShader.targetKey, DisplayShader.source)]
        case .transform: return [(TransformShader.key, TransformShader.source)]
        case .resample: return [(ResampleShader.pass, ResampleShader.source), (ResampleShader.scatter, ResampleShader.source)]
        case .blur:
            return [(BlurShader.pass, BlurShader.source), (UnsharpShader.mask, UnsharpShader.source),
                    (ResampleShader.scatter, ResampleShader.source)]
        case .adjust: return [(AdjustShader.key, AdjustShader.source)]
        case .retouch: return [(RetouchShader.key, RetouchShader.source)]
        case .composite, .blendSeparable, .blendNonSeparable:
            return BlendMode.allCases.filter { RenderOp(compositing: $0) == op }.compactMap { try? compositeKernel(for: $0) }
        case .maskedComposite, .affine, .effect, .color: return []  // `RenderOp.notOnMetalYet`: no kernels yet
        }
    }

    /// Builds `families`' pipelines in `RenderOp` order, each with the lock free, memoises each under the lock
    /// and lets each family out of `compiling` when it is done or has failed. Runs on the background queue.
    func compileBuiltIns(_ families: Set<RenderOp>) {
        withLock { compiledOnMainThread = Thread.isMainThread }
        for op in RenderOp.allCases where families.contains(op) {
            do {
                for (key, source) in Self.builtInPipelines(for: op) where !withLock({ pipelines.holds(key) }) {
                    let state = try MetalPipelines.build(key, source: source, on: device)
                    withLock { pipelines.install(state, for: key) }
                }
            } catch {
                fail("compile \(op.rawValue): \(error)")
            }
            withCapabilities { $0.finishCompiling(op) }
        }
    }
}
#endif
