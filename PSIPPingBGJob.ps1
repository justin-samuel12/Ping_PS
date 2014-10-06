#run below before executing
#set-executionpolicy remotesigned
PARAM ( $HostFile, [int]$NoOfItemsPerJob = 100, [Boolean]$Outfile = $true,$ShowResults="ALL",[Switch]$HelpFile )

$HelpText = @'
#######################################################################################
 Name    	    : PSIPPingBGJob.ps1
 Date    	    : 08/29/2013
 Original Author: xb90@PoshTips.com
 Modify Author  : Justin S.
  
 Usage:
    ./PSIPPingBGJob -HostFile [-NoOfItemsPerJob ][-OutFile(True/False) ][-$ShowResults(All/Success/Fail) ][-HelpFile]

 Where:

	-HostFile         Specifies a text file containing a list of network devices to
						be pinged. List items can be either host names or IP Addresses.
						Hostnames, or IP Addresses are accepted (IPv4 or IPv6 ok); only
						ONE ITEM per line. Entries beginning with "#" will be treated as
						comments and ignored.
	-NoOfItemsPerJob  Specifies the maximum number of hosts that will be submitted to
						a background job. Default is 100.
	-OutFile          Specifies a filename to which the CSV-formatted results will be
						written. True/False field, default true and output file will be on 
						user desktop. If False, then results will be output as a PowerShell object
	-ShowResults      Specifies which type of ping result to output. 
						Options are:
						"FAIL"    = Only output non-successful results
						"SUCCESS" = Only output successful results
						Omit this parameter to show all results
	-$HelpFile        Displays this help

 Examples:
	.\PSIPPingBGJob.ps1 -hostfile servers.txt -NoOfItemsPerJob 200 
		Results will be written to the the file ".\Desktop\PSIPPingBGJob_FinalResults_{0:MM_dd_yyyy-hhmmss}.csv"
	
	$result = .\PSIPPingBGJob.ps1 -hostfile servers.txt -NoOfItemsPerJob 200 -OutFile $false
		Results will be assigned to the variable "$result" as a PowerShell object array 
		
 Comments:
 	Since the BGPing.ps1 was developed before Powershell v3, test-connection was only pinging 1 EVEN thou use specify how many times
	to ping. Starting with v3, it went back to the intended behavior, similar to cmd line ping. Results are now increased by x times it ping.
	For instance if there are 100 IPs to ping and want to ping 5 times, results will come back as 500. So added grouping by IP and taking the last
	status
#######################################################################################
'@

#show help file
if ($HelpFile -or (!$HostFile)){
    write-host $HelpText    
    exit
    }
		
#Note: Status Code 99999  has been added to flag test-connectin call failures
$StatusCodes = @{
        0 =	"Success";
    11001 = "Buffer Too Small";
    11002 = "Destination Net Unreachable";
    11003 = "Destination Host Unreachable";
    11004 = "Destination Protocol Unreachable";
    11005 = "Destination Port Unreachable";
    11006 = "No Resources";
    11007 = "Bad Option";
    11008 = "Hardware Error";
    11009 = "Packet Too Big";
    11010 = "Request Timed Out";
    11011 = "Bad Request";
    11012 = "Bad Route";
    11013 = "TimeToLive Expired Transit";
    11014 = "TimeToLive Expired Reassembly";
    11015 = "Parameter Problem";
    11016 = "Source Quench";
    11017 = "Option Too Big";
    11018 = "Bad Destination";
    11032 = "Negotiating IPSEC";
    11050 = "General Error has occurred";
    99999 = "CALL FAILED"}

