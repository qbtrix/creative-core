// LayeredImage.swift: the neutral layered image the codecs read and write.
// A stack of pixel layers (each placed at an integer offset, with opacity,
// blend mode, visibility, clipping and an optional placed mask) and nested
// groups, bottom to top, plus the optional merged composite. Any app maps its
// own layers to and from this; PSD and OpenRaster translate it to bytes.
// The ICC profile the file embeds rides along; nil when it has none.
// CodecError is the error the layered codecs throw: `PSD.read`, `PSD.write`,
// `OpenRaster.read`, `OpenRaster.write`, `ZipStore.archive`,
// `ZipStore.entries` and a `PixelCodec`'s `decodePNG` and `encodePNG`. Every
// other CoreRaster API throws `RasterError`.
import CoreColor

/// A layered image: canvas size, the layer tree bottom to top, the merged
/// composite when the file carries one, the channel depth it was read at and
/// the colour profile it embeds.
public struct LayeredImage: Equatable, Sendable {
    /// The canvas size in pixels. Layers and masks are placed on it.
    public var width: Int, height: Int
    /// The layer tree, bottom to top: the first node is drawn first.
    public var nodes: [LayerNode]
    /// The flattened image stored in the file (canvas size), if any; nil when
    /// the file carries none.
    public var composite: PixelBuffer?
    /// Bits per channel of the file's samples: 8 (0...255) or 16 (0...65535).
    /// Pixels in memory are Float32 whatever this is; it records the depth the
    /// file was read at and the depth a writer saves. 8 or 16; PSD and
    /// OpenRaster read and write both, and a writer throws
    /// `CodecError.unsupported` for any other value.
    public var bitsPerChannel: Int
    /// The embedded colour profile; nil when the file has none or embeds one
    /// `ColorProfile(iccData:)` refuses (the readers then open the image
    /// without it). PSD writes a grayscale file for a gray profile.
    /// The pixels are the file's numbers decoded with the sRGB curve, not with
    /// this profile's curves; convert them with
    /// `PixelBuffer.converted(from: profile, to:)`, which undoes that decode,
    /// not with `ProfileTransform.applyLinear` directly.
    public var profile: ColorProfile?

    public init(width: Int, height: Int, nodes: [LayerNode] = [],
                composite: PixelBuffer? = nil, bitsPerChannel: Int = 8, profile: ColorProfile? = nil) {
        self.width = width
        self.height = height
        self.nodes = nodes
        self.composite = composite
        self.bitsPerChannel = bitsPerChannel
        self.profile = profile
    }
}

/// One entry of a layer tree: a pixel layer or a group of entries.
public enum LayerNode: Equatable, Sendable {
    case pixels(PixelLayer), group(LayerGroup)

    /// The synthesized `==`, compared with an explicit stack: recursing through
    /// `OpenRaster.maxDepth` groups overflows the 512 KB stack of a secondary
    /// thread on macOS. Groups compare every field but `children` with their
    /// own `==`, then their children pairwise.
    public static func == (lhs: LayerNode, rhs: LayerNode) -> Bool {
        var pending = [(lhs, rhs)]
        while let (a, b) = pending.popLast() {
            switch (a, b) {
            case let (.pixels(a), .pixels(b)): guard a == b else { return false }
            case let (.group(a), .group(b)):
                var (bareA, bareB) = (a, b)
                (bareA.children, bareB.children) = ([], [])
                guard bareA == bareB, a.children.count == b.children.count else { return false }
                pending += zip(a.children, b.children)
            default: return false
            }
        }
        return true
    }
}

