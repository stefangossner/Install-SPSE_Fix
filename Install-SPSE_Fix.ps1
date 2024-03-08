<#
 This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.  
 THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
 INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  
 We grant you a nonexclusive, royalty-free right to use and modify the sample code and to reproduce and distribute the object 
 code form of the Sample Code, provided that you agree: 
    (i)   to not use our name, logo, or trademarks to market your software product in which the sample code is embedded; 
    (ii)  to include a valid copyright notice on your software product in which the sample code is embedded; and 
    (iii) to indemnify, hold harmless, and defend us and our suppliers from and against any claims or lawsuits, including 
          attorneys' fees, that arise or result from the use or distribution of the sample code.
 Please note: None of the conditions outlined in the disclaimer above will supercede the terms and conditions contained within 
              the Premier Customer Services Description.


  SUMMARY: 
    
   This script identifies and stops/restarts Services to reduce the patch install time for SharePoint Server Subscription Edition Cumlative Update.
   As input parameter it takes the path to the SharePoint patch to be installed and 
   whether a graceful shutdown of the distributed cache on the current server should be performed if the current machine hosts the distributed cache service

   Reference: https://blog.stefan-gossner.com/2024/03/08/solving-the-extended-install-time-for-spse-cus/

#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$CULocation,

    [Parameter(Mandatory=$false)]
    [bool]$ShouldGracefulStopDCache = $false
)

if (!$CULocation.ToLower().EndsWith(".exe") -or ![System.IO.File]::Exists($CULocation))
{
    Write-Host -ForegroundColor Yellow "Please specify the path of the SharePoint Server Subscription Edition Update fix (e.g. C:\temp\uber-subscription-kb5002560-fullfile-x64-glb.exe)"
    Exit
}

$MachineName = $env:COMPUTERNAME

$srvSPTimerv4 = Get-Service "SPTimerV4"
$srvSPTraceV4 = Get-Service "SPTraceV4"
$srvSPAdminV4 = Get-Service "SPAdminV4"

$srvw3svc = Get-Service "w3svc"

$srvOSearch16 = Get-Service "OSearch16"
$srvSPSearchHostController = Get-Service "SPSearchHostController"

$srvSPCache = Get-Service "SPCache"

$restartOSearch16 = $false
$restartSPSearchHostController = $false
$restartDCache = $false

Write-Host -ForegroundColor Yellow "Warning: This script will stop the following services before applying the fix:"
if ($srvSPTimerv4.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- SPTimerV4"
}
if ($srvSPTraceV4.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- SPTraceV4"
}
if ($srvSPAdminV4.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- SPAdminV4"
}
if ($srvw3svc.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- W3SVC"
}
if ($srvOSearch16.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- OSearch16"
}
if ($srvSPSearchHostController.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- SPSearchHostController"
}
if ($srvSPCache.Status -eq "Running")
{
    Write-Host -ForegroundColor Yellow "- SPCache "
}

Write-Host -ForegroundColor Yellow ""
Read-Host "PRESS ENTER TO CONTINUE"


if ($srvSPTimerv4.Status -eq "Running")
{
    Write-Host "Stopping SPTimerV4 service..."
    $srvSPTimerv4.Stop()
    $srvSPTimerv4.WaitForStatus("Stopped")
}

if ($srvSPTraceV4.Status -eq "Running")
{
    Write-Host "Stopping SPTraceV4 service..."
    $srvSPTraceV4.Stop()
    $srvSPTraceV4.WaitForStatus("Stopped")
}

if ($srvSPAdminV4.Status -eq "Running")
{
    Write-Host "Stopping SPAdminV4 service..."
    $srvSPAdminV4.Stop()
    $srvSPAdminV4.WaitForStatus("Stopped")
}

if ($srvw3svc.Status -eq "Running")
{
    Write-Host "Stopping W3SVC service..."
    $srvw3svc.Stop()
    $srvw3svc.WaitForStatus("Stopped")
}

if ($srvOSearch16.Status -eq "Running")
{
    $restartOSearch16 = $true
    Write-Host "Stopping OSearch16 service..."
    $srvOSearch16.Stop()
    $srvOSearch16.WaitForStatus("Stopped")
}

if ($srvSPSearchHostController.Status -eq "Running")
{
    $restartSPSearchHostController = $true
    Write-Host "Stopping SPSearchHostController service..."
    $srvSPSearchHostController.Stop()
    $srvSPSearchHostController.WaitForStatus("Stopped")
}

