#!/bin/sh --
# Copyright [2009-2014] EMBL-European Bioinformatics Institute
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

## We use this to run a sister script below
script_dir=`readlink -f $(dirname $0)`

## The first option to the script is the location for the co
dir=$1
if [ -z "$dir" ]; then
    echo "Usage: $0 <dir> [branch]" 1>&2
    exit 1
fi

## The second option is the branch to use (master by default)
branch="-b master"
if [ ! -z "$2" ]; then
    branch="-b $2"
fi

if [ ! -e "$dir" ]; then
    echo "Directory $dir does not exist - creating..." 1>&2
    mkdir -p $dir
fi

dir=$(readlink -f $dir)

echo "Creating Ensembl work directory in $dir"
echo

cd $dir

## Now checkout Ensembl
for module in \
    ensembl \
    ensembl-compara \
    ensembl-funcgen \
    ensembl-production \
    ensembl-rest \
    ensembl-tools \
    ensembl-variation
do
    echo "Checking out $module ($branch)"
    git clone $branch https://github.com/Ensembl/${module} || {
        echo "Could not check out Ensembl module $module" 1>&2
        exit 2
    }
    echo
    echo
done

## Now checkout hive, analysis and pipeline (no release branch!)
for module in \
    ensembl-hive \
    ensembl-analysis \
    ensembl-pipeline
do
    echo "Checking out $module (default branch)"
    git clone         https://github.com/Ensembl/${module} || {
        echo "Could not check out Ensembl module $module" 1>&2
        exit 2
    }
    echo
    echo
done

## Now checkout ensemblgenomes-api
echo "Checking out ensemblgenomes-api (default branch)"
git clone https://github.com/EnsemblGenomes/ensemblgenomes-api || {
    echo "Could not check out Ensembl module ensemblgenomes-api" 1>&2
    exit 2
}
echo
echo

echo "Checkout complete"

cd -

#echo "Creating a setup script"
#$script_dir/create_setup_script.sh $dir

