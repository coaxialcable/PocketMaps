#!/bin/bash

##############################################################################
##
##  Starcommander@github.com
##  Pauls script to download and convert all maps!
##  The only manual steps:
##  - Import the mapfile-writer
##  - - See also https://github.com/mapsforge/mapsforge-creator
##  - Install: zip svn wget curl bc xmlstarlet
##  - Maybe you have to increase MEMORY_USE
##
##  ============= Steps that are executed automatically: ===========
##  Download the osm-maps from:
##  - http://download.geofabrik.de/
##  Import the map:
##  - ./graphhopper.sh import downloadedMap.osm.pbf
##  Download existing map file, or create the map file with osmosis tool:
##  - osmosis --rb file=/tmp/berlin.osm.pbf --mapfile-writer file=/tmp/berlin.map
##  - - See also http://wiki.openstreetmap.org/wiki/Osmosis/Installation
##  Create file city_nodes.txt for limited OfflineSearch (Geocoding)
##  Compress the content of mapdir-gh to mapdir.ghz
##  Copy map and create entry into json list and html file (server mode)
##
##  ============= Workaround to create SwapMemory ===============
##  These lines can be executed when not enought ram-memory exists on system.
##  This may slow down build process, but creates 4GB swap-memory.
##  > dd if=/dev/zero of=/tmp/swapfile1 bs=1024 count=4194304
##  > chown root:root /tmp/swapfile1
##  > chmod 0600 /tmp/swapfile1
##  > mkswap /tmp/swapfile1
##  > swapon /tmp/swapfile1
##
##############################################################################

WORK_DIR="/tmp/graphhopper_0-10-0/"
HOPPER_REP="https://github.com/graphhopper/graphhopper.git/tags/0.10.0"
GEO_TMP="/tmp/geofabrik-list.txt"
GEO_URL="http://download.geofabrik.de/"
MAP_URL="http://ftp-stud.hs-esslingen.de/pub/Mirrors/download.mapsforge.org/maps/v5/"
MAP_URL_ZIP_ALASKA="http://ftp.gwdg.de/pub/misc/openstreetmap/openandromaps//maps/usa/Alaska.zip"
MAP_DIR="/tmp/graphhopper_0-10-0/maps-osm/"
LINK_BRAZIL=$GEO_URL"south-america/brazil-latest.osm.pbf"
CONTINUE="ask"
MEMORY_USE="2048m"
SERVER_MAPS_DIR_DEFAULT="/var/www/html/maps/maps/"
SERVER_MAPS_DIR_DAYS=180
# Tags: VERSION_USED MANIPULATE

print_map_list() # Args europe|europe/germany
{
  curl "$GEO_URL$1.html" > "$GEO_TMP"
  local lineS=$(cat -n "$GEO_TMP" | grep "Sub Regions" | head -n 1 | awk '{ print $1; }')
  local content=$(cat "$GEO_TMP" | tail --lines="+$lineS")
  local hasSpecSubs=$(cat "$GEO_TMP" | grep "Special Sub Regions")
  if [ ! -z "$hasSpecSubs" ]; then
    local lineE=$(cat -n "$GEO_TMP" | grep "Special Sub Regions" | head -n 1 | awk '{ print $1; }')
    local lineE=$(echo "$lineE - $lineS" | bc)
    local content=$(echo "$content" | head --lines="$lineE")
  fi
  echo "$content" | grep -o 'href=".*-latest\.osm\.pbf\"'
}

check_exist() # Args: file|dir
{
  if [ ! -e "$1" ]; then
    echo "Error, path is missing: $1"
    exit 1
  fi
}

