@IsTest
private class PMWorkOrderGenerationServiceTest {
    @TestSetup
    static void setupData() {
        Account accountRecord = new Account(Name = 'PM Customer');
        insert accountRecord;
        Product2 productRecord = new Product2(
            Name = 'PM Product',
            IsActive = true,
            Requires_Maintenance__c = true
        );
        insert productRecord;
        Asset assetRecord = new Asset(
            Name = 'PM Instrument',
            AccountId = accountRecord.Id,
            Product2Id = productRecord.Id,
            Status = 'Installed',
            PM_Automation_Enabled__c = true,
            PM_Base_Date__c = Date.today().addDays(-60)
        );
        insert assetRecord;
        ServiceContract contractRecord = new ServiceContract(
            Name = 'PM Service Contract',
            AccountId = accountRecord.Id,
            StartDate = Date.today().addDays(-365),
            EndDate = Date.today().addDays(365)
        );
        insert contractRecord;
        insert new Entitlement(
            Name = 'PM Coverage',
            AccountId = accountRecord.Id,
            AssetId = assetRecord.Id,
            ServiceContractId = contractRecord.Id,
            StartDate = Date.today().addDays(-365),
            EndDate = Date.today().addDays(365),
            PM_Generation_Enabled__c = true,
            PM_Interval_Days__c = 90,
            PM_Creation_Lead_Days__c = 30,
            IsPerIncident = true,
            WorkOrdersPerEntitlement = 2,
            RemainingWorkOrders = 2
        );
    }

