// Seeds fictional order intakes that cover each demo scenario, as if MuleSoft had already
// read, classified and extracted the emails. Run seed-demo-data.apex first.
// Safe to re-run: intakes whose Gmail_Message_Id__c already exists are skipped.
// Run: sf apex run --file scripts/apex/seed-demo-intakes.apex --target-org orderintake

Map<String, Id> productByCode = new Map<String, Id>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode != null]) productByCode.put(p.ProductCode, p.Id);
Map<String, Id> accountByName = new Map<String, Id>();
for (Account a : [SELECT Id, Name FROM Account]) accountByName.put(a.Name, a.Id);
Map<Id, Decimal> listPrice = new Map<Id, Decimal>();
for (PricebookEntry e : [SELECT Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2.IsStandard = true]) listPrice.put(e.Product2Id, e.UnitPrice);

Set<String> existing = new Set<String>();
for (Order_Intake__c i : [SELECT Gmail_Message_Id__c FROM Order_Intake__c WHERE Gmail_Message_Id__c LIKE 'seed-%']) existing.add(i.Gmail_Message_Id__c);

// {messageId, account, from, subject, body, classification, classConf, extractConf, status, exceptions, poNumber, hoursAgo}
List<List<Object>> intakeRows = new List<List<Object>>{
    new List<Object>{ 'seed-brightline-45120', 'Brightline Manufacturing', 'demo.dealer.po+brightline@gmail.com',
        'PO 45120 - widgets, bearings and valves',
        'Hi team, please find attached PO 45120 for our Dayton plant. Delivery needed by next Friday. Thanks, Maya Chen',
        'Purchase Order', 98, 91, 'Needs Review', 'Unknown SKU;Price Mismatch', '45120', 3 },
    new List<Object>{ 'seed-cobalt-7781', 'Cobalt Fabrication Ltd', 'demo.dealer.po+cobalt@gmail.com',
        'Purchase order 7781',
        'Hello, attached is purchase order 7781 for fasteners and gaskets. Regards, Daniel Okafor',
        'Purchase Order', 99, 96, 'Extracted', null, '7781', 2 },
    new List<Object>{ 'seed-harborpine-2210', 'Harbor and Pine Facilities', 'demo.dealer.po+harborpine@gmail.com',
        'PO HP-2210 pumps for site upgrade',
        'Please process the attached PO HP-2210 for 80 centrifugal pumps for our facilities upgrade. Sofia Marin',
        'Purchase Order', 97, 95, 'Extracted', null, 'HP-2210', 5 },
    new List<Object>{ 'seed-summit-5530', 'Summit Machine Works', 'demo.dealer.po+summit@gmail.com',
        'PO SMW-5530 (scanned)',
        'Attached is a scan of PO SMW-5530 for hydraulic filters. Liam Novak',
        'Purchase Order', 93, 62, 'Needs Review', 'Low Confidence;Unknown SKU', 'SMW-5530', 1 },
    new List<Object>{ 'seed-summit-inquiry', 'Summit Machine Works', 'demo.dealer.po+summit@gmail.com',
        'Pump availability',
        'Do you have the 0.5 HP centrifugal pump in stock, and what is the lead time for 5 units?',
        'Inquiry', 92, null, 'Not Order', null, null, 6 }
};

