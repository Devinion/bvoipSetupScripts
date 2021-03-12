$pbxSbcFqdn = "devinion-sbc.bvoip.net"
$pbxSbcPort = 7005

Try { 
	$session = New-CsOnlineSession -ErrorAction Stop
} catch { 
	if ($_.Exception.Message -like "*Basic authentication is currently disabled*") {
		write-host "WinRM Basic is disabled on the system."
		$winrmValues = winrm get winrm/config/client/auth
		foreach ($winrmValue in $winrmValues) {
			$results = [Regex]::Matches($winrmValue, ".*Basic = (?<val>.*)")
			if ($results.count -gt 0) {
				$textValue = $results[0].Groups["val"].value
				
				$furtherResults = [Regex]::Matches($textValue, "(?<bool>^\w+) ?(?<source>\[.*\])?")
				if ($furtherResults.count -gt 0) {
					if ($furtherResults[0].Groups["bool"].value -eq "false") {
						$reason = $furtherResults[0].Groups["source"].value
						
						if ([string]::isNullOrEmpty($reason)) {
							$reasonFix = "Run: winrm set winrm/config/client/auth '@{Basic=""true""}' as administrator and then re-run this script"
						} elseif ($reason -match "GPO") {
							$RegProperty = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client\' -Name 'AllowBasic' -ErrorAction SilentlyContinue
							if ($null -ne $RegProperty) {
								$reasonFix = "Group Policy set the restriction. Please contact an administrator."
								if ($RegProperty.AllowBasic -EQ 0) {
									$response = $null
									while ($response -notin @('Y','N')) {
										$response = Read-Host -prompt "Do you want us to try and update the policy? (y/n)"
									}
									if ($response -eq 'Y') {
										try {
											Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client\' -Name 'AllowBasic' -Value 1 -ErrorAction Stop
											$reasonFix = "We have temporarily updated your computer's policy to allow Basic Authentication for WinRM"
										} catch {
											$reasonFix = "Have an administrator run the following command on your system and re-run the script:`nSet-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client\' -Name 'AllowBasic' -Value 1"
										}
									} else {
										write-host "Error: $response"
									}
								}	
							}
						}				
						 
						write-host $reasonFix
					} elseif ($furtherResults[0].Groups["bool"].value -eq "true") {
						write-host "The host is set correctly for Basic authentication, please close your Powershell sessions and try again."
					}
				}
			}
		}	
	}
	exit 1
}
Import-PSSession -Session $session -AllowClobber
Write-Host "Session started!"

$CsOnlinePSTNGateway = Get-CsOnlinePSTNGateway | ?{$_.Identity -like "*$($pbxSbcFqdn)*"}
if ($CsOnlinePSTNGateway -like "*$($pbxSbcFqdn)*") { 
	Set-CsOnlinePSTNGateway -Identity $pbxSbcFqdn -Enabled $true -SipSignalingPort $pbxSbcPort -MaxConcurrentSessions 100
	Write-Host "CsOnlinePSTNGateway successfully updated!"
}else{
	New-CsOnlinePSTNGateway -Identity $pbxSbcFqdn -Enabled $true -SipSignalingPort $pbxSbcPort -MaxConcurrentSessions 100
	Write-Host "CsOnlinePSTNGateway successfully created!"
}

$CsOnlinePstnUsage = (Get-CsOnlinePstnUsage).Usage | Where-Object {$_ -like "*$($pbxSbcFqdn)*"}
if (!($CsOnlinePstnUsage -like "*$($pbxSbcFqdn)*")) { 
	Set-CsOnlinePstnUsage -Identity Global -Usage @{Add="Route-$($pbxSbcFqdn)"}
	Write-Host "CsOnlinePstnUsage route successfully created!"
}else{
	Write-Host "CsOnlinePstnUsage route already exists"
}

$CsOnlineVoiceRoutingPolicy = (Get-CsOnlineVoiceRoutingPolicy).OnlinePstnUsages | Where-Object {$_ -like "*$($pbxSbcFqdn)*"}
if ($CsOnlineVoiceRoutingPolicy -like "*$($pbxSbcFqdn)*") { 
	Set-CsOnlineVoiceRoutingPolicy "PBX $($pbxSbcFqdn)" -OnlinePstnUsages "Route-$($pbxSbcFqdn)"
	Write-Host "CsOnlineVoiceRoutingPolicy successfully updated!"
}else{
	New-CsOnlineVoiceRoutingPolicy "PBX $($pbxSbcFqdn)" -OnlinePstnUsages "Route-$($pbxSbcFqdn)"
	Write-Host "CsOnlineVoiceRoutingPolicy successfully created!"
}

$CsOnlineVoiceRoute = (Get-CsOnlineVoiceRoute).OnlinePstnGatewayList | Where-Object {$_ -like "*$($pbxSbcFqdn)*"}
if ($CsOnlineVoiceRoute -like "*$($pbxSbcFqdn)*") { 
	Set-CsOnlineVoiceRoute -id "Route $($pbxSbcFqdn)" -NumberPattern ".*" -OnlinePstnGatewayList $pbxSbcFqdn -OnlinePstnUsages "Route-$($pbxSbcFqdn)"
	Write-Host "CsOnlineVoiceRoute successfully updated!"
}else{
	New-CsOnlineVoiceRoute -id "Route $($pbxSbcFqdn)" -NumberPattern ".*" -OnlinePstnGatewayList $pbxSbcFqdn -OnlinePstnUsages "Route-$($pbxSbcFqdn)"
	Write-Host "CsOnlineVoiceRoute successfully created!"
}

Remove-PSSession -Session $session