if ($srvSPCache.Status -eq "Running")
{
    $restartDCache = $true
    if ($ShouldGracefulStopDCache)
    {
        Use-SPCacheCluster
        import-module "C:\Program Files\Common Files\microsoft shared\Web Server Extensions\16\BIN\CacheModules\DistributedCacheAdministration\DistributedCacheAdministration"
        get-spcacheclusterhealth
        try
        {
            Write-Host "Graceful stopping Cache Host..."
            stop-afcachehost -graceful -computername $MachineName -CachePort 22233
            Remove-SPDistributedCacheServiceInstance
        }
        catch 
        {
            $_
            Write-Host -ForegroundColor Yellow "Graceful stopping of Cache Host failed. Will fallback to non graceful stop of the caching service."
            # graceful failed fallback to stopping the caching service
            $ShouldGracefulStopDCache = $false
            Write-Host "Stopping SPCache service..."
            $srvSPCache.Stop()
            $srvSPCache.WaitForStatus("Stopped")
        }
    }
    else
    {
        Write-Host "Stopping SPCache service..."
        $srvSPCache.Stop()
        $srvSPCache.WaitForStatus("Stopped")
    }
}

Write-Host 
Write-Host -ForegroundColor Green "All relevant Services have been stopped."
Write-Host -ForegroundColor Green "The SharePoint CU will now be applied..."

$startTime = Get-Date

$pInfo = New-Object System.Diagnostics.ProcessStartInfo
$pInfo.FileName = $CULocation
$pInfo.Arguments = "/passive"

$Process = [Diagnostics.Process]::Start($pInfo) 

$afterLaunchTime = Get-Date

$delta = $afterLaunchTime - $startTime

Write-Host 
Write-Host "Fix installation has been initiated. Waiting for completion..."
Write-Host -ForegroundColor Green "Time taken to launch installer: " $delta.Minutes "Minutes," $delta.Seconds "Seconds"

while (!$Process.HasExited)
{
    Start-Sleep -seconds 1
}

## we cannot use $Process.WaitForExit as it does not work reliably. 
## In my tests it did not return even after the process ended in several tests
## Need to loop and check HasExited instead

$endTime = Get-Date

$delta = $endTime - $afterLaunchTime

Write-Host 
Write-Host -ForegroundColor Green "Fix installation completed."
Write-Host -ForegroundColor Green "Time taken to install fix: " $delta.Minutes "Minutes," $delta.Seconds "Seconds"
Write-Host 


# get services again to get current status
$srvSPTimerv4 = Get-Service "SPTimerV4"
$srvSPTraceV4 = Get-Service "SPTraceV4"
$srvSPAdminV4 = Get-Service "SPAdminV4"

$srvw3svc = Get-Service "w3svc"

$srvOSearch16 = Get-Service "OSearch16"
$srvSPSearchHostController = Get-Service "SPSearchHostController"

$srvSPCache = Get-Service "SPCache"

if ($srvSPCache.Status -ne "Running" -and $restartDCache)
{
    if ($ShouldGracefulStopDCache)
    {
        Write-Host "Add SPDistributedCacheServiceInstance"
        Add-SPDistributedCacheServiceInstance
    }
    else
    {
        Write-Host "Start SPCache service..."
        $srvSPCache.Start()
        $srvSPCache.WaitForStatus("Running")
    }
}

if ($srvSPSearchHostController.Status -ne "Running" -and $restartSPSearchHostController)
{
    Write-Host "Start SPSearchHostController service..."
    $srvSPSearchHostController.Start()
    $srvSPSearchHostController.WaitForStatus("Running")
}

if ($srvOSearch16.Status -eq "Running" -and $restartOSearch16)
{
    Write-Host "Start OSearch16 service..."
    $srvOSearch16.Start()
    $srvOSearch16.WaitForStatus("Running")
}

if ($srvw3svc.Status -ne "Running")
{
    Write-Host "Start W3SVC service..."
    $srvw3svc.Start()
    $srvw3svc.WaitForStatus("Running")
}

if ($srvSPAdminV4.Status -ne "Running")
{
    Write-Host "Start SPAdminV4 service..."
    $srvSPAdminV4.Start()
    $srvSPAdminV4.WaitForStatus("Running")
}

if ($srvSPTraceV4.Status -ne "Running")
{
    Write-Host "Start SPTraceV4 service..."
    $srvSPTraceV4.Start()
    $srvSPTraceV4.WaitForStatus("Running")
}

if ($srvSPTimerv4.Status -ne "Running")
{
    Write-Host "Start SPTimerv4 service..."
    $srvSPTimerv4.Start()
    $srvSPTimerv4.WaitForStatus("Running")
}

Write-Host 
Write-Host -ForegroundColor Green "Service restart completed."

