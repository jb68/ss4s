#!/bin/bash

# include parse_yaml function
APPDIR=`dirname $0`

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
eval $(parse_yaml $APPDIR/config.yml "conf_")

# Backup directory
DEST=$conf_global_destDir
# rsync path
LOCAL_RSYNC=$conf_global_rsyncLocal
REMOTE_RSYNC=$conf_global_rsyncRemote
DAYS=$conf_global_retDays
WEEKS=$conf_global_retWeeks
MONTHS=$conf_global_retMonths
echo "Retention Policy (dd/ww/mm) $DAYS/$WEEKS/$MONTHS"

# check structure
for (( i=($conf_length-1); $i>0; i-- ))
do
    eval HOST=\$conf_host${i}_name
    eval DIRS=\$conf_host${i}_dirs
    eval SRC=\$conf_host${i}_src
    eval RUSER=\$conf_host${i}_user

    echo "Snapshotting $HOST, dirs: $DIRS"

    if [ ! -d $DEST/$HOST/rsync.part ]; then
        mkdir -p $DEST/$HOST/rsync.part;
    else
        echo "Found unfinished snapshot... continue"
    fi
    if [ -d $DEST/$HOST/day.0 ]; then
        LINK_DEST="--link-dest=$DEST/$HOST/day.0"
    fi
    for DIR in $DIRS; do
        echo "-- Snapshotting $DIR"
        $LOCAL_RSYNC -ahR --rsync-path=$REMOTE_RSYNC --stats \
           --delete $LINK_DEST $RUSER@$HOST:$DIR $DEST/$HOST/rsync.part/
        [ $? -eq 0 ] || ( echo "ERROR $RET" && exit 1 )
    done
    echo "--------------- ROtation of $HOST --------"
    # current day of week
    DOW=$(date +%u)
    [ $DOW -eq 3 ] && ROTATEWEEK=1 || ROTATEWEEK=0
    DOM=$(date +%e)
    # current day of month
    [ $DOM -eq 3 ] && ROTATEMONTH=1 || ROTATEMONTH=0

    echo "ROW=$ROTATEWEEK ROM=$ROTATEMONTH"
    rm -rf $DEST/$HOST/month.$MONTHS
    if [ $ROTATEMONTH -eq 1 ] && [ -d $DEST/$HOST/week.$WEEKS ]; then
        for (( j=$MONTHS; $j>0; j=$j-1 )) do
            ND=$((j-1))
            if [ -d $DEST/$HOST/month.$ND ]; then
                echo "month.$ND --> month.$j"
                mv -f $DEST/$HOST/month.$ND $DEST/$HOST/month.$j
            fi
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
        for (( j=$WEEKS; $j>0; j=$j-1 )) do
            ND=$((j-1))
            if [ -d $DEST/$HOST/week.$ND ]; then
                echo "week.$ND --> week.$j"
                mv -f $DEST/$HOST/week.$ND $DEST/$HOST/week.$j
            fi
         done

        if [ -d $DEST/$HOST/day.$DAYS ]; then
           echo "day.$DAYS --> week.0"
           mv $DEST/$HOST/day.$DAYS $DEST/$HOST/week.0
        fi
    else
        echo "remove day.$DAYS"
        rm -rf $DEST/$HOST/day.$DAYS
    fi

     # days
    for (( j=$DAYS; $j>0; j=$j-1 )) do
        ND=$((j-1))
        if [ -d $DEST/$HOST/day.$ND ]; then
            echo "day.$ND --> day.$j"
            mv -f $DEST/$HOST/day.$ND $DEST/$HOST/day.$j
        fi
    done
    mv $DEST/$HOST/rsync.part $DEST/$HOST/day.0
done
