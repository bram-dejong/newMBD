public class MockAssetNameplateRecognitionProvider implements AssetNameplateRecognitionProvider {
    public AssetPhotoIdentificationController.ProviderResponse analyze(
        AssetPhotoIdentificationController.ProviderRequest request
    ) {
        AssetPhotoIdentificationController.ProviderResponse response =
            new AssetPhotoIdentificationController.ProviderResponse();
        response.providerName = 'Unconfigured provider';
        response.status = 'UNAVAILABLE';
        response.confidence = 0;
        response.guidance =
            'AI photo analysis is not configured in this org. Read the serial number from the nameplate photo, enter it below, and confirm the matching Asset.';
        return response;
    }
}
