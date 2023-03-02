param ($fichiertxt, $Utilisateurs, $FichierGroupes)

$nomdns = ((Get-Content $fichiertxt)[10] -split ':')[1].Trim()

$NomMachine = (((Get-Content $fichiertxt)[0]) -split ':')[1].Trim()             #on récupère les données du fichier txt, nom dns, nom vm, groupe de ressource 

$NomGroupeRessource = (((Get-Content $fichiertxt)[3]) -split ':')[1].Trim()

$donnescsv = Import-CSV -Path $Utilisateurs -Delimiter ";" -Encoding UTF8       #on récupère les données du CSV avec les utilisateurs 

$Groupesacreer = Get-Content $FichierGroupes   #on récupère les données du fichier groupes avec les groupes à créer 


Invoke-AzVMRunCommand -ResourceGroupName $NomGroupeRessource -VMName $NomMachine -CommandId 'RunPowerShellScript' -ScriptString { 
    param ($dns, $nouveaugroupes)
                                                #on lance un script powershell dans la VM avec des paramêtres qui sont des variables
    $DomainNameDNS = $dns
    $DomainNameNetbios = $DomainNameDNS.Split(".")[0]           #on récupère et convertis les données le nom netbiios sans le .local, le suffixe juste le local 
    $point = $dns.IndexOf(".")
    $suffixe = $dns.Substring($point + 1)
    
    $testOU = Get-ADOrganizationalUnit -Identity "OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe" -erroraction 'silentlycontinue'
    if ($testOU -eq $null){  
        New-ADOrganizationalUnit -Name $DomainNameNetbios -Path "DC=$DomainNameNetbios,DC=$suffixe"}                                                             #on test si l'ou créé existe deja 
    else {
        Write-Output "L'ou $DomainNameNetbios existe deja elle ne sera pas ecrasee"}

    $testOrdinateurs = Get-ADOrganizationalUnit -Identity "OU=Ordinateurs,OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe" -erroraction 'silentlycontinue'
    if ($testOrdinateurs -eq $null){
        New-ADOrganizationalUnit -Name "Ordinateurs" -Path "OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe"}     
    else {
        Write-Output "L'ou Ordinateurs existe deja elle ne sera pas ecrasee"}

    $testUtilisateurs = Get-ADOrganizationalUnit -Identity "OU=Utilisateurs,OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe" -erroraction 'silentlycontinue'
    if ($testUtilisateurs -eq $null){
        New-ADOrganizationalUnit -Name "Utilisateurs" -Path "OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe"}
        
    else {
        Write-Output "L'ou Utilisateurs existe deja elle ne sera pas ecrasee"}

    $testGroupes = Get-ADOrganizationalUnit -Identity "OU=Groupes,OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe" -erroraction 'silentlycontinue'
    if ($testGroupes -eq $null){
        New-ADOrganizationalUnit -Name "Groupes" -Path "OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe"}

    else {
        Write-Output "L'ou Groupes existe deja elle ne sera pas ecrasee"}
    
    $splitString = $nouveaugroupes -split ","           #on récupère les données du fichier txt avec les groupes a créer, en coupant chaucn des éléments avec le "," et si le groupe existe on ne fait rien si il existe on le cree 
    
    foreach ($groupenom in $splitString) 
        {
            $testGroupe = Get-ADGroup -Identity $groupenom -erroraction 'silentlycontinue'
            if ($testGroupe -eq $null){
                New-ADGroup -Name $groupenom -SamAccountName $groupenom -GroupCategory Security -GroupScope Global -DisplayName $groupenom -Path "OU=Groupes,OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe"}
            else {
                Write-Output "Un groupe avec le nom $groupenom existe deja il ne sera pas ecrasee"}
            Clear-Variable -Name "testGroupe"    #a chaque tour du for each on remet "testgroupe" a 0 pour que cela n'interfere pas avec les autres tour du foreach
        } #on créé des groupes à partir du fichier txt

}-Parameter @{dns = "$nomdns"; nouveaugroupes = "$Groupesacreer"}
    
    
    
