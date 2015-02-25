#!/usr/bin/env perl
=head1 submit_open_job_arrays.pl

=head2 Usage

  submit_open_job_arrays.pl -dryrun
  
  submit_open_job_arrays.pl 

=head2 Description

  This is a script you have to run in addition to how rulemanager is described in Ensembl's documentation.

  PBS on Barrine requires job arrays. This adaptation of the genebuild pipeline creates job arrays. Once enough jobs have been collected for an array, it is submitted to PBS. At the end of a run of rulemanager there may be job arrays left over that have not been submitted yet, because there weren't enough jobs to fill it up. 

=cut

my $dryrun;
=head3 -dryrun

  Run in dryrun mode. No changes will be made and not jobs submitted.

=cut
my $help;
=head3 -help

Prints this documentation.

=cut

use strict;
use Data::Dumper;
use Bio::EnsEMBL::Pipeline::BatchSubmission::BraemblPBS;

use BRAEMBL::DefaultLogger;
my $logger = &get_logger;

use Getopt::Long;

# Mapping of command line paramters to variables
my %config_hash = (
  "dryrun"             => \$dryrun,
  "help"               => \$help,
);

# Loading command line paramters into variables and into a hash.
my $result = GetOptions(
  \%config_hash, 
  'dryrun',
  'help',
);

if ($dryrun) {
  $logger->info('Running in dryrun mode. No changes will be made.');
} else {
  $logger->info('Not running in dryrun mode.');
}

if ($help) {
  $logger->info('Help requested.');
  system('perldoc', $0);
  exit;
}

my $queue = Bio::EnsEMBL::Pipeline::BatchSubmission::BraemblPBS->new();

my $submit_job_array_base_file_name = $Bio::EnsEMBL::Pipeline::BatchSubmission::BraemblPBS::job_array_basenames->{submit_job_array};

my $open_job_arrays_file = $queue->_get_open_job_arrays_file;

if (! -e $open_job_arrays_file) {
  $logger->fatal("Can't find file $open_job_arrays_file!");
  exit;
} else {
  $logger->info("Reading open job arrays from $open_job_arrays_file");
}

use File::Slurp;
my @open_job_directory = map { chomp; $_ } read_file( $open_job_arrays_file );

foreach my $directory (@open_job_directory) {

  chomp($directory);
  
  $logger->info("Looking in directory: $directory");
  
  my $submit_job_array_file = File::Spec->catfile($directory, $submit_job_array_base_file_name);
  
  if (! -e $submit_job_array_file) {
    $logger->warn(
      "Skipping directory: Can't find array submission file $submit_job_array_base_file_name in " 
      . $submit_job_array_file 
    );
    next DIR;
  }
  
  $logger->info("Submitting job array by running " . $submit_job_array_file);
  
  unless($dryrun) {
  
    sub Bio::EnsEMBL::Pipeline::BatchSubmission::BraemblPBS::job_array_dir {
      return _parse_job_array_root_dir_from_file_name($submit_job_array_file);
    }  
    $queue->_submit_job_array($directory);
  }
}

$logger->info("All directories done. Exiting.");
exit;

sub _parse_job_array_root_dir_from_file_name {

  my $s = shift;

  my $job_array_root_dir_found = $s =~ /^(\/.+?job_array_files)/;

  if ($job_array_root_dir_found) {

    my $job_array_root_dir = $1;
    return $job_array_root_dir;

  } else {
    die "Not found!\n";
  }
}
