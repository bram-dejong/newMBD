public without sharing class PMWorkOrderBatch implements Database.Batchable<SObject> {
    private final Date runDate;

    public PMWorkOrderBatch() {
        this(Date.today());
    }

    @TestVisible
    private PMWorkOrderBatch(Date runDate) {
        this.runDate = runDate;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, AccountId, AssetId, ServiceContractId, StartDate, EndDate,
                WorkOrdersPerEntitlement, PM_Generation_Enabled__c,
                PM_Interval_Days__c, PM_Creation_Lead_Days__c,
                Asset.Id, Asset.Name, Asset.AccountId, Asset.PM_Automation_Enabled__c,
                Asset.PM_Base_Date__c, Asset.Last_PM_Date__c,
                Asset.Product2.Id, Asset.Product2.Requires_Maintenance__c,
                ServiceContract.AccountId, ServiceContract.StartDate, ServiceContract.EndDate
            FROM Entitlement
            WHERE PM_Generation_Enabled__c = true
                AND AssetId != null
                AND ServiceContractId != null
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        List<Entitlement> entitlements = new List<Entitlement>();
        for (SObject recordItem : scope) {
            entitlements.add((Entitlement) recordItem);
        }
        PMWorkOrderGenerationService.generate(entitlements, runDate);
    }

    public void finish(Database.BatchableContext context) {
    }
}
