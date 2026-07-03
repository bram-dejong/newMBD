ContentVersion proof = new ContentVersion(
    Title = 'Third Party Compliance Proof Smoke Test',
    PathOnClient = 'third-party-compliance-proof.txt',
    VersionData = Blob.valueOf('Proof document smoke test for Third_Party_Compliance__c')
);
insert proof;

proof = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id = :proof.Id
];

insert new ContentDocumentLink(
    ContentDocumentId = proof.ContentDocumentId,
    LinkedEntityId = 'a05Aq00000gSWeJIAW',
    ShareType = 'V',
    Visibility = 'AllUsers'
);

System.debug('CONTENT_DOCUMENT_ID=' + proof.ContentDocumentId);
