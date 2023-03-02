param ($fichier)

Connect-AzAccount

$fichier = "text.txt"

$NomMachine = (((Get-Content $fichier)[0]) -split ':')[1].Trim()

$TypeVm = (((Get-Content $fichier)[1]) -split ':')[1].Trim()

$NomZone = (((Get-Content $fichier)[2]) -split ':')[1].Trim()

$NomGroupeRessource = (((Get-Content $fichier)[3]) -split ':')[1].Trim()

$NomVswitch = (((Get-Content $fichier)[4]) -split ':')[1].Trim()
                                                                                #on récupère les différentes variables du fichier txt
$IpSwitch = (((Get-Content $fichier)[5]) -split ':')[1].Trim()

$NomSubnet = (((Get-Content $fichier)[6]) -split ':')[1].Trim()

$IpSubnet = (((Get-Content $fichier)[7]) -split ':')[1].Trim()

$disques = ((Get-Content $fichier)[8] -split ':')[1].Trim()

$NomCompteStockage = ((Get-Content $fichier)[9] -split ':')[1].Trim()

$nomdns = ((Get-Content $fichier)[10] -split ':')[1].Trim()

grouperessource -GroupeRessourceNom $NomGroupeRessource -zone $NomZone.   #on appelle la fonction groupe de ressource

$reset = NomVM -GroupeRessourceNom $NomGroupeRessource -zone $NomZone -MachineNom $NomMachine #on teste le nom de la VM 

if ($reset -eq 1) 
    {
        Write-Output "Impossible d'utiliser ce nom de VM car il est déjà utilisé"
        exit
    }       
$reset = compte-stockage -GroupeRessourceNom $NomGroupeRessource -CompteStockageNom $NomCompteStockage -zone $NomZone #création ou récupération compte de stockage
if ($reset -eq 1) 
    {
        Write-Output "Impossible d'utiliser ce groupe de stockage car il est déjà utilisé"        #on appelle le groupe de stockage, on le créé car on a besoin d'un compte de stockage pour stcoker les logs ( recommandation azure)
        exit
    }       
    
$disquestab = @()
$ListeDisques = $disques -split "," | ForEach-Object {                                                  #on réupère ici les disques, on créé un tableau dans lequel on rentre les valeur Nom, Taille et Type dans chaque colonne
    $NomDisque, $TailleDisque, $TypeDeStockage = $_ -split "/"                                          #Grâce à un split
    $ajoutvaleur = [pscustomobject]@{NomDisque=$NomDisque; TailleDisque=$TailleDisque; TypeStockage=$TypeDeStockage}
    $disquestab += $ajoutvaleur
}


$identifiantsVm = Get-Credential -Message "Entrez le nom d'utilisateur de la vm et son mot de passe" #on recupere les identifiants de connexion de la vm 

$ConfigVM = New-AzVMConfig -VMName $NomMachine -VMSize $TypeVm #on créé notre Vm en renseignant le type B1, B1s etc ..

$ConfigVM = Set-AzVMOperatingSystem -VM $ConfigVM -Windows -ComputerName $NomMachine -Credential $identifiantsVm -ProvisionVMAgent –EnableAutoUpdate #on renseigne l'OS les identifiants et le nom de la machine

$ConfigVM = Set-AzVMSourceImage -VM $ConfigVM -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest" #on renseigne la version de windows

$interfacereseau = reseau -GroupeRessourceNom $NomGroupeRessource -VswitchNom $NomVswitch -SubnetNom $NomSubnet -SubnetIp $IpSubnet -MachineNom $NomMachine -SwitchIp $IpSwitch -zone $NomZone

$interfacereseau = Get-AzNetworkInterface -ResourceGroupName $NomGroupeRessource -Name "InterfaceReseau-$NomMachine"

$ConfigVM = Add-AzVMNetworkInterface -VM $ConfigVM -Id $interfacereseau.Id #on renseigne les paramêtre reseau

$i = 0
$lun = 0                

Foreach ($ligne in $disquestab) 
 {
    if ($i -eq 0) 
        {                                                   #on récupère les données du tableau des disques, le premier est le disque de l'OS, on rensigne sa tille son nom sa redondance
            $disquenom = $ligne.NomDisque
            $disquenom = "$NomMachine-$disquenom"
            $ConfigVM = Set-AzVMOSDisk -VM $ConfigVM -Name $disquenom -DiskSizeInGB $ligne.TailleDisque -StorageAccountType $ligne.TypeStockage -Caching ReadWrite -CreateOption FromImage
            $ConfigVM = Set-AzVMBootDiagnostic -VM $ConfigVM -Enable -ResourceGroupName $NomGroupeRessource -StorageAccountName $NomCompteStockage
            New-AzVM -ResourceGroupName $NomGroupeRessource -Location $NomZone -VM $ConfigVM
        } 
    else 
        {
            $disquenom = $ligne.NomDisque
            $disquenom = "$NomMachine-$disquenom"
            $ConfigDisque = New-AzDiskConfig -SkuName $ligne.TypeStockage -Location $NomZone -CreateOption Empty -DiskSizeGB $ligne.TailleDisque           #on ajoute ensuite les autres disques 
            $DisqueCree = New-AzDisk -DiskName $disquenom -Disk $ConfigDisque -ResourceGroupName $NomGroupeRessource
            $MachineVirtuelle = Get-AzVM -ResourceGroupName $NomGroupeRessource -Name $NomMachine
            Add-AzVMDataDisk -Vm $MachineVirtuelle -Name $disquenom -CreateOption Attach -ManagedDiskId $DisqueCree.Id -Lun $lun
            Update-AzVM -ResourceGroupName $NomGroupeRessource -VM $MachineVirtuelle
        }
    $i++
    $lun++

 } 