// messageId -> lines {lineNo, rawSku, rawDescription, qty, poPrice, matchedCode or null}
Map<String, List<List<Object>>> lineRows = new Map<String, List<List<Object>>>{
    'seed-brightline-45120' => new List<List<Object>>{
        new List<Object>{ 1, 'WID-1001', 'Industrial Widget 10mm', 200, 12.50, 'WID-1001' },
        new List<Object>{ 2, 'BRG6204', 'Ball bearing 6204 sealed', 500, 4.20, null },
        new List<Object>{ 3, 'VLV-5001', 'Ball valve 1/2 in brass', 40, 29.00, 'VLV-5001' }
    },
    'seed-cobalt-7781' => new List<List<Object>>{
        new List<Object>{ 1, 'BLT-3001', 'Hex bolt M8x40 box/100', 30, 22.00, 'BLT-3001' },
        new List<Object>{ 2, 'NUT-3101', 'Hex nut M8 box/100', 30, 9.80, 'NUT-3101' },
        new List<Object>{ 3, 'GSK-4001', 'Rubber gasket 50mm', 200, 1.35, 'GSK-4001' }
    },
    'seed-harborpine-2210' => new List<List<Object>>{
        new List<Object>{ 1, 'PMP-6001', 'Centrifugal pump 0.5HP', 80, 449.00, 'PMP-6001' }
    },
    'seed-summit-5530' => new List<List<Object>>{
        new List<Object>{ 1, 'FLT-7001', 'Hydraulic filter cartridge', 25, 27.40, 'FLT-7001' },
        new List<Object>{ 2, 'HYD-FLTR-CRTG', 'HYD FLTR CRTG 10 MIC', 10, 27.40, null }
    }
};

List<Order_Intake__c> intakes = new List<Order_Intake__c>();
for (List<Object> r : intakeRows) {
    if (existing.contains((String) r[0])) continue;
    intakes.add(new Order_Intake__c(
        Gmail_Message_Id__c = (String) r[0], Account__c = accountByName.get((String) r[1]),
        Source_Email_From__c = (String) r[2], Subject__c = (String) r[3], Email_Body__c = (String) r[4],
        Classification__c = (String) r[5], Classification_Confidence__c = (Integer) r[6],
        Extraction_Confidence__c = (Integer) r[7], Status__c = (String) r[8], Exception_Reason__c = (String) r[9],
        Customer_PO_Number__c = (String) r[10], Received_At__c = System.now().addHours(-((Integer) r[11])),
        Mule_Correlation_Id__c = 'demo-' + (String) r[0]
    ));
}
// Lines go in before the final status, so review cases opened by OrderIntakeTrigger list them
Map<String, String> finalStatus = new Map<String, String>();
for (Order_Intake__c intake : intakes) {
    if (lineRows.containsKey(intake.Gmail_Message_Id__c)) {
        finalStatus.put(intake.Gmail_Message_Id__c, intake.Status__c);
        intake.Status__c = 'Classified';
    }
}
insert intakes;

List<Order_Intake_Line__c> lines = new List<Order_Intake_Line__c>();
for (Order_Intake__c intake : intakes) {
    if (!lineRows.containsKey(intake.Gmail_Message_Id__c)) continue;
    for (List<Object> l : lineRows.get(intake.Gmail_Message_Id__c)) {
        Id productId = l[5] == null ? null : productByCode.get((String) l[5]);
        Decimal poPrice = (Decimal) l[4];
        Decimal catalogPrice = productId == null ? null : listPrice.get(productId);
        String match = 'Unmatched';
        if (productId != null) {
            match = (catalogPrice != null && Math.abs(poPrice - catalogPrice) / catalogPrice > 0.05) ? 'Price Mismatch' : 'Matched';
        }
        lines.add(new Order_Intake_Line__c(
            Order_Intake__c = intake.Id, Line_No__c = (Integer) l[0], Raw_SKU__c = (String) l[1],
            Raw_Description__c = (String) l[2], Quantity__c = (Integer) l[3], Unit_Price_On_PO__c = poPrice,
            Product__c = productId, List_Price__c = catalogPrice, Match_Status__c = match
        ));
    }
}
insert lines;
List<Order_Intake__c> statusUpdates = new List<Order_Intake__c>();
for (Order_Intake__c intake : intakes) {
    if (finalStatus.containsKey(intake.Gmail_Message_Id__c)) {
        statusUpdates.add(new Order_Intake__c(Id = intake.Id, Status__c = finalStatus.get(intake.Gmail_Message_Id__c)));
    }
}
update statusUpdates;

System.debug('SEED RESULT: intakes+' + intakes.size() + ' lines+' + lines.size());