goto_graphhopper()
{
  export JAVA_OPTS="-Xmx$MEMORY_USE -Xms1000m -server"
  if [ -d "$WORK_DIR/gh" ]; then
    cd "$WORK_DIR/gh"
    return
  fi
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"
  echo "Checking out graphhopper repository, please wait ..."
  # VERSION_USED: graphhopper_0.10.0
  svn co "$HOPPER_REP"
  local hopper_dirname=$(basename "$HOPPER_REP")
  mv "$hopper_dirname" gh
  cd gh
  # MANIPULATE: The default config must be changed, because some flags are missing otherwise.
  # MANIPULATE: Also changed to use hdd instead of ram memory.
  # MANIPULATE: Also in PocketMaps: MapHandler.java: "shortest" must be added manually
  cp config-example.properties config.properties
  sed -i -e "s#^graph.flag_encoders=car\$#graph.flag_encoders=car,bike,foot#g" config.properties
  sed -i -e "s#^prepare.ch.weightings=fastest\$#prepare.ch.weightings=fastest,shortest#g" config.properties
  sed -i -e "s#^graph.dataaccess=RAM_STORE\$#graph.dataaccess=MMAP_STORE#g" config.properties
}

goto_osmosis()
{
  local work_tmp_dir="$WORK_DIR/osmosis_tmp"
  export JAVACMD_OPTIONS="-Xmx$MEMORY_USE -server -Djava.io.tmpdir=$work_tmp_dir"
  if [ ! -d "$work_tmp_dir" ]; then
    mkdir "$work_tmp_dir"
  fi
  if [ -d "$WORK_DIR/osmosis" ]; then
    cd "$WORK_DIR/osmosis"
    return
  fi
  mkdir -p "$WORK_DIR/osmosis"
  # VERSION_USED: osmosis-0.46.tgz and plugin mapsforge-map-writer-master-20171203.163155-186-jar-with-dependencies.jar
  wget http://bretth.dev.openstreetmap.org/osmosis-build/osmosis-latest.tgz -O "$WORK_DIR/osmosis/osmosis-latest.tgz"
  cd "$WORK_DIR/osmosis"
  tar xvfz osmosis-latest.tgz
  rm osmosis-latest.tgz
  chmod a+x bin/osmosis
}

printCityNodeLine() # args: key value
{
  if [ ! -z "$2" ]; then
    echo "$1=$2"
  fi
}

printCityNode() # args: cityNodes.osm counter/count start_line
{
  local node_start=$3
  local node_length=$(cat "$1" | tail --lines=+$node_start | grep --max-count=1 --line-number "^ *</node" | cut -d':' -s -f 1)
  local node_content=$(cat "$1" | tail --lines=+$node_start | head --lines=$node_length)

  local vLat=$(echo "$node_content" | xmlstarlet sel -t -v "/node/@lat")
  local vLon=$(echo "$node_content" | xmlstarlet sel -t -v "/node/@lon")
  local vName=$(echo "$node_content" | xmlstarlet sel -t -v "/node/tag[@k='name']/@v")
  local vNameEn=$(echo "$node_content" | xmlstarlet sel -t -v "/node/tag[@k='name:en']/@v")
  local vPostal=$(echo "$node_content" | xmlstarlet sel -t -v "/node/tag[@k='post']/@v")

  if [ -n "$vName$vNameEn" -a -n "$vLat" -a -n "$vLon" ]; then
    echo "name=$vName"
    printCityNodeLine "name:en" "$vNameEn"
    printCityNodeLine "post" "$vPostal"
    printCityNodeLine "lat" "$vLat"
    printCityNodeLine "lon" "$vLon"
    echo "CityNode $2: $vName" 1>&2
  fi
}

printCityNodes() # args: cityNodes.osm
{
  local node_start_lines=$(cat "$1" | grep --line-number "^ *<node" | cut -d':' -s -f 1)
  local node_count=$(echo "$node_start_lines" | wc -l)
  local node_up="1"
  for cur_city_node_line in $node_start_lines
  do
    printCityNode "$1" "$node_up/$node_count" "$cur_city_node_line"
    local node_up=$(echo "$node_up + 1" | bc)
  done
  echo "CityNode finish!" 1>&2
}

