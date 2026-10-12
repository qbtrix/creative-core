// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command listed
// here must never touch another layer, a scene field, a symbol or a machine.
//
// Until each family takes an owner param (Q5b to Q5d), it names a scene layer:
// the extension below computes `owner` from `sceneID` for every listed command.

extension AddLayer: SceneLayerCommand {
    public var layerID: String { layer.id }
}

extension RemoveLayer: SceneLayerCommand {}
extension RenameLayer: SceneLayerCommand {}
extension ReorderLayer: SceneLayerCommand {}
extension SetLayerFlags: SceneLayerCommand {}
extension SetKeyframe: SceneLayerCommand {}
extension MoveKeyframe: SceneLayerCommand {}
extension RemoveKeyframe: SceneLayerCommand {}
extension SetKeyframeEasing: SceneLayerCommand {}
extension ShiftKeyframes: SceneLayerCommand {}
extension AddShape: SceneLayerCommand {}
extension RemoveShape: SceneLayerCommand {}
extension SetShapeFill: SceneLayerCommand {}
extension TranslateShape: SceneLayerCommand {}
extension AddTextShape: SceneLayerCommand {}
extension RemoveTextShape: SceneLayerCommand {}
extension SetTextString: SceneLayerCommand {}
extension SetTextFont: SceneLayerCommand {}

/// The listed commands that still address a layer by scene id.
protocol SceneLayerCommand: LayerCommand {
    var sceneID: String { get }
}

extension SceneLayerCommand {
    public var owner: LayerOwner { .scene(sceneID) }
}
