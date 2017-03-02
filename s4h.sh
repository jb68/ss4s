#!/bin/sh
set -f
# include parse_yaml function
APPDIR=`dirname $0`
LOCKFILE=${0%.*}".pid"
CONFIG=${1:-"s4h.conf.yml"}
ROTATE=1
# 1 day max age
MAXAGE=$((60*60*24))

if [ -r $LOCKFILE ] && read pid <$LOCKFILE; then
    echo "Found same process lock-file. Is another instance still running?"
    if [ $(($(date +%s) - $(date -r $LOCKFILE +%s))) -le $MAXAGE ]; then
        echo "Please delete $LOCKFILE and re-run script"
        echo "........ exiting"
        exit 7
    else
        echo "$LOCKFILE is older than 1 day, deleted"
        echo "........ continue"
    fi
fi
echo 1> $LOCKFILE

# YAML parser from:
# https://gist.github.com/pkuczynski/8665367
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   echo ${prefix}length=$(grep '^\S' $1 | wc -l)
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2; l=0;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# load config
eval $(parse_yaml $APPDIR/$CONFIG "conf_")

# Backup directory
DEST=$conf_local_destDir
# rsync path
LOCAL_RSYNC=$conf_local_rsync
REMOTE_RSYNC=$conf_host_rsync
DAYS=$conf_local_retDays
WEEKS=$conf_local_retWeeks
MONTHS=$conf_local_retMonths
echo "Retention Policy (dd/ww/mm) $DAYS/$WEEKS/$MONTHS"

HOST=$conf_host_name
HOMEDIR=$conf_host_homedir
SRC=$conf_host_src
RUSER=$conf_host_user
EXCLUDES=$conf_host_excl

if [ "$EXCLUDES" ]; then
    for EXCLUDE in $EXCLUDES; do
        CMDEXCLUDE="$CMDEXCLUDE --exclude=$EXCLUDE"
    done
fi
echo "CNDEXCLUDE=$CMDEXCLUDE"

# Grab usernames from HOST
USERS=$(ssh $HOST ls $HOMEDIR)
for USER in $USERS; do
    echo "Creating snapshot for $USER"

    if [ -d $DEST/$USER/day.0 ]; then
        LINK_DEST="--link-dest=$DEST/$USER/day.0"
        if [ $(($(date +%s) - $(date -r $DEST/$USER/day.0 +%s))) -le $MAXAGE ];
            then
            echo "Skipping $USER, last snapshot newer than 1 day"
            i=$((i-1))
            continue
        fi
    else
        LINK_DEST=""
    fi

    if [ ! -d $DEST/$USER/rsync.part ]; then
        mkdir -p $DEST/$USER/rsync.part;
    else
        echo "Found unfinished snapshot... continue"
    fi

        echo "-- Snapshotting $USER"
        $LOCAL_RSYNC -ahRv --rsync-path=$REMOTE_RSYNC --stats $CMDEXCLUDE \
           --delete $LINK_DEST $RUSER@$HOST:$HOMEDIR $DEST/$USER/rsync.part/
        [ $? -eq 0 ] || { echo "ERROR, trying next $USER"; ERROR=1; }

    #i=$((i-1)); continue
    if [ $ERROR -gt 0 ]; then
        echo "ERRORS encountered on user $USER, skipping rotation"
        i=$((i-1))
        ERROR=0
        continue
    fi
    if [ $ROTATE -eq 0 ]; then
        echo "-------- No Rotation Selected ---------"
        i=$((i-1))
        continue
    fi

    echo "--------------- Rotation of $USER --------"
    # current day of week
    DOW=$(date +%u)
    [ $DOW -eq 3 ] && ROTATEWEEK=1 || ROTATEWEEK=0
    DOM=$(date +%e)
    # current day of month
    [ $DOM -eq 3 ] && ROTATEMONTH=1 || ROTATEMONTH=0

    echo "ROW=$ROTATEWEEK ROM=$ROTATEMONTH"
    rm -rf $DEST/$USER/month.$MONTHS
    if [ $ROTATEMONTH -eq 1 ] && [ -d $DEST/$USER/week.$WEEKS ]; then

        j=$MONTHS
        while [ $j -gt 0 ]; do
            ND=$((j-1))
            if [ -d $DEST/$USER/month.$ND ]; then
                echo "month.$ND --> month.$j"
                mv -f $DEST/$USER/month.$ND $DEST/$USER/month.$j
            fi
            j=$((j-1))
        done

        if [ -d $DEST/$USER/week.$WEEKS ]; then
            echo "week.$WEEKS --> month.0"
            mv $DEST/$USER/week.$WEEKS $DEST/$USER/month.0
        fi
    elif [ $ROTATEWEEK -eq 1 ]; then
        echo "remove week.$WEEKS"
        rm -rf $DEST/$USER/week.$WEEKS
    fi

    if [ $ROTATEWEEK -eq 1 ]; then

        j=$WEEKS
        while [ $j -gt 0 ]; do
            ND=$((j-1))
            if [ -d $DEST/$USER/week.$ND ]; then
                echo "week.$ND --> week.$j"
                mv -f $DEST/$USER/week.$ND $DEST/$USER/week.$j
            fi
            j=$((j-1))
         done

        if [ -d $DEST/$USER/day.$DAYS ]; then
           echo "day.$DAYS --> week.0"
           mv $DEST/$USER/day.$DAYS $DEST/$USER/week.0
        fi
    else
        echo "remove day.$DAYS"
        rm -rf $DEST/$USER/day.$DAYS
    fi

    j=$DAYS
   [ $ROTATE ] || j=0 
    while [ $j -gt 0 ]; do
        ND=$((j-1))
        if [ -d $DEST/$USER/day.$ND ]; then
            echo "day.$ND --> day.$j"
            mv -f $DEST/$USER/day.$ND $DEST/$USER/day.$j
        fi
        j=$((j-1))
    done
    mv $DEST/$USER/rsync.part $DEST/$USER/day.0
done
rm $LOCKFILE