# Deletes doubles when newest file is at least one hour old.
clear_old_double_files() # args: Path/to/maps_dir
{
  local cur_tmp_file=$(mktemp)
  find "$1" -name "*.ghz" | xargs --max-args=1 basename | sort -u > "$cur_tmp_file"
  while read line ; do
    if [ -z "$line" ]; then
      continue
    fi
    local map_files=$(find "$1" -name "$line" | sort -r)
    local map_files_count=$(echo "$map_files" | wc -l)
    if [ $map_files_count -lt 2 ]; then
      continue
    fi
    local map_file_first=$(echo "$map_files" | head --lines=1)
    local last_mod=$(stat -c '%Y' "$map_file_first")
    local last_mod=$(echo "$(date +%s) - $last_mod" | bc)
    local one_hour="3600"
    if [ $last_mod -lt $one_hour ]; then
      continue
    fi
    find $1 -name "$line" -not -wholename "$map_file_first" -delete
  done < "$cur_tmp_file"
  rm "$cur_tmp_file"
}

import_map_box() # Args: lat1,lon1,lat2,lon2 /abs/path/cont_country.osm.pbf subName
{
  if [ -z "$3" ]; then
    echo "Args input error for map_box!"
    exit 1
  fi
  local target_file=$MAP_DIR$(basename "$2" | sed -e "s#.osm.pbf\$#-$3-latest.osm.pbf#g")
  
  local bbox_top=$(echo "$1" | cut -d',' -s -f 1)
  local bbox_left=$(echo "$1" | cut -d',' -s -f 2)
  local bbox_bottom=$(echo "$1" | cut -d',' -s -f 3)
  local bbox_right=$(echo "$1" | cut -d',' -s -f 4)
  local arg_bbox="--bounding-box top=$bbox_top left=$bbox_left bottom=$bbox_bottom right=$bbox_right"
  
  goto_osmosis
  ./bin/osmosis --rb file="$2" $arg_bbox --write-pbf file="$target_file"
  if [ "$?" != "0" ]; then
    echo "Osmosis returned an error, clearing file."
    rm "$target_file"
  fi

  local continent=$(basename "$2" | cut -d'_' -s -f 1)
  local country=$(basename "$2" | cut -d'_' -s -f 2 | cut -d'.' -s -f 1)
  check_exist "$target_file"
  import_map $(basename "$target_file")
}

