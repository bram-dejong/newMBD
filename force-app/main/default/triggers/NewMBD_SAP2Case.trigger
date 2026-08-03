/**
 * Routes MBD SAP2CASE email-to-case records through the newMBD-specific handler.
 * Web-to-Case, CEC deduplication, and PCC processing intentionally remain out of scope.
 */
trigger NewMBD_SAP2Case on Case (before insert) {
    NewMBD_SAP2CaseHandler.beforeInsert(Trigger.new);
}
