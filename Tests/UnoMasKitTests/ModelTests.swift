import Testing
@testable import UnoMasKit

struct ModelTests {
    @Test func matchesExactNamesAndAliases() {
        #expect(ModelInfo.matching(bluetoothName: "1MORE SonoFlow")?.model == "HC905")
        #expect(ModelInfo.matching(bluetoothName: "1MORE Fit S51")?.model == "S51")
        // The vendor apps match case included: these are two different models.
        #expect(ModelInfo.matching(bluetoothName: "1MORE PistonBuds Pro")?.model == "EC302")
        #expect(ModelInfo.matching(bluetoothName: "1MORE PistonBuds PRO")?.model == "EC305")
    }

    @Test func unknownOneMoreDevicesGetTheGenericModel() {
        let model = ModelInfo.matching(bluetoothName: "1MORE Future Buds")
        #expect(model?.model == "Unknown")
        #expect(model?.bluetoothName == "1MORE Future Buds")
        #expect(model?.verified == false)
        #expect(model?.eqPresets.isEmpty == true)
    }

    @Test func refusesTuyaModelsAndOtherBrands() {
        #expect(ModelInfo.matching(bluetoothName: "1MORE S52") == nil)
        #expect(ModelInfo.matching(bluetoothName: "1MORE S22Ultra") == nil)
        #expect(ModelInfo.matching(bluetoothName: "AirPods Pro") == nil)
    }

    @Test func onlyTheSonoFlowIsVerified() {
        #expect(ModelInfo.known.filter(\.verified).map(\.model) == ["HC905"])
        #expect(ModelInfo.sonoFlow.listenModes == [.off, .strongANC, .transparent])
        #expect(ModelInfo.sonoFlow.eqPresets.map(\.id) == Array(0x00...0x0B))
        #expect(ModelInfo.sonoFlow.dualDevice)
    }

    @Test func presetNamesFollowTheModel() {
        let hq60 = ModelInfo.matching(bluetoothName: "1MORE HQ60")!
        #expect(hq60.eqPresetName(0x03) == "Sound by LUCA")
        let comfoBudsPro = ModelInfo.matching(bluetoothName: "1MORE ComfoBuds Pro")!
        #expect(comfoBudsPro.eqPresetName(0x03) == "Bass Booster 1")
        #expect(comfoBudsPro.eqPresets.count == 22)
        #expect(ModelInfo.sonoFlow.eqPresetName(0x0B) == "Vocal Booster")
        #expect(ModelInfo.sonoFlow.eqPresetName(0x0C) == "Custom")
    }
}