    @IsTest
    static void createsWorkOrderAtLeadBoundaryWithStandardAssociations() {
        Entitlement coverage = getCoverage();

        Test.startTest();
        PMWorkOrderGenerationService.GenerationResult result =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ coverage },
                Date.today()
            );
        Test.stopTest();

        System.assertEquals(1, result.createdCount);
        WorkOrder generated = [
            SELECT AccountId, AssetId, EntitlementId, ServiceContractId, Status, StartDate,
                System_Generated_PM__c, PM_Due_Date__c, PM_Generation_Key__c
            FROM WorkOrder
            WHERE EntitlementId = :coverage.Id
        ];
        System.assertEquals(coverage.AccountId, generated.AccountId);
        System.assertEquals(coverage.AssetId, generated.AssetId);
        System.assertEquals(coverage.Id, generated.EntitlementId);
        System.assertEquals(coverage.ServiceContractId, generated.ServiceContractId);
        System.assertEquals('New', generated.Status);
        System.assertEquals(true, generated.System_Generated_PM__c);
        System.assertEquals(Date.today().addDays(30), generated.PM_Due_Date__c);
        System.assertEquals(
            Datetime.newInstance(generated.PM_Due_Date__c, Time.newInstance(8, 0, 0, 0)),
            generated.StartDate
        );
        System.assert(generated.PM_Generation_Key__c.endsWith(String.valueOf(generated.PM_Due_Date__c)));
    }

    @IsTest
    static void rerunIsIdempotentAndOpenWorkPreventsNextOrder() {
        Entitlement coverage = getCoverage();
        PMWorkOrderGenerationService.generate(new List<Entitlement>{ coverage }, Date.today());

        Test.startTest();
        PMWorkOrderGenerationService.GenerationResult rerun =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ getCoverage() },
                Date.today().addDays(120)
            );
        Test.stopTest();

        System.assertEquals(0, rerun.createdCount);
        System.assertEquals(1, [SELECT COUNT() FROM WorkOrder WHERE EntitlementId = :coverage.Id]);
    }

    @IsTest
    static void fallsBackToLastPmDateWhenBaseDateIsBlank() {
        Asset assetRecord = [
            SELECT Id, PM_Base_Date__c, Last_PM_Date__c
            FROM Asset
            WHERE Name = 'PM Instrument'
        ];
        assetRecord.PM_Base_Date__c = null;
        assetRecord.Last_PM_Date__c = Date.today().addDays(-60);
        update assetRecord;

        PMWorkOrderGenerationService.GenerationResult result =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ getCoverage() },
                Date.today()
            );

        System.assertEquals(1, result.createdCount);
        WorkOrder generated = [SELECT PM_Due_Date__c FROM WorkOrder LIMIT 1];
        System.assertEquals(Date.today().addDays(30), generated.PM_Due_Date__c);
    }

    @IsTest
    static void closedWorkAdvancesCadenceButHonorsEntitlementLimit() {
        Entitlement coverage = getCoverage();
        PMWorkOrderGenerationService.generate(new List<Entitlement>{ coverage }, Date.today());
        WorkOrder firstWork = [SELECT Id FROM WorkOrder WHERE EntitlementId = :coverage.Id];
        firstWork.Status = 'Closed';
        update firstWork;

        PMWorkOrderGenerationService.GenerationResult secondRun =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ getCoverage() },
                Date.today().addDays(120)
            );
        System.assertEquals(1, secondRun.createdCount);
        WorkOrder secondWork = [
            SELECT Id, PM_Due_Date__c
            FROM WorkOrder
            WHERE EntitlementId = :coverage.Id AND Id != :firstWork.Id
        ];
        System.assertEquals(Date.today().addDays(120), secondWork.PM_Due_Date__c);
        secondWork.Status = 'Closed';
        update secondWork;

        PMWorkOrderGenerationService.GenerationResult cappedRun =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ getCoverage() },
                Date.today().addDays(240)
            );
        System.assertEquals(0, cappedRun.createdCount);
        System.assertEquals(2, [SELECT COUNT() FROM WorkOrder WHERE EntitlementId = :coverage.Id]);
    }

    @IsTest
    static void skipsBeforeWindowInvalidConfigurationAndCoverageEnd() {
        Entitlement coverage = getCoverage();
        PMWorkOrderGenerationService.GenerationResult beforeWindow =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ coverage },
                Date.today().addDays(-1)
            );
        System.assertEquals(0, beforeWindow.createdCount);

        coverage.PM_Interval_Days__c = 0;
        PMWorkOrderGenerationService.GenerationResult invalid =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ coverage },
                Date.today()
            );
        System.assertEquals(0, invalid.createdCount);

        coverage = getCoverage();
        coverage.EndDate = Date.today().addDays(10);
        PMWorkOrderGenerationService.GenerationResult afterCoverage =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ coverage },
                Date.today()
            );
        System.assertEquals(0, afterCoverage.createdCount);

        coverage = getCoverage();
        coverage.WorkOrdersPerEntitlement = 0;
        PMWorkOrderGenerationService.GenerationResult noAllowance =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ coverage },
                Date.today()
            );
        System.assertEquals(0, noAllowance.createdCount);
    }

    @IsTest
    static void requiresMaintenanceProductAndCurrentCoverage() {
        Product2 productRecord = [SELECT Id, Requires_Maintenance__c FROM Product2 WHERE Name = 'PM Product'];
        productRecord.Requires_Maintenance__c = false;
        update productRecord;
        PMWorkOrderGenerationService.GenerationResult notMaintainable =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ getCoverage() },
                Date.today()
            );
        System.assertEquals(0, notMaintainable.createdCount);

        productRecord.Requires_Maintenance__c = true;
        update productRecord;
        Entitlement expiredCoverage = getCoverage();
        expiredCoverage.StartDate = Date.today().addDays(-100);
        expiredCoverage.EndDate = Date.today().addDays(-1);
        PMWorkOrderGenerationService.GenerationResult expired =
            PMWorkOrderGenerationService.generate(
                new List<Entitlement>{ expiredCoverage },
                Date.today()
            );
        System.assertEquals(0, expired.createdCount);
    }

    @IsTest
    static void schedulerLaunchesBatch() {
        Test.startTest();
        new PMWorkOrderScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM WorkOrder WHERE System_Generated_PM__c = true]);
    }

    private static Entitlement getCoverage() {
        return [
            SELECT Id, AccountId, AssetId, ServiceContractId, StartDate, EndDate,
                WorkOrdersPerEntitlement, PM_Generation_Enabled__c,
                PM_Interval_Days__c, PM_Creation_Lead_Days__c,
                Asset.Id, Asset.Name, Asset.AccountId, Asset.PM_Automation_Enabled__c,
                Asset.PM_Base_Date__c, Asset.Last_PM_Date__c,
                Asset.Product2.Id, Asset.Product2.Requires_Maintenance__c,
                ServiceContract.AccountId, ServiceContract.StartDate, ServiceContract.EndDate
            FROM Entitlement
            WHERE Name = 'PM Coverage'
            LIMIT 1
        ];
    }
}
