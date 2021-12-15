#!/bin/sh
set -f
# include parse_yaml function
APPDIR=$(dirname $0)
LOCKFILE=${0%.*}".pid"
CONFIG=${1:-"s4s.conf.yml"}
ROTATE=1
# 1 day max age
MAXAGE=$((60*60*20))

if [ -r $LOCKFILE ] && read PID <$LOCKFILE &&  ps -p $PID; then
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
echo $$ > $LOCKFILE

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
DEST=$conf_global_destDir
# rsync path
LOCAL_RSYNC=$conf_global_rsyncLocal
DAYS=$conf_global_retDays
WEEKS=$conf_global_retWeeks
MONTHS=$conf_global_retMonths
ERRORS=""
ERROR=0

if [ ! -x $LOCAL_RSYNC ]; then
    echo "Cannot find local rsync program. ${0%.*} depend on it to function"
    echo "##########  Please install rsync and re-run ${0%.*}    ##########"
    exit 1
fi
echo "Retention Policy (dd/ww/mm) $DAYS/$WEEKS/$MONTHS"

# check structure
HOSTSNo=$((conf_length-1))
for i in $(seq 1 $HOSTSNo); do
    eval HOST=\$conf_host${i}_fqdn
    eval DIRS=\$conf_host${i}_dirs
    eval SRC=\$conf_host${i}_src
    eval RUSER=\$conf_host${i}_user
    eval EXCLUDES=\$conf_host${i}_excl
    eval ALIAS=\$conf_host${i}_alias
    eval RRSYNC=\$conf_host${i}_rsync

    [ -z "$HOST" ] && { ERRORS+="ERROR: Host number mismach, check config"; }
    if [ -z "$RRSYNC" ]; then
        REMOTE_RSYNC=$conf_global_rsyncRemote
    else
        REMOTE_RSYNC=$RRSYNC;
    fi

    echo "Snapshotting $HOST, dirs: $DIRS"
    if [ -d $DEST/$HOST/day.0 ]; then
        LINK_DEST="--link-dest=$DEST/$HOST/day.0"
        if [ $(($(date +%s) - $(date -r $DEST/$HOST/day.0 +%s))) -le $MAXAGE ];
            then
            echo "Skipping $HOST, last snapshot newer than 1 day"
            i=$((i-1))
            continue
        fi
    else
        LINK_DEST=""
    fi

	CMDEXCLUDE=''
    if [ "$EXCLUDES" ]; then
        for EXCLUDE in $EXCLUDES; do
            CMDEXCLUDE="$CMDEXCLUDE --exclude=$EXCLUDE"
        done
    fi
    echo "CNDEXCLUDE=$CMDEXCLUDE"
    if [ ! -d $DEST/$HOST/rsync.part ]; then
        mkdir -p $DEST/$HOST/rsync.part;
    else
        echo "Found unfinished snapshot... continue"
    fi
    for DIR in $DIRS; do
        echo "-- Snapshotting $DIR"
        RES=$( $LOCAL_RSYNC -ahR --rsync-path=$REMOTE_RSYNC --stats $CMDEXCLUDE \
           --delete $LINK_DEST $RUSER@$HOST:$DIR $DEST/$HOST/rsync.part/ 2>&1 )

        [ $? -eq 0 ] || { echo $RES; ERROR=1;
                          ERRORS+="ERROR on host $HOST: $RES";                  
                          echo "ERROR, trying next DIR"; continue; }
        echo $RES
    done

    if [ $ERROR -gt 0 ]; then
        echo "ERRORS encountered on host $HOST, skipping rotation"

        ERROR=0
        continue
    fi
    if [ $ROTATE -eq 0 ]; then
        echo "-------- No Rotation Selected ---------"
        continue
    fi

    echo "--------------- Rotation of $HOST --------"
    # current day of week
    DOW=$(date +%u)
    [ $DOW -eq 3 ] && ROTATEWEEK=1 || ROTATEWEEK=0
    DOM=$(date +%e)
    # current day of month
    [ $DOM -eq 3 ] && ROTATEMONTH=1 || ROTATEMONTH=0

    echo "ROW=$ROTATEWEEK ROM=$ROTATEMONTH"
    rm -rf $DEST/$HOST/month.$MONTHS
    if [ $ROTATEMONTH -eq 1 ] && [ -d $DEST/$HOST/week.$WEEKS ]; then

        j=$MONTHS
        while [ $j -gt 0 ]; do
            ND=$((j-1))
            if [ -d $DEST/$HOST/month.$ND ]; then
                echo "month.$ND --> month.$j"
                mv -f $DEST/$HOST/month.$ND $DEST/$HOST/month.$j
            fi
            j=$((j-1))
        done

        if [ -d $DEST/$HOST/week.$WEEKS ]; then
            echo "week.$WEEKS --> month.0"
            mv $DEST/$HOST/week.$WEEKS $DEST/$HOST/month.0
        fi
    elif [ $ROTATEWEEK -eq 1 ]; then
        echo "remove week.$WEEKS"
        rm -rf $DEST/$HOST/week.$WEEKS
    fi

    if [ $ROTATEWEEK -eq 1 ]; then

        j=$WEEKS
        while [ $j -gt 0 ]; do
            ND=$((j-1))
            if [ -d $DEST/$HOST/week.$ND ]; then
                echo "week.$ND --> week.$j"
                mv -f $DEST/$HOST/week.$ND $DEST/$HOST/week.$j
            fi
            j=$((j-1))
        done
        if [ -d $DEST/$HOST/day.$DAYS ]; then
           echo "day.$DAYS --> week.0"
           mv $DEST/$HOST/day.$DAYS $DEST/$HOST/week.0
        fi
    else
        echo "remove day.$DAYS"
        rm -rf $DEST/$HOST/day.$DAYS
    fi

    j=$DAYS
    [ $ROTATE ] || j=0 
    while [ $j -gt 0 ]; do
        ND=$((j-1))
        if [ -d $DEST/$HOST/day.$ND ]; then
            echo "day.$ND --> day.$j"
            mv -f $DEST/$HOST/day.$ND $DEST/$HOST/day.$j
        fi
        j=$((j-1))
    done
    mv $DEST/$HOST/rsync.part $DEST/$HOST/day.0
done
if [ ! -z "$ERRORS" ]; then
    echo "--------------------------------------------------------------"
    echo $ERRORS
    echo "--------------------------------------------------------------"
fi
rm $LOCKFILE
