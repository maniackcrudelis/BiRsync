#!/bin/bash

RESURG_MD5=0	# La variable RESURG_MD5 est à 0 par défaut. Ainsi, un fichier en conflit md5sum sera envoyé sur le serveur pour mettre fin au conflit. Sinon, rsync fera ressortir le fichier à chaque analyse. Placer la variable à 1 pour annuler ce comportement.

LOCAL=$1	# Dossier local à synchroniser
DISTANT=$2	# Dossier distant à synchroniser
TMPDIR=$3	# Dossier contenant les fichiers temporaires

EXCLUDE=$4	# Listes d'exclusion
LAST_SYNC_DATE=$5 # Fichier contenant la date de dernière synchro

SSH_HOST=$6	# Nom d'hôte du serveur ssh
SSH_PORT=$7	# Port ssh
SSHSOCKET=$8 # Socket ssh

LOGFILE=$9 # Emplacement du fichier de log

# Fichiers temporaires:
if [ ! -e "$TMPDIR" ]	# Si le dossier de fichier temporaire n'existe pas.
then
	mkdir "$TMPDIR"	# Créer le dossier
fi

RSYNCDRY_U_FIRST="$TMPDIR/Ufirst"
RSYNCDRY_D_FIRST="$TMPDIR/Dfirst"
RSYNCDRY_U_MOD="$TMPDIR/Umod"
echo -n > "$RSYNCDRY_U_MOD"
RSYNCDRY_D_MOD="$TMPDIR/Dmod"
echo -n > "$RSYNCDRY_D_MOD"
RSYNCDRY_U_DEL="$TMPDIR/Udel"
echo -n > "$RSYNCDRY_U_DEL"
RSYNCDRY_D_DEL="$TMPDIR/Ddel"
echo -n > "$RSYNCDRY_D_DEL"
RSYNC_U_EXCLUDE="$EXCLUDE.U"
RSYNC_D_EXCLUDE="$EXCLUDE.D"
cat "$EXCLUDE" > "$RSYNC_U_EXCLUDE"
cat "$EXCLUDE" > "$RSYNC_D_EXCLUDE"
RSYNC_U_SUPPR_DATE="$TMPDIR/USdate"
RSYNC_D_SUPPR_DATE="$TMPDIR/DSdate"
RSYNCDRY_CONFLICT="$TMPDIR/conflict"
echo -n > "$RSYNCDRY_CONFLICT"
RSYNC_CONFLICT_MD5="$TMPDIR/CMD5"
RSYNC_CONFLICT_DATE="$TMPDIR/Cdate"



