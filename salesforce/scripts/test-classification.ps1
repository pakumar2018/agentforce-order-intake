# Creates sample Order Intake records, runs the Classify_Order_Email prompt template
# on each through the REST API (the same call MuleSoft makes), then deletes them.
# Run: .\scripts\test-classification.ps1
param([string]$Org = 'orderintake', [string]$ApiVersion = 'v65.0')

$samples = @(
    @{ From = 'demo.dealer.po+brightline@gmail.com'; Subject = 'PO 45120 - widgets and bearings'
       Body = 'Hi team, please find attached our purchase order PO 45120 for 200 x WID-1001 and 500 x BRG-2001. Deliver to our Dayton plant. Thanks, Maya'; Expect = 'Purchase Order' },
    @{ From = 'demo.dealer.po+cobalt@gmail.com'; Subject = 'Change to PO 7781'
       Body = 'Hello, please change the quantity of VLV-5001 on our PO 7781 from 40 to 60 and cancel the gasket line. Regards, Daniel'; Expect = 'Change Order' },
    @{ From = 'demo.dealer.po+summit@gmail.com'; Subject = 'Pump availability'
       Body = 'Do you have the 0.5 HP centrifugal pump in stock, and what would be the lead time for 5 units?'; Expect = 'Inquiry' },
    @{ From = 'demo.dealer.po+harborpine@gmail.com'; Subject = 'Out of office'
       Body = 'I am out of the office until Monday with limited access to email.'; Expect = 'Other' }
)

$i = 0
foreach ($s in $samples) {
    $i++
    $values = "Subject__c='$($s.Subject)' Source_Email_From__c='$($s.From)' Gmail_Message_Id__c='classify-test-$i' Email_Body__c='$($s.Body)'"
    $rec = sf data create record --sobject Order_Intake__c --values $values --target-org $Org --json | ConvertFrom-Json
    $id = $rec.result.id

    $body = @{
        isPreview = $false
        inputParams = @{ valueMap = @{ 'Input:Order_Intake' = @{ value = @{ id = $id } } } }
        additionalConfig = @{ numGenerations = 1; temperature = 0; applicationName = 'PromptBuilderPreview' }
    } | ConvertTo-Json -Depth 10 -Compress
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $body -Encoding utf8
    $resp = sf api request rest "/services/data/$ApiVersion/einstein/prompt-templates/Classify_Order_Email/generations" --method POST --body "@$tmp" --target-org $Org 2>&1 | Out-String
    Remove-Item $tmp

    # Windows PowerShell's ConvertFrom-Json rejects the response's empty-named property, so pull "text" out directly
    $text = if ($resp -match '"text"\s*:\s*"((?:[^"\\]|\\.)*)"') { $Matches[1] -replace '\\"', '"' } else { $resp }
    "[$($s.Expect)] $($s.Subject)`n   -> $text`n"

    sf data delete record --sobject Order_Intake__c --record-id $id --target-org $Org | Out-Null
}
