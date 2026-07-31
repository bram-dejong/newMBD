import { api, LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getLocationService } from 'lightning/mobileCapabilities';
import finalizeAuditWithAssets from '@salesforce/apex/AssetLocationAuditController.finalizeAuditWithAssets';
import analyzePhoto from '@salesforce/apex/AssetPhotoIdentificationController.analyzePhoto';
import findCandidates from '@salesforce/apex/AssetPhotoIdentificationController.findCandidates';

const AUDIT_MODE_COMPLETE = 'complete';
const AUDIT_MODE_SPOT_CHECK = 'spot';
const PHOTO_STAGE_DEVICE = 'DEVICE';
const PHOTO_STAGE_NAMEPLATE = 'NAMEPLATE';
const MAX_IMAGE_DIMENSION = 1200;

export default class AssetLocationAudit extends NavigationMixin(LightningElement) {
    @api recordId;
    @api locationId;
    @api label = 'Asset QR Audit';

    selectedLocationId;
    auditMode = AUDIT_MODE_COMPLETE;
    manualCode = '';
    scannedCodes = [];
    identifiedAssets = [];
    errorMessage;
    statusMessage;
    result;
    isBusy = false;
    locationService = getLocationService();
    photoActive = false;
    photoStage = PHOTO_STAGE_DEVICE;
    photoPreview;
    photoGuidance;
    serialInput = '';
    modelInput = '';
    candidates = [];
    selectedCandidateId;
    isIdentifying = false;

    barcodeTypes = ['QR'];
    auditModeOptions = [
        {
            label: 'Complete Inventory',
            value: AUDIT_MODE_COMPLETE
        },
        {
            label: 'Spot Check',
            value: AUDIT_MODE_SPOT_CHECK
        }
    ];

    get effectiveLocationId() {
        return this.recordId || this.locationId || this.selectedLocationId;
    }

    get showLocationPicker() {
        return !this.recordId && !this.locationId;
    }

    get hasScannedCodes() {
        return this.scannedCodes.length > 0;
    }

    get scannedCount() {
        return this.scannedCodes.length + this.identifiedAssets.length;
    }

    get scannedCodeItems() {
        return this.scannedCodes.map((code) => ({
            code,
            key: code,
            removeLabel: `Remove ${code}`
        }));
    }

    get completeInventory() {
        return this.auditMode === AUDIT_MODE_COMPLETE;
    }

    get finalizeDisabled() {
        return this.isBusy || !this.effectiveLocationId || !this.hasAddedAssets;
    }

    get hasAddedAssets() {
        return this.scannedCodes.length > 0 || this.identifiedAssets.length > 0;
    }

    get identifiedAssetItems() {
        return this.identifiedAssets.map((item) => ({
            ...item,
            sourceLabel: 'Camera / serial',
            removeLabel: `Remove ${item.assetName}`
        }));
    }

    get hasIdentifiedAssets() {
        return this.identifiedAssets.length > 0;
    }

    get photoInputLabel() {
        return this.photoStage === PHOTO_STAGE_DEVICE
            ? 'Photograph the whole device'
            : 'Photograph the serial-number label';
    }

    get showContinueToNameplate() {
        return this.photoStage === PHOTO_STAGE_DEVICE && Boolean(this.photoPreview);
    }

    get showSerialSearch() {
        return this.photoStage === PHOTO_STAGE_NAMEPLATE && Boolean(this.photoPreview);
    }

    get hasCandidates() {
        return this.candidates.length > 0;
    }

    get candidateOptions() {
        return this.candidates.map((item) => ({
            label: `${item.assetName} — S/N ${item.serialNumber || 'not recorded'} — ${item.salesforceLocationName || 'No location'}`,
            value: item.assetId
        }));
    }

    get confirmCandidateDisabled() {
        return this.isIdentifying || !this.selectedCandidateId;
    }

    get hasResult() {
        return Boolean(this.result?.auditId);
    }

    handleLocationChange(event) {
        this.selectedLocationId = event.detail.recordId;
        this.clearFeedback();
    }

    handleStartPhotoIdentification() {
        if (!this.effectiveLocationId) {
            this.errorMessage = 'Select a Location before identifying an Asset from a photo.';
            return;
        }
        this.resetPhotoWorkflow();
        this.photoActive = true;
        this.photoGuidance =
            'Start with the whole device. The next step will ask you to move close to the serial-number label.';
    }

    handleCancelPhotoIdentification() {
        this.resetPhotoWorkflow();
        this.statusMessage = 'Photo identification cancelled. No photo was saved.';
    }

    async handlePhotoSelected(event) {
        const file = event.target.files?.[0];
        event.target.value = '';
        if (!file) return;
        if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
            this.errorMessage = 'Choose a JPEG, PNG, or WebP image.';
            return;
        }