#check if file exist or valid
if (!(test-path $HostFile)){
    write-host "ERROR: `"$HostFile`" is not a  valid file" -back black -fore red
    write-host "REQUIRED ACTION: Re-run this script using a valid filename" -back red -fore white
    exit
}

#################### VARIABLES #######################
$defaultPath = [string][Environment]::GetFolderPath("Desktop")
$elapsedTime = [system.diagnostics.stopwatch]::StartNew()
$result = @()
$BackgroundJob="PSIPPingBGJob"
$itemCount = 0
$offset = 0
$timesToPing = 5
$CheckAfter=0
$activeJobCount = 0
$totalJobCount = 0
$FileGetContent = gc $HostFile |sort |get-unique | ? {((!$_.startswith("#")) -and ($_ -ne ""))}
$itemCount = $FileGetContent | measure-object -line |% {$_.lines}
$callFailure = test-connection -computername localhost -count 1
$callFailure.statuscode = 99999
$callFailure.address = "notset"				
######################################################


#check to see if there are any jobs with the name as $BackgroundJob still running. if so, destroy 
$BGPingJob = get-job |? {$_.name -like "$($BackgroundJob)*"}		
if ($BGPingJob.count -gt 0){
	Write-host "ERROR: There are pending background jobs in this session:" -back red -fore white
	$BGPingJob | Out-Host
	Write-host "They will be removed automatically" -back black -fore yellow
	foreach ($jobs in $BGPingJob) { Remove-Job $jobs.id -Force }
	Write-host "Sleeping for 5 seconds...." -back red -fore black
	sleep -Seconds 5 #sleep for x seconds
}

Write-host " $($BackgroundJob) started at $(get-date) ".padright(60)  -back black -fore green
Write-host "   -HostFile      : $HostFile"                            -back black -fore green
Write-host "                    (contains $itemCount unique entries)" -back black -fore green
if ($OutFile -eq $true){$File = "file to be saved onto desktop"}else{$File="results to saved as PS Object"}
write-host "   -OutFile       : $File" -back black -fore green                 
Write-host "Submitting background ping jobs..." -back black -fore yellow 


#create the batches
for ($offset=0; $offset -lt $itemCount;$offset += $NoOfItemsPerJob){
	$activeJobCount += 1; $totalJobCount += 1; $HostList = @()
	$HostList += $FileGetContent | select -skip $offset -first $NoOfItemsPerJob 
	$j = test-connection -computername $HostList -count $timesToPing -BufferSize 512 -delay 5 -throttlelimit 32 -erroraction silentlycontinue -asjob 
	$j.name = "$($BackgroundJob)`:$totalJobCount`:$($offset+1)`:$($HostList.count)"

	#write-host "$($j.name)"
    write-host "+" -back black -fore cyan -nonewline

    if (($checkAfter) -and ($activeJobCount -ge $checkAfter)){
        Write-host "`n$totaljobCount jobs submitted; checking for completed jobs..." -back black -fore yellow
        foreach ($j in get-job | ? {$_.name -like "$($BackgroundJob)*" -and $_.state -ne "Running"}){
            $result += receive-job $j
            remove-job $j
            $activeJobcount -= 1
            Write-host "-" -back black -fore cyan -nonewline
        }
    }
}

Write-host "`n$totaljobCount jobs submitted, checking for completed jobs..." -back black -fore yellow 

$recCnt = 0
while (get-job |? {$_.name -like "$($BackgroundJob)*"}){
	foreach ($j in get-job | ? {$_.name -like "$($BackgroundJob)*"}){	
	$temp = @()
		if ($j.state -eq "completed"){
			$temp = @()
		    $temp += receive-job $j
		    $result += $temp
		    #Write-host " (read $($temp.count) Lines - result count : $($result.count))"  -back black -fore green
		    remove-job $j
		    $ActiveJobCount -= 1
			Write-host "-" -back black -fore cyan -nonewline
		    }
		elseif ($j.state -eq "failed"){
    		$temp = $j.name.split(":")
    		if ($temp[1] -eq "R"){
		        #
		        # This is a single-entry recovery Job failure
		        #    extract hostname from the JobName and update our callFailure record
		        #    force-feed callFailure record into the results array
		        #    delete the job
		        #
		        Write-host " "
		        Write-host "Call Failure on Host: $($temp[2]) " -back red -fore white
		        remove-job $j
		        $callFailure.address = $temp[2]
		        $result += $callFailure
		        Write-host "resuming check for completed jobs..." -back black -fore yellow
	        }
  			else{
		        #
		        # The original background job failed, so need to resubmit each hostname from that job
		        # to determine which host failed and gather accurate ping results for the others
		        #
		        # Recovery Job Name Format: $($BackgroundJob):R:
		        #   where "R" indicates a Recovery job and  is the hostname or IP Address to be pinged
		        #   Recovery jobs will only have ONE hostname specified
		        #
		        Write-host "`nFailure detected in job: $($j.name); recovering now..." -back black -fore red
		        remove-job $j
		        $ActiveJobCount -= 1
		        $HostList = gc $HostFile |sort|get-unique|? {((!$_.startswith("#")) -and ($_ -ne ""))} | select -skip $($temp[2]-1) -first $temp[3]
		        foreach ($x in $HostList){
		            $j = test-connection -computername $x -count $timesToPing -throttlelimit 32 -erroraction silentlycontinue -asjob
		            $j.name = "$($BackgroundJob)*:R:$x"
		            Write-host "." -back black -fore cyan -nonewline
            	}
        	Write-host "`nresuming check for completed jobs..." -back black -fore yellow
        	}
    	}
}
if ($result.count -lt $itemCount){ sleep 5 }
}

