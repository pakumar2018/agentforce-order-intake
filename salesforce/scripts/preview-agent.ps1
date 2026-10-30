# Sends a scripted conversation to an Order Intake Assistant preview session and prints
# each agent reply. Start the session first with:
#   sf agent preview start --json --authoring-bundle Order_Intake_Assistant --simulate-actions
# Run: .\scripts\preview-agent.ps1 -SessionId <id> -Messages "first message","second message"
param(
    [Parameter(Mandatory = $true)][string]$SessionId,
    [Parameter(Mandatory = $true)][string[]]$Messages,
    [string]$Org = 'orderintake'
)

foreach ($m in $Messages) {
    "REP:   $m"
    $raw = sf agent preview send --json --authoring-bundle Order_Intake_Assistant --session-id $SessionId -u $m --target-org $Org 2>&1 | Out-String
    $reply = try {
        (($raw | ConvertFrom-Json).result.messages | ForEach-Object { $_.message }) -join "`n"
    } catch {
        $raw
    }
    "AGENT: $reply`n"
}