import_map() # Args: map_url_rel
{
  local free_space=$(df --output=avail "$MAP_DIR" | sed 1d)
  if [ "$free_space" -lt 10000000 ]; then
    local free_space=$(df -h --output=size "$MAP_DIR" | sed 1d)
    echo "Error, low disk space: $free_space" 1>&2
    echo "Exiting."
    exit 2
  fi
  local start_time=$(date +%s)
  local map_file=$(echo "$1" | tr '/' '_')
  local gh_map_name=$(echo "$map_file" | sed -e 's/-latest.osm.pbf$//g')
  local gh_map_dir=$(echo "$map_file" | sed -e 's/-latest.osm.pbf$/-gh/g')
  local gh_map_file=$(echo "$map_file" | sed -e 's/-latest.osm.pbf$/.map/g')
  local gh_mapfile_path=$(echo "$1" | sed -e 's/-latest.osm.pbf$/.map/g') # WGET source file
  local gh_map_zip=$(echo "$map_file" | sed -e 's/-latest.osm.pbf$/.ghz/g')

  if [ -f "$MAP_DIR$gh_map_zip" ]; then
    echo "Allready existing: $gh_map_zip"
    return
  fi
  if [ ! -z "$SERVER_MAPS_DIR" ]; then
    local serv_map_file_new=$(find "$SERVER_MAPS_DIR" -name "$gh_map_zip" -mtime "-$SERVER_MAPS_DIR_DAYS")
    if [ ! -z "$serv_map_file_new" ]; then
      # There is already one actual file.
      return
    fi
    clear_old_double_files "$SERVER_MAPS_DIR"
  fi
  mkdir -p "$MAP_DIR"
  if [ ! -f "$MAP_DIR$map_file" ]; then
    wget "$GEO_URL$1" -O "$MAP_DIR$map_file"
  fi
  check_exist "$MAP_DIR$map_file"
  if [ ! -d "$MAP_DIR$gh_map_dir" ]; then
    goto_graphhopper
    ./graphhopper.sh import "$MAP_DIR$map_file"
    if [ "$?" != "0" ]; then
      echo "Graphhopper returned an error, clearing file."
      rm "$MAP_DIR$gh_map_name"-latest.osm-gh"/nodes_ch_fastest_car"
    elif [ -d "$MAP_DIR$gh_map_name"-latest.osm-gh ]; then
      mv "$MAP_DIR$gh_map_name"-latest.osm-gh "$MAP_DIR$gh_map_dir"
    fi
  fi
  check_exist "$MAP_DIR$gh_map_dir/nodes_ch_fastest_car"
  if [ ! -f "$MAP_DIR$gh_map_dir/$gh_map_file" ]; then
    goto_osmosis
    if wget -q --spider "$MAP_URL/$gh_mapfile_path" ; then
      #TODO: Check timestamp of source-file.
      wget "$MAP_URL/$gh_mapfile_path" -O "$MAP_DIR$gh_map_dir/$gh_map_file"
    elif [[ "$gh_map_file" == *"alaska.map" ]]; then
      #TODO: Check timestamp of source-file.
      local unzip_dir=$(mktemp -d)
      wget -q --spider "$MAP_URL_ZIP_ALASKA" && \
      wget "$MAP_URL_ZIP_ALASKA" -O "$unzip_dir/file.zip" && \
      unzip "$unzip_dir/file.zip" -d "$unzip_dir/" && \
      mv "$unzip_dir/"*.map "$MAP_DIR$gh_map_dir/$gh_map_file" && \
      rm -r "$unzip_dir"
    else
      ./bin/osmosis --rb file="$MAP_DIR$map_file" --mapfile-writer type=hd file="$MAP_DIR$gh_map_dir/$gh_map_file"
      if [ "$?" != "0" ]; then
        echo "Osmosis returned an error, clearing file."
        rm "$MAP_DIR$gh_map_dir/$gh_map_file"
      fi
    fi
    check_exist "$MAP_DIR$gh_map_dir/$gh_map_file"
    ./bin/osmosis --rb file="$MAP_DIR$map_file" \
                  --tf reject-relations \
                  --tf reject-ways \
                  --tf accept-nodes place=city,town,village \
                  --write-xml "$MAP_DIR$gh_map_dir/cityNodes.osm"
    if [ "$?" != "0" ]; then
      echo "Osmosis for cityNodes returned an error, clearing file."
      echo "" > "$MAP_DIR$gh_map_dir/cityNodes.osm"
    else
      cat "$MAP_DIR$gh_map_dir/cityNodes.osm" \
         | grep -o "<tag k=\"name\".*\|<node id=\".*\|<tag k=\".*postal_code.*\|</node>" \
         > "$MAP_DIR$gh_map_dir/cityNodes.txt"
      # TODO: cityNodes.txt is Deprecated! use the following city_nodes.txt instead
      printCityNodes "$MAP_DIR$gh_map_dir/cityNodes.osm" > "$MAP_DIR$gh_map_dir/city_nodes.txt"
    fi
    rm "$MAP_DIR$gh_map_dir/cityNodes.osm"
  fi
  if [ ! -f "$MAP_DIR$gh_map_zip" ]; then
    cd "$MAP_DIR$gh_map_dir"
    zip -r "$WORK_DIR$gh_map_zip" *
    rm -r -f "$MAP_DIR/$gh_map_dir" # Cleanup
    rm "$MAP_DIR/$map_file" # Cleanup
    mv "$WORK_DIR$gh_map_zip" "$MAP_DIR"
  fi
  check_exist "$MAP_DIR$gh_map_zip"
  local ghz_size=$(du -h "$MAP_DIR$gh_map_zip" | awk '{ print $1 }')
  local ghz_time=$(date +%Y-%m)
  local diff_time=$(date +%s)
  local diff_time=$(echo "$diff_time - $start_time" | bc)
  local diff_time_h=$(echo "$diff_time / 3600" | bc)
  local diff_time_m=$(echo "$diff_time / 60" | bc)
  local diff_time_m=$(echo "$diff_time_m % 60" | bc)
  echo "Duration: $diff_time_h h and $diff_time_m min"
  echo "Successful created: $gh_map_zip"
  
  ##### Store map-file and update json_file and html_file! #####
  if [ ! -z "$SERVER_MAPS_DIR" ]; then
    if [ ! -d "$SERVER_MAPS_DIR/$ghz_time" ]; then
      mkdir "$SERVER_MAPS_DIR/$ghz_time"
    fi
    mv "$MAP_DIR$gh_map_zip" "$SERVER_MAPS_DIR/$ghz_time/$gh_map_zip"
    touch "$MAP_DIR$gh_map_zip"
    
    ##### Update json #####
    echo "Todo: split map versions in json first!" #TODO: Split first json file because of different graphhopper-versions!
    local json_line="    { \"name\": \"$gh_map_name\", \"size\": \"$ghz_size\", \"time\": \"$ghz_time\" }"
    local json_file=$(dirname "$SERVER_MAPS_DIR")/map_url_json
    local json_key="^    { \"name\": \"$gh_map_name\".*,\$"
    local json_comma=","
    local json_pre=""
    local has_comma=$(grep "$json_key" "$json_file")
    if [ -z "$has_comma" ]; then
      local json_key="^    { \"name\": \"$gh_map_name\".*"
      local json_comma=""
      local has_comma=$(grep "$json_key" "$json_file")
      if [ -z "$has_comma" ]; then
        local json_key="^  \["
        local json_comma=","
        local json_pre="  [\n"
      fi
    fi
    sed -i -e "s#$json_key#$json_pre$json_line$json_comma#g" "$json_file"
    
    ##### Update html #####
    local html_line="    <li><a href=\"maps/$ghz_time/$gh_map_zip\">$ghz_time $gh_map_zip</a>\&emsp;size:$ghz_size"" build_duration=$diff_time_h""h $diff_time_m min</a></li>"
    local html_file=$(dirname "$SERVER_MAPS_DIR")/index.html
    local html_key="^    <li><a href=\"maps/[0-9][0-9][0-9][0-9]-[0-9][0-9]/$gh_map_zip\".*"
    local html_post=""
    local has_line=$(grep "$html_key" "$html_file")
    if [ -z "$has_line" ]; then
      local html_key="^  </body>\$"
      local html_post="\n  </body>"
    fi
    sed -i -e "s#$html_key#$html_line$html_post#g" "$html_file"
  fi
}

