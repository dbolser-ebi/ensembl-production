#!/bin/bash
# Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


#################################################
#                                               #
# Sanger Ensembl specific script to compute and #
# store Alternative splicing events in a core   #
# database.                                     #
# Author: Gautier Koscielny                     #
# e-mail: ensembl-dev mailing list              #
#                                               #
#################################################
 
port=3306
host=""
password=""
user=""
species=""
db=""
core=""
output_dir="/tmp"

print_help () { 
    echo "Usage:";
    echo "    as_event_computations.sh -h <dbhost> [-P <dbport>] -u <dbuser> [-p <dbpass>] -s <species> [-d <dbname>] [-o <output_dir>]";
    echo "";
    echo "If the species name is passed, the script will find the corresponding core database on <dbhost>.";
    echo "If the database name <dbname> is passed, the script will use this database as the core database.";
    echo "By default, all intermediate results will be written in the /tmp directory.";
    echo "Please use the -o parameter to pass a different existing writable directory.";
}

echo "Parsing parameters..."

while getopts ":h:u:p:P:s:d:o:" optname
  do
    #echo $optname
    case "$optname" in
      "h")
        echo "Hostname=$OPTARG";
				host=$OPTARG;
				echo $host
        ;;
      "o")
        echo "Output directory=$OPTARG";
				output_dir=$OPTARG;
        ;;
      "P")
        echo "Port=$OPTARG";
				port=$OPTARG;
        ;;
      "p")
        echo "Password=$OPTARG";
				password=$OPTARG;
        ;;
      "u")
        echo "User=$OPTARG";
				user=$OPTARG
        ;;
      "d")
        echo "Database=$OPTARG";
				db=$OPTARG
        ;;
      "s")
        echo "Species=$OPTARG";
				species=$OPTARG
        ;;
      "?")
        echo "Unknown option $OPTARG";
				print_help;
        ;;
      ":")
        echo "No argument value for option $OPTARG"
				print_help;
        ;;
      *)
      # Should not occur
        echo "Unknown error while processing options"
        ;;
    esac
    #echo "OPTIND is now $OPTIND"
  done

if [[ -n "$host" && -n "$user" ]]
then
  if [ -z "$db" ]
  then 
    if  [ -n "$species" ]
    then
      ## Find a core database for this species on the specified server.
	  if [[ -n "$password" && $password != "" ]]
	  then
				db=`mysql -h${host} -P${port} -u${user} -p${password} -s --skip-column-names -e "show databases like '${species}\_core\_%'"`
	  else
				db=`mysql -h${host} -P${port} -u${user} -s --skip-column-names -e "show databases like '${species}\_core\_%'"`
	  fi
    else
				echo "Species or/and database name are required." ;
				print_help;
				exit 1;
    fi
  else
			echo "Using ${db} as core database.";
  fi
else
		echo "Hostname and username are required."
		print_help;
		exit 1;
fi

# count how many databases match this name

y=0;

for X in ${db}
do
		y=$[$y+1];
done

if [[ ${y} -eq 0 ]]
then
		echo "Check your parameters, there is no database matching species '${species}'";
		exit 1;
fi


if [[ ${y} -gt 1 ]]
then
		echo "Check your parameters, there are ${y} databases matching species '${species}':";
		echo "${db}";
		exit 1;
fi

echo "Using ${db} as core database.";

# Otherwise, start the pipeline

NOW=$(date +"%Y-%m-%d-%H-%M-%S")

echo "Starting pipeline with timestamp '${NOW}'";

echo "Fetch the gene models from ${db}..."
if [ -n "$password" ]
then
		perl Fetch_gff.pl -dbname ${db} -dbhost ${host} -dbport ${port} -dbuser ${user} -dbpass ${password} -o ${output_dir}/${db}_${NOW}_variants.gff;
else
		perl Fetch_gff.pl -dbname ${db} -dbhost ${host} -dbport ${port} -dbuser ${user} -o ${output_dir}/${db}_${NOW}_variants.gff;
fi

echo "Compute the Alternative Splicing events";
altSpliceFinder -i ${output_dir}/${db}_${NOW}_variants.gff -o ${output_dir}/${db}_${NOW}_events.gff --relax --statistics

echo "Populate ${db} with alternative splicing information";

if [ -n "$password" ]
then
		perl load_alt_splice_gff.pl -file ${output_dir}/${db}_${NOW}_events.gff -host ${host} -user ${user} -pass ${password} -dbname ${db}

    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    meta_cmdline_opts="-dbhost ${host} -dbuser ${user} -dbpass ${password} -dbpattern ${db}"
    if [ -d $DIR/../../../ensembl ]; then
      echo "Running update_meta_coord.pl for this new data"
      perl $DIR/../../../ensembl/misc-scripts/meta_coord/update_meta_coord.pl $meta_cmdline_opts
    else
      echo "Cannot find the ensembl checkout directory. You can run the script yourself using the following command line"
      echo "perl misc-scripts/meta_coord/update_meta_coord.pl $meta_cmdline_opts"
    fi
else 
		echo "Sorry, you did not provide any password. The script can't populate the database with the Alternative splicing information.";
		echo "However, the results are available in ${output_dir}/${db}_${NOW}_events.gff";
fi

echo "All done.";
exit 0;
