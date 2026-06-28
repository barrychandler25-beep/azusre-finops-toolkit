# =============================================================
# cost-by-rg.ps1
# Azure FinOps Toolkit — Monthly Cost Report by Resource Group
# =============================================================
# PURPOSE:
#   Pulls the last 30 days of Azure cost data grouped by resource
#   group and exports to CSV for stakeholder reporting. The
#   foundation of any showback or chargeback programme.
#
# PREREQUISITES:
#   Install-Module -Name Az -Scope CurrentUser -Force
#   Connect-AzAccount
#
# USAGE:
#   ./cost-by-rg.ps1
#   ./cost-by-rg.ps1 -SubscriptionId "your-sub-id"
#   ./cost-by-rg.ps1 -DaysBack 60 -OutputPath "./q2-costs.csv"
#
# OUTPUT:
#   CSV file + formatted table in terminal
# =============================================================

param(
    [string]$SubscriptionId = "",
    [int]$DaysBack = 30,
    [string]$OutputPath = "./cost-report-$(Get-Date -Format 'yyyy-MM-dd').csv",
    [switch]$ShowZeroCost
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Azure Cost Report by Resource Group"
Write-Host " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Az module is installed
if (-not (Get-Module -ListAvailable -Name Az.Billing)) {
    Write-Host "ERROR: Az module not installed." -ForegroundColor Red
    Write-Host "Run: Install-Module -Name Az -Scope CurrentUser -Force"
    exit 1
}

# Set subscription context
if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-Host "Using subscription: $SubscriptionId"
} else {
    $ctx = Get-AzContext
    if (-not $ctx) {
        Write-Host "ERROR: Not logged in to Azure. Run: Connect-AzAccount" -ForegroundColor Red
        exit 1
    }
    Write-Host "Using subscription: $($ctx.Subscription.Name) ($($ctx.Subscription.Id))"
}

# Date range
$EndDate   = (Get-Date).ToString("yyyy-MM-dd")
$StartDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")
Write-Host "Date range:         $StartDate  →  $EndDate"
Write-Host "Days back:          $DaysBack"
Write-Host ""
Write-Host "Fetching cost data (this may take 30–60 seconds)..." -ForegroundColor Yellow

# Pull usage detail
try {
    $UsageDetails = Get-AzConsumptionUsageDetail `
        -StartDate $StartDate `
        -EndDate $EndDate `
        -ErrorAction Stop
} catch {
    Write-Host ""
    Write-Host "ERROR pulling cost data: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Ensure your account has Cost Management Reader role or higher."
    exit 1
}

if (-not $UsageDetails -or $UsageDetails.Count -eq 0) {
    Write-Host "No cost data returned for this subscription/period." -ForegroundColor Yellow
    exit 0
}

Write-Host "Processing $($UsageDetails.Count) usage records..."
Write-Host ""

# Group by resource group and sum costs
$Report = $UsageDetails |
    Group-Object -Property ResourceGroupName |
    ForEach-Object {
        $totalCost    = ($_.Group | Measure-Object -Property PretaxCost -Sum).Sum
        $resourceCount = ($_.Group | Select-Object -Unique InstanceId).Count
        $topService   = ($_.Group | Group-Object ConsumedService |
                         Sort-Object Count -Descending | Select-Object -First 1).Name

        [PSCustomObject]@{
            ResourceGroup  = if ($_.Name) { $_.Name } else { "(unassigned)" }
            TotalCostGBP   = [math]::Round($totalCost, 2)
            ResourceCount  = $resourceCount
            TopService     = $topService
            AvgDailyCost   = [math]::Round($totalCost / $DaysBack, 2)
        }
    } |
    Where-Object { $ShowZeroCost -or $_.TotalCostGBP -gt 0 } |
    Sort-Object TotalCostGBP -Descending

# Summary stats
$GrandTotal   = [math]::Round(($Report | Measure-Object -Property TotalCostGBP -Sum).Sum, 2)
$TopRG        = $Report | Select-Object -First 1
$MonthlyRate  = [math]::Round(($GrandTotal / $DaysBack) * 30, 2)

Write-Host "========================================"
Write-Host " Summary"
Write-Host "========================================"
Write-Host " Total spend ($DaysBack days):    £$GrandTotal"
Write-Host " Projected monthly run rate: £$MonthlyRate"
Write-Host " Highest cost RG:           $($TopRG.ResourceGroup) (£$($TopRG.TotalCostGBP))"
Write-Host " Resource groups with cost: $($Report.Count)"
Write-Host ""

# Display table
$Report | Format-Table -AutoSize

# Export to CSV
$Report | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host ""
Write-Host "Report saved to: $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "FINOPS NOTE: Share this report in monthly cost review."
Write-Host "Flag any RG where cost has grown >20% month-on-month."
