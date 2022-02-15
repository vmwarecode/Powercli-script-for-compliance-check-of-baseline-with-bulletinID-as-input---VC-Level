#This a sample script that demonstrate the use of APIs (powercli cmd-lets) to know the particular bulletin is installed on the host or not. 
#The users should first evaluate the script and must validate in their test environment to confirm the behavior. 
#VMware is not responsible for any outage, damage or issues arising out of it.
#Install-Module -Name VMware.VumAutomation -Scope CurrentUser
#
#C:\Users\x\Desktop\vum_test_per_vc.ps1 -VC_IP x.x.x.x -User <user> -Password <pass> -BaselineName security-baseline -BulletinID ESXi650-201912104-SG

 param(
[parameter(Mandatory = $true)]
$VC_IP,
[parameter(Mandatory = $true)]
$User,
[parameter(Mandatory = $true)]
$Password,
[parameter(Mandatory = $true)]
$BaselineName,
[parameter(Mandatory = $true)]
$BulletinID)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
#Connect to VI Server
$error = 0



function Fn-Cleanup{
write-output "`n Done with script execution, Disconnecting from VC: $VC_IP"
Disconnect-VIServer -Server $VC_IP -Confirm:$false
exit 1
}

try{
	Connect-VIServer -Server $VC_IP -User $User -Password $Password -ErrorAction Stop
	}
catch [Exception]{

	Write-output "`nUnable to connect to vc $VC_IP, $_"
	exit 1
	#$error = 1
	}
$baselinecreated = 0
#Get the patch baseline with the name give in the commandline. 
#If the baseline is created already, we dont create it, if not we create it.

Try{
	$staticBaseline  = Get-PatchBaseline -Name $BaselineName -ErrorAction Stop
	}
Catch [Exception]{
	Write-output "`nNo Baseline with name $BaselineName, $_.Exception. Creating one"
	}
if($staticBaseline){
	Write-output "`nThe baseline $BaselineName exists. No need to create. Will proceed with attaching the baseline"}
else{
	Write-output "`nNo baseline with name $BaselineName exists. Creating one"
	Write-output "`n$BulletinID"
		Try{
			$staticBaseline = New-PatchBaseline -Static -Name $BaselineName -IncludePatch (Get-Patch -SearchPhrase $BulletinID) -ErrorAction stop
			Write-Output "`nCreated baseline $BaselineName"
			$baselinecreated = 1
			}
			
		Catch [Exception]{
			Write-output "`nUnable to create baseline $BaselineName with Exception: $_. Will exit"
			#exit 1
			Fn-Cleanup
			#$error=1
			}
	}

#Get the inventory object where the baseline needs to be attached. Currently only DC is supported, FOr other inventory objects, please make changes accordingly

#Get the DCs in the VC and check in each of those DCs


	Try{

		$allDC = Get-Datacenter -ErrorAction Stop
		write-output "`nThe datacenter names retrieved in the VC : $VC_IP are $allDC . Proceeding with test compliance on each of these datacenters"

	}
	Catch [Exception]{
		Write-Output "`nCommand to retrieve datacenters on the VC : $VC_IP failed with exception: $_. Will Exit"
		#exit 1
		Fn-Cleanup
		#$error = 1
	}



$total_noncomp_hosts_list = @()
$total_noncomp_hosts_number = 0

