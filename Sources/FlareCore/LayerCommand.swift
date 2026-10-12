// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command listed
// here must never touch another layer, a scene field, a symbol or a machine.

extension AddLayer: LayerCommand {
    public var layerID: String { layer.id }
}

extension RemoveLayer: LayerCommand {}
extension RenameLayer: LayerCommand {}
extension ReorderLayer: LayerCommand {}
extension SetLayerFlags: LayerCommand {}
extension SetKeyframe: LayerCommand {}
extension MoveKeyframe: LayerCommand {}
extension RemoveKeyframe: LayerCommand {}
extension SetKeyframeEasing: LayerCommand {}
extension ShiftKeyframes: LayerCommand {}
extension AddShape: LayerCommand {}
extension RemoveShape: LayerCommand {}
extension SetShapeFill: LayerCommand {}
extension TranslateShape: LayerCommand {}
extension AddTextShape: LayerCommand {}
extension RemoveTextShape: LayerCommand {}
extension SetTextString: LayerCommand {}
extension SetTextFont: LayerCommand {}
