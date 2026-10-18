// LayeredImageProfileTests.swift: a LayeredImage built without a profile
// (as every file without an embedded one reads) has `profile` nil, and a
// profile, when present, is part of the value.
import CoreColor
import CoreRaster
import Testing

@Test func layeredImageWithoutProfileHasNone() throws {
    let image = LayeredImage(width: 4, height: 3)
    #expect(image.profile == nil && image.bitsPerChannel == 8)
    let full = LayeredImage(width: 2, height: 2, nodes: [], composite: try PixelBuffer(width: 2, height: 2),
                            bitsPerChannel: 8)
    #expect(full.profile == nil)
}

@Test func layeredImageKeepsItsProfile() {
    let tagged = LayeredImage(width: 1, height: 1, profile: .displayP3)
    #expect(tagged.profile == .displayP3)
    #expect(tagged != LayeredImage(width: 1, height: 1))
    var untagged = tagged
    untagged.profile = nil
    #expect(untagged == LayeredImage(width: 1, height: 1))
}
