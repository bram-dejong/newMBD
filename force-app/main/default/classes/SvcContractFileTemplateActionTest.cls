@IsTest
private class SvcContractFileTemplateActionTest {
    @IsTest
    static void createsFilePublishedToServiceContract() {
        Account account = new Account(Name = 'Template Test Account');
        insert account;

        ServiceContract contract = new ServiceContract(
            Name = 'Template Test Contract',
            AccountId = account.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addYears(1),
            Term = 12
        );
        insert contract;

        ContentVersion template = new ContentVersion(
            Title = 'Service Contract Template - Standard',
            PathOnClient = 'Service Contract Template - Standard.txt',
            VersionData = Blob.valueOf('Template body')
        );
        insert template;

        ServiceContractFileFromTemplateAction.Request request =
            new ServiceContractFileFromTemplateAction.Request();
        request.serviceContractId = String.valueOf(contract.Id);
        request.templateContentVersionId = String.valueOf(template.Id);
        request.newFileTitle = 'Generated Service Contract';

        Test.startTest();
        List<ServiceContractFileFromTemplateAction.Result> results =
            ServiceContractFileFromTemplateAction.createFiles(
                new List<ServiceContractFileFromTemplateAction.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One generated file result should be returned.');
        System.assertNotEquals(null, results[0].contentDocumentId, 'A ContentDocument should be created.');

        ContentVersion generated = [
            SELECT Title, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :results[0].contentVersionId
        ];
        System.assertEquals('Generated Service Contract', generated.Title);
        System.assertEquals('Template body', generated.VersionData.toString());

        ContentDocumentLink link = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :generated.ContentDocumentId
            AND LinkedEntityId = :contract.Id
            LIMIT 1
        ];
        System.assertEquals(contract.Id, link.LinkedEntityId);
    }
}
