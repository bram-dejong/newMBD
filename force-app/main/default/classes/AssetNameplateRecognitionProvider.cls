public interface AssetNameplateRecognitionProvider {
    AssetPhotoIdentificationController.ProviderResponse analyze(
        AssetPhotoIdentificationController.ProviderRequest request
    );
}