import_split_box() # Args: lat1,lon1,lat2,lon2 /abs/path/cont_country.osm.pbf subName dlLink bClearDl
{
  local target_name=$(basename "$2" | sed -e "s#.osm.pbf\$#-$3#g")
  if [ "$CONTINUE" = "ask" ]; then
    echo "Finish! Get the maps from $MAP_DIR"
    echo "=================================="
    echo "Starting with map $target_name"
    echo "Continue? y=yes b=break a=yesToAll"
    echo "          s=skip"
    read -e -p ">>>" ANSWER
    if [ "$ANSWER" = "b" ]; then
      echo "Stop by user, exiting."
      exit 0
    elif [ "$ANSWER" = "a" ]; then
      CONTINUE="yesToAll"
    elif [ "$ANSWER" = "s" ]; then
      return
    elif [ "$ANSWER" = "y" ]; then
      echo "Continue ..."
    else
      echo "Unknown user input, exiting."
      exit 1
    fi
  fi
  if [ ! -e "$2" ]; then
    wget "$4" -O "$2"
  fi
  check_exist "$2"
  import_map_box "$1" "$2" "$3"
  if [ "$5" = "true" ]; then
    rm "$2"
  fi
}

import_continent() # Args europe|europe/germany
{
  local isCountry=$(echo "$1" | grep "/")
  local full_list=$(print_map_list "$1" | cut -d'"' -s -f 2)
  for curUrl in $full_list ; do
    if [ "$CONTINUE" = "ask" ]; then
      echo "Finish! Get the maps from $MAP_DIR"
      echo "=================================="
      echo "Starting with map $curUrl"
      echo "Continue? y=yes b=break a=yesToAll"
      echo "          s=skip w=skipWhooleContinent"
      read -e -p ">>>" ANSWER
      if [ "$ANSWER" = "b" ]; then
        echo "Stop by user, exiting."
        exit 0
      elif [ "$ANSWER" = "a" ]; then
        CONTINUE="yesToAll"
      elif [ "$ANSWER" = "s" ]; then
        continue
      elif [ "$ANSWER" = "w" ]; then
        break
      elif [ "$ANSWER" = "y" ]; then
        echo "Continue ..."
      else
        echo "Unknown user input, exiting."
        exit 1
      fi
    fi
    if [ -z "$isCountry" ]; then
      import_map "$curUrl"
    else
      local continent=$(echo "$1" | cut -d'/' -s -f 1)
      import_map "$continent/$curUrl"
    fi
  done
}

