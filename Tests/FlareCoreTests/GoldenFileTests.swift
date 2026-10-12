// GoldenFileTests.swift: pins the .flare encoding of `Fixtures.document()` byte
// for byte, so encoder differences between Linux and macOS show up in CI. If
// you change the format on purpose, copy the printed actual output into
// `golden` in the same PR.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import FlareCore
import Testing

@Suite struct GoldenFileTests {
    static let golden = """
    {
      "document" : {
        "scenes" : [
          {
            "background" : {
              "a" : 1,
              "b" : 1,
              "g" : 1,
              "r" : 1
            },
            "durationFrames" : 48,
            "fps" : 24,
            "guides" : [

            ],
            "height" : 400,
            "id" : "s1",
            "labels" : {
              "start" : 0
            },
            "layers" : [
              {
                "id" : "bg",
                "instances" : [

                ],
                "isLocked" : false,
                "isVisible" : true,
                "name" : "Background",
                "shapes" : [

                ],
                "tracks" : {

                }
              },
              {
                "id" : "ball",
                "instances" : [

                ],
                "isLocked" : false,
                "isVisible" : true,
                "name" : "Ball",
                "shapes" : [
                  {
                    "closed" : true,
                    "fill" : {
                      "a" : 1,
                      "b" : 0.25,
                      "g" : 0.5,
                      "r" : 1
                    },
                    "points" : [
                      {
                        "x" : 0,
                        "y" : 0
                      },
                      {
                        "x" : 10,
                        "y" : 0
                      },
                      {
                        "x" : 10,
                        "y" : 10
                      },
                      {
                        "x" : 0,
                        "y" : 10
                      }
                    ]
                  }
                ],
                "tracks" : {
                  "x" : [
                    {
                      "easing" : {
                        "cubicBezier" : {
                          "x1" : 0.42,
                          "x2" : 0.58,
                          "y1" : 0,
                          "y2" : 1
                        }
                      },
                      "frame" : 0,
                      "value" : 0
                    },
                    {
                      "easing" : {
                        "linear" : {

                        }
                      },
                      "frame" : 24,
                      "value" : 100
                    }
                  ]
                }
              }
            ],
            "name" : "Main",
            "width" : 550
          }
        ],
        "symbols" : [

        ]
      },
      "format" : "flare",
      "version" : 1
    }
    """

    @Test func encodeMatchesGolden() throws {
        let data = try FlareFormat.encode(Fixtures.document())
        let actual = String(decoding: data, as: UTF8.self)
        #expect(actual == Self.golden, "encoding changed; actual output:\n\(actual)")
    }

    @Test func decodingGoldenGivesFixture() throws {
        let document = try FlareFormat.decode(Data(Self.golden.utf8))
        #expect(document == Fixtures.document())
    }
}
