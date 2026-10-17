// MetalCapabilitiesTests.swift: the capability and health state the dispatcher
// reads. A fresh value supports nothing and is healthy; `fail` turns healthy
// off with the reason but keeps `supported`; `recover` restores health and
// clears the reason; `enable` is idempotent and never heals; a family still
// compiling stays in `supported` but out of `effectiveSupports` until it finishes.
import CoreRender
import Testing

@Suite struct MetalCapabilitiesTests {
    @Test func aFreshValueSupportsNothingAndIsHealthy() {
        let capabilities = MetalCapabilities()
        #expect(capabilities.supported.isEmpty)
        #expect(capabilities.healthy)
        #expect(capabilities.lastError == nil)
    }

    @Test func failKeepsSupportedAndTurnsUnhealthyWithTheReason() {
        var capabilities = MetalCapabilities()
        capabilities.enable(.display)
        capabilities.enable(.composite)
        capabilities.fail("command buffer error: device lost")
        #expect(capabilities.supported == [.display, .composite], "the status note still says what would run")
        #expect(capabilities.healthy == false)
        #expect(capabilities.lastError == "command buffer error: device lost")
        capabilities.fail("second")
        #expect(capabilities.lastError == "second", "a later failure replaces the reason")
        capabilities.enable(.adjust)
        #expect(capabilities.supported == [.display, .composite, .adjust])
        #expect(capabilities.healthy == false, "enabling an op does not heal the backend")
    }

    @Test func recoverRestoresHealthClearsTheErrorAndKeepsSupported() {
        var capabilities = MetalCapabilities()
        capabilities.enable(.transform)
        capabilities.fail("device lost")
        capabilities.recover()
        #expect(capabilities.healthy)
        #expect(capabilities.lastError == nil)
        #expect(capabilities.supported == [.transform])
    }

    @Test func enableTwiceIsTheSameAsOnce() {
        var once = MetalCapabilities()
        once.enable(.blur)
        var twice = MetalCapabilities()
        twice.enable(.blur)
        twice.enable(.blur)
        #expect(once == twice)
        #expect(twice.supported == [.blur])
    }

    @Test func failEmptiesEffectiveSupportsAndRecoverRestoresIt() {
        var capabilities = MetalCapabilities()
        capabilities.enable(.display)
        #expect(capabilities.effectiveSupports == [.display])
        capabilities.fail("x")
        #expect(capabilities.effectiveSupports.isEmpty, "an unhealthy backend supports nothing")
        #expect(capabilities.supported == [.display])
        capabilities.recover()
        #expect(capabilities.effectiveSupports == [.display])
    }

    @Test func aCompilingFamilyIsHeldOutUntilItFinishes() {
        var capabilities = MetalCapabilities()
        for op in [RenderOp.display, .blur, .composite] { capabilities.enable(op) }
        capabilities.startCompiling([.blur, .composite])
        #expect(capabilities.compiling == [.blur, .composite])
        #expect(capabilities.effectiveSupports == [.display], "a cold family draws on the CPU")
        #expect(capabilities.supported == [.display, .blur, .composite], "compiling keeps supported")
        capabilities.finishCompiling(.blur)
        #expect(capabilities.effectiveSupports == [.display, .blur])
        capabilities.fail("x")
        #expect(capabilities.effectiveSupports.isEmpty)
        capabilities.recover()
        capabilities.finishCompiling(.composite)
        #expect(capabilities.compiling.isEmpty && capabilities.effectiveSupports == capabilities.supported)
    }
}
