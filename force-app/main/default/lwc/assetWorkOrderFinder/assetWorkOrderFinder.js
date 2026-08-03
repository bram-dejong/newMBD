import { api, LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getDocumentScanner } from 'lightning/mobileCapabilities';
import findByQrCode from '@salesforce/apex/AssetWorkOrderFinderController.findByQrCode';
import findByAssetId from '@salesforce/apex/AssetWorkOrderFinderController.findByAssetId';
import analyzePhoto from '@salesforce/apex/AssetPhotoIdentificationController.analyzePhoto';
import findCandidates from '@salesforce/apex/AssetPhotoIdentificationController.findCandidates';

const MAX_IMAGE_DIMENSION = 1200;

export default class AssetWorkOrderFinder extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @api locationId;

    barcodeTypes = ['QR'];
    manualCode = '';
    isBusy = false;
    errorMessage;
    statusMessage;
    result;
    photoActive = false;
    photoPreview;
    photoGuidance;
    serialInput = '';
    modelInput = '';
    candidates = [];
    selectedCandidateId;
    recordLookupStarted = false;
    documentScanner = getDocumentScanner();

    renderedCallback() {
        if (
            !this.recordLookupStarted &&
            this.recordId &&
            (!this.objectApiName || this.objectApiName === 'Asset')
        ) {
            this.recordLookupStarted = true;
            this.lookupByAssetId(this.recordId);
        }
    }

    get hasResult() {
        return Boolean(this.result?.assetId);
    }

    get hasWorkOrders() {
        return (this.result?.workOrders?.length || 0) > 0;
    }

    get hasCandidates() {
        return this.candidates.length > 0;
    }

    get candidateOptions() {
        return this.candidates.map((item) => ({
            label: `${item.assetName} | S/N ${item.serialNumber || 'not recorded'} | ${item.productName || 'Product not recorded'}`,
            value: item.assetId
        }));
    }

    get confirmCandidateDisabled() {
        return this.isBusy || !this.selectedCandidateId;
    }

    get documentScannerAvailable() {
        return Boolean(this.documentScanner?.isAvailable());
    }

    handleBarcodeScan(event) {
        const detail = event.detail || {};
        const scanned = detail.scannedBarcode || detail.scannedBarcodes?.[0] || detail.value;
        const code = this.extractBarcodeValue(scanned);
        if (code) {
            this.lookupByQrCode(code);
        }
    }

    handleScannerError(event) {
        this.errorMessage =
            event.detail?.error?.message ||
            event.detail?.message ||
            'The camera scanner is unavailable. Enter the QR code manually.';
    }

    handleManualCodeChange(event) {
        this.manualCode = event.target.value;
    }

    handleManualCodeKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleManualLookup();
        }
    }

    handleManualLookup() {
        const code = String(this.manualCode || '').trim();
        const input = this.template.querySelector('.manual-code');
        input?.setCustomValidity(code ? '' : 'Enter the code printed below the QR symbol.');
        input?.reportValidity();
        if (code) {
            this.lookupByQrCode(code);
        }
    }

    async lookupByQrCode(qrCode) {
        await this.runLookup(
            () => findByQrCode({ qrCode }),
            'Finding the Asset and its open work orders...'
        );
        if (this.hasResult) {
            this.manualCode = '';
        }
    }

    async lookupByAssetId(assetId) {
        await this.runLookup(
            () => findByAssetId({ assetId }),
            'Loading open work orders for this Asset...'
        );
    }

    async runLookup(action, progressMessage) {
        this.isBusy = true;
        this.errorMessage = undefined;
        this.statusMessage = progressMessage;
        this.result = undefined;
        try {
            const response = await action();
            this.result = this.normalizeResult(response);
            if (!this.result.assetId) {
                throw new Error('No Asset matched that identifier. Check the code and try again.');
            }
            const count = this.result.workOrders.length;
            this.statusMessage = count
                ? `${count} open work order${count === 1 ? '' : 's'} found.`
                : 'Asset identified. It has no open work orders.';
            this.resetPhotoWorkflow();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.statusMessage = undefined;
        } finally {
            this.isBusy = false;
        }
    }

    normalizeResult(response) {
        const asset = response?.asset || response?.identifiedAsset || response || {};
        const rawWorkOrders = response?.openWorkOrders || response?.workOrders || [];
        return {
            assetId: asset.Id || asset.id || asset.assetId,
            assetName: asset.Name || asset.name || asset.assetName || 'Asset',
            serialNumber: asset.SerialNumber || asset.serialNumber,
            productName: asset.Product2?.Name || asset.productName,
            locationName:
                asset.Location__r?.Name ||
                asset.Location?.Name ||
                asset.locationName ||
                asset.salesforceLocationName,
            workOrderLimitReached: Boolean(response?.workOrderLimitReached),
            workOrders: rawWorkOrders.map((item) => ({
                id: item.Id || item.id || item.workOrderId,
                number: item.WorkOrderNumber || item.workOrderNumber || item.number || 'Work order',
                subject: item.Subject || item.subject,
                status: item.Status || item.status || 'Open',
                priority: item.Priority || item.priority,
                summary: [item.Status || item.status, item.Priority || item.priority]
                    .filter(Boolean)
                    .join(' | ')
            }))
        };
    }

    handleOpenAsset() {
        this.navigateToRecord(this.result?.assetId, 'Asset');
    }

    handleOpenWorkOrder(event) {
        this.navigateToRecord(event.currentTarget.dataset.recordId, 'WorkOrder');
    }

    navigateToRecord(recordId, objectApiName) {
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    handleStartPhoto() {
        this.result = undefined;
        this.errorMessage = undefined;
        this.photoActive = true;
        this.photoGuidance =
            'Fill the frame with the nameplate. Keep the serial number sharp and avoid glare.';
    }

    async handleScanNameplate() {
        if (!this.documentScannerAvailable) {
            this.errorMessage =
                'Native nameplate scanning is unavailable here. Take or choose a photo instead.';
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            const documents = await this.documentScanner.scan({
                imageSource: 'DEVICE_CAMERA',
                scriptHint: 'LATIN',
                returnImageBytes: false,
                permissionRationaleText:
                    'Allow Salesforce to use the camera to read the Asset nameplate.'
            });
            const recognizedText = documents?.[0]?.text || '';
            const suggestedSerial = this.extractSerialFromText(recognizedText);
            if (suggestedSerial) {
                this.serialInput = suggestedSerial;
                this.photoGuidance =
                    'A serial number was suggested from the scan. Verify or correct it before searching.';
            } else {
                this.photoGuidance =
                    'Text was scanned, but no clearly labelled serial number was found. Enter it below.';
            }
            this.candidates = [];
            this.selectedCandidateId = undefined;
        } catch (error) {
            if (error?.code !== 'USER_DISMISSED') {
                this.errorMessage =
                    error?.message || 'The nameplate could not be scanned. Take a photo or enter the serial manually.';
            }
        } finally {
            this.isBusy = false;
        }
    }

    handleCancelPhoto() {
        this.resetPhotoWorkflow();
        this.statusMessage = 'Photo identification cancelled. The photo was not saved.';
    }

    async handlePhotoSelected(event) {
        const file = event.target.files?.[0];
        event.target.value = '';
        if (!file) return;
        if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
            this.errorMessage = 'Choose a JPEG, PNG, or WebP image.';
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        this.candidates = [];
        try {
            const image = await this.prepareImage(file);
            this.photoPreview = image.dataUrl;
            const analysis = await analyzePhoto({
                imageBase64: image.base64,
                mimeType: image.mimeType,
                stage: 'NAMEPLATE'
            });
            this.serialInput = analysis.extractedSerial || '';
            this.modelInput = analysis.extractedModel || '';
            this.photoGuidance =
                analysis.guidance ||
                'Check the detected serial number, correct it if needed, then search.';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
        }
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
        const serialNumber = String(this.serialInput || '').trim();
        if (!serialNumber) {
            this.errorMessage = 'Enter the serial number shown on the nameplate.';
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            this.candidates = await findCandidates({
                serialNumber,
                model: this.modelInput,
                locationId: this.locationId || null
            });
            this.selectedCandidateId = undefined;
            this.photoGuidance = this.candidates.length
                ? 'Select the matching Asset.'
                : 'No Asset matched. Check the serial number or retake the photo.';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handleCandidateSelection(event) {
        this.selectedCandidateId = event.detail.value;
    }

    handleConfirmCandidate() {
        if (this.selectedCandidateId) {
            this.lookupByAssetId(this.selectedCandidateId);
        }
    }

    resetPhotoWorkflow() {
        this.photoActive = false;
        this.photoPreview = undefined;
        this.photoGuidance = undefined;
        this.serialInput = '';
        this.modelInput = '';
        this.candidates = [];
        this.selectedCandidateId = undefined;
    }

    prepareImage(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onerror = () => reject(new Error('The photo could not be read.'));
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
                        reject(new Error('The processed photo is too large. Move closer and retake it.'));
                        return;
                    }
                    resolve({ dataUrl, base64, mimeType: 'image/jpeg' });
                };
                image.src = reader.result;
            };
            reader.readAsDataURL(file);
        });
    }

    extractBarcodeValue(item) {
        return String(typeof item === 'string' ? item : item?.value || item?.data || '').trim();
    }

    extractSerialFromText(text) {
        const normalized = String(text || '').replace(/\r/g, '\n');
        const labelled = normalized.match(
            /(?:serial(?:\s*(?:number|no\.?))?|s\s*\/\s*n)\s*[:#-]?\s*([a-z0-9][a-z0-9._\/-]{2,79})/i
        );
        return labelled?.[1] || '';
    }

    reduceError(error) {
        const body = error?.body;
        if (Array.isArray(body)) return body.map((item) => item.message).join(', ');
        return body?.message || error?.message || 'The Asset could not be identified. Try again.';
    }
}
