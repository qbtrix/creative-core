// ColorErrorTests.swift: CoreColor's test target. Conversion tests land here.
import CoreColor
import Testing

@Test func colorErrorsCompareByMessage() {
    #expect(ColorError.invalid("a") == ColorError.invalid("a"))
    #expect(ColorError.invalid("a") != ColorError.invalid("b"))
}
