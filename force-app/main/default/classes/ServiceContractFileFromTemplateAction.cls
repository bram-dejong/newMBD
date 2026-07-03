public with sharing class ServiceContractFileFromTemplateAction {
    private static final String TEMPLATE_LIBRARY_NAME = 'Contract Templates';
    private static final String GENERATED_CONTRACT_LIBRARY_NAME = 'Contracts';
    private static final String TEMPLATE_TITLE_PREFIX = 'Contract template|';

    public class Request {
        @InvocableVariable(required=true label='Service Contract Id')
        public String serviceContractId;

        @InvocableVariable(required=true label='Template Content Version Id')
        public String templateContentVersionId;

        @InvocableVariable(label='New File Title')
        public String newFileTitle;
    }

    public class Result {
        @InvocableVariable(label='Content Document Id')
        public Id contentDocumentId;

        @InvocableVariable(label='Content Version Id')
        public Id contentVersionId;
    }

    @InvocableMethod(
        label='Create Service Contract File from Template'
        description='Copies a selected template file and publishes the new file to a Service Contract.'
    )
    public static List<Result> createFiles(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Result>();
        }

        Set<Id> templateVersionIds = new Set<Id>();
        Set<Id> serviceContractIdSet = new Set<Id>();
        for (Request request : requests) {
            if (request == null || request.serviceContractId == null || request.templateContentVersionId == null) {
                throw new FlowException('Service Contract Id and Template Content Version Id are required.');
            }
            templateVersionIds.add((Id) request.templateContentVersionId);
            serviceContractIdSet.add((Id) request.serviceContractId);
        }

        Map<Id, ContentVersion> templatesById = new Map<Id, ContentVersion>([
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :templateVersionIds
        ]);
        Map<Id, ServiceContract> serviceContractsById = new Map<Id, ServiceContract>([
            SELECT Id, Name
            FROM ServiceContract
            WHERE Id IN :serviceContractIdSet
        ]);
        Set<Id> approvedTemplateDocumentIds = getApprovedTemplateDocumentIds(templatesById.values());
        Id contractsLibraryId = getLibraryId(GENERATED_CONTRACT_LIBRARY_NAME);

        List<ContentVersion> filesToCreate = new List<ContentVersion>();
        List<Id> serviceContractIds = new List<Id>();
        for (Request request : requests) {
            ContentVersion template = templatesById.get((Id) request.templateContentVersionId);
            if (template == null) {
                throw new FlowException('The selected template file could not be found.');
            }
            if (!template.Title.startsWith(TEMPLATE_TITLE_PREFIX)) {
                throw new FlowException('The selected template file must start with "' + TEMPLATE_TITLE_PREFIX + '".');
            }
            if (!approvedTemplateDocumentIds.contains(template.ContentDocumentId)) {
                throw new FlowException('The selected template file must be stored in the "' + TEMPLATE_LIBRARY_NAME + '" library.');
            }
            ServiceContract serviceContract = serviceContractsById.get((Id) request.serviceContractId);
            if (serviceContract == null) {
                throw new FlowException('The selected Service Contract could not be found.');
            }

            String title = String.isBlank(request.newFileTitle)
                ? buildDefaultTitle(serviceContract, template)
                : request.newFileTitle.trim();

            filesToCreate.add(new ContentVersion(
                Title = title,
                PathOnClient = title + getExtensionSuffix(template.FileExtension),
                VersionData = template.VersionData,
                FirstPublishLocationId = contractsLibraryId
            ));
            serviceContractIds.add((Id) request.serviceContractId);
        }

        insert filesToCreate;

        List<Result> results = new List<Result>();
        List<ContentDocumentLink> contractLinks = new List<ContentDocumentLink>();
        Integer resultIndex = 0;
        for (ContentVersion createdFile : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :filesToCreate
            ORDER BY CreatedDate ASC
        ]) {
            Result result = new Result();
            result.contentVersionId = createdFile.Id;
            result.contentDocumentId = createdFile.ContentDocumentId;
            results.add(result);
            contractLinks.add(new ContentDocumentLink(
                ContentDocumentId = createdFile.ContentDocumentId,
                LinkedEntityId = serviceContractIds[resultIndex],
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
            resultIndex++;
        }
        insert contractLinks;
        return results;
    }

    private static String getExtensionSuffix(String fileExtension) {
        return String.isBlank(fileExtension) ? '' : '.' + fileExtension;
    }

    private static String buildDefaultTitle(ServiceContract serviceContract, ContentVersion template) {
        String templateName = template.Title.removeStart(TEMPLATE_TITLE_PREFIX).trim();
        return String.isBlank(templateName)
            ? serviceContract.Name
            : serviceContract.Name + ' ' + templateName;
    }

    private static Set<Id> getApprovedTemplateDocumentIds(List<ContentVersion> templates) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentVersion template : templates) {
            if (template.ContentDocumentId != null) {
                documentIds.add(template.ContentDocumentId);
            }
        }

        Set<Id> approvedDocumentIds = new Set<Id>();
        for (ContentWorkspaceDoc workspaceDoc : [
            SELECT ContentDocumentId
            FROM ContentWorkspaceDoc
            WHERE ContentDocumentId IN :documentIds
            AND ContentWorkspace.Name = :TEMPLATE_LIBRARY_NAME
        ]) {
            approvedDocumentIds.add(workspaceDoc.ContentDocumentId);
        }
        return approvedDocumentIds;
    }

    private static Id getLibraryId(String libraryName) {
        List<ContentWorkspace> libraries = [
            SELECT Id
            FROM ContentWorkspace
            WHERE Name = :libraryName
            LIMIT 1
        ];
        if (libraries.isEmpty()) {
            throw new FlowException('The "' + libraryName + '" library could not be found.');
        }
        return libraries[0].Id;
    }
}