#add columns to the results array
$result | add-member -membertype NoteProperty -Name StatusDescr -value "" -Force
$result | add-member -membertype NoteProperty -Name Id -value "" -Force
	foreach ($r in $result){
	    if ($r.statusCode -eq $null){ $r.statusCode = 99999 }
	    $r.StatusDescr = $statusCodes.item([int]$r.statusCode)
		$r.Id = ([array]::IndexOf($result, $r))+1
	    }

#take the last ping results per address
$result = $result |  select id, address,statuscode,statusdescr | Foreach-Object {$_.Id = $_.id; $_} |  Group-Object address |  Foreach-Object {$_.Group | Sort-Object Id | Select-Object -Last 1}
$result = $result | select  address,statuscode,statusdescr | sort address,statuscode 
					
Write-host " "
Write-host  " $($BackgroundJob) finished Pinging at $(get-date) ".padright(60) -back darkgreen -fore white
Write-host ("   Hosts Pinged : {0}" -f $($result.count)) -back black -fore green
Write-host ("   Elapsed Time : {0}" -f $($ElapsedTime.Elapsed.ToString())) -back black -fore green

#display the count grouped by status code
write-host "`nSUMMARY:" -back black -fore cyan
$result | group statuscode | sort count | `
ft -auto `
    @{Label="Status"; Alignment="left"; Expression={"$($_.name)"}}, `
    @{Label="Description"; Alignment="left"; Expression={"{0}" -f $statuscodes.item([int]$_.name)}}, `
    count `
| out-host

#display if user wants to see success or fail. default is show all
switch ($ShowResults){
	SUCCESS{
	    write-host "extracting Successful ping results..." -back black -fore yellow
	    $result|? {$_.statuscode -eq 0} | Out-Host
	    write-host "done" -back black -fore yellow
	    write-host ("  Elapsed Time : {0}" -f $($ElapsedTime.Elapsed.ToString())) -back black -fore green
	    }
	FAIL{
	    write-host "extracting Unsuccessful ping results..." -back black -fore yellow
	    $result|? {$_.statuscode -ne 0} | Out-Host
	    write-host "done" -back black -fore yellow
	    write-host ("  Elapsed Time : {0}" -f $($ElapsedTime.Elapsed.ToString())) -back black -fore green
	    }
}

if($Outfile -eq $true){

	#add incremental Id
	$i = 1
	$result = $result | select Id, address, statusdescr | sort statuscode, address 
	foreach ($r in $result){ $r.Id =  $i; $i++ }
	
	$savefilename = "$($defaultPath)\$($BackgroundJob)_FinalResults_{0:MM_dd_yyyy-hhmmss}.csv" -f $(Get-Date)
	Write-Host "File has been to :$savefilename" -back black -fore yellow
	$result | select Id, address, statusdescr | sort statuscode, address | export-csv  -notypeinfo -path $savefilename	
}
else
	{$result}

#End 
Write-host  " $($BackgroundJob) completed all requested operations at $(get-date) ".padright(60) -back darkgreen -fore white
Write-host ("   Elapsed Time : {0}" -f $($ElapsedTime.Elapsed.ToString())) -back black -fore green
