// MachinePlayer.swift: evaluation layer. Plays one state machine of a document:
// which state it is in, which scene frame that state shows, and the current
// input values. Triggers move it between states; advancing loops the current
// state's frame range. Reads the model, never changes the document.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Plays a state machine. Create one per machine you want to run, then call
/// `fire` when a trigger happens (for example "pointerEnter"), `set` when an
/// input changes, and `advance` once per displayed frame. Read `stateID` and
/// `frame` to know what to draw: frame `frame` of the current state's scene.
/// The same calls in the same order always give the same states and frames.
public struct MachinePlayer: Sendable, Hashable {
    /// The machine being played, copied from the document at `init`.
    public let machine: StateMachine
    /// The id of the current state.
    public private(set) var stateID: String
    /// The scene frame showing now: a frame of the current state's scene,
    /// always inside that state's `startFrame...endFrame`.
    public private(set) var frame: Int
    /// The current value of every declared input, by name. Starts at each
    /// input's declared default.
    public private(set) var inputs: [String: InputValue]

    /// Starts machine `machineID` of `document` in its initial state, at that
    /// state's `startFrame`, with every input at its default.
    /// Throws `TimelineError.stateMachineNotFound` when the document has no
    /// machine with that id, and `TimelineError.invalidMachine` with the first
    /// error issue when the machine breaks a rule (see `issues(in:)`).
    public init(machineID: String, in document: Document) throws {
        guard let found = document.stateMachines.first(where: { $0.id == machineID }) else {
            throw TimelineError.stateMachineNotFound(machineID)
        }
        if let issue = found.firstError(in: document) {
            throw TimelineError.invalidMachine(issue)
        }
        guard let initial = found.states.first(where: { $0.id == found.initialState }) else {
            throw TimelineError.stateMachineNotFound(machineID)  // unreachable: issues(in:) checks it
        }
        machine = found
        stateID = initial.id
        frame = initial.startFrame
        inputs = found.defaultInputValues
    }

    /// Sets input `input` to `value` and returns true. Returns false and
    /// changes nothing when the machine declares no such input, when `value`
    /// has another type than the input's default, or when it is a non-finite
    /// number. Setting an input never changes state by itself; conditions are
    /// read the next time a trigger fires.
    public mutating func set(_ input: String, to value: InputValue) -> Bool {
        guard let current = inputs[input], current.sameType(as: value), value.isFinite else { return false }
        inputs[input] = value
        return true
    }

    /// Fires trigger `trigger`. The first transition (in declaration order)
    /// from the current state with this trigger whose conditions hold moves
    /// the player to its target state and restarts that state at its
    /// `startFrame`, even when the target is the current state. A trigger no
    /// transition takes, or an unknown one, changes nothing.
    public mutating func fire(_ trigger: String) {
        guard let transition = machine.firing(from: stateID, trigger: trigger, inputs: inputs),
            let target = machine.states.first(where: { $0.id == transition.to })
        else { return }
        stateID = target.id
        frame = target.startFrame
    }

    /// Moves `count` frames forward, looping the current state's
    /// `startFrame...endFrame` range: one past `endFrame` is `startFrame`.
    /// A count of 0 or less changes nothing. Never overflows, even for a
    /// state spanning `0...Int.max` and a count of `Int.max`.
    public mutating func advance(frames count: Int) {
        guard count > 0, let state = machine.states.first(where: { $0.id == stateID }),
            state.startFrame >= 0, state.startFrame <= frame, frame <= state.endFrame
        else { return }
        // Durations have no upper limit, so work in UInt: end - start <= Int.max,
        // so length <= 2^63, and offset + count % length < 2^64.
        let length = UInt(state.endFrame - state.startFrame) + 1
        let step = (UInt(frame - state.startFrame) + UInt(count) % length) % length
        frame = state.startFrame + Int(step)  // step <= end - start, so this fits
    }
}
