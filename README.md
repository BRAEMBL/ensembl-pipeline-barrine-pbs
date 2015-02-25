How to set the pipeline up
==========================

Checkout
--------

```bash
git clone https://github.com/BRAEMBL/ensembl-pipeline-barrine-pbs
```

Bioperl
-------

```bash
wget http://bioperl.org/DIST/old_releases/bioperl-1.2.3.tar.gz
tar xzvf bioperl-1.2.3.tar.gz
```

Checkout Ensembl code
---------------------

Use the script checkout_ensembl.sh to get the ensembl code:

```bash
./ensembl-pipeline-barrine-pbs/scripts/checkout_ensembl.sh lib/
```

This creates a directory called "lib". Move the other libraries there:

```bash
mv bioperl-1.2.3 lib/bioperl
mv ensembl-pipeline-* lib/
```

Setup environment variables
---------------------------

Now that bioperl is in the lib directory too, the environment set up files have to be regenerated to include bioperl:

```bash
./lib/ensembl-pipeline-barrine-pbs/scripts/create_setup_script.sh lib/
```

There should now be an updated file environment.bash in your current directory. Source it to set your PERL5LIB and your PATH.

```bash
. environment.bash
```

Use the above command every time you want to set up your PERL5LIB and PATH to run the genebuild pipeline.

Apply schema patch
------------------

Before running the pipeline, apply the patch in

```bash
lib/ensembl-pipeline-barrine-pbs/sql/patch_job_array_submission_ids.sql
```

to you core database.

After running rulemanager
-------------------------

This is a step you have to run in addition to how rulemanager is described in Ensembl's documentation.

PBS on Barrine requires job arrays. This adaptation of the genebuild pipeline creates job arrays. Once enough jobs have been collected for an array, it is submitted to PBS. At the end of a run of rulemanager there may be job arrays left over that have not been submitted yet, because there weren't enough jobs to fill it up. These jobs can be submitted like this:

```bash
submit_open_job_arrays.pl
```

If you have configured analyses that depend on one of the current analyses to finish, you should run rulemanager again, so jobs can be created for the dependent analysis.

Ideally one day this script could be merged into rulemanager.


