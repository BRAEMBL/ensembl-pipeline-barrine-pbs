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

dir=$1
if [ -z "$dir" ]; then
    echo "Usage: $0 <dir> [branch]" 1>&2 
    exit 1
fi

dir=$(readlink -f $dir)
if [ ! -e "$dir" ]; then
    echo "Directory $dir does not exist" 1>&2
    exit 1
fi

setup_module_file=`readlink -f $dir/../environment.module`
setup_environment_file=`readlink -f $dir/../environment.bash`

# create module file in parallel w/ shell script
# module is a linux command, may not be present on mac??
echo -n > $setup_environment_file
echo "#%Module1.0" > $setup_module_file

current_dir=$PWD
cd $dir

echo 'module-whatis "enviromment for EnsEMBL databases"' >>$setup_module_file

echo "setenv ENSEMBL_ROOT_DIR $dir" >> $setup_module_file
echo "setenv ENSEMBL_CVS_ROOT_DIR $dir" >> $setup_module_file

echo "ENSEMBL_ROOT_DIR=$dir" >> $setup_environment_file
echo "ENSEMBL_CVS_ROOT_DIR=$dir" >> $setup_environment_file

for module in $(ls -d */); do
    module=$(readlink -f $dir/$module)
    if [ -d $module/modules ]; then
      echo "prepend-path PERL5LIB $module/modules" >> $setup_module_file
      echo "PERL5LIB=$module/modules:\$PERL5LIB" >> $setup_environment_file
    fi
    if [ -d $module/lib ]; then
      echo "prepend-path PERL5LIB $module/lib" >> $setup_module_file
      echo "PERL5LIB=$module/lib:\$PERL5LIB" >> $setup_environment_file
    fi
    if [ -d $module/bin ]; then
        echo "prepend-path PATH $module/bin" >> $setup_module_file
        echo "PATH=$module/bin:\$PATH" >> $setup_environment_file
    fi
    if [ -d $module/scripts ]; then
        echo "prepend-path PATH $module/scripts" >> $setup_module_file
        echo "PATH=$module/scripts:\$PATH" >> $setup_environment_file
    fi
done

if [ -d ./bioperl ]; then
    bioperl_module_path=$(readlink -f bioperl)
    echo "prepend-path PERL5LIB $bioperl_module_path" >> $setup_module_file
    echo "PERL5LIB=$bioperl_module_path:\$PERL5LIB" >> $setup_environment_file
fi

echo "export PERL5LIB ENSEMBL_ROOT_DIR ENSEMBL_CVS_ROOT_DIR PATH" >> $setup_environment_file

echo "To set up your environment run '. $setup_environment_file' or 'module load $setup_module_file'"