$motdepassedomaine = Read-Host -Prompt 'Entrez le mot de passe du domaine' -MaskInput  #on demande le mot de passe du domaine

$AdresseIpPrivee = (Get-AzNetworkInterface -Name "InterfaceReseau-$NomMachine" -ResourceGroupName $NomGroupeRessource).IpConfigurations.PrivateIpAddress #on récupère l'adresse ip de la machine

Invoke-AzVMRunCommand -ResourceGroupName $NomGroupeRessource -VMName $NomMachine -CommandId 'RunPowerShellScript' -ScriptString {  #on lance une commande powershell dans notre VM avec des paramêtres

    param ($mdpdomaine, $dns, $AdresseIP)

    $pass = $mdpdomaine
    $Password = $pass | ConvertTo-SecureString -AsPlainText -Force
    $DomainNameDNS = $dns                               #on définit les variables
    $ipAddr = $AdresseIP
    $DomainNameNetbios = $DomainNameDNS.Split(".")[0] 
    
    $ForestConfiguration = @{
    '-DatabasePath'= 'C:\Windows\NTDS';
    '-SafeModeAdministratorPassword'= $Password;
    '-DomainMode' = 'Default';
    '-DomainName' = $DomainNameDNS;
    '-DomainNetbiosName' = $DomainNameNetbios;          #on donne les informations de configuration du domaine et de son controleur 
    '-ForestMode' = 'Default';
    '-InstallDns' = $true;
    '-LogPath' = 'C:\Windows\NTDS';
    '-NoRebootOnCompletion' = $false;
    '-SysvolPath' = 'C:\Windows\SYSVOL';
    '-Force' = $true;
    '-CreateDnsDelegation' = $false }
    
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools     #on installe le rôle Active Directory
    
    Import-Module ADDSDeployment    #on importe le module de déploiement active directory
    
    Install-ADDSForest @ForestConfiguration     #on configure notre forêt
    
    Add-DnsServerPrimaryZone -Name $DomainNameDNS -ZoneFile "$DomainNameDNS.dns" #on install notre première zone DNS
    
    Add-DnsServerResourceRecordA -ZoneName $DomainNameDNS -Name "ns1" -IPv4Address $ipAddr
    Add-DnsServerResourceRecordA -ZoneName $DomainNameDNS -Name "@" -IPv4Address $ipAddr             #on ajoute des enregistrement DNS
    
    Add-DnsServerForwarder -IPAddress 8.8.8.8 -PassThru #on ajoute des redirecteurs pour utiliser notre serveur comme serveur DNS 
    
    Restart-Service DNS #on redemarre le service pour appliquer les changements

} -Parameter @{mdpdomaine = "$motdepassedomaine"; dns = "$nomdns"; AdresseIP = $AdresseIpPrivee}

Get-AzRemoteDesktopFile -ResourceGroupName $NomGroupeRessource -Name $nomMachine -LocalPath $NomMachine".rdp" #on créé un fichier RDP pour ce connecter à notre machine

Write-Output "Veuillez attendre 5 minutes que le serveur redémarre et finisse d'installer le controleur de domaine"

$ippublique = (Get-AzPublicIpAddress -Name "IpPublique-$NomMachine" -ResourceGroupName $NomGroupeRessource).IpAddress #on récupère l'adresse Ip publique de la VM

Write-Output "Voici l'adresse ip publique de votre machine virtuel $ippublique" #on donne l'adresse ip publique 

function grouperessource {

    param ($GroupeRessourceNom, $zone)
    
    if ((Get-AzResourceGroup).ResourceGroupName -contains $GroupeRessourceNom)
        {
            Write-Output "Un groupe de ressource du même nom existe déjà il sera donc utilisé"
            $groupederesource = Get-AzResourceGroup -Name $GroupeRessourceNom                                   #Ici on regarde si un groupe de ressouurce existe ou non
        }                                                                                                       #Si oui on utilise ce dernier sinon on en crée un et on ajoute +1 à $valeur
    else
        {
            $groupederesource = New-AzResourceGroup -Name $GroupeRessourceNom -Location $zone
        }

}