/// A pixel layer with its top left at (`x`, `y`) on the canvas; it may lie
/// partly or wholly outside it.
public struct PixelLayer: Equatable, Sendable {
    /// The layer's name as the file stores it, in Unicode.
    public var name: String
    /// The layer's own pixels; their size is the layer's bounds, not the canvas.
    public var pixels: PixelBuffer
    /// The canvas pixel the layer's top left pixel sits on, counted from the
    /// canvas's top left (0, 0), x to the right and y down. Negative or past
    /// the canvas is allowed.
    public var x: Int, y: Int
    /// How much of the layer shows, 0...1: 0 is invisible, 1 is fully opaque.
    /// It multiplies the pixels' own alpha.
    public var opacity: Float
    /// How the layer combines with what is below it.
    public var blendMode: BlendMode
    /// Hidden layers are kept in the file but not drawn.
    public var isHidden: Bool
    /// Clipped to the layer below it: shows only where that layer has alpha.
    public var clipsToBelow: Bool
    /// The layer's mask, nil when it has none.
    public var mask: PlacedMask?

    public init(name: String, pixels: PixelBuffer, x: Int = 0, y: Int = 0,
                opacity: Float = 1, blendMode: BlendMode = .normal, isHidden: Bool = false,
                clipsToBelow: Bool = false, mask: PlacedMask? = nil) {
        self.name = name
        self.pixels = pixels
        self.x = x
        self.y = y
        self.opacity = opacity
        self.blendMode = blendMode
        self.isHidden = isHidden
        self.clipsToBelow = clipsToBelow
        self.mask = mask
    }
}

/// A layer mask with its top left at (`x`, `y`) on the canvas, and the
/// coverage of every canvas pixel outside it.
public struct PlacedMask: Equatable, Sendable {
    /// Coverage per mask pixel, 0 (hides the layer) to 1 (shows it).
    public var mask: Mask
    /// The canvas pixel the mask's top left sits on, from the canvas's top
    /// left, x to the right and y down; independent of the layer's offset.
    public var x: Int, y: Int
    /// The coverage of every canvas pixel outside the mask's bounds: 0 hides
    /// the layer there, 1 shows it. PSD stores it as a default colour of 0 or
    /// 255, so a file reads 0 or 1.
    public var defaultCoverage: Float
    /// A disabled mask is kept in the file but not applied: the layer draws
    /// as if it had no mask.
    public var isDisabled: Bool

    public init(mask: Mask, x: Int = 0, y: Int = 0, defaultCoverage: Float = 0, isDisabled: Bool = false) {
        self.mask = mask
        self.x = x
        self.y = y
        self.defaultCoverage = defaultCoverage
        self.isDisabled = isDisabled
    }
}

/// A named group of entries, bottom to top.
public struct LayerGroup: Equatable, Sendable {
    /// The group's name, in Unicode.
    public var name: String
    /// The group's entries, bottom to top.
    public var children: [LayerNode]
    /// How much of the group shows, 0...1: 0 is invisible, 1 is fully opaque.
    public var opacity: Float
    /// nil is pass through: the children blend straight into what is below.
    public var blendMode: BlendMode?
    /// A hidden group hides every entry in it.
    public var isHidden: Bool
    /// Shown expanded in a layers list.
    public var isOpen: Bool

    public init(name: String, children: [LayerNode] = [], opacity: Float = 1,
                blendMode: BlendMode? = nil, isHidden: Bool = false, isOpen: Bool = true) {
        self.name = name
        self.children = children
        self.opacity = opacity
        self.blendMode = blendMode
        self.isHidden = isHidden
        self.isOpen = isOpen
    }
}

/// Why a codec could not read or write a layered file.
public enum CodecError: Error, Equatable, Sendable {
    /// The bytes are not this format at all (wrong signature).
    case notThisFormat
    /// The file is this format but broken; the text says where.
    case damaged(String)
    /// The file uses a feature this codec does not read or write.
    case unsupported(String)
    /// A size or count is over the codec's limits.
    case tooLarge(String)
    /// An archive entry is compressed; the text names it.
    case compressedEntry(String)
    /// The injected `PixelCodec` failed; the text says why.
    case pixelCodec(String)
}
