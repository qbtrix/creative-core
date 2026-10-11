// SymbolCycles.swift: rejects symbols that contain themselves, directly or
// through other symbols. The walk is an iterative depth-first search, so a
// chain of thousands of nested symbols cannot overflow the stack.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension FlareFormat {
    /// Throws `FormatError.invalid("symbol cycle ...")` if any symbol reaches
    /// itself through instances. Instances of unknown symbols are ignored here;
    /// `validate` reports them separately.
    static func checkSymbolCycles(_ symbols: [Symbol]) throws {
        var index: [String: Int] = [:]
        for (i, symbol) in symbols.enumerated() where index[symbol.id] == nil {
            index[symbol.id] = i
        }
        let edges: [[Int]] = symbols.map { symbol in
            symbol.layers.flatMap { layer in layer.instances.compactMap { index[$0.symbolID] } }
        }
        // 0 = unvisited, 1 = on the current path, 2 = finished.
        var state = [UInt8](repeating: 0, count: symbols.count)
        for root in symbols.indices where state[root] == 0 {
            // Each frame is (symbol, next edge to follow).
            var stack: [(node: Int, next: Int)] = [(root, 0)]
            state[root] = 1
            while let top = stack.last {
                let children = edges[top.node]
                guard top.next < children.count else {
                    state[top.node] = 2
                    stack.removeLast()
                    continue
                }
                stack[stack.count - 1].next += 1
                let child = children[top.next]
                switch state[child] {
                case 0:
                    state[child] = 1
                    stack.append((child, 0))
                case 1:
                    var path = stack.map { symbols[$0.node].id }
                    if let start = path.firstIndex(of: symbols[child].id) { path.removeFirst(start) }
                    path.append(symbols[child].id)
                    throw FormatError.invalid("symbol cycle \(path.joined(separator: " -> "))")
                default:
                    break
                }
            }
        }
    }
}
