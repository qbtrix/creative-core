// ColorError.swift: the one error type of CoreColor, the shared color module
// (color spaces and conversions). CoreColor is Linux-safe, Foundation only, and
// depends on no other target. Every throwing API in this module throws this.
public enum ColorError: Error, Equatable, Sendable {
    /// A component or parameter is NaN, infinite or out of its allowed range. Also thrown by ICC
    /// read and write: damaged bytes, or a profile kind (LUT-based, CMYK, Lab) that is not
    /// supported; the text names which.
    case invalid(String)
}
