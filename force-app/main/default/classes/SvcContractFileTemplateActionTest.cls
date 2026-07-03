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
            Title = 'Contract template|Standard',
            PathOnClient = 'Contract template|Standard.txt',
            VersionData = Blob.valueOf('Template body')
        );
        insert template;
        template = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :template.Id
        ];

        ContentWorkspace templateLibrary = getOrCreateLibrary('Contract Templates', 'Contract_Templates');
        ContentWorkspace contractsLibrary = getOrCreateLibrary('Contracts', 'Contracts');

        insert new ContentWorkspaceDoc(
            ContentWorkspaceId = templateLibrary.Id,
            ContentDocumentId = template.ContentDocumentId
        );

        ServiceContractFileFromTemplateAction.Request request =
            new ServiceContractFileFromTemplateAction.Request();
        request.serviceContractId = String.valueOf(contract.Id);
        request.templateContentVersionId = String.valueOf(template.Id);

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
        System.assertEquals('Template Test Contract Standard', generated.Title);
        System.assertEquals('Template body', generated.VersionData.toString());

        ContentDocumentLink link = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :generated.ContentDocumentId
            AND LinkedEntityId = :contract.Id
            LIMIT 1
        ];
        System.assertEquals(contract.Id, link.LinkedEntityId);

        ContentWorkspaceDoc generatedLibraryDocument = [
            SELECT ContentWorkspaceId
            FROM ContentWorkspaceDoc
            WHERE ContentDocumentId = :generated.ContentDocumentId
            AND ContentWorkspaceId = :contractsLibrary.Id
            LIMIT 1
        ];
        System.assertEquals(contractsLibrary.Id, generatedLibraryDocument.ContentWorkspaceId);
    }

    private static ContentWorkspace getOrCreateLibrary(String name, String developerName) {
        List<ContentWorkspace> libraries = [
            SELECT Id
            FROM ContentWorkspace
            WHERE Name = :name
            LIMIT 1
        ];
        if (libraries.isEmpty()) {
            ContentWorkspace library = new ContentWorkspace(
                Name = name,
                DeveloperName = developerName
            );
            insert library;
            return library;
        }
        return libraries[0];
    }
}
