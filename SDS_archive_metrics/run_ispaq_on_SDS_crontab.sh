#!/bin/bash

# wrapper script to run the ispaq-python scripts more efficiently.
# When running ispaq on a large archive, the filename matching becomes extremely slow and slows
# down the whole program. This wrapper script starts ispaq with additional parameters that confine ispaq's 
# file search to smaller subdirectories.

# Author: Felix Halpaap, 2021

# function defintion
run_ispaq_on_network () {
  metrics="${1}"
  startday="${2}"
  endday="${3}"
  declare -a net_stations=("${!4}")

  echo "Starting up to $n_cores runs simultaneously"
  #loop over years and stations in network
  startyear=$(echo $startday | awk '{print substr($0,1,4)}')
  endyear=$(echo $startday | awk '{print substr($0,1,4)}')
    for net_station in "${net_stations[@]}";
    do
      network=$(echo $net_station | awk -F"." '{print $1}')
      station=$(echo $net_station | awk -F"." '{print $2}')
      echo "Starting ispaq for $network.$station"
      # check if stations /channel folders exist with wildcard
      if compgen -G "$archiveDir/$endyear/$network/$station/$channels.?" > /dev/null; then
        # Define the command to start ispaq for one year at one station
        ispaqCommand="python2 -u $binDir/run_ispaq.py -P $prefFile \
          -M $metrics -S $network.$station.*.$channels \
           --starttime "$startday"T00:00:00 --endtime  "$endday"T23:59:59 \
          --dataselect_url $archiveDir/$endyear/$network/$station \
          --station_url $inventory_stationxml"
        echo $ispaqCommand
        # check how many unique ispaq-commands are running
        nruns=`ps axu | grep -e "run_ispaq.py" | awk '{print $19, $21, $23}' | sort | uniq | wc -l`
        while [ $nruns -ge $n_cores ];
        do
          sleep 3s
          nruns=`ps axu | grep -e "run_ispaq.py" | awk '{print $19, $21, $23}' | sort | uniq | wc -l`
        done
        sleep 1s # wait so that IRIS web service will not be overwhelmed by requests
        $ispaqCommand > /dev/null &
      else
        echo "No data folder for $endyear/$network/$station/$channels.? in archive $archiveDir"
      fi
    done
}


wait_for_ispaq_complete () {
  # Function to wait for the completion of some ispaq-runs
  # input: date that is contained within command to invoke the relevant ispaq-runs
  endday="${1}"
  nruns=`ps axu | grep -e "run_ispaq.py"  | grep -e "--starttime" | grep -e "$endday" | sort -n | uniq | wc -l`
  while [ $nruns -ge 1 ];
  do
    sleep 5s
    nruns=`ps axu | grep -e "run_ispaq.py"  | grep -e "--starttime" | grep -e "$endday" | sort -n | uniq | wc -l`
  done
}


# Function to crop the PDF plots and resize them to a size that fits well for browser display
resize_crop_pdf_plots () {
  # input: $1: startday for PDF aggregation to plot
  #        $2: endday for PDF aggregation to plot
  startday="${1}"
  endday="${2}"
  declare -a net_stations=("${!3}")
  startyear=$(echo $startday | awk '{print substr($0,1,4)}')
  endyear=$(echo $startday | awk '{print substr($0,1,4)}')
  for net_station in "${net_stations[@]}";  do
    network=$(echo $net_station | awk -F"." '{print $1}')
    station=$(echo $net_station | awk -F"." '{print $2}')
    echo "Resizing PDF plots for $network.$station"
    # PDFs/NS/BER/NS.BER.00.HHE.2021-01-25_2021-02-23_PDF.png
    pdf_plot_form=PDFs/"$network"/"$station"/"$network"."$station".*."$channels"."$startday"_"$endday"_PDF.png
    if compgen -G $pdf_plot_form > /dev/null; then
      for pdf_plot in $(ls -d $pdf_plot_form); do
        echo "/usr/bin/convert -resize 60% -quality 100 -trim -border 8x8 -bordercolor White $pdf_plot tmp.png"
        /usr/bin/convert -resize 60% -quality 100 -trim -border 8x8 -bordercolor White $pdf_plot tmp.png
        echo "mv tmp.png $pdf_plot"
        mv tmp.png $pdf_plot
      done
    fi
  done
}


