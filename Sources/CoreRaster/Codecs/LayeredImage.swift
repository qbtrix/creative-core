// LayeredImage.swift: the neutral layered image the codecs read and write.
// A stack of pixel layers (each placed at an integer offset, with opacity,
// blend mode, visibility, clipping and an optional placed mask) and nested
// groups, bottom to top, plus the optional merged composite. Any app maps its
// own layers to and from this; PSD and OpenRaster translate it to bytes.
// CodecError is the one error the codecs throw.

/// A layered image: canvas size, the layer tree bottom to top, the merged
/// composite when the file carries one, and the channel depth it was read at.
public struct LayeredImage: Equatable, Sendable {
    public var width: Int, height: Int
    /// Bottom to top.
    public var nodes: [LayerNode]
    /// The flattened image stored in the file, if any.
    public var composite: PixelBuffer?
    /// Bits per channel in the file: 8 for now.
    public var bitsPerChannel: Int

    public init(width: Int, height: Int, nodes: [LayerNode] = [],
                composite: PixelBuffer? = nil, bitsPerChannel: Int = 8) {
        self.width = width
        self.height = height
        self.nodes = nodes
        self.composite = composite
        self.bitsPerChannel = bitsPerChannel
    }
}

/// One entry of a layer tree: a pixel layer or a group of entries.
public enum LayerNode: Equatable, Sendable {
    case pixels(PixelLayer), group(LayerGroup)
}

/// A pixel layer with its top left at (`x`, `y`) on the canvas; it may lie
/// partly or wholly outside it.
public struct PixelLayer: Equatable, Sendable {
    public var name: String
    public var pixels: PixelBuffer
    public var x: Int, y: Int
    /// 0...1.
    public var opacity: Float
    public var blendMode: BlendMode
    public var isHidden: Bool
    /// Clipped to the layer below it.
    public var clipsToBelow: Bool
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
    public var mask: Mask
    public var x: Int, y: Int
    /// Coverage outside the mask's bounds, 0...1.
    public var defaultCoverage: Float
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
    public var name: String
    public var children: [LayerNode]
    /// 0...1.
    public var opacity: Float
    /// nil is pass through: the children blend straight into what is below.
    public var blendMode: BlendMode?
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
