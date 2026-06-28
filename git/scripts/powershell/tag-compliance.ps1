# =============================================================
# tag-compliance.ps1
# Azure FinOps Toolkit — Tag Compliance Audit
# =============================================================
# PURPOSE:
#   Scans all resources across the current subscription and
#   reports which are missing mandatory FinOps tags. Without
#   tags there is no chargeback, without chargeback there is
#   no cost accountability culture.
#
# PREREQUISITES:
#   Install-Module -Name Az -Scope CurrentUser -Force
#   Connect-AzAccount
#
# USAGE:
#   ./tag-compliance.ps1
#   ./tag-compliance.ps1 -RequiredTags @("cost_centre","environment")
#   ./tag-compliance.ps1 -ResourceGroupFilter "prod-*"
#
# OUTPUT:
#   Compliance summary + CSV of non-compliant resources
# =============================================================

param(
    [string[]]$RequiredTags = @("cost_centre", "environment", "application", "owner"),
    [string]$ResourceGroupFilter = "*",
    [string]$OutputPath = "./tag-compliance-$(Get-Date -Format 'yyyy-MM-dd').csv",
    [switch]$SummaryOnly
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Azure Tag Compliance Audit"
Write-Host " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Required tags: $($RequiredTags -join ' | ')"
Write-Host "RG filter:     $ResourceGroupFilter"
Write-Host ""

# Check context
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "ERROR: Not logged in. Run: Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Subscription: $($ctx.Subscription.Name)"
Write-Host ""
Write-Host "Scanning resources..." -ForegroundColor Yellow

# Get all resources (optionally filtered by resource group pattern)
try {
    $AllResources = Get-AzResource -ErrorAction Stop
    if ($ResourceGroupFilter -ne "*") {
        $AllResources = $AllResources | Where-Object { $_.ResourceGroupName -like $ResourceGroupFilter }
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$TotalCount = $AllResources.Count
Write-Host "Total resources scanned: $TotalCount"
Write-Host ""

# Evaluate compliance for each resource
$NonCompliant = [System.Collections.Generic.List[PSCustomObject]]::new()
$CompliantCount = 0

foreach ($Resource in $AllResources) {
    $MissingTags = @()
    $PresentTags = @()

    foreach ($Tag in $RequiredTags) {
        if ($Resource.Tags -and $Resource.Tags.ContainsKey($Tag) -and $Resource.Tags[$Tag]) {
            $PresentTags += $Tag
        } else {
            $MissingTags += $Tag
        }
    }

    if ($MissingTags.Count -gt 0) {
        $NonCompliant.Add([PSCustomObject]@{
            ResourceName   = $Resource.Name
            ResourceType   = $Resource.ResourceType
            ResourceGroup  = $Resource.ResourceGroupName
            Location       = $Resource.Location
            MissingTags    = $MissingTags -join ", "
            PresentTags    = if ($PresentTags) { $PresentTags -join ", " } else { "none" }
            MissingCount   = $MissingTags.Count
        })
    } else {
        $CompliantCount++
    }
}

# Compliance rate
$NonCompliantCount = $NonCompliant.Count
$ComplianceRate    = if ($TotalCount -gt 0) {
    [math]::Round(($CompliantCount / $TotalCount) * 100, 1)
} else { 0 }

# Colour-code the compliance rate
$RateColour = if ($ComplianceRate -ge 90) { "Green" }
              elseif ($ComplianceRate -ge 70) { "Yellow" }
              else { "Red" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Results"
Write-Host "========================================"
Write-Host " Total resources:      $TotalCount"
Write-Host " Fully compliant:      $CompliantCount"
Write-Host " Non-compliant:        $NonCompliantCount"
Write-Host " Compliance rate:      $ComplianceRate%" -ForegroundColor $RateColour
Write-Host ""

if ($ComplianceRate -lt 70) {
    Write-Host " WARNING: Compliance below 70%. Chargeback/showback accuracy" -ForegroundColor Red
    Write-Host " will be unreliable until tagging is remediated." -ForegroundColor Red
} elseif ($ComplianceRate -lt 90) {
    Write-Host " NOTE: Compliance between 70-90%. Trending in the right direction" -ForegroundColor Yellow
    Write-Host " but still impacting allocation accuracy." -ForegroundColor Yellow
} else {
    Write-Host " GOOD: Compliance above 90%. Cost allocation model is reliable." -ForegroundColor Green
}

Write-Host ""

# Breakdown by missing tag
Write-Host "--- Missing tag breakdown ---"
foreach ($Tag in $RequiredTags) {
    $Count = ($NonCompliant | Where-Object { $_.MissingTags -match $Tag }).Count
    $Pct   = if ($TotalCount -gt 0) { [math]::Round(($Count / $TotalCount) * 100, 1) } else { 0 }
    Write-Host "  $Tag : $Count resources missing ($Pct%)"
}
Write-Host ""

# Show detail unless summary only
if (-not $SummaryOnly -and $NonCompliant.Count -gt 0) {
    Write-Host "--- Non-compliant resources (top 20) ---"
    $NonCompliant |
        Sort-Object MissingCount -Descending |
        Select-Object -First 20 |
        Format-Table ResourceName, ResourceGroup, ResourceType, MissingTags -AutoSize
}

# Export full list
if ($NonCompliant.Count -gt 0) {
    $NonCompliant | Sort-Object ResourceGroup, ResourceName |
        Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host ""
    Write-Host "Full non-compliant list saved to: $OutputPath" -ForegroundColor Green
} else {
    Write-Host "All resources are fully compliant. No CSV generated." -ForegroundColor Green
}

Write-Host ""
Write-Host "FINOPS NOTE: Use Azure Policy to enforce tags at resource group"
Write-Host "level and prevent future non-compliance at source."
