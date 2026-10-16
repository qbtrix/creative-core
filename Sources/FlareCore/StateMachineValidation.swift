// StateMachineValidation.swift: the format layer's check of the state machine
// invariants listed at the top of StateMachine.swift. FlareFormat.validate
// calls validateStateMachines; it throws FormatError.invalid on a duplicate
// machine id, or on the first error issue of a machine (StateMachineIssues.swift).
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension FlareFormat {
    /// Checks the invariants listed at the top of StateMachine.swift.
    static func validateStateMachines(_ document: Document) throws {
        var machineIDs = Set<String>()
        for machine in document.stateMachines {
            let m = machine.id
            guard machineIDs.insert(m).inserted else { throw FormatError.invalid("duplicate state machine id \(m)") }
            if let issue = machine.issues(in: document).first(where: { $0.severity == .error }) {
                throw FormatError.invalid("state machine \(m): \(issue.message)")
            }
        }
    }
}