        this.isIdentifying = true;
        this.errorMessage = undefined;
        this.candidates = [];
        this.selectedCandidateId = undefined;
        try {
            const processed = await this.prepareImage(file);
            this.photoPreview = processed.dataUrl;
            const response = await analyzePhoto({
                imageBase64: processed.base64,
                mimeType: processed.mimeType,
                stage: this.photoStage
            });
            this.photoGuidance = response.guidance;
            if (response.extractedSerial) this.serialInput = response.extractedSerial;
            if (response.extractedModel) this.modelInput = response.extractedModel;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isIdentifying = false;
        }
    }

    handleContinueToNameplate() {
        this.photoStage = PHOTO_STAGE_NAMEPLATE;
        this.photoPreview = undefined;
        this.photoGuidance =
            'Move close enough for the serial-number label to fill the frame. Avoid glare and keep the text sharp.';
    }

    handleSerialChange(event) {
        this.serialInput = event.target.value;
        this.candidates = [];
        this.selectedCandidateId = undefined;
    }

    handleModelChange(event) {
        this.modelInput = event.target.value;
    }

    async handleFindCandidates() {
        const serial = String(this.serialInput || '').trim();
        if (!serial) {
            this.errorMessage = 'Enter the serial number visible on the nameplate.';
            return;
        }
        this.isIdentifying = true;
        this.errorMessage = undefined;
        try {
            this.candidates = await findCandidates({
                serialNumber: serial,
                model: this.modelInput,
                locationId: this.effectiveLocationId
            });
            this.selectedCandidateId = undefined;
            this.photoGuidance = this.candidates.length
                ? 'Select the matching Salesforce Asset and confirm it.'
                : 'No Asset matched that serial. Check the label, correct the serial, or retake the photo.';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isIdentifying = false;
        }
    }

    handleCandidateSelection(event) {
        this.selectedCandidateId = event.detail.value;
    }

    handleConfirmCandidate() {
        const candidate = this.candidates.find((item) => item.assetId === this.selectedCandidateId);
        if (!candidate) return;
        if (!this.identifiedAssets.some((item) => item.assetId === candidate.assetId)) {
            this.identifiedAssets = [...this.identifiedAssets, candidate];
        }
        this.resetPhotoWorkflow();
        this.statusMessage = `${candidate.assetName} confirmed from serial ${candidate.serialNumber}.`;
        this.result = undefined;
    }

    handleRemoveIdentifiedAsset(event) {
        const assetId = event.currentTarget.dataset.assetId;
        this.identifiedAssets = this.identifiedAssets.filter((item) => item.assetId !== assetId);
        this.result = undefined;
    }

    handleAuditModeChange(event) {
        this.auditMode = event.detail.value;
        this.clearFeedback();
    }

    handleManualCodeChange(event) {
        this.manualCode = event.target.value;
    }

    handleManualCodeKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleAddManualCode();
        }
    }

    handleAddManualCode() {
        const input = this.template.querySelector('.manual-code');
        const code = this.normalizeCode(this.manualCode);

        if (!code) {
            input?.setCustomValidity('Enter a QR code.');
            input?.reportValidity();
            return;
        }

        input?.setCustomValidity('');
        input?.reportValidity();
        this.addCodes([code]);
        this.manualCode = '';
    }

    handleBarcodeScan(event) {
        const detail = event.detail || {};
        const values = [];

        if (detail.scannedBarcode) {
            values.push(detail.scannedBarcode);
        }
        if (Array.isArray(detail.scannedBarcodes)) {
            values.push(...detail.scannedBarcodes);
        }
        if (detail.value) {
            values.push(detail.value);
        }

        const codes = values
            .map((item) => (typeof item === 'string' ? item : item?.value || item?.data))
            .filter(Boolean);

        if (codes.length) {
            this.addCodes(codes);
        }
    }

    handleScannerError(event) {
        this.errorMessage =
            event.detail?.error?.message ||
            event.detail?.message ||
            'The camera scanner is unavailable. Enter the QR code manually instead.';
    }

    handleRemoveCode(event) {
        const code = event.currentTarget.dataset.code;
        this.scannedCodes = this.scannedCodes.filter((item) => item !== code);
        this.statusMessage = `${code} removed.`;
        this.result = undefined;
    }

    handleClearCodes() {
        this.scannedCodes = [];
        this.statusMessage = 'All scanned codes removed.';
        this.result = undefined;
        this.errorMessage = undefined;
    }

    async handleFinalize() {
        if (this.finalizeDisabled) {
            return;
        }

        this.isBusy = true;
        this.clearFeedback();

        try {
            this.statusMessage = 'Capturing the current device location...';
            const position = await this.captureCurrentPosition();
            const accuracy =
                Number.isFinite(position.coords.accuracy) && position.coords.accuracy >= 0
                    ? position.coords.accuracy
                    : null;

            this.statusMessage = 'Comparing scanned assets and location coordinates...';
            const response = await finalizeAuditWithAssets({
                locationId: this.effectiveLocationId,
                scannedCodes: [...this.scannedCodes],
                completeInventory: this.completeInventory,
                deviceLatitude: position.coords.latitude,
                deviceLongitude: position.coords.longitude,
                deviceAccuracyMeters: accuracy,
                capturedAtEpochMs: position.timestamp || Date.now(),
                confirmedAssetIds: this.identifiedAssets.map((item) => item.assetId)
            });

            this.result = {
                auditId: response.auditId,
                anomalyCount: response.anomalyCount ?? 0,
                expectedCount: response.expectedCount ?? 0,
                scannedCount: response.scannedCount ?? this.scannedCount,
                distanceMeters: response.distanceMeters,
                geoValidationStatus: response.geoValidationStatus,
                message: response.message || response.summary
            };
            this.statusMessage = `Audit finalized with ${this.result.anomalyCount} anomalies.`;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Audit finalized',
                    message: `${this.result.anomalyCount} location anomalies detected.`,
                    variant: this.result.anomalyCount ? 'warning' : 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    async captureCurrentPosition() {
        if (this.locationService?.isAvailable()) {
            try {
                return await this.locationService.getCurrentPosition({
                    enableHighAccuracy: true
                });
            } catch (error) {
                throw new Error(this.locationServiceErrorMessage(error));
            }
        }

        if (navigator.geolocation) {
            return new Promise((resolve, reject) => {
                navigator.geolocation.getCurrentPosition(
                    resolve,
                    (error) => reject(new Error(this.browserLocationErrorMessage(error))),
                    {
                        enableHighAccuracy: true,
                        timeout: 15000,
                        maximumAge: 0
                    }
                );
            });
        }

        throw new Error(
            'Location capture is unavailable on this device. Use Salesforce Mobile with Location Services enabled.'
        );
    }

    locationServiceErrorMessage(error) {
        const code = error?.code;
        const messages = {
            locationServiceDisabled:
                'Enable Location Services on this device, then try again.',
            userDisabledPermissions:
                'Allow Salesforce to access the device location in the device settings.',
            userDeniedPermission:
                'Salesforce needs location permission to complete this audit.',
            unavailableOnHardware:
                'This device cannot capture a location.'
        };
        return messages[code] || error?.message || 'The device location could not be captured. Try again.';
    }

    browserLocationErrorMessage(error) {
        const messages = {
            1: 'Location permission was denied. Allow location access and try again.',
            2: 'The current location is unavailable. Move to an area with better reception and try again.',
            3: 'Location capture timed out. Try again.'
        };
        return messages[error?.code] || 'The current location could not be captured. Try again.';
    }

    handleViewAudit() {
        if (!this.result?.auditId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.result.auditId,
                objectApiName: 'Asset_Location_Audit__c',
                actionName: 'view'
            }
        });
    }

    resetPhotoWorkflow() {
        this.photoActive = false;
        this.photoStage = PHOTO_STAGE_DEVICE;
        this.photoPreview = undefined;
        this.photoGuidance = undefined;
        this.serialInput = '';
        this.modelInput = '';
        this.candidates = [];
        this.selectedCandidateId = undefined;
        this.isIdentifying = false;
    }

    prepareImage(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onerror = () => reject(new Error('The selected image could not be read.'));
            reader.onload = () => {
                const image = new Image();
                image.onerror = () => reject(new Error('The selected file is not a readable image.'));
                image.onload = () => {
                    const scale = Math.min(1, MAX_IMAGE_DIMENSION / Math.max(image.width, image.height));
                    const canvas = document.createElement('canvas');
                    canvas.width = Math.max(1, Math.round(image.width * scale));
                    canvas.height = Math.max(1, Math.round(image.height * scale));
                    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
                    const dataUrl = canvas.toDataURL('image/jpeg', 0.72);
                    const base64 = dataUrl.split(',')[1];
                    if (!base64 || Math.ceil((base64.length * 3) / 4) > 750000) {
                        reject(new Error('The image is still too large. Move closer to the label and retake it.'));
                        return;
                    }
                    resolve({ dataUrl, base64, mimeType: 'image/jpeg' });
                };
                image.src = reader.result;
            };
            reader.readAsDataURL(file);
        });
    }

    addCodes(rawCodes) {
        const existing = new Map(
            this.scannedCodes.map((code) => [this.codeKey(code), code])
        );
        let added = 0;
        let rejected = 0;

        rawCodes.forEach((rawCode) => {
            const code = this.normalizeCode(rawCode);
            const key = this.codeKey(code);
            if (code.length > 255) {
                rejected += 1;
            } else if (code && !existing.has(key)) {
                existing.set(key, code);
                added += 1;
            }
        });

        this.scannedCodes = [...existing.values()];
        this.statusMessage =
            added > 0
                ? `${added} code${added === 1 ? '' : 's'} added. ${this.scannedCount} total.`
                : 'Duplicate code ignored.';
        this.errorMessage = rejected
            ? `${rejected} scanned code${rejected === 1 ? ' was' : 's were'} longer than 255 characters and could not be added.`
            : undefined;
        this.result = undefined;
    }

    normalizeCode(value) {
        return String(value || '').trim();
    }

    codeKey(value) {
        return this.normalizeCode(value).toLocaleUpperCase();
    }

    clearFeedback() {
        this.errorMessage = undefined;
        this.statusMessage = undefined;
        this.result = undefined;
    }

    reduceError(error) {
        const body = error?.body;

        if (Array.isArray(body)) {
            return body.map((item) => item.message).join(', ');
        }
        return body?.message || error?.message || 'The audit could not be finalized. Try again.';
    }
}