if [ "$1" = "-i" ]; then
  echo "Starting ..."
elif [ "$1" = "-si" ]; then
  SERVER_MAPS_DIR="$SERVER_MAPS_DIR_DEFAULT"
elif [ "$1" = "-s" ]; then
  SERVER_MAPS_DIR="$SERVER_MAPS_DIR_DEFAULT"
  CONTINUE="yesToAll"
elif [ "$1" = "-g" ]; then
  import_map_box "$2" "$3" "$4"
  echo "Finish! Get the maps from $MAP_DIR"
  exit 0
else
  echo "The server mode ensures to update html-file and json-list-file."
  echo "Also server mode copies the maps to server path: SERVER_MAPS_DIR_DEFAULT"
  echo "Interactive asks for each map to import, skip or importAll"
  echo "======================================="
  echo "Usage:"
  echo "For interactive mode enter: $0 -i"
  echo "For server mode enter: $0 -s"
  echo "For interactive server mode enter: $0 -si"
  echo "For import desired geo-box enter:"
  echo "     -g top,left,bottom,right /abs/path/cont_country.osm.pbf subName"
  echo "     (example: -g 5.2,-74.0,-13.7,-46.0 /tmp/south-america_brazil.osm.pbf north)"
  exit 0
fi

### Skip files that are too big at once ###
touch "$MAP_DIR/russia.ghz"
touch "$MAP_DIR/europe_germany.ghz"
touch "$MAP_DIR/europe_italy.ghz"
touch "$MAP_DIR/europe_france.ghz"
touch "$MAP_DIR/north-america_canada.ghz"
touch "$MAP_DIR/south-america_brazil.ghz"

### Start imports ###
import_continent europe
import_continent africa
import_continent asia
import_continent australia-oceania
import_continent central-america
import_continent north-america
import_continent south-america
import_continent russia
import_continent europe/germany
import_continent europe/italy
import_continent europe/france
import_continent north-america/canada
import_split_box -21.9,-57.8,-33.8,-47.7 /tmp/south-america_brazil.osm.pbf s "$LINK_BRAZIL" false
import_split_box -14.2,-52.9,-25.5,-39.5 /tmp/south-america_brazil.osm.pbf se "$LINK_BRAZIL" false
import_split_box  -0.7,-48.4,-18.3,-34.6 /tmp/south-america_brazil.osm.pbf ne "$LINK_BRAZIL" false
import_split_box   5.2,-74.0,-13.7,-46.0 /tmp/south-america_brazil.osm.pbf n "$LINK_BRAZIL" false
import_split_box  -7.4,-61.5,-24.0,-45.9 /tmp/south-america_brazil.osm.pbf cw "$LINK_BRAZIL" true

echo "Finish! Get the maps from $MAP_DIR"
