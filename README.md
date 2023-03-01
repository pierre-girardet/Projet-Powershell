# Projet-Powershell
Projet Powershell ESGI

Le but dans ce projet est de mettre en place une machine virtuelle Azure à partir d'un fichier Txt.

Le fichier txt a différentes options, le groupe de ressource, le nom de la machine, l'ip du switch etc ...

Par la suite une fois la Vm de configurée on va installer et configurer un contrôleur de domaine avec une forêt active directory. 

Et enfin on va configurer ce domaine en ajoutant, des groupes, utilisateurs dans le domaine à partir d'un fichier txt et CSV.

Tout d'abord pour éxecuter ces scripts il faut installer le module Azure pour powershell et non utiliser le Cloud Shell ! :

"Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force"

Il faut aussi avoir un abonnement azure valide et qui fonctionne

On execute le premier fichier avec :

./projet1.ps1 -fichier "nom-du-fichier-txt 

exemple : ./projet1.ps1 -fichier text.txt

Ce fichier va configurer la vm et installer et configurer l'active directory. 

Ensuite pour ajouter des éléments à notre AD on fait la commande suivante :

./AD.ps1 -fichiertxt text.txt -utilisateurs Classeur1.csv -fichiergroupes groupes.txt

Ici le fichier txt est le même que pour le premier code, le CSV est pour les utilisateurs à créer avec ses groupes respectif et enfin le fichier txt (groupes.txt) est pour les groupes.

Un exemple des fichier configuration est disponible dans ce git. 
