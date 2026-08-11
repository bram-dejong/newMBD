import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import search from '@salesforce/apex/AccountCreationController.search';
import createLead from '@salesforce/apex/AccountCreationController.createLead';

const SEARCH_DELAY_MS = 500;

export default class AccountCreationWizard extends NavigationMixin(LightningElement) {
    company = '';
    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    website = '';
    street = '';
    city = '';
    state = '';
    postalCode = '';
    country = '';
    dbMatches = [];
    accountMatches = [];
    selectedDbData;
    canCreateLead = false;
    isSearching = false;
    isSaving = false;
    errorMessage;
    statusMessage;
    searchTimer;

    get isBusy() {
        return this.isSearching || this.isSaving;
    }

    get searchDisabled() {
        return this.isBusy || String(this.company || '').trim().length < 3;
    }

    get saveDisabled() {
        return this.isBusy || !String(this.company || '').trim() || !String(this.lastName || '').trim() || this.hasAccountMatches;
    }

    get hasDbMatches() {
        return this.dbMatches.length > 0 && !this.selectedDbData && !this.hasAccountMatches;
    }

    get hasAccountMatches() {
        return this.accountMatches.length > 0;
    }

    get showLeadForm() {
        return !this.hasAccountMatches && (Boolean(this.selectedDbData) || this.canCreateLead);
    }

    get selectedDbLabel() {
        return `D&B: ${this.selectedDbData?.dbDataName || this.selectedDbData?.companyName}`;
    }

    handleCompanyChange(event) {
        this.company = event.target.value;
        this.clearSearchState();
        clearTimeout(this.searchTimer);
        if (String(this.company || '').trim().length >= 3) {
            this.searchTimer = setTimeout(() => this.runSearch(), SEARCH_DELAY_MS);
        }
    }

    handleCompanyKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            clearTimeout(this.searchTimer);
            this.handleSearch();
        }
    }

    handleSearch() {
        const input = this.template.querySelector('.name-input');
        const valid = input?.reportValidity();
        if (valid !== false && !this.searchDisabled) this.runSearch();
    }

    async runSearch() {
        const searchedName = String(this.company || '').trim();
        if (searchedName.length < 3) return;
        this.isSearching = true;
        this.errorMessage = undefined;
        this.statusMessage = 'Searching existing Accounts and D&B organizations...';
        this.selectedDbData = undefined;
        try {
            const response = await search({ accountName: searchedName });
            if (searchedName !== String(this.company || '').trim()) return;
            this.dbMatches = (response.dbMatches || []).map((item) => ({
                ...item,
                addressSummary: [item.street, item.city, item.state, item.postalCode, item.country].filter(Boolean).join(', ')
            }));
            this.accountMatches = response.accountMatches || [];
            this.canCreateLead = Boolean(response.canCreateLead);
            if (this.accountMatches.length) {
                this.statusMessage = `${this.accountMatches.length} existing Account match${this.accountMatches.length === 1 ? '' : 'es'} found. Open the Account instead of creating a Lead.`;
            } else if (this.dbMatches.length) {
                this.statusMessage = `No Salesforce Account was found. Select the correct D&B organization for the new Lead.`;
            } else {
                this.statusMessage = 'No Account or D&B organization was found. Enter the new Lead details.';
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.statusMessage = undefined;
            this.dbMatches = [];
            this.accountMatches = [];
            this.canCreateLead = false;
        } finally {
            this.isSearching = false;
        }
    }

    handleSelectDbData(event) {
        const selected = this.dbMatches.find((item) => item.dbDataId === event.currentTarget.dataset.id);
        if (!selected) return;
        this.selectedDbData = selected;
        this.company = selected.companyName || this.company;
        this.street = selected.street || '';
        this.city = selected.city || '';
        this.state = selected.state || '';
        this.postalCode = selected.postalCode || '';
        this.country = selected.country || '';
        this.statusMessage = `${selected.companyName} selected. Complete the contact details for the new Lead.`;
        this.errorMessage = undefined;
    }

    handleFieldChange(event) {
        this[event.target.dataset.field] = event.detail?.value ?? event.target.value;
    }

    async handleCreateLead() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-textarea')];
        if (!inputs.reduce((valid, input) => input.reportValidity() && valid, true)) return;
        this.isSaving = true;
        this.errorMessage = undefined;
        this.statusMessage = 'Rechecking Accounts and creating the Lead...';
        try {
            const result = await createLead({
                request: {
                    dbDataId: this.selectedDbData?.dbDataId || null,
                    company: this.company,
                    firstName: this.firstName,
                    lastName: this.lastName,
                    email: this.email,
                    phone: this.phone,
                    website: this.website,
                    street: this.street,
                    city: this.city,
                    state: this.state,
                    postalCode: this.postalCode,
                    country: this.country
                }
            });
            this.statusMessage = `${result.leadName} was created as a Lead for ${result.company}.`;
            this.navigateToRecord(result.leadId, 'Lead');
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.statusMessage = undefined;
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenAccount(event) {
        this.navigateToRecord(event.currentTarget.dataset.id, 'Account');
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    clearSearchState() {
        this.dbMatches = [];
        this.accountMatches = [];
        this.selectedDbData = undefined;
        this.canCreateLead = false;
        this.errorMessage = undefined;
        this.statusMessage = undefined;
    }

    reduceError(error) {
        const body = error?.body;
        if (Array.isArray(body)) return body.map((item) => item.message).join(', ');
        return body?.message || error?.message || 'The Account search or Lead creation could not be completed.';
    }
}
