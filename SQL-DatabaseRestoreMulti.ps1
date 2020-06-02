#######################
<#
    File Name                     : SQL-DatabaseRestoreMulti.ps1
    Current Version               : v1.0
    Script Create Date  		  : 
    Script Modified Date & By?	  : 
    DESCRIPTION                   : Restore multiple databases
#>
#######################

$invocLoc= Split-Path -Parent $MyInvocation.MyCommand.Path

#Read Configuration file
[xml]$ConfigFile = Get-Content "$invocLoc\Config_SqlDatabaseRestoreMulti.xml"



$backupFileLocation = $ConfigFile.Param.BackupLocation
$datafilesDest      = $ConfigFile.Param.DataFileLoc
$logfilesDest       = $ConfigFile.Param.LogFileLoc
$server             = $ConfigFile.Param.ServerName

$backupRoot = Get-ChildItem -Path $backupFileLocation
$now=Get-Date -Format ("MM_dd_yyyy_HH_mm")
set-Variable -Name DbRestoreTime -value (get-date) -Force
$Logfile = "$backupFileLocation\$(gc env:computername)_RestoreDatabase_Log_$now.log"

function Write-Log
{
   Param ([string]$logstring)

   Add-content $Logfile -value $logstring
}

function Estimated-Time($stTime,$edTime2)
{
        $TimeDiff = New-TimeSpan $stTime $edTime2
        if ($TimeDiff.Seconds -lt 0) 
        {
	        $Hrs = ($TimeDiff.Hours) + 23
	        $Mins = ($TimeDiff.Minutes) + 59
	        $Secs = ($TimeDiff.Seconds) + 59 
        }
    else {
	        $Hrs = $TimeDiff.Hours
	        $Mins = $TimeDiff.Minutes
	        $Secs = $TimeDiff.Seconds 
         }
    $Difference = '{0:00}:{1:00}:{2:00}' -f $Hrs,$Mins,$Secs
    Write-Host "`nTotal time to process(hh:mm:ss):: $Difference"
    write-log -logstring "`nTotal time to process(hh:mm:ss):: $Difference"
}
Write-Host "Starting @:: $DbRestoreTime"
write-log -logstring "Restore Multiple Database"
write-log -logstring "Starting @:: $DbRestoreTime"
## For each folder in the backup root directory...
foreach($folder in $backupRoot)
{   
    # Get the most recent .bak files for all databases...
    $backupFiles = Get-ChildItem -Path $folder.FullName -Filter "*.bak" -Recurse | Sort-Object -Property CreationTime -Descending | Select-Object -First 1
    

    # For each .bak file...
    foreach ($backupFile in $backupFiles)
    {
        
    
        $smoRestore = New-Object -Type Microsoft.SqlServer.Management.Smo.Restore
        $backupDevice = New-Object -Type Microsoft.SqlServer.Management.Smo.BackupDeviceItem -Argumentlist $backupFile,"File"
        $smoRestore.Devices.Add($backupDevice)
        $smoRestore.NoRecovery = $false
        $smoRestore.ReplaceDatabase = $true
        $smoRestore.Action = "Database"
        $smoRestore.PercentCompleteNotification = 10


        # Restore the header to get the database name...
        $query = "RESTORE HEADERONLY FROM DISK = N'"+$backupFile.FullName+"'"
        $headerInfo = Invoke-Sqlcmd -ServerInstance $server -Query $query
        $databaseName = $headerInfo.DatabaseName

        # Restore the file list to get the logical filenames of the database files...
        $query = "RESTORE FILELISTONLY FROM DISK = N'"+$backupFile.FullName+"'"
        $files = Invoke-Sqlcmd -ServerInstance $server -Query $query

        #Set restore configurations
        $smoRestore.Database = $databaseName
        Write-Host "`n[INFO] Preparing restore of:: $databaseName from:: $backupFile"
        Write-Log "`n[INFO] Preparing restore of:: $databaseName from:: $backupFile"

        #event handler to stream back progress on the restore (found from post on http://www.sqlservercentral.com/Forums/Topic1671065-3411-1.aspx)
        $percentEventHandler = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler]  {
                        Write-Host "[INFO] Restoring $($_.Percent)%"
                        Write-Log "[INFO] Restoring $($_.Percent)%"
        }
        $completedEventHandler = [Microsoft.SqlServer.Management.Common.ServerMessageEventHandler] {
            Write-Log "[INFO] Restore of database:: $DatabaseName with:: $backupFile completed "
        }
         
        $smoRestore.add_PercentComplete($percentEventHandler)
        $smoRestore.add_Complete($completedEventHandler)

        foreach ($row in $files)
            {
            
                $fileType = $row["Type"].ToUpper()
                 if ($fileType.Equals("D")) 
                   {
                      $dbLogicalName = $row["LogicalName"]
                      $smoRestoreFile = New-Object("Microsoft.SqlServer.Management.Smo.RelocateFile") 
                      $smoRestoreFile.LogicalFileName = $dbLogicalName
                      $a=$row["PhysicalName"]
                      $ab=$a.Split("\"" ")[-1]
                      $smoRestoreFile.PhysicalFileName = $datafilesDest+ '\'+ $ab
                      $smoRestore.RelocateFiles.Add($smoRestoreFile) | Out-Null
                                            
                   }
                   elseif ($fileType.Equals("L")) 
                   {
                      $logLogicalName = $row["LogicalName"]
                      $smoRestoreLog = New-Object("Microsoft.SqlServer.Management.Smo.RelocateFile")
                      $smoRestoreLog.LogicalFileName = $logLogicalName
                      $b=$row["PhysicalName"]
                      $ba=$b.Split("\"" ")[-1]
                      $smoRestoreLog.PhysicalFileName = $logfilesDest + '\'+ $ba
                      $smoRestore.RelocateFiles.Add($smoRestoreLog) | Out-Null
                   }

            }

         Write-Host "`n[INFO] Starting restore of:: $databaseName " #+ Get-Date -Format ("MM/dd/yyyy HH:mm:ss") 
         Write-Log "[INFO] Starting restore of:: $databaseName " #+ Get-Date -Format ("MM/dd/yyyy HH:mm:ss")
         $Time1= Get-Date -format HH:mm:ss            
         $smoRestore.SqlRestore($server)
         $Time2= Get-Date -format HH:mm:ss 
         Write-Host "`n[INFO] Completed restore of:: $databaseName"
         Write-Log "[INFO] Completed restore of:: $databaseName"
         Estimated-Time -stTime $Time1 -edTime2 $Time2

     }
} 

#*******************************************************END*****************************************************************************