function NomVM {

    param ($GroupeRessourceNom, $MachineNom, $zone)

    $TestSiVmExiste = Get-AzVm -ResourceGroupName $GroupeRessourceNom -Name $MachineNom -erroraction 'silentlycontinue'
    
    if($TestSiVmExiste)
        {
            return 1
        }                                                                                                           #Ici on teste si une VM du même nom existe ou non
    else                                                                                                            #Si oui on supprime le groupe de ressource créé et on arrête 
        {                                                                                                           #Si non on continue le code 
            $MachineNom = $MachineNom
        }
    
}


function compte-stockage {

    param ($GroupeRessourceNom, $CompteStockageNom, $zone)

    $checkcomptestockage = Get-AzStorageAccount -ResourceGroupName $GroupeRessourceNom -StorageAccountName $CompteStockageNom -erroraction 'silentlycontinue'
    if($checkcomptestockage)                                                               #On teste si un groupe de stockage du même nom existe dans notre groupe de ressource
        {    
            $CompteStockageNom = $CompteStockageNom
            Write-Output "Un Compte de Stockage du même nom est déjà utilisé il sera donc utilisé"                                                                                                       #Si oui on l'utilise et on continue Si non On passe un d'autres test
        }
    
    else
        {
            if((Get-AzStorageAccountNameAvailability $NomCompteStockage).NameAvailable -eq "true")                  #On teste deja si le nom de compte de stockage est disponible ou non car il doit avoir un nom unique à azure si il est dispo on le créé sinon on retourne 1 ce qui a pour accès d'arrêter le code
                {
                    New-AzStorageAccount -ResourceGroupName $NomGroupeRessource -Name $NomCompteStockage -SkuName "Standard_LRS" -Kind "Storage" -Location $zone
                }
            else
                {
                    return 1
                }
        }    
}

function reseau {

    param ($GroupeRessourceNom, $VswitchNom, $SubnetNom, $SubnetIp, $MachineNom, $SwitchIp, $zone)

    if ((Get-AzVirtualNetwork -ResourceGroupName $GroupeRessourceNom).name -contains $VswitchNom)
        {
            Write-Output "Un Vswitch du même nom est déjà utilisé il sera donc utilisé"
            $reseauvirtuel = Get-AzVirtualNetwork -Name $VswitchNom -ResourceGroupName $GroupeRessourceNom                  #on teste si un Vswitch du même nom existe ou non
                                                                                                                                #Si oui on l'utilise et on teste si un subnet du même nom que donné existe ou non si oui on l'utilise sinon on le créé
            if((Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $reseauvirtuel).name -contains $SubnetNom)                 #Si non on créé un nouveau Vswitch avec un nouveau subnet
            {
                Write-Output "Un Subnet du même nom existe déjà sur ce Vswitch il sera donc utilisé"
                $subnetconfig = Get-AzVirtualNetworkSubnetConfig -Name $SubnetNom -VirtualNetwork $reseauvirtuel
            }
            else 
            {
                $subnetconfig = New-AzVirtualNetworkSubnetConfig -name $SubnetNom -AddressPrefix $SubnetIp
            }
                
        }
        
    else
        {
            $subnetconfig = New-AzVirtualNetworkSubnetConfig -name $SubnetNom -AddressPrefix $SubnetIp
            $reseauvirtuel = New-AzVirtualNetwork -ResourceGroupName $GroupeRessourceNom -Location $zone -Name $VswitchNom -AddressPrefix $SwitchIp -Subnet $subnetConfig
        }
        
        
    $adresseippublique = New-AzPublicIpAddress -Name "IpPublique-$MachineNom" -ResourceGroupName $GroupeRessourceNom -Location $Zone -AllocationMethod Static

    $interfacereseau = New-AzNetworkInterface -Name "InterfaceReseau-$MachineNom" -ResourceGroupName $GroupeRessourceNom -Location $Zone -SubnetId $reseauvirtuel.Subnets[0].Id -PublicIpAddressId $adresseippublique.Id #on cree une interface reseau avec le vswitch et l'adresse IP publique

    $GroupSecu = New-AzNetworkSecurityGroup -Name "GroupeSecu-$MachineNom" -ResourceGroupName $GroupeRessourceNom -Location $Zone
            
    $interfacereseau.NetworkSecurityGroup = $GroupSecu
            
    $interfacereseau | Set-AzNetworkInterface 
            
    Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $GroupSecu -name "RDP-IN" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 
            
    Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $GroupSecu -name "DNS-TCP-IN" -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 53   #création groupe de sécurité + de règles dans ce dernier pour autoriser RDP + DNS 
            
    Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $GroupSecu -name "DNS-UDP-IN" -Access Allow -Protocol Udp -Direction Inbound -Priority 120 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 53
            
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $GroupSecu
}

