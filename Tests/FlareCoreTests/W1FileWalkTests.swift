// W1FileWalkTests.swift: engine-contracts EC-9, the file half of KJ-EC. A v1
// `.flare` written before W1 (no W1 field anywhere) and one that sets every
// W1 field W1Model.swift defines (layer masks, a track matte, text runs, a
// paragraph style, text on a path, colour tracks for a fill, a stroke and a
// text, and a shape track) both decode and pass `FlareFormat.validate`, with
// every value inside its documented range.
import FlareCore
import Foundation
import Testing

@Suite struct W1FileWalkTests {
    static let red = #"{"r":1,"g":0,"b":0,"a":1}"#
    static let blue = #"{"r":0,"g":0,"b":1,"a":1}"#
    static let square = #"{"elements":[{"move":{"to":{"x":0,"y":0}}},{"line":{"to":{"x":10,"y":0}}},"#
        + #"{"line":{"to":{"x":10,"y":10}}},{"close":{}}]}"#

    /// A v1 file: a background layer and a layer with one shape and one text.
    /// `extra` adds fields to the shape layer, `textExtra` to its text.
    static func file(extra: String = "", textExtra: String = "") -> String {
        #"{"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":24,"#
            + #""width":64,"height":64,"layers":[{"id":"bg","name":"Bg","shapes":[],"tracks":{}},"#
            + #"{"id":"ball","name":"Ball","tracks":{},"shapes":[{"closed":true,"fill":\#(red),"#
            + #""stroke":{"color":\#(blue),"width":2,"join":"miter","cap":"butt"},"#
            + #""points":[{"x":0,"y":0},{"x":10,"y":0},{"x":10,"y":10}]}],"#
            + #""texts":[{"string":"Hello","fontFamily":"Inter","fontSize":12,"position":{"x":1,"y":2},"#
            + #""fill":\#(red)\#(textExtra)}]\#(extra)}]}]}}"#
    }

    /// The W1 fields of the shape layer, each value inside its range.
    static let layerFields = #","masks":[{"path":\#(square),"mode":"subtract","feather":2,"opacity":0.5,"#
        + #""inverted":true},{"path":\#(square),"mode":"intersect","feather":0,"opacity":1,"inverted":false}],"#
        + #""matte":{"sourceLayerID":"bg","kind":"lumaInverted"},"#
        + #""colorTracks":{"fill.0":[{"frame":0,"value":\#(red),"easing":{"linear":{}}},"#
        + #"{"frame":24,"value":\#(blue),"easing":{"hold":{}}}],"#
        + #""stroke.0":[{"frame":6,"value":\#(blue),"easing":{"linear":{}}}],"#
        + #""text.0":[{"frame":12,"value":\#(red),"easing":{"linear":{}}}]},"#
        + #""shapeTracks":[{"shapeIndex":0,"keys":[{"frame":0,"path":\#(square),"easing":{"linear":{}}},"#
        + #"{"frame":12,"path":\#(square),"easing":{"cubicBezier":{"x1":0.42,"y1":0,"x2":0.58,"y2":1}}}]}]"#

    /// The W1 fields of the text, each value inside its range.
    static let textFields = #","runs":[{"start":0,"length":2,"fontFamily":"Inter","fontSize":14,"weight":700,"#
        + #""italic":true,"fill":\#(blue)},{"start":2,"length":3,"tracking":0.5,"baselineShift":-1}],"#
        + #""paragraph":{"alignment":"justified","lineHeight":1.5,"tracking":0.25,"paragraphSpacing":4,"boxWidth":200},"#
        + #""onPath":{"path":\#(square),"startOffset":0.25,"flipped":true}"#

    @Test func walk() throws {
        // A file from before W1: decodes with every W1 field at its default, and validates.
        let old = try FlareFormat.decode(Data(Self.file().utf8))
        try FlareFormat.validate(old)
        let plain = old.scenes[0].layers[1]
        #expect(plain.masks.isEmpty && plain.matte == nil && plain.colorTracks.isEmpty && plain.shapeTracks.isEmpty)
        #expect(plain.texts[0].runs.isEmpty && plain.texts[0].paragraph == nil && plain.texts[0].onPath == nil)

        // The same file with every W1 field set: decodes each one, and validates.
        let full = try FlareFormat.decode(Data(Self.file(extra: Self.layerFields, textExtra: Self.textFields).utf8))
        try FlareFormat.validate(full)
        let layer = full.scenes[0].layers[1]
        #expect(layer.masks.map(\.mode) == [.subtract, .intersect])
        #expect(layer.masks[0] == LayerMask(path: layer.masks[0].path, mode: .subtract, feather: 2, opacity: 0.5,
                                             inverted: true))
        #expect(layer.matte == TrackMatte(sourceLayerID: "bg", kind: .lumaInverted))
        #expect(Set(layer.colorTracks.keys) == ["fill.0", "stroke.0", "text.0"])
        #expect(layer.colorTracks["fill.0"]?.map(\.frame) == [0, 24])
        #expect(layer.shapeTracks.map(\.shapeIndex) == [0])
        #expect(layer.shapeTracks[0].keys.map(\.easing) == [.linear, .easeInOut])
        let text = layer.texts[0]
        #expect(text.runs == [TextRun(start: 0, length: 2, fontFamily: "Inter", fontSize: 14, weight: 700, italic: true,
                                      fill: .solid(Color(r: 0, g: 0, b: 1, a: 1))),
                              TextRun(start: 2, length: 3, tracking: 0.5, baselineShift: -1)])
        #expect(text.paragraph == ParagraphStyle(alignment: .justified, lineHeight: 1.5, tracking: 0.25,
                                                 paragraphSpacing: 4, boxWidth: 200))
        #expect(text.onPath?.startOffset == 0.25 && text.onPath?.flipped == true)
        #expect(text.onPath?.path == layer.masks[0].path)

        // Only the W1 fields differ: the full file without them is the old one.
        var stripped = layer
        (stripped.masks, stripped.matte, stripped.colorTracks, stripped.shapeTracks) = ([], nil, [:], [])
        (stripped.texts[0].runs, stripped.texts[0].paragraph, stripped.texts[0].onPath) = ([], nil, nil)
        #expect(stripped == plain)
    }
}
