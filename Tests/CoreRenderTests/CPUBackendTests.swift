// RB-3 owns the CPU backend tests. RB-2 leaves this file with one disabled
// placeholder so the target builds before CPUBackend exists.
import Testing

@Test(.disabled("waits on RB-3: CPUBackend"))
func cpuBackendPlaceholder() {}
