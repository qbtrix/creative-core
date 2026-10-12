// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command listed
// here must never touch another layer, a scene or symbol field, or a machine.
//
// The keyframe family takes an owner param. Until the other families do (Q5b,
// Q5d), they name a scene layer: `SceneLayerCommand` computes `owner` from
// `sceneID` for them.

extension AddLayer: SceneLayerCommand {
    public var layerID: String { layer.id }
}

extension RemoveLayer: SceneLayerCommand {}
extension RenameLayer: SceneLayerCommand {}
extension ReorderLayer: SceneLayerCommand {}
extension SetLayerFlags: SceneLayerCommand {}
extension SetKeyframe: LayerCommand {}
extension MoveKeyframe: LayerCommand {}
extension RemoveKeyframe: LayerCommand {}
extension SetKeyframeEasing: LayerCommand {}
extension ShiftKeyframes: LayerCommand {}
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
