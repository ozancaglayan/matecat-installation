# Some configuration parameters
UNIXUSER="matecat"
DBUSER=${UNIXUSER}
DBPASS=`cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w ${1:-10} | head -n 1`
WWWDIR="/home/${UNIXUSER}/www-data"
STORAGEDIR="${WWWDIR}/storage"
