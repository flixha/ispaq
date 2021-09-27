#!/bin/bash

# wrapper script to run the ispaq-python scripts more efficiently.
# When running ispaq on a large archive, the filename matching becomes extremely slow and slows
# down the whole program. This wrapper script starts ispaq with additional parameters that confine ispaq's
# file search to smaller subdirectories.

# Author: Felix Halpaap, 2021

# function defintion
run_ispaq_on_network () {
  startyear="${1}"
  endyear="${2}"
  network="${3}"
  declare -a stations=("${!4}")

  echo "Starting up to $n_cores runs simultaneously"
  #loop over years and stations in network
  for year in $(seq $startyear $endyear);
  do
    echo $year
    for station in "${stations[@]}";
    do
      echo "Starting ispaq for $network.$station"
      # check if stations /channel folders exist with wildcard
      if compgen -G "$archiveDir/$year/$network/$station/$channels.?" > /dev/null; then
        # Define the command to start ispaq for one year at one station
        ispaqCommand="python2 -u $binDir/run_ispaq.py -P $prefFile \
          -M $metrics -S $network.$station.*.$channels \
           --starttime $year-01-01T00:00:00 --endtime $year-12-31T23:59:59 \
          --dataselect_url $archiveDir/$year/$network/$station \
          --station_url $inventory_stationxml"
        echo $ispaqCommand
        # check how many unique ispaq-commands are running
        nruns=`ps axu | grep -e "run_ispaq.py" | grep -e  "--starttime" | awk '{print $19, $21, $23}' | sort | uniq | wc -l`
        while [ $nruns -ge $n_cores ];
        do
          sleep 10s
          nruns=`ps axu | grep -e "run_ispaq.py" | grep -e  "--starttime" | awk '{print $19, $21, $23}' | sort | uniq | wc -l`
        done
        sleep 1s # wait so that IRIS web service will not be overwhelmed
        $ispaqCommand &
      else
        echo "No data folder for $year/$network/$station/$channels.? in archive $archiveDir"
      fi
    done
  done
}



############################## MAIN ############################################
# Don't change this
nrun=0

############################# Parameters ######################################
conda activate ispaq
binDir="/home/felix/repos/ispaq"
prefFile="/home/felix/repos/ispaq/preference_files/pref_UiB_test.txt"
inventory_stationxml="/home/felix/Documents2/ArrayWork/Inventory/NorSea_inventory_noResp.xml"

archiveDir="/data/seismo-wav/SLARCHIVE"
archiveDir="/data/seismo-wav/EIDA/archive"
emailadress="myself@my-domain.no"
metrics="all"
#metrics="simpleMetrics"
#metrics="psdPdf"
#metrics="pdf" # just redraw metrics
#metrics="crossTalk"
#metrics="missing"
n_cores=20
#channels="BH*"
#channels="HH*"
channels="*"

startyear=2019
endyear=2021

# missing metrics (e.g.crossTalk)	: BN, DK, GB, GE, HE, II, IM, IU, NO, PL, UP, UR, VI

network="NS"
lstations=(ASK BER BJO1 BLS5 DOMB EKO1 FAUS FOO GILDE HAMF HOMB HOPEN HYA JMI JMIN JNE \
           JNW KMY KONS KTK1 LEIR LOF LOSSI MOL MOR MOR8 NSS ODD1 ODLO OSL RAUS ROEST RUND \
           SKAR SNART STAV STEI STOK SUE TBLU TRO VADS VAGH VBYGD)
run_ispaq_on_network $startyear $endyear $network lstations[@]

################## define other networks + stations here
startyear=1990
endyear=2021
network="IU"
lstations=(KONO KBS KEV)
run_ispaq_on_network $startyear $endyear $network lstations[@]

tail -n50 ISPAQ_TRANSCRIPT.log >| ISPAQ_tail.dat
mail -s "ISPAQ script completed" $emailadress < ISPAQ_tail.dat