if ($allDC){
     
	foreach ($datacenter in $allDC){
	
        Write-Output "`nPicking up the dc $datacenter from VC : $VC_IP for the test"
		Write-Output "`nChecking if the dc $datacenter from VC : $VC_IP has any hosts in it"
		
		Try{
			$hosts = Get-VMHost -Location $datacenter -ErrorAction Stop
			if (!$hosts){
			write-output "`nThe datacenter $datacenter in  VC : $VC_IP does not seem to have any hosts. Will continue with next datacenter..."
			continue
				}
			}
		Catch [Exception]{
			Write-Output "`nGetVmhost on datacenter $datacenter in  VC : $VC_IP failed. Continueng with other datacenters"
			continue
			}		
		
		Try{
			$dc = Get-Datacenter -Name $datacenter -ErrorAction Stop
			write-output "`nThe datacenter is $datacenter in the VC : $VC_IP. It has hosts. Proceeding with test compliance"
			}
		Catch [Exception]{
			Write-Output "`nNo Datacenter with the name $datacenter The exception is: $_. Will Exit"
			#exit 1
			Fn-Cleanup
			}

		#Attach the baseline to the inventory object

		Try{
			Add-EntityBaseline -Entity $dc -Baseline $staticBaseline -ErrorAction Stop
			Write-output "`nThe baseline $BaselineName is attached. Proceeding with test compliance"
			}
		Catch [Exception]{
			Write-Output "`nCannot attach the baseline $BaselineName to the inventory object $dc. Failed with Exception :  $_ Will exit"
			#exit 1
			Fn-Cleanup
			}

		#Test the complance with the baseline

		Try{
			Test-Compliance -Entity $dc -updatetype hostpatch -ErrorAction Stop
			write-output "`nThe test compliance worked. Will go ahead and get the status"
			}
		Catch [Exception]{
			Write-output "`nThe test-complaince faied with the exception : $_. Exiting"
			#exit 1
			Fn-Cleanup
			}

		$comps = Get-VMHost -Location $dc
		$n= 0
		$i = 0
		$noncomp_hosts = @()
		foreach ($comp in $comps){

			try{

				$status1 = Get-Compliance -Entity $comp -Baseline $staticBaseline| Select-Object @{N="Baseline";E={$_.Baseline.Name}},Entity,@{N="Status";E={$_.Status}} -ErrorAction Stop
				if ($status1.Status -eq "NotCompliant"){
					$n=$n+1
					$noncomp_hosts = $noncomp_hosts + $comp 
					$noncomp_hosts = $noncomp_hosts + ","
					$total_noncomp_hosts_list = $total_noncomp_hosts_list + $comp
					$total_noncomp_hosts_list = $total_noncomp_hosts_list + ","
					$total_noncomp_hosts_number = $total_noncomp_hosts_number + 1
					}
				
				write-output $status1 | Format-Table
				$i = $i +1
				}

			catch [Exception]{
				write-output "`nThe get-compliance check for the host $comp failed with $_."
				}
			}
			
		write-output "`nThere are a total of $i hosts out of which $n hosts are NotCompliant($noncomp_hosts)"
		write-output "`n"

		write-output "`nThe test is complete. Proceeding with detaching the baseline $BaselineName from the datacenter $dc"
		try{
     
			Remove-EntityBaseline -Entity $dc -Baseline $staticBaseline
    		write-output "`nSuccessfuly detached the baseline $BaselineName from the datacenter $dc"
			}

		catch [Exception]{
			write-output "`n Detaching the baseline $BaselineName from the datacenter $dc failed with the exception $_. Exiting"
			#exit 1
			Fn-Cleanup
			}	
}
}

if ($baselinecreated){
	write-output "`nThe baseline, $BaselineName was created by the script, thus  Proceeding to delete and clean it up"
	try{
		Remove-Baseline -Baseline $staticBaseline -Confirm:$false
    	write-output "`nSuccessfuly deleted the baseline $BaselineName"
		}

	catch [Exception]{
		write-output "`n Deleting the baseline $BaselineName failed with the exception $_. Exiting"
		#exit 1
		Fn-Cleanup
		}
}else{
	write-output "`n The baseline $BaselineName was not created by this script, hence not deleting it"
}

if ($total_noncomp_hosts_number){

write-output "`n All in all , in the vc : $VC_IP, there are a total of $total_noncomp_hosts_number non-compliant hosts. And they are ($total_noncomp_hosts_list)"
}else{
write-output "`n All in all , in the vc : $VC_IP, there are no non-compliant hosts. Status is GREEN."
}

Fn-Cleanup
