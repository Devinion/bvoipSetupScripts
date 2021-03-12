$pbxSbcFqdn = "devinion-sbc.bvoip.net"
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
Import-PSSession -Session $session -allowclobber
Write-Host "Session started!"

$registeringUsers = $true
while($registeringUsers -eq $true){
	$registerUser = Read-Host -Prompt 'Enter the email address for the user you want to activate. Make sure the user have the "Microsoft 365 Phone System" license'
	$userPhoneNumber = Read-Host -Prompt 'Enter the phone number for the user. Example: +<YOUR_COUNTRY_PREFIX><YOUR_EXT_NUMBER>, +1300'
	Get-CsOnlineUser -Identity $registerUser | fl RegistrarPool
	Grant-CsOnlineVoiceRoutingPolicy -Identity $registerUser -PolicyName "PBX $($pbxSbcFqdn)"
	Set-CsUser -Identity $registerUser -EnterpriseVoiceEnabled $true -HostedVoiceMail $true -OnPremLineURI tel:$userPhoneNumber
	$registerAnother = Read-Host -Prompt 'Do you want to register another user? (yes/no)'
	$registerAnother = $registerAnother.ToLower()
	if ($registerAnother -ne "yes" -And $registerAnother -ne "y") { 
		$registeringUsers = $false
	}
}
