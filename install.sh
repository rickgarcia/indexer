#!/bin/bash

PERL=`which perl`
SUDO=''
# Ensure dependencies before continuing
while true; do
	$PERL -e 'require DBD::SQLite;' > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "SQLite Dependency not found; attempting install"
		export PERL_MM_USE_DEFAULT=1
		$SUDO perl -MCPAN -e "install DBD::SQLite"

		# elevate to root/admin if needed...	
		if [ $? -eq 13 ]; then
			echo 
			read -p "Admin privileges needed for install; continue? [y/n]" yn
			case $yn in
				[Yy]* ) SUDO='sudo ';;
				* ) echo; exit;;
			esac
		fi
	else
		echo "Dependencies OK"
		break;
	fi
done