# Function to append the newly calculated metrics to the base-file for each station
append_new_metrics_to_file () {
  day="${1}"
  declare -a net_stations=("${!2}")
  for net_station in "${net_stations[@]}";
  do
    network=$(echo $net_station | awk -F"." '{print $1}')
    station=$(echo $net_station | awk -F"." '{print $2}')
    echo "Appending metrics for today's calculations for $network.$station"
    csv_files=($(ls csv/*_"$network"."$station".x.x_*"$day"_[[:alpha:]]*.csv 2> /dev/null))
    #csv_files=($(ls csv/*_"$network"."$station".x.x_????-??-??_"$day"_[[:alpha:]]*.csv 2> /dev/null))
    for csv_file in "${csv_files[@]}";
    do
      prefix=$(echo $csv_file | awk -F"_" '{print $1}')
      prefix2=$(echo $csv_file | awk -F"_" '{print $2}')
      midfix=$(echo $csv_file | awk -F"_" '{print $(NF-1)}')
      #midfix2=$(echo $csv_file | awk -F"_" '{print $4}')
      suffix=$(echo $csv_file | awk -F"_" '{print $NF}')
      # previous_csv_file=$(ls -d "$prefix"_"$prefix2"_????-??-??_????-??-??_"$suffix" 2> /dev/null)
      # glob into bash-array
      previous_csv_files=("$prefix"_"$prefix2"_????-??-??_????-??-??_"$suffix")
      # Get latest csv-file
      previous_csv_file=${previous_csv_files[-1]}
      # Check that the latest csv-file is not itself - otherwise, get 2nd latest csv file
      if [ "$previous_csv_file" == "$csv_file" ]; then
        previous_csv_file=${previous_csv_files[-2]}
      fi
      if [ ! -z "$previous_csv_file" ] && [ -f $previous_csv_file ]; then
         awk 'NR>1{print $0}' $csv_file  >> $previous_csv_file
         prev_midfix=$(echo $previous_csv_file | awk -F"_" '{print $3}')
         new_csv_file="$prefix"_"$prefix2"_"$prev_midfix"_"$midfix"_"$suffix"
         echo "$previous_csv_file >| $new_csv_file"
         mv $previous_csv_file $new_csv_file
      else
         cat $csv_file  >| "$prefix"_"$prefix2"_"$midfix"_"$midfix"_"$suffix"
      fi
      rm $csv_file
    done
  done
}



############################## MAIN ############################################
# Adjust to your setup
nrun=0
export SHELL="/usr/bin/bash"
export BASH_ENV="/home/seismo/.bashrc_conda"
# /opt/miniconda3/condabin/conda init
source /opt/miniconda3/bin/activate ispaq

############################# Parameters ######################################
binDir="/home/user/repos/ispaq"
prefFile="/home/user/repos/ispaq/preference_files/pref_UiB_cron.txt"
archiveDir="/data/seismo-wav/SLARCHIVE"

# Inventory: this could instead be changed to the FDSN-station-WS later if that has all the updated station information.
inventory_stationxml="/home/felix/Documents2/ArrayWork/Inventory/Inventory_noResp.xml"
emailadress="myself@mydomain.no"
metrics="all" # This  set of metrics is without plotting
#metrics="simpleMetrics"
#metrics="psdPdf"
#metrics="pdf" # just redraw metrics
#metrics="crossTalk"
#metrics="missing"
n_cores=16
channels="*"


######################## RUN ################################################

# 00:00 six days ago until eveneing of yesterdauy
startdate_yesterday=$(date -d "yesterday" '+%Y-%m-%d')
enddate_yesterday=$(date -d "yesterday" '+%Y-%m-%d')

# read in station list from station_list.dat
IFS=$'\r\n' GLOBIGNORE='*' command eval  'lstations=($(cat station_list_full.dat))'

# compute all metrics for yesterday
run_ispaq_on_network $metrics $startdate_yesterday $enddate_yesterday lstations[@]
# Wait until all ispaq-runs are completed
wait_for_ispaq_complete $enddate_yesterday
# Append new metrics to csv-files
append_new_metrics_to_file $enddate_yesterday lstations[@]
# Now replot the PDF for the last 7 days
run_ispaq_on_network pdf $startdate_lastweek $enddate_yesterday lstations[@]
wait_for_ispaq_complete
resize_crop_pdf_plots $startdate_lastweek $enddate_yesterday lstations[@]
# Now replot the PDF for the last 30 days
run_ispaq_on_network pdf $startdate_30days_ago $enddate_yesterday lstations[@]
wait_for_ispaq_complete
resize_crop_pdf_plots $startdate_30days_ago $enddate_yesterday lstations[@]

# email a bit of a summary to me
tail -n50 ISPAQ_TRANSCRIPT.log >| ISPAQ_tail.dat
mail -s "ISPAQ script completed network $network" $emailadress < ISPAQ_tail.dat

# Save log file
mv ISPAQ_TRANSCRIPT.log Logs/ISPAQ_TRANSCRIPT_"$enddate_yesterday".log
