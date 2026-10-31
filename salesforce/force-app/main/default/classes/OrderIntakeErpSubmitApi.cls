/**
 * REST endpoint MuleSoft calls right after the extraction endpoint created the order for a clean intake
 * (order.autoSubmitErp). Sends the order to the ERP with the same logic as the agent's Submit Order To ERP
 * action. It runs in its own transaction because the ERP callout cannot follow the order DML of the
 * extraction request. When the ERP confirms, the response carries the customer confirmation with the
 * ERP order number; when it fails, the intake becomes ERP Failed and gets a review Case (OrderIntakeTrigger).
 *
 * POST /services/apexrest/orderintake/v1/erp-submit   {"intakeId": "a0X..."}
 */
@RestResource(urlMapping='/orderintake/v1/erp-submit')
global with sharing class OrderIntakeErpSubmitApi {
    global class SubmitRequest {
        public Id intakeId;
    }

    global class SubmitResponse {
        public String intakeNumber;
        /** Intake status after the submit: ERP Confirmed, ERP Failed, or unchanged when it could not be sent */
        public String status;
        public String erpOrderNumber;
        public String message;
        /** Order confirmation for the customer, set when the ERP confirmed the order */
        public String replySubject;
        public String replyBody;
    }

    @HttpPost
    global static SubmitResponse receive() {
        SubmitRequest req = (SubmitRequest) JSON.deserialize(RestContext.request.requestBody.toString(), SubmitRequest.class);
        try {
            return submit(req.intakeId);
        } catch (Exception e) {
            RestContext.response.statusCode = 400;
            SubmitResponse res = new SubmitResponse();
            res.status = 'Error';
            res.message = e.getMessage();
            return res;
        }
    }

    public static SubmitResponse submit(Id intakeId) {
        Order_Intake__c intake = [SELECT Id, Name FROM Order_Intake__c WHERE Id = :intakeId WITH USER_MODE];

        SubmitOrderToErp.Request submitReq = new SubmitOrderToErp.Request();
        submitReq.intakeReference = intake.Name;
        SubmitOrderToErp.Result submitted = SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ submitReq })[0];

        SubmitResponse res = new SubmitResponse();
        res.intakeNumber = intake.Name;
        res.status = [SELECT Status__c FROM Order_Intake__c WHERE Id = :intake.Id WITH USER_MODE].Status__c;
        res.erpOrderNumber = String.isBlank(submitted.erpOrderNumber) ? null : submitted.erpOrderNumber;
        res.message = submitted.message;
        if (submitted.success == true) {
            DraftOrderConfirmationEmail.Request draftReq = new DraftOrderConfirmationEmail.Request();
            draftReq.intakeReference = intake.Name;
            DraftOrderConfirmationEmail.Result draft = DraftOrderConfirmationEmail.draft(new List<DraftOrderConfirmationEmail.Request>{ draftReq })[0];
            if (draft.ready == true) {
                res.replySubject = draft.subject;
                res.replyBody = draft.body;
            }
        }
        return res;
    }
}
