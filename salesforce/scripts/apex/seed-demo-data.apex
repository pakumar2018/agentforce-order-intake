// Seeds fictional demo data for the Order Intake agent: products with list prices
// in the Standard Price Book, plus customer accounts and buyer contacts.
// Safe to re-run: existing products (by ProductCode) and accounts (by Name) are reused.
// Run: sf apex run --file scripts/apex/seed-demo-data.apex --target-org orderintake

// ---- Products: {ProductCode, Name, Family, ListPrice}
List<List<Object>> productRows = new List<List<Object>>{
    new List<Object>{ 'WID-1001', 'Industrial Widget 10mm', 'Widgets', 12.50 },
    new List<Object>{ 'WID-1002', 'Industrial Widget 20mm', 'Widgets', 18.75 },
    new List<Object>{ 'BRG-2001', 'Ball Bearing 6204-2RS', 'Bearings', 4.20 },
    new List<Object>{ 'BRG-2002', 'Ball Bearing 6205-2RS', 'Bearings', 5.10 },
    new List<Object>{ 'BLT-3001', 'Hex Bolt M8x40 (box of 100)', 'Fasteners', 22.00 },
    new List<Object>{ 'BLT-3002', 'Hex Bolt M10x50 (box of 100)', 'Fasteners', 29.50 },
    new List<Object>{ 'NUT-3101', 'Hex Nut M8 (box of 100)', 'Fasteners', 9.80 },
    new List<Object>{ 'GSK-4001', 'Rubber Gasket 50mm', 'Seals', 1.35 },
    new List<Object>{ 'VLV-5001', 'Ball Valve 1/2 inch Brass', 'Valves', 34.90 },
    new List<Object>{ 'VLV-5002', 'Ball Valve 1 inch Brass', 'Valves', 58.00 },
    new List<Object>{ 'PMP-6001', 'Centrifugal Pump 0.5 HP', 'Pumps', 449.00 },
    new List<Object>{ 'FLT-7001', 'Hydraulic Filter Cartridge', 'Filters', 27.40 }
};

Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
if (!std.IsActive) {
    std.IsActive = true;
    update std;
}

Set<String> codes = new Set<String>();
for (List<Object> r : productRows) codes.add((String) r[0]);
Map<String, Product2> existing = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :codes]) existing.put(p.ProductCode, p);

List<Product2> newProducts = new List<Product2>();
for (List<Object> r : productRows) {
    if (!existing.containsKey((String) r[0])) {
        newProducts.add(new Product2(ProductCode = (String) r[0], Name = (String) r[1], Family = (String) r[2], IsActive = true,
            Description = 'Demo product for the Order Intake agent'));
    }
}
insert newProducts;
for (Product2 p : newProducts) existing.put(p.ProductCode, p);

Set<Id> pricedIds = new Set<Id>();
for (PricebookEntry e : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :std.Id AND Product2.ProductCode IN :codes]) pricedIds.add(e.Product2Id);
List<PricebookEntry> entries = new List<PricebookEntry>();
for (List<Object> r : productRows) {
    Product2 p = existing.get((String) r[0]);
    if (!pricedIds.contains(p.Id)) {
        entries.add(new PricebookEntry(Pricebook2Id = std.Id, Product2Id = p.Id, UnitPrice = (Decimal) r[3], IsActive = true));
    }
}
insert entries;

// ---- Customers: {Name, AccountNumber, Website, BuyerFirst, BuyerLast, BuyerEmail}
List<List<String>> accountRows = new List<List<String>>{
    // Buyer emails are "+" aliases of the dealer Gmail account (demo.dealer.po), so one account can send as every customer
    new List<String>{ 'Brightline Manufacturing', 'CUST-1001', 'brightline-mfg.example', 'Maya', 'Chen', 'demo.dealer.po+brightline@gmail.com' },
    new List<String>{ 'Cobalt Fabrication Ltd', 'CUST-1002', 'cobaltfab.example', 'Daniel', 'Okafor', 'demo.dealer.po+cobalt@gmail.com' },
    new List<String>{ 'Harbor and Pine Facilities', 'CUST-1003', 'harborpine.example', 'Sofia', 'Marin', 'demo.dealer.po+harborpine@gmail.com' },
    new List<String>{ 'Summit Machine Works', 'CUST-1004', 'summitmw.example', 'Liam', 'Novak', 'demo.dealer.po+summit@gmail.com' }
};
Set<String> names = new Set<String>();
for (List<String> r : accountRows) names.add(r[0]);
Map<String, Account> accounts = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :names]) accounts.put(a.Name, a);

List<Account> newAccounts = new List<Account>();
for (List<String> r : accountRows) {
    if (!accounts.containsKey(r[0])) {
        newAccounts.add(new Account(Name = r[0], AccountNumber = r[1], Website = r[2], Type = 'Customer - Direct', Industry = 'Manufacturing'));
    }
}
insert newAccounts;
for (Account a : newAccounts) accounts.put(a.Name, a);

Set<String> emails = new Set<String>();
for (List<String> r : accountRows) emails.add(r[5]);
Set<String> existingEmails = new Set<String>();
for (Contact c : [SELECT Email FROM Contact WHERE Email IN :emails]) existingEmails.add(c.Email.toLowerCase());
List<Contact> contacts = new List<Contact>();
for (List<String> r : accountRows) {
    if (!existingEmails.contains(r[5].toLowerCase())) {
        contacts.add(new Contact(AccountId = accounts.get(r[0]).Id, FirstName = r[3], LastName = r[4], Email = r[5], Title = 'Purchasing Manager'));
    }
}
insert contacts;

System.debug('SEED RESULT: products+' + newProducts.size() + ' prices+' + entries.size()
    + ' accounts+' + newAccounts.size() + ' contacts+' + contacts.size());