Foreach($Utilisateur in $donnescsv)
    {
        
        $UtilisateurPrenom = $Utilisateur.Prenom #recuperation valeur prenom dans CSV 
        $UtilisateurNom = $Utilisateur.Nom  #recuperation valeur nom dans CSV 
        $Groupes = $Utilisateur.Groupe #on definit le ou les de l'utilisateur a partir du csv

        Invoke-AzVMRunCommand -ResourceGroupName $NomGroupeRessource -VMName $NomMachine -CommandId 'RunPowerShellScript' -ScriptString { #on envoie le script suivant avec les valeurs du CSV
        
        param ($Prenom, $Nom, $StringGroupes, $dns)

        $UtilisateurNom = $Nom
        $UtilisateurPrenom = $Prenom
        $Groupes = $StringGroupes
        $UtilisateurLogin = ($UtilisateurNom).ToLower()+"."+($UtilisateurPrenom).ToLower()          #on cree le login                    
        $UtilisateurMotDePasse = "Test42Test42/*"       #on ajoute un mot de passe qui sera changé à la première connexion
        $DomainNameDNS = $dns
        $DomainNameNetbios = $DomainNameDNS.Split(".")[0]           #on récupère et convertis les données le nom netbiios sans le .local, le suffixe juste le local 
        $point = $dns.IndexOf(".")
        $suffixe = $dns.Substring($point + 1)
    
        if (Get-ADUser -Filter {SamAccountName -eq $UtilisateurLogin}) 
            {
            $UNC = Get-ADUser -Identity $UtilisateurLogin                             #on cherche pour l'utilisateur si il existe dejà les groupes aux quel il appartient
            $groupe = Get-ADPrincipalGroupMembership -Identity $UtilisateurLogin
            Foreach ($group in $groupe ) 
                { 
                    if ($($group.name) -ne "Domain Users" ) #on supprime ensuite tout les groupes au quel appartient l'utilisateur a part le groupe utilisateurs du domaine qui ne peut être supprimé
                        {
                            Remove-ADGroupMember $group -Members $UNC -confirm:$false
                        }
                } 

            $splitString = $Groupes -split ","
                                                    #On ajoute à l'utilisateur ses nouveaux utilisateurs 
            foreach ($item in $splitString) 
                {
                    Add-ADGroupMember -Identity $item -Members $UtilisateurLogin
                }
    
          
            }
        else #si l'utilisateur n'existe pas on le créé, l'ajoute dans l'OU et on lui donne les bon groupes + l'option de changer de mot de passe au prochain démarrage     
            {
           
                New-ADUser -Name "$UtilisateurNom $UtilisateurPrenom" `
                            -DisplayName "$UtilisateurNom $UtilisateurPrenom" `
                            -GivenName $UtilisateurPrenom `
                            -Surname $UtilisateurNom `
                            -SamAccountName $UtilisateurLogin `
                            -UserPrincipalName "$UtilisateurLogin@$DomainNameDNS"`
                            -Path "OU=Utilisateurs,OU=$DomainNameNetbios,DC=$DomainNameNetbios,DC=$suffixe" `
                            -AccountPassword(ConvertTo-SecureString $UtilisateurMotDePasse -AsPlainText -Force) `
                            -Enabled $true `
                            -ChangePasswordAtLogon $true
    
                        $splitString = $Groupes -split ","
    
                        foreach ($item in $splitString) 
                            {
                                $UNC = Get-ADUser -Identity $UtilisateurLogin
                                Add-ADGroupMember -Identity $item -Members $UNC
                            }
                 
            }
    }-Parameter @{Prenom = "$UtilisateurPrenom"; Nom = "$UtilisateurNom"; StringGroupes = "$Groupes"; dns = "$nomdns"}
    
    
    }