# Vérifie l'existence du fichier contenant la dernière date de synchro
if [ -e "$LAST_SYNC_DATE" ]	# Si le fichier existe
then
	length=$(cat "$LAST_SYNC_DATE")
	if [ ${#length} -eq 0 ] # Mais qu'il est vierge
	then
		echo 0 > "$LAST_SYNC_DATE"	# Créer un fichier date contenant 0, pour forcer le script à ignorer la date de synchro
		echo "Fichier $LAST_SYNC_DATE existant mais vide. Remise à zéro."
	fi
else
	echo 0 > "$LAST_SYNC_DATE"	# Créer un fichier date contenant 0, pour forcer le script à ignorer la date de synchro
	echo "Fichier $LAST_SYNC_DATE inexistant. Remise à zéro."
fi


# rsync originaux pour voir ce qu'il voudrait faire
echo "-> Analyse des fichiers à transférer." >> "$LOGFILE"
if [ -e "$LOCAL" ]
then	# Effectue l'analyse rsync seulement si le dossier à traiter existe
	rsync -avzhE --dry-run --modify-window=1 --exclude-from="$EXCLUDE" --delete "$LOCAL" -e "ssh -p $SSH_PORT -o ControlPath=$SSHSOCKET" $SSH_HOST:"\"$DISTANT\"" > "$RSYNCDRY_U_FIRST"
else
	echo "Le dossier ou fichier \"$LOCAL\" n'existe pas sur la machine locale."
fi
if [ $(ssh $SSH_HOST -p $SSH_PORT -o ControlPath=$SSHSOCKET "if test -e \"$DISTANT\"; then echo 1; else echo 0; fi") -eq 1 ]
then	# Effectue l'analyse rsync seulement si le dossier à traiter existe
	rsync -avzhEs --dry-run --modify-window=1 --exclude-from="$EXCLUDE" --delete -e "ssh -p $SSH_PORT -o ControlPath=$SSHSOCKET" $SSH_HOST:"$DISTANT" "$LOCAL" > "$RSYNCDRY_D_FIRST"
else
	echo "Le dossier ou fichier \"$DISTANT\" n'existe pas sur la machine distante."
fi

if [ ! -e "$RSYNCDRY_D_FIRST" ]; then
    touch "$RSYNCDRY_D_FIRST"	# Créer le fichier, si il n'existe pas.
fi

LOCAL=$(echo "$LOCAL" | sed 's#//$##')	# Supprime l'eventuel / à la fin du chemin

# Isole les suppressions des modifications sur les 2 listes
echo "-> Traitement de la liste de fichiers pour séparer les suppressions des modifications." >> "$LOGFILE"
# Boucle 2 fois pour traiter les 2 listes
# la commande "seq a b" compte de a à b
for bcl in `seq 1 2`
do
	if [ $bcl -eq 1 ]; then
		rsyncdry_first="$RSYNCDRY_U_FIRST"
		rsyncdry_mod="$RSYNCDRY_U_MOD"
		rsyncdry_del="$RSYNCDRY_U_DEL"
		DIRSUPPR=$(basename "$LOCAL")	# basename renvoi le dernier dossier du chemin
	else
		rsyncdry_first="$RSYNCDRY_D_FIRST"
		rsyncdry_mod="$RSYNCDRY_D_MOD"
		rsyncdry_del="$RSYNCDRY_D_DEL"
		DIRSUPPR=$(basename "$DISTANT")	# basename renvoi le dernier dossier du chemin
	fi
	grep '^deleting ' "$rsyncdry_first" | sed 's#^deleting ##g' > "$rsyncdry_del"	# Isole les lignes commençant par 'deleting ', en retirant la mention deleting
	grep -v '^deleting ' "$rsyncdry_first" > "$rsyncdry_mod"	# Et isole les lignes ne commençant pas par 'deleting ' dans le second fichier
	# Suppression des 3 lignes d'rsync dans le fichier mod
	sed -i '\#[a-z]*ing incremental file list#d' "$rsyncdry_mod"
	sed -i '\#sent.*bytes  received.*bytes.*bytes/sec#d' "$rsyncdry_mod"
	sed -i '\#total size is.*speedup is.*(DRY RUN)#d' "$rsyncdry_mod"
	sed -i "s#^$DIRSUPPR/##g" "$rsyncdry_del"	# Retire le nom du dossier au début de chaque ligne de rsyncdry_del
	sed -i "s#^$DIRSUPPR/##g" "$rsyncdry_mod"	# Retire le nom du dossier distant au début de chaque ligne de rsyncdry_mod
done

if [ -f "$LOCAL" ]	# Si on a un fichier à synchroniser et pas un dossier
then
	LOCAL=$(dirname "$LOCAL")	# Retire le dernier dossier, qui vient en doublon du nom du fichier.
	DISTANT=$(dirname "$DISTANT")	# Retire le dernier dossier, qui vient en doublon du nom du fichier.
fi

# Élimination des conflits de suppression sur les listes opposées.
# Boucle 2 fois pour traiter les 2 listes
# la commande "seq a b" compte de a à b
echo "-> Suppression des fichiers en double dans la liste mod. Pour qu'ils soient gérés en conflit de suppression uniquement." >> "$LOGFILE"
for bcl in `seq 1 2`
do
	if [ $bcl -eq 1 ]; then
		rsyncdry_del="$RSYNCDRY_U_DEL"
		rsyncdry_mod_opp="$RSYNCDRY_D_MOD"
	else
		rsyncdry_del="$RSYNCDRY_D_DEL"
		rsyncdry_mod_opp="$RSYNCDRY_U_MOD"
	fi
	while read LIGNE_DEL
	do
		grep -c "^$LIGNE_DEL$" "$rsyncdry_mod_opp" > /dev/null	# Cherche le fichier à supprimer dans la liste mod opposée pour l'y retirer
 		if [ $? -eq 0 ]	# Si grep renvoi 0 en sortie, c'est qu'il a trouvé
		then	# Si grep trouve le fichier dans la liste mod opposée
			sed -i "\#$LIGNE_DEL#d" "$rsyncdry_mod_opp"	# Suppression de la ligne dans le fichier mod. # est utilisé comme délimiteur, il ne devrait donc pas être présent dans un nom de fichier!
		fi
	done < "$rsyncdry_del"
done

# Gestion des conflits de suppression
if [ -s "$RSYNCDRY_U_DEL" ]	# Continue l'analyse seulement si le fichier U_del n'est pas vide
then
	echo "-> Comparaison des conflits de suppressions." >> "$LOGFILE"
	cat -s "$RSYNCDRY_U_DEL" | sed "s#^#$DISTANT/#g" | ssh $SSH_HOST -p $SSH_PORT -o ControlPath=$SSHSOCKET "xargs -d \"\n\" stat -c %Z" > "$RSYNC_D_SUPPR_DATE"
	# stat -c %Z affiche la date de dernier changement en seconde.
	# xargs -d \"\n\" prend en argument la sortie de sed et la délimite par ses retours à la ligne
	# sed "s#^#$DISTANT/#g" ajoute le chemin distant à chaque début de ligne afin d'obtenir des chemins absolu
	# Et cat liste simplement la liste de suppression upload.
	# On obtient ainsi la date de modification des fichiers sur le serveur que le client veut supprimer.
fi
if [ -s "$RSYNCDRY_D_DEL" ]	# Continue l'analyse seulement si le fichier D_del n'est pas vide
then
	cat "$RSYNCDRY_D_DEL" | sed "s#^#$LOCAL/#g" | xargs -d "\n" stat -c %Z > "$RSYNC_U_SUPPR_DATE"
fi

# Compare les dates des fichiers à supprimer avec la date de dernière synchronisation
# Boucle 2 fois pour traiter les 2 listes
# la commande "seq a b" compte de a à b
for bcl in `seq 1 2`
do
	if [ $bcl -eq 1 ]
	then
		rsyncdry_del="$RSYNCDRY_U_DEL"
		rsync_suppr_date="$RSYNC_D_SUPPR_DATE"
		rsync_exclude_local="$RSYNC_U_EXCLUDE"
		rsync_exclude_opp="$RSYNC_D_EXCLUDE"
	else
		rsyncdry_del="$RSYNCDRY_D_DEL"
		rsync_suppr_date="$RSYNC_U_SUPPR_DATE"
		rsync_exclude_local="$RSYNC_D_EXCLUDE"
		rsync_exclude_opp="$RSYNC_U_EXCLUDE"
	fi
	nbl=0
	while read LIGNE_DEL
	do
		nbl=$(($nbl + 1))
 		if [ $(cat "$LAST_SYNC_DATE") -ge $(sed -n "$nbl"p "$rsync_suppr_date") ] # -ge	est plus grand ou égal à
		then	# Si le fichier a supprimer est plus ancien que la date de dernière synchro. Il sera supprimé.
			echo $LIGNE_DEL >> "$rsync_exclude_opp"	# On l'exclue donc de la liste opposée afin qu'il ne soit pas ajouté.
		else	# Sinon, c'est un nouveau fichier à ajouter
			echo $LIGNE_DEL >> "$rsync_exclude_local"	# On l'exclue de la liste locale afin de ne pas le supprimer.
		fi
	done < "$rsyncdry_del"
done

# Isolement des conflits de fichiers modifiés
echo "-> Isolement des conflits de modifications." >> "$LOGFILE"
while read LIGNE_MOD
do
	if [ -n "$LIGNE_MOD" ]
	then	# Cherche la ligne seulement si ce n'est pas une ligne vide.
		grep -c "^$LIGNE_MOD$" "$RSYNCDRY_D_MOD" > /dev/null	# Cherche le fichier à supprimer dans la liste mod opposée pour l'y retirer
		if [ $? -eq 0 ]	# Si grep renvoi 0 en sortie, c'est qu'il a trouvé
		then	# Si grep trouve le fichier dans la liste mod opposée
			echo $LIGNE_MOD >> "$RSYNCDRY_CONFLICT"	# Ajoute le fichier à la liste de conflit, il sera géré ultérieurement
		fi
	fi
done < "$RSYNCDRY_U_MOD"


# Gestion des conflits de fichiers modifiés
echo "-> Gestion des conflits de modifications." >> "$LOGFILE"
sed -i '/^$/d' "$RSYNCDRY_CONFLICT"	# Supprime les lignes vierges du fichier conclict avant d'en analyser le contenu.
if [ -s "$RSYNCDRY_CONFLICT" ]	# Continue l'analyse seulement si le fichier conflict n'est pas vide
then
	cat -s "$RSYNCDRY_CONFLICT" | sed "s#^#$DISTANT/#g" | ssh $SSH_HOST -p $SSH_PORT -o ControlPath=$SSHSOCKET "xargs -d \"\n\" stat --printf='%Z  %n\n'" > "$RSYNC_CONFLICT_DATE"
	cat -s "$RSYNCDRY_CONFLICT" | sed "s#^#$DISTANT/#g" | ssh $SSH_HOST -p $SSH_PORT -o ControlPath=$SSHSOCKET "xargs -d \"\n\" md5sum" > "$RSYNC_CONFLICT_MD5" 2> /dev/null # Efface les erreurs, pour ne pas afficher les échecs de md5sum sur les dossiers
	# stat -c %Z affiche la date de dernier changement en seconde.
	# md5sum affiche la somme de contrôle md5
	# xargs -d \"\n\" prend en argument la sortie de sed et la délimite par ses retours à la ligne
	# sed "s#^#$DISTANT_SED/#g" ajoute le chemin distant à chaque début de ligne afin d'obtenir des chemins absolu
	nbl=0; nblC=0
	nblm=$(wc -l "$RSYNCDRY_CONFLICT" | cut -d " " -f 1)
	rept=0
	while read <&3 LIGNE
	do
 		if [ -e "$LOCAL/$LIGNE" ]	# Si le fichier existe, c'est notamment utile pour ignorer les liens symboliques brisés
		# Comparaison des checksum tout d'abord
		rep=$rept	# Initialise la réponse pour la gestion des conflits
		then
			nbl=$(($nbl + 1))
			POSITION="0"
			if [ -f "$LOCAL/$LIGNE" ]	# Si le fichier est un fichier ordinaire, effectue le test des sommes de contrôle
			then
				nblC=$(($nblC + 1))	# Incrémente séparément les lignes pour md5sum, afin d'éviter le décalage des dossiers absent
				if [ $(md5sum "$LOCAL/$LIGNE" | cut -d " " -f 1) = $(sed -n "$nblC"p "$RSYNC_CONFLICT_MD5" | cut -d " " -f 1) ]
				then
					echo "" >> "$LOGFILE"
					echo "--> Conflit sur fichier \"$LOCAL$LIGNE\"" >> "$LOGFILE"
					echo "--> Fichiers identiques." >> "$LOGFILE"
					if [ $RESURG_MD5 -eq 0 ]
					then	# Si RESURG_MD5 à 0, on garde le fichier distant pour mettre fin au conflit. On crée un backup inutile, mais on s'assure que c'est bien le même fichier qui sera partout. Garder le fichier local pousse chaque machine à renvoyer son propre fichier.
						echo "--> Le fichier distant sera rappatrié pour éviter la résurgence du conflit." >> "$LOGFILE"
						rep=d	# Fichier distant gardé
					else	# Sinon, le fichier est ignoré, mais il risque de revenir à la prochaine analyse.
						rep=c	# Permet de passer à travers la gestion des conflit pour ignorer ce fichier
					fi
				fi
			fi
			if [ $rep = "0" ]
			then	# Si la comparaison des sommes de contrôle n'est pas réussie
				if [ $(cat "$LAST_SYNC_DATE") -gt $(sed -n "$nbl"p "$RSYNC_CONFLICT_DATE" | cut -d " " -f 1) ] # -gt	est plus grand que
				then	# Si le fichier distant est plus ancien que la date de dernière synchro
					POSITION="local"
				elif [ $(cat "$LAST_SYNC_DATE") -gt $(stat -c %Z "$LOCAL/$LIGNE" | cut -d " " -f 1) ] # -gt	est plus grand que
				then	# Si le fichier local est plus ancien que la date de dernière synchro
					POSITION="distant"
				fi
				if [ $POSITION != "0" ]
				then
					# C'est simplement un fichier à mettre à jour. L'option -u de rsync devrait gérer cela, mais elle interfere avec la gestion des conflits. Rsync prenant simplement le plus récent, sans autre considération.
					echo "" >> "$LOGFILE"
					echo "--> Conflit sur fichier \"$LOCAL$LIGNE\"" >> "$LOGFILE"
					echo "Fichier $POSITION modifié." >> "$LOGFILE"
					rep=u	# On gère donc ce cas particulier, on choississant le plus récent seulement pour cette situation de fichier modifié que d'un seul côté.
				fi
			fi
			if [ $rep = "0" ] && [ -d "$LOCAL/$LIGNE" ]
			then	#Si aucune réponse n'est déjà sélectionnée et que le fichier est un dossier. Évite de demander la gestion de conflit pour les dossiers. C'est inutile.
			    rep=u	# Le dossier le plus récent sera conservé.
			fi
			if [ $rep = "0" ]	# Demande l'action à l'utilisateur seulement si elle n'est pas déjà renseignée
			then
				echo ""
				echo ""
				echo "----> Conflit de fichiers $nbl/$nblm!"
				echo "Sur \"$LOCAL$LIGNE\""
				echo "Date de dernière syncho sur la machine : `date --date=@$(cat "$LAST_SYNC_DATE")`"
				echo "Date de modification du fichier local  : `date --date=@$(stat -c %Z "$LOCAL/$LIGNE" | cut -d " " -f 1-2)`"
				echo "Date de modification du fichier distant: `date --date=@$(sed -n "$nbl"p "$RSYNC_CONFLICT_DATE" | cut -d " " -f 1)`"
				echo ""
				echo "Quelle action effectuer ?"
				echo "Garder le fichier local: l"
				echo "Garder le fichier distant: d"
				echo "Garder le fichier le plus récent: r"
				echo "Garder les 2 versions du fichier: a"
				echo "Faire suivre de 't' pour appliquer à tous. Ex: lt pour garder le fichier local sur tout les conflits"
				while [ ${rep:0:1} != 'l' ] && [ ${rep:0:1} != 'd' ] && [ ${rep:0:1} != 'r' ] && [ ${rep:0:1} != 'a' ]
				do
					echo -n "(l/d/r/a)?: "
					read rep
					rep=$(echo $rep | tr 'A-Z' 'a-z')	# Force en minuscule
				done
				if [ ${#rep} -gt 1 ]	# Si rep contient plus d'1 seul caractère
				then
					if [ ${rep:1:1} = 't' ]	# Si le 2e caractère est t
					then
						rept=${rep:0:1}	# La saisie de l'utilisateur devient la saisie par défaut pour les conflits suivants
					fi
					rep=${rep:0:1}	# Et rep ne reprend que le premier caractère.
				fi
			fi
			case $rep in
			"l" | "m")	# On garde le fichier local. m dans le cas d'un conflit md5
				echo $LIGNE >> "$RSYNC_D_EXCLUDE"	# Donc on exclue dans la liste distante
				if [ $rep = "l" ]	# Affiche sur la sortie standard uniquement si ce n'est pas en raison d'un conflit md5
				then
				    echo "Fichier local gardé."
				else	# Sinon, affiche uniquement dans le log.
				    echo "Fichier local gardé." >> "$LOGFILE"
				fi
				;;
			"d")	# On garde le fichier distant
				echo $LIGNE >> "$RSYNC_U_EXCLUDE"	# Donc on exclue dans la liste locale.
				echo "Fichier distant gardé."
				;;
			"r" | "u")	# On garde le plus récent. u pour la substitution de -u de rsync
				if [ $rep = "r" ]	# Affiche sur la sortie standard uniquement si ce n'est pas la substitution de -u
				then
				    echo -n "Fichier le plus récent gardé ("
				else	# Sinon, affiche uniquement dans le log.
				    echo -n "Fichier le plus récent gardé (" >> "$LOGFILE"
				fi
				if [ $(stat -c %Z "$LOCAL/$LIGNE") -lt $(sed -n "$nbl"p "$RSYNC_CONFLICT_DATE" | cut -d " " -f 1) ]	# Si date locale inférieure (plus ancienne) à date distante
				then	# On garde le fichier distant
					echo $LIGNE >> "$RSYNC_U_EXCLUDE"	# Donc on exclue dans la liste locale
					if [ $rep = "r" ]	# Affiche sur la sortie standard uniquement si ce n'est pas la substitution de -u
					then
					    echo "fichier distant)."
					else	# Sinon, affiche uniquement dans le log.
					    echo "fichier distant)." >> "$LOGFILE"
					fi
				else	# On garde le fichier local
					echo $LIGNE >> "$RSYNC_D_EXCLUDE"	# Donc on exclue dans la liste distante
					if [ $rep = "r" ]	# Affiche sur la sortie standard uniquement si ce n'est pas la substitution de -u
					then
					    echo "fichier local)."
					else	# Sinon, affiche uniquement dans le log.
					    echo "fichier local)." >> "$LOGFILE"
					fi
				fi
				;;
			"a")	# On garde les 2 fichiers
				NEWFILE="$(echo -n "$LIGNE"; echo -n _$(date +%d.%m.%y-%X))"
				mv "$LOCAL/$LIGNE" "$LOCAL/$NEWFILE"	# On renomme le fichier local.
				echo -e "$LIGNE"\\n"$NEWFILE" >> "$RSYNC_U_EXCLUDE"	# Et on exclue les 2 fichiers dans la liste locale
				echo "$NEWFILE" >> "$RSYNC_D_EXCLUDE"	# On exclue également le nouveau fichier dans la liste distante
				echo "2 fichiers gardés, le fichier local est renommé."
				;;
			"c")	# Checksum de 2 fichiers identiques
				echo $LIGNE >> "$RSYNC_U_EXCLUDE"	# On exclue dans la liste locale
				echo $LIGNE >> "$RSYNC_D_EXCLUDE"	# Et dans la liste distante
				;;
			*)	# case non référencé
				echo "Aucune action associée."
				;;
			esac
		fi
	done 3< "$RSYNCDRY_CONFLICT"
	# L'ensemble d'instruction 'read <&3 LIGNE' et 'done 3< "$RSYNCDRY_CONFLICT"' permettent d'utiliser le descripteur 3 (inutilisé) plutôt que le descripteur 1 (stdin). Car le descripteur 1 est également utilisé par 'read rep' dans la boucle. Ainsi, on évite un conflit, en permettant à 'read rep' de ne pas lire le fichier mais bien l'entrée standard du clavier.
fi
