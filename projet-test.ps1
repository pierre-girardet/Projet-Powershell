Connect-AzAccount

$zone = "francecentral"
$nomgrpressource = "ESGI"
$nomreseauvirtel = "VSWITCH"
$typedemachine = "Standard_B1s"
$prefixip = "192.168.0.0/16"
$subnet = "192.168.1.0/24"
$nomcomptedestockage = "projetpowershellesgi"
$typedestockage = "Standard_LRS"
$nommachine = "Machine1"
$cheminstockage = "vhds/myVMDisk1.vhd"

$groupederesource = New-AzResourceGroup -Name $nomgrpressource -Location $zone

$subnetConfig = New-AzVirtualNetworkSubnetConfig -name "Subnet" -AddressPrefix $subnet

$reseauvirtuel = New-AzVirtualNetwork -ResourceGroupName $nomgrpressource -Location $zone -Name $nomreseauvirtel -AddressPrefix $prefixip -Subnet $subnetConfig 

$adresseippublique = New-AzPublicIpAddress -Name "IpPublique" -ResourceGroupName $nomgrpressource -Location $zone -AllocationMethod Static

Get-AzStorageAccountNameAvailability $nomcomptedestockage

$interfacereseau = New-AzNetworkInterface -Name "InterfaceReseau" -ResourceGroupName $nomgrpressource -Location $zone -SubnetId $reseauvirtuel.Subnets[0].Id -PublicIpAddressId $adresseippublique.Id

$identifiants = Get-Credential -Message "Entre le nom d'utilisateur de la vm et son mot de passe"

$myVM = New-AzVMConfig -VMName $nommachine -VMSize $typedemachine

$myVM = Set-AzVMOperatingSystem -VM $myVM -Windows -ComputerName $nommachine -Credential $identifiants -ProvisionVMAgent –EnableAutoUpdate

$myVM = Set-AzVMOperatingSystem -VM $myVM -Windows -ComputerName $nommachine -Credential $identifiants -ProvisionVMAgent –EnableAutoUpdate

$myVM = Set-AzVMSourceImage -VM $myVM -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest"

$myVM = Add-AzVMNetworkInterface -VM $myVM -Id $interfacereseau.Id

$myVM = Set-AzVMOSDisk -VM $myVM -Name "disque1" -StorageAccountType $typedestockage -Caching ReadWrite -CreateOption FromImage
           
New-AzVM -ResourceGroupName $nomgrpressource -Location $zone -VM $myVM





