#!/bin/bash

if [ $# = 1 ]	# Si la sync liste est donnée en argument
then
	SYNC_LISTE=$1
else
	SYNC_LISTE="/media/DOCUMENTS/Mes documents/0.Sync/Sync liste"	# L'emplacement de la sync_liste peut-être donné "en dur" si elle n'est pas donnée en argument du script
fi

SYNC_DIR="/media/data/Dossier de synchronisation"	# Emplacement des synchronisations sur le serveur
SSH_HOST="USER@DOMAIN.TLD"
SSH_PORT=PORT

SSHSOCKET=~/.ssh/ssh-socket-%r-%h-%p
NB_BACKUP=3	# Nombre de backup à garder par défaut


RSYNC () {
if [ -d "$1" ]	# Si c'est un dossier qui doit être synchronisé
then	# Ajoute les / à la fin des chemins pour que rsync traite le fichier comme un dossier. Cela évite qu'il créer un dossier avant de synchroniser.
	SYNC_1="$1/"
	SYNC_2="$2/"
else
	SYNC_1="$1"
	SYNC_2="$2"
fi
if [ $FORCE_SYNC -eq 0 ]	# Appel birsync seulement si il n'y a pas de forçage de synchronisation unidirectionnel
then
    echo "Appel du script birsync." >> "$LOGFILE"
    "$WORK_DIR/birsync.sh" "$SYNC_1" "$SYNC_DIR/$2" "$TMPDIR" "$EXCLUDE_LISTE" "$LAST_SYNC_DATE" "$SSH_HOST" "$SSH_PORT" "$SSHSOCKET" "$LOGFILE" 2>&1 | tee -a "$LOGFILE"	# Appel du script birsync pour créer les 2 listes d'exclusion afin de traiter 2 appel de rsync, un dans chaque sens.
    # "$WORK_DIR/birsync.sh" "$1" "$SYNC_DIR/$2" "$TMPDIR" "$EXCLUDE_LISTE" "$LAST_SYNC_DATE" "$SSH_HOST" "$SSH_PORT" "$SSHSOCKET" 2>&1 | tee -a "$LOGFILE"	# Appel du script birsync pour créer les 2 listes d'exclusion afin de traiter 2 appel de rsync, un dans chaque sens.
    # Les 2 premiers arguments de birsync sont 'Dossier local à synchroniser' et 'Dossier distant à synchroniser'
else	# Si on ne passe pas par birsync, les listes d'exclusions U et D doivent être créés manuellement.
    cat "$EXCLUDE_LISTE" > "$EXCLUDE_LISTE.U"
    cat "$EXCLUDE_LISTE" > "$EXCLUDE_LISTE.D"
fi

echo "" | tee -a "$LOGFILE"
echo "**********************************************************************************" | tee -a "$LOGFILE"
echo "**********************************************************************************" | tee -a "$LOGFILE"
echo "Synchronisation de $1" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
if [ $FORCE_SYNC -ne 1 ]	# Synchro vers le serveur, seulement si on a pas un forçage distant
then
    if [ $FORCE_SYNC -eq 2 ]
    then
	echo "MISE À JOUR FORCÉE DEPUIS LES FICHIERS LOCAUX" | tee -a "$LOGFILE"
    fi
    echo "Mise à jour des fichiers sur le serveur" | tee -a "$LOGFILE"
    echo "1=$1" >> "$LOGFILE"
    echo "SYNC_1=$SYNC_1" >> "$LOGFILE"
    echo "SYNC_DIR=$SYNC_DIR" >> "$LOGFILE"
    echo "2=$2" >> "$LOGFILE"
    echo "SYNC_2=$SYNC_2" >> "$LOGFILE"
    rsync -avzhEi --modify-window=1 --progress --exclude-from="$EXCLUDE_LISTE.U" --delete "$SYNC_1" -e "ssh -p $SSH_PORT -o ControlPath=$SSHSOCKET" $SSH_HOST:"\"$SYNC_DIR/$2\"" 2>&1 | tee -a "$LOGFILE"
fi

if [ $FORCE_SYNC -ne 2 ]	# Synchro depuis le serveur, seulement si on a pas un forçage local
then
    echo "**********************************************************************************" | tee -a "$LOGFILE"
    if [ $FORCE_SYNC -eq 1 ]
    then
	echo "MISE À JOUR FORCÉE DEPUIS LES FICHIERS DISTANTS" | tee -a "$LOGFILE"
    fi
    echo "Mise à jour des fichiers sur le poste local" | tee -a "$LOGFILE"

    rsync -avzbhEis --modify-window=1 --progress --exclude-from="$EXCLUDE_LISTE.D" --delete --backup-dir="$BACKUPDIR/$(basename "$1")" -e "ssh -p $SSH_PORT -o ControlPath=$SSHSOCKET" $SSH_HOST:"$SYNC_DIR/$SYNC_2" "$1" 2>&1 | tee -a "$LOGFILE"
fi

echo "**********************************************************************************" | tee -a "$LOGFILE"
echo "**********************************************************************************" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
## Options rsync:
# -a archive (rlptgoD)
# -v verbose
# --delete, supprime les fichiers absent dans la source
# -b backup
# --backup-dir=DIR
# -z compression des données pour le transfert
# -h human readable
# --progress
# -e ssh login@serveur_ip_ou_nom: 	pour utiliser ssh
# -E preserve executability
# -u update, ne remplace pas un fichier si il est plus récent que la source - A PROSCRIRE, INTERFÈRE AVEC BIRSYNC
# --modify-window=NUM     compare les dates avec une précision moins fine
# -i détails sur les actions de rsync
#     s taille différente
#     t Date différente
#     p permission différente
#     o propriétaire différent
#     g groupe différent
# -s --protect-args, Permet de ne pas interpréter les espaces dans les chemins de fichiers. Gros problème avec rsync, qui parfois ne veut pas accepter les espaces, même échappé! Pour des raisons obscures, le problème ne se présente qu'en download. En upload, l'option -s créer des problèmes...
}

BACKUP_DIR () {
PARENT_DIR_BACKUP=$(dirname "$BACKUPDIR")	# Récupère le chemin du dossier sans le nom de ce dernier
NAME_DIR_BACKUP=$(basename "$BACKUPDIR")	# Récupère le dernier dossier du chemin
ls -1 "$PARENT_DIR_BACKUP" | grep $NAME_DIR_BACKUP > "$TEMP_FILE"
if [ $(wc -l "$TEMP_FILE" | cut -d " " -f 1) -ge $NB_BACKUP ]	# Compte le nombre de lignes du fichier (-ge >=)
then	# Si il y a au moins $NB_BACKUP dossiers
  DIRSUPPR=$(cat "$TEMP_FILE" | sed -n 1p)
  if [ -n "$PARENT_DIR_BACKUP" ] && [ -n "$DIRSUPPR" ]
  then
	rm -R "$PARENT_DIR_BACKUP/$DIRSUPPR"	# Supprime le dossier le plus ancien (seulement si aucune des variables n'est vide, afin d'éviter des incidents)
  fi
fi

incr=$(date '+%Y-%m-%d_%Hh%M,%Ss')	#La date est affichée à l'inverse pour respecter l'ordre de tri.
echo -n "$BACKUPDIR" > "$TEMP_FILE"
echo _$incr >> "$TEMP_FILE"
BACKUPDIR=$(cat "$TEMP_FILE")
mkdir "$BACKUPDIR"

LOGFILE="$BACKUPDIR/rsync.log"	# Nomme le fichier de log
echo -e "Synchronisation du `date +%c`\n" > "$LOGFILE"
}

PARSE_SYNC_LISTE () {
if [ $PARSE_PASS -eq 1 ]
then
	VALID_HOSTNAME=0
	VALID_WORKDIR=0
	VALID_BACKUP=0
	VALID_NB_BACKUP=0
	VALID_CLIENT=0
	VALID_DEFAUT_ALL=0
	VALID_HOSTNAME_SYNC=0
fi
VALID_FILE_SYNC=0
ERROR=0
echo "Construction de la liste de fichiers à synchroniser"
while read LIGNE
do
	if [ "$(echo $LIGNE | cut -c1)" != '#' ] || [ -z "$LIGNE" ]	# Si la ligne n'est pas un commentaire ou si ce n'est pas une ligne vide
	then
		if [ $PARSE_PASS -eq 1 ]
		then	# 1ère phase, détection des dossier de la machine cliente
			if [ $VALID_CLIENT -eq 0 ]	# Si la machine cliente n'est pas déjà trouvée et validée.
			then
				# Détecte la machine cliente
				if [ $(echo "$LIGNE" | grep -c '^>MACHINE:') -eq 1 ]	# Si la ligne commence par >MACHINE
				then
					if [ $VALID_HOSTNAME -ne 1 ]	# Si le hostname de la machine n'est pas trouvé, identifie une machine dans la liste
					then
						hostname_list=$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's/ *//g' )	# Prend le hostname de la machine indiqué dans la liste, en retirant tout les espaces superflus
						if [ $hostname_list = $(hostname) ] || [ $hostname_list = "ALL" ]	# Si le nom de la machine correspond à l'entrée dans la liste ou si c'est ALL.
						then
							VALID_HOSTNAME=1	# hostname de la machine locale trouvé dans la liste, ou ALL trouvé
						else
							VALID_HOSTNAME=-1	# hostname non valide pour la machine trouvé
						fi
					else	# Sinon, c'est peut-être une erreur.
						if [ $VALID_WORKDIR = 0 ]; then
							echo "Erreur de syntaxe dans la liste de synchronisation, le dossier de travail de la machine $hostname_list n'a pas été trouvé"
							ERROR=1
						fi
						if [ $VALID_BACKUP = 0 ]; then
							echo "Erreur de syntaxe dans la liste de synchronisation, le dossier de backup de la machine $hostname_list n'a pas été trouvé"
							ERROR=1
						fi
					fi
				fi
				# Détecte le dossier de travail
				if [ $(echo "$LIGNE" | grep -c '^>WORK_DIR:') -eq 1 ]	# Si la ligne commence par >WORK_DIR
				then
					if [ $VALID_WORKDIR -eq 0 ] && [ $VALID_HOSTNAME -eq 1 ]	# Si le dossier de travail n'est pas trouvé, lit le chemin du dossier de travail
					then
						WORK_DIR=$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@^ *@@;s@ *$@@' )	# Prend le chemin du dossier de travail en effaçant les espaces en début et fin de ligne
						VALID_WORKDIR=1
					else	# Sinon, c'est peut-être une erreur.
						if [ $VALID_HOSTNAME -eq -1 ]; then
							echo "Dossier de travail d'une autre machine, ignorer."
							VALID_WORKDIR=1	# Dossier validé pour ne pas provoquer d'erreur
						else
							if [ $VALID_HOSTNAME = 0 ]; then
								echo "Erreur de syntaxe dans la liste de synchronisation, le nom de la machine correspondant au dossier de travail de la ligne $LIGNE n'a pas été trouvé"
								ERROR=1
							fi
							if [ $VALID_BACKUP = 0 ]; then
								echo "Erreur de syntaxe dans la liste de synchronisation, le dossier de backup de la machine $hostname_list n'a pas été trouvé"
								ERROR=1
							fi
						fi
					fi
				fi
				# Détecte le dossier de backup
				if [ $(echo "$LIGNE" | grep -c '^>BACKUP:') -eq 1 ]	# Si la ligne commence par >BACKUP
				then
					if [ $VALID_BACKUP -eq 0 ] && [ $VALID_HOSTNAME -eq 1 ]	# Si le dossier de backup n'est pas trouvé, lit le chemin du dossier de backup
					then
						BACKUPDIR=$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@^ *@@;s@ *$@@' | sed "s@\$WORK_DIR@$WORK_DIR@" )	# Prend le chemin du dossier de backup en effaçant les espaces en début et fin de ligne et en interprétant éventuellement la variable $WORK_DIR si elle est présente
						VALID_BACKUP=1
					else	# Sinon, c'est peut-être une erreur.
						if [ $VALID_HOSTNAME -eq -1 ]; then
							echo "Dossier de backup d'une autre machine, ignorer."
							VALID_BACKUP=1	# Dossier validé pour ne pas provoquer d'erreur
						else
							if [ $VALID_HOSTNAME = 0 ]; then
								echo "Erreur de syntaxe dans la liste de synchronisation, le nom de la machine correspondant au dossier de backup de la ligne $LIGNE n'a pas été trouvé"
								ERROR=1
							fi
							if [ $VALID_WORKDIR = 0 ]; then
								echo "Erreur de syntaxe dans la liste de synchronisation, le dossier de travail de la machine $hostname_list n'a pas été trouvé"
								ERROR=1
							fi
						fi
					fi
				fi
				# Détecte le dossier de backup
				if [ $(echo "$LIGNE" | grep -c '^>NB_BACKUP:') -eq 1 ]	# Si la ligne commence par >NB_BACKUP:
				then
					if [ $VALID_NB_BACKUP -eq 0 ] && [ $VALID_HOSTNAME -eq 1 ]	# Si le nombre de backup n'est pas trouvé, lit le nombre de backup
					then
						NB_BACKUP=$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@^ *@@;s@ *$@@')	# Prend le nombre de backup en effaçant les espaces en début et fin de ligne
						VALID_NB_BACKUP=1
					else	# Sinon, c'est peut-être une erreur.
echo "VALID_HOSTNAME=$VALID_HOSTNAME"
echo "VALID_WORKDIR=$VALID_WORKDIR"
echo "VALID_BACKUP=$VALID_BACKUP"
						if [ $VALID_HOSTNAME -eq -1 ]; then
							echo "Nombre de backup d'une autre machine, ignorer."
							VALID_NB_BACKUP=1	# Dossier validé pour ne pas provoquer d'erreur
						else
							if [ $VALID_HOSTNAME = 0 ]; then
								echo "Erreur de syntaxe dans la liste de synchronisation, le nom de la machine correspondant au nombre de backup de la ligne $LIGNE n'a pas été trouvé"
								ERROR=1
							fi
							if [ $VALID_WORKDIR = 0 ]; then
								echo "Erreur de syntaxe dans la liste de synchronisation, le dossier de travail de la machine $hostname_list n'a pas été trouvé"
								ERROR=1
							fi
						fi
					fi
				fi
				if [ $VALID_HOSTNAME -ne 0 ] && [ $VALID_WORKDIR -eq 1 ] && [ $VALID_BACKUP -eq 1 ] && [ $VALID_NB_BACKUP -eq 1 ]
				then
					if [ $VALID_HOSTNAME -eq -1 ]	# Si la machine validée n'est pas la machine hôte.
					then	# Ignore la machine validée
						VALID_HOSTNAME=0	# Et invalide les dossiers trouvés, dans l'hypothèse de trouver spécifiquement la machine cliente
						VALID_WORKDIR=0
						VALID_BACKUP=0
						VALID_NB_BACKUP=0
					else
						echo ""
						echo "Machine $hostname_list validée."
						echo "Dossier de travail: $WORK_DIR"
						echo "Dossier de backup: $BACKUPDIR"
						echo "Nombre de backup: $NB_BACKUP"
						echo ""
						if [ $hostname_list = $(hostname) ]; then	# Si la machine validée est la machine cliente
						VALID_CLIENT=1	# Valide la machine trouvée
						valid_hostname_list=$hostname_list
						elif [ $hostname_list = "ALL" ]; then	# Sinon, si c'est ALL
						VALID_DEFAUT_ALL=1	# Valide ALL
						VALID_HOSTNAME=0	# Et invalide les dossiers trouvés, dans l'hypothèse de trouver spécifiquement la machine cliente
						VALID_WORKDIR=0
						VALID_BACKUP=0
						VALID_NB_BACKUP=0
						WORK_DIR_ALL=$WORK_DIR	# Copie des infos trouvée pour la machine ALL
						BACKUPDIR_ALL=$BACKUPDIR
						NB_BACKUP_ALL=$NB_BACKUP
						valid_hostname_list=$hostname_list
						fi
					fi
				fi
			fi
		elif [ $PARSE_PASS -eq 2 ]
		then	# 2e phase, détection des fichiers à synchroniser
# 			if [ $VALID_CLIENT = 1 ] || [ $VALID_DEFAUT_ALL = 1 ]	# Si la machine cliente est trouvée et validée.
# 			then
				# Détecte la machine cliente
				if [ $(echo "$LIGNE" | grep -c '^>MACHINE_SYNC:') -eq 1 ]	# Si la ligne commence par >MACHINE_SYNC
				then
					if [ $VALID_HOSTNAME_SYNC -eq 0 ]	# Si le hostname n'est pas trouvé, identifie une machine dans la liste
					then
						if [ $valid_hostname_list = $(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@ *@@g' ) ]	# Si le nom de la machine correspond à l'entrée dans la liste (sans les espaces superflus)
						then
							VALID_HOSTNAME_SYNC=1	# hostname de la machine locale trouvé dans la liste
							echo -n > "$WORK_DIR/Listersync"
						fi
					else	# Sinon, c'est peut-être une erreur.
						if [ $VALID_FILE_SYNC = 0 ]; then
							echo "Erreur de syntaxe dans la liste de synchronisation, aucun dossier ou fichier à synchroniser trouvé pour la machine $hostname_list"
							ERROR=1
						elif [ $VALID_HOSTNAME_SYNC=1 ] && [ $VALID_FILE_SYNC = 1 ]; then	# Si $VALID_FILE_SYNC = 1, alors c'est simplement la fin des arguments pour cette machine, et le début de la machine suivante. La lecture des arguments doit donc s'arrêter là.
							VALID_HOSTNAME_SYNC=2	# La machine a été trouvée, et on arrive à la machine suivante
						fi
					fi
				fi
				if [ $VALID_HOSTNAME_SYNC -eq 1 ]	# Recherche les fichiers à synchroniser seulement si la machine est trouvée et qu'on est pas encore arrivé à la suivante
				then
					# Détecte les fichiers ou dossiers à synchroniser
					if [ $(echo "$LIGNE" | grep -c '^>SYNC:') -eq 1 ]	# Si la ligne commence par >SYNC
					then
							echo -en "\\n$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@^ *@@;s@ *$@@')" >> "$WORK_DIR/Listersync"	# Ajoute le chemin du dossier ou fichier à synchroniser à la liste en effaçant les espaces en début et fin de ligne
							VALID_FILE_SYNC=1
							FIRST_EXCLUSION=0
					fi
					# Détecte le dossier distant
					if [ $(echo "$LIGNE" | grep -c '^>DOSSIER_DISTANT:') -eq 1 ]	# Si la ligne commence par >DOSSIER_DISTANT
					then
						if [ $VALID_FILE_SYNC -eq 1 ]	# Seulement si un dossier à synchroniser est validé en amont
						then
							echo -en ":D-$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@^ *@@;s@ *$@@')" >> "$WORK_DIR/Listersync"	# Ajoute le chemin du dossier distant à la suite de liste en effaçant les espaces en début et fin de ligne
						fi
					fi
					# Détecte les fichiers à exclure
					if [ $(echo "$LIGNE" | grep -c '^>EXCLUSION:') -eq 1 ]	# Si la ligne commence par >EXCLUSION
					then
						if [ $VALID_FILE_SYNC -eq 1 ]	# Seulement si un dossier à synchroniser est validé en amont
						then
							if [ $FIRST_EXCLUSION -eq 0 ]
							then
								echo -n ":E-" >> "$WORK_DIR/Listersync"
								FIRST_EXCLUSION=1
							else
								echo -n "|" >> "$WORK_DIR/Listersync"
							fi
							echo -n "$(echo "$LIGNE" | cut -d ":" -f 2 | sed 's@^ *@@;s@ *$@@')" >> "$WORK_DIR/Listersync"	# Ajoute le chemin du fichier ou dossier à exclure à la suite de liste en effaçant les espaces en début et fin de ligne
						fi
					fi
					# Détecte un éventuel forçage
					if [ $(echo "$LIGNE" | grep -c '^>FORCE:') -eq 1 ]	# Si la ligne commence par >FORCE
					then
						if [ $VALID_FILE_SYNC -eq 1 ]	# Seulement si un dossier à synchroniser est validé en amont
						then
							if [ $(echo "$LIGNE" | grep -c 'ocal') -eq 1 ]
							then
								echo -n ":force_local" >> "$WORK_DIR/Listersync"	# Indique un forçage de synchro depuis les fichiers locaux
							elif [ $(echo "$LIGNE" | grep -c 'istant') -eq 1 ]
							then
								echo -n ":force_distant" >> "$WORK_DIR/Listersync"	# Indique un forçage de synchro depuis les fichiers distants
							fi
						fi
					fi
				fi
# 			fi
		fi
	fi
done < "$SYNC_LISTE"
if [ $PARSE_PASS -eq 1 ]
then
	if [ $VALID_CLIENT = 0 ] && [ $VALID_DEFAUT_ALL = 0 ]	# Si la machine cliente n'est pas trouvée et validée, ni la machine ALL. Alors on a une erreur dans la liste.
	then
		echo "Erreur dans la liste de synchronisation, ni la machine $(hostname) ni la machine ALL n'ont été trouvé. Impossible d'analyser les dossiers pour cette machine."
		ERROR=1
	elif [ $VALID_CLIENT = 0 ] && [ $VALID_DEFAUT_ALL = 1 ]	# Sinon, si on a validé la machine ALL seulement
	then
		WORK_DIR=$WORK_DIR_ALL	# Récupère les infos stockée pour la machine ALL
		BACKUPDIR=$BACKUPDIR_ALL
		NB_BACKUP=$NB_BACKUP_ALL
	fi
fi

if [ $ERROR = 1 ]
then
	echo -e "\nDes erreurs ont été rencontrées pendant l'analyse du fichier de liste. Ces erreurs doivent être corrigées avant de continuer."
	read -p "Appuyer sur une touche pour terminer..."
	exit
fi
}

PARSE_PASS=1
PARSE_SYNC_LISTE	# Effectue un premier parsing de la sync_liste pour récupérer les informations de la machine courante.

TEMP_FILE="$WORK_DIR/back_temp"
LAST_SYNC_DATE="$WORK_DIR/last_sync_date"

BACKUP_DIR	# Appel la fonction gérant les dossiers de backup
TMPDIR="$BACKUPDIR/tmpfiles"
mkdir "$TMPDIR"	# Créer le dossier de fichiers. temporaires.
EXCLUDE_LISTE="$TMPDIR/Liste_exclude"
touch "$EXCLUDE_LISTE"	# Créer le fichier, si il n'existe pas.


echo "Connection ssh initiale" | tee -a "$LOGFILE"
ssh $SSH_HOST -p $SSH_PORT -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.

FORCE_SYNC=0
echo "Synchronisation de la liste de fichier" | tee -a "$LOGFILE"
LISTE_ONLY=$(basename "$SYNC_LISTE")
RSYNC "$SYNC_LISTE" "$LISTE_ONLY"

PARSE_PASS=2
echo "Analyse des dossiers à synchroniser dans la liste de synchronisation" | tee -a "$LOGFILE"
PARSE_SYNC_LISTE	# Effectue le 2e parsing pour récupérer la liste des fichiers à synchroniser.

ERROR=0
echo "Analyse de la liste de fichier" | tee -a "$LOGFILE"
# Parsing de la liste de fichier créée
sed -i '/^$/d' "$WORK_DIR/Listersync"	# Supprime les lignes vierges du fichier avant d'en analyser le contenu.
echo "" >> "$WORK_DIR/Listersync"	# Ajoute une ligne vierge à la fin du fichier afin de permettre le traitement de la dernière ligne.
while read <&4 LIGNE
do
	FORCE_SYNC=0
	LOCAL=$(echo $LIGNE | cut -d ":" -f 1)
	if [ $(echo $LIGNE | cut -d ":" -f 2 | cut -c1-2) = "D-" ]	# Si la 2e partie de la ligne commence par D-
	then # C'est le dossier distant
		DIR_DIST=$(echo $LIGNE | cut -d ":" -f 2)
	elif [ $(echo $LIGNE | cut -d ":" -f 2 | cut -c1-2) = "E-" ] # Sinon, si ça commence par E-
	then	# C'est la liste d'exlusion
		EXCLUDE=$(echo $LIGNE | cut -d ":" -f 2)
	else
		echo "Erreur de lecture dans le fichier Listersync. Le chemin $(echo $LIGNE | cut -d ":" -f 2) n'est pas reconnu comme étant le dossier distant ou un élément à exclure"
		ERROR=1
	fi
	if [ -n "$(echo $LIGNE | cut -d ":" -f 3)" ]	# Si la 3e partie de la ligne n'est pas vide
	then
		if [ $(echo $LIGNE | cut -d ":" -f 3 | cut -c1-2) = "D-" ]	# Si la 3e partie de la ligne commence par D-
		then # C'est le dossier distant
			DIR_DIST=$(echo $LIGNE | cut -d ":" -f 3)
		elif [ $(echo $LIGNE | cut -d ":" -f 3 | cut -c1-2) = "E-" ] # Sinon, si ça commence par E-
		then	# C'est la liste d'exlusion
			EXCLUDE=$(echo $LIGNE | cut -d ":" -f 3)
		else
			echo "Erreur de lecture dans le fichier Listersync. Le chemin $(echo $LIGNE | cut -d ":" -f 3) n'est pas reconnu comme étant le dossier distant ou un élément à exclure"
			ERROR=1
		fi
	fi
	if [ $(echo "$LIGNE" | grep -c ':force_distant') -eq 1 ]	# Si une commande de forçage a été ajoutée.
	then
	    FORCE_SYNC=1
	elif [ $(echo "$LIGNE" | grep -c ':force_local') -eq 1 ]	# Si une commande de forçage a été ajoutée.
	then
	    FORCE_SYNC=2
	fi

	if [ $ERROR = 1 ]
	then
		echo -e "\nDes erreurs ont été rencontrées pendant l'analyse du fichier Listersync. Ces erreurs doivent être corrigées en vérifiant la syntaxe du fichier de liste avant de continuer."
		read -p "Appuyer sur une touche pour terminer..."
		exit
	fi
	DIR_DIST=$(echo "$DIR_DIST" | sed 's@^D-@@')	# Retire D- au début de DIR_DIST
	EXCLUDE=$(echo "$EXCLUDE" | sed 's@^E-@@')	# Retire E- au début de EXCLUDE
	echo "-> Traitement de la ligne $LOCAL" | tee -a "$LOGFILE"
	# Création de la liste d'exclusion à partir de EXCLUDE
	echo -n > "$EXCLUDE_LISTE"	# Efface le contenu du fichier
	n=1
	while !(test -z "$(echo "$EXCLUDE" | cut -d "|" -f $n)")	#Faux si la chaine de caractère en sortie de cut est nulle. Ainsi, la boucle continue tant qu'il trouve encore des champs sur cut.
	do
		echo "$EXCLUDE" | cut -d "|" -f $n >> "$EXCLUDE_LISTE"
		n=$(($n + 1))
		if [ $(echo $EXCLUDE | grep -c "|") -eq 0 ]; then
			break	# Sortie de la boucle while si aucun | n'est présent dans la liste d'exclusion
		fi
	done
	if [ "$DIR_DIST" = '=' ]
	then
		DIR_DIST=$(basename "$LOCAL")	# Récupère le dernier dossier du chemin
	fi
	PARENT_DIR_LOCAL=$(dirname "$LOCAL")	# Récupère le chemin du dossier sans le nom de ce dernier
  	RSYNC "$LOCAL" "$DIR_DIST"
done 4< "$WORK_DIR/Listersync"
# L'ensemble d'instruction 'read <&4 LIGNE' et 'done 4< "$WORK_DIR/Listersync"' permettent d'utiliser le descripteur 4 (inutilisé) plutôt que le descripteur 1 (stdin). Car les descripteur 1 et 3 sont utilisés par le sous script birsync dans la boucle.

date +%s > "$LAST_SYNC_DATE"

echo "Fermeture de la connection ssh maître." | tee -a "$LOGFILE"
ssh $SSH_HOST -p $SSH_PORT -S $SSHSOCKET -O exit

# while read -e -t 1; do : ; done	# Vide le buffer stdin
read -p "Appuyer sur une touche pour terminer..."
