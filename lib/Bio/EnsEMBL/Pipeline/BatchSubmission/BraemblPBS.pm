package Bio::EnsEMBL::Pipeline::BatchSubmission::BraemblPBS;
=head1 Bio::EnsEMBL::Pipeline::BatchSubmission::BraemblPBS

  Module with code allowing the genebuild pipeline to be run on Barrine.
  
  Note: For job tracking to work with job arrays, you have to run
  
  alter table job modify column submission_id varchar(60)  

=cut

use warnings;
use Bio::EnsEMBL::Pipeline::BatchSubmission;
use Bio::EnsEMBL::Utils::Exception qw(throw warning stack_trace_dump stack_trace verbose deprecate info try catch);
use Bio::EnsEMBL::Pipeline::Config::General;
use Bio::EnsEMBL::Pipeline::Config::BatchQueue;
use vars qw(@ISA);
use strict;

@ISA = qw(Bio::EnsEMBL::Pipeline::BatchSubmission);

=head2 Constants

  The following constants configure how this module generates the job arrays
  for barrine.
  
=cut

=head3 max_number_of_jobs_in_current_job_array

  The maximum number of jobs that can go into a job array file. If there are 
  more commands to be done, they will go into a new file.

=cut
my $max_number_of_jobs_in_current_job_array = 100;

=head3 max_job_arrays

  The maximum number of job arrays that can be in the queue. If this number
  is exceeded, then no new jobs will be submitted.
  
  Only done, if "-dbload 1" is set when running rulemanager.

=cut
my $max_job_arrays = 10;

=head3 testrunner_command_file_basename

  Name of the file into which the commands to be executed in a job array will 
  be written.

=cut
my $testrunner_command_file_basename = 'testrunner_commands.bash';

our $job_array_basenames = {

  # Command run to submit the job array to PBS.
  #
  submit_job_array        => 'submit_job_array.bash',
  
  # Name of the file into which the commands to be executed in a job array will 
  # be written.
  #
  testrunner_command_file => 'testrunner_commands.bash',
  
  # Command executed by PBS on the cluster. Picks a line from 
  # testrunner_command_file indexed by the PBS_ARRAY_INDEX and
  # executes it.
  #
  job_feeder              => 'job_feeder.bash',

};

=head3 run_job_arrays_when_ready

  If set, job arrays will be submitted, once a batch is ready for submission 
  to PBS.

=cut
my $run_job_arrays_when_ready = 1;

my $default_max_tries = 10;
my $default_num_tries =  0;
my $default_sleep_time_between_tries = 60;

=head3 max_number_of_jobs_allowed_in_queue

  If "-dbload 1" is set when running rulemanager for the pipeline and there 
  are more than this number of jobs in the queue, no more jobs will be 
  submitted. All jobs count, not job arrays.

=cut
my $max_number_of_jobs_allowed_in_queue = 400;


# Global variables used in the module
#
# These should not be set by the user.
#
# The number of jobs in the job array that is currently being created. By 
# using this we don't have to count every time.
#
my $LAST_KNOWN_NUMBER_OF_JOBS_IN_JOB_ARRAY = undef;

# Hack to save having to find this every time a new command has been 
# generated.
#
# Finding this number involves running ls on a directory that can be large,
# so hopefully caching this information speeds up command generation.
#
# We must remember to update this when starting a new job array file.
#
#my $LAST_KNOWN_ARRAY_NUMBER_USED = undef;
#
# End of Global variables used in the module

sub DESTROY {

#   print "\n------------------------------------------------\n";
#   print "\n Destroy method called! \n";
#   print "\n------------------------------------------------\n";

}

sub qsub {
    my ( $self, $qsub_line ) = @_;

    if ( defined($qsub_line) ) {
        $self->{_qsub} = $qsub_line;
    }
    return $self->{_qsub};
}

=head3 job_array_dir

  This is the directory in which the files defining the job arrays will be
  written. Every job array is known by a number. The files belonging to the
  job array go into a subdirectory of job_array_dir and the name of the
  subdirectory is the number the job array goes by.

=cut
sub job_array_dir {

  my $self = shift;
  my $batch_queue_entry = $self->batch_queue_entry;
  
  use Digest::MD5 qw(md5_hex);
  
  my $everything_that_influences_the_resource_requirements = join '_', grep { $_ } (
    $self->parameters,
    $self->pre_exec,
    $self->queue,
    $self->resource,
  );

  my $array_subdir = md5_hex($everything_that_influences_the_resource_requirements);  
  
  my $output_dir = $batch_queue_entry->{output_dir};
  
  if (!$output_dir) {
    $output_dir = File::Spec->catfile(
      $DEFAULT_OUTPUT_DIR, 
      $batch_queue_entry->{logic_name}
    );
  }

  return File::Spec->catfile(
    $output_dir,
    $array_subdir,
    'job_array_files',
  );
}

sub last_used_array_number_file {

  my $self = shift;
  return File::Spec->catfile($self->job_array_dir, 'last_used_array_number.txt');

}

sub _run_with_retries {

  my $self  = shift;
  my $param = shift;

  my $max_tries                = $param->{max_tries};
  my $num_tries                = $param->{num_tries};
  my $run_cmd                  = $param->{run_cmd};
  my $sleep_time_between_tries = $param->{sleep_time_between_tries};
  my $accepted_exit_values     = $param->{accepted_exit_values};
  
  my $output;

  while ($num_tries<$max_tries) {

    $num_tries++;
    eval {
      $output = System::ShellRunner::run_cmd($run_cmd, undef, $accepted_exit_values);
    };
    if ($@) {
      print "The command\n\n$run_cmd\n\nhas failed. It has been tried "
      . "$num_tries times. We will try a total of $max_tries times.\n";
      print "The problem was:$@\n";
      print "Now sleeping for $sleep_time_between_tries seconds.\n";
      #sleep($sleep_time_between_tries);
      $self->_sleep_with_status_report($sleep_time_between_tries);
      print "Waking up and retrying.\n";
    } else {
      last;
    }
  }
  return $output;
}

sub _sleep_with_status_report {

  my $self                   = shift;
  my $seconds_to_sleep       = shift;
  my $seconds_to_next_status = 1;
  
  my $seconds_left_to_sleep = $seconds_to_sleep;
  
  while ($seconds_left_to_sleep>0) {
  
    print "$seconds_left_to_sleep ";
    sleep($seconds_to_next_status);
    $seconds_left_to_sleep -= $seconds_to_next_status;
  }
}

sub fetch_job_ids_in_queue {

  my $self = shift;
  
  # Can't use grep to filter straight away, because grep returns an exit code 
  # for failure, when it doesn't find anything. However, the user might 
  # genuinely not have any jobs running and this must not be interpretd as an
  # error. Therefore the grep has been moved into perl further down.
  #
  #my $command = "qstat -1tnwu $ENV{USER} | grep \" R \" | cut -f 1 -d \" \" | grep -P \"^\\d\"" ;  
  #my $command = "qstat -1tnwu $ENV{USER} | grep \" R \" | cut -f 1 -d \" \"" ;
  my $command = "qstat -1tnwu $ENV{USER} | cut -b 1-31,113-114" ;
  #qstat -1ntw | head -n 30 | cut -b 1-31,113-114
  #   
  # Output from command looks like this:
  # 
  #   paroo3: 
  # 
  #   Job ID                         S 
  #   ------------------------------ - 
  #   1150615.paroo3                 E 
  #   1185397.paroo3                 Q 
  #   1215308.paroo3                 H 
  #   1215318.paroo3                 H 
  #   1215326.paroo3                 H 
  #   1228622.paroo3                 Q 
  #   1228896.paroo3                 H 
  #   1235124[].paroo3               H 
  #   1235124[0].paroo3              Q 
  #   1235124[1].paroo3              Q 
  #   1235124[2].paroo3              Q 
  #   1235124[3].paroo3              Q 
  #   1235124[4].paroo3              Q 
  #   1235124[5].paroo3              Q 
  #   1235124[6].paroo3              Q 
  
  #my $run_cmd   = "/home/genebuild/ensembl_genebuild_pogona/pogona_code/scripts/timeout.pl $command 2>&1";
  my $run_cmd   = "timeout.pl $command 2>&1";

  my $output = $self->_run_with_retries({
    max_tries => $default_max_tries,
    num_tries => $default_num_tries,
    sleep_time_between_tries => $default_sleep_time_between_tries,
    run_cmd   => $run_cmd,
  });
  
  my @line = 
    # grep done in perl now instead of the command line to avoid confusion
    # with grep's exit codes.
    #
    grep { /^\d/ }
    split "\n", $output;  
  
  my %existing_ids;

  LINE: while (my $current_line = shift @line) {
  
    chomp $current_line;
  
    (
      my $current_job_id_field,
      my $current_status
    )
      = split / +/, $current_line
    ;
    
    last LINE
      if ( $current_line eq '');

    # This should not be set to 1, but to the status.
    # RuleManager uses this to count pending jobs.
    #
    $existing_ids{ $current_job_id_field } = $current_status;
      
#     my $job_id_found = $current_job_id_field =~ /^(.+)\./;    
#     if ( $job_id_found ) {
#       $existing_ids{ $1 } = 1;
#       #$existing_ids{ $current_job_id_field } = 1;
#     } else {
#       next LINE;
#     }
  }
  return \%existing_ids;
}

sub check_existence {
  my ( $self, $id_hash, $verbose ) = @_;

  my %job_submission_ids = %$id_hash;  
  my %existing_ids = %{$self->fetch_job_ids_in_queue};
  
  my @awol_jobs;
  foreach my $job_id ( keys(%job_submission_ids) ) {
    if ( !$existing_ids{$job_id} ) {
      push( @awol_jobs, @{ $job_submission_ids{$job_id} } );
    }
  }  
  return \@awol_jobs;
} 

sub _create_array_subdirectory_name_by_job_array_number {

  my $self   = shift;
  my $number = shift;

  # Using binary, but decimal would do to.
  my $as_binary = sprintf("%b", $number);
  
  # Reversing makes the directories in the beginning change more
  # often. That way the data is better distributed across the
  # directories.
  #
  my @subdirectories = split '', reverse $as_binary;
  
  return File::Spec->catfile(@subdirectories);
}

sub _create_array_directory_name_by_job_array_number {

  my $self   = shift;
  my $job_array_number = shift;
  
  return File::Spec->catfile(
    $self->job_array_dir, 
    $self->_create_array_subdirectory_name_by_job_array_number($job_array_number)
  );
}

sub _get_last_known_array_directory_name {

  my $self   = shift;

  my $job_array_number = $self->_get_last_used_array_number;
  return $self->_create_array_directory_name_by_job_array_number($job_array_number);
}

sub _get_current_array_directory_name {

  my $self   = shift;

  my $job_array_number = $self->_get_current_job_array_number;
  return $self->_create_array_directory_name_by_job_array_number($job_array_number);
}

sub _get_created_job_arrays_file {
  return File::Spec->catfile( $DEFAULT_OUTPUT_DIR, 'job_arrays_created.txt' );
}
sub _get_submitted_job_arrays_file {
  return File::Spec->catfile( $DEFAULT_OUTPUT_DIR, 'job_arrays_submitted.txt' );
}
sub _get_open_job_arrays_file {
  return File::Spec->catfile( $DEFAULT_OUTPUT_DIR, 'job_arrays_open.txt' );
}
  
=head3 _save_as_job_array_directory_created

  Remember job arrays that have been started, but not submitted yet. If there 
  are no more jobs in the pipeline, they have to be submitted.

=cut
sub _save_as_job_array_directory_created {

  my $self = shift;
  my $current_job_array_dir = shift;
  
  my $job_array_registry_file = $self->_get_created_job_arrays_file;
  
  use File::Basename;
  my $dirname = dirname($job_array_registry_file);
  
  if (! -d $dirname) {
    use File::Path qw( mkpath );
    mkpath($dirname);
  }

  open OUT, ">>$job_array_registry_file";
  print OUT $current_job_array_dir;
  print OUT "\n";
  close OUT;
  
  $self->_update_open_job_arrays_file;
}
  
=head3 _save_as_job_array_directory_submitted

  Remove a job array from the registry file.
  
  In first instance we will just create a new file with the removed ones.

=cut
sub _save_as_job_array_directory_submitted {

  my $self = shift;
  my $current_job_array_dir = shift;
  
  my $job_array_registry_file = $self->_get_submitted_job_arrays_file;
  
  open OUT, ">>$job_array_registry_file";
  print OUT $current_job_array_dir;
  print OUT "\n";
  close OUT;
  
  $self->_update_open_job_arrays_file;
}

sub _update_open_job_arrays_file {

  my $self = shift;
  my $open_job_arrays_file = $self->_get_open_job_arrays_file;
  
  if (! -e $self->_get_submitted_job_arrays_file) {
    System::ShellRunner::run_cmd("touch " . $self->_get_submitted_job_arrays_file);
  }
  if (! -e $self->_get_created_job_arrays_file) {
    System::ShellRunner::run_cmd("touch " . $self->_get_created_job_arrays_file);
  }

  my $cmd = qq(diff --changed-group-format='%>' --unchanged-group-format='' )  
    . $self->_get_submitted_job_arrays_file  
    . qq( )
    . $self->_get_created_job_arrays_file  
    . qq( > )
    . $open_job_arrays_file
  ;

  $self->_run_with_retries({
    max_tries => $default_max_tries,
    num_tries => $default_num_tries,
    sleep_time_between_tries => $default_sleep_time_between_tries,
    run_cmd   => $cmd,
    
    # Diff command can run successfully, but return non zero exit code, so
    # the run method has to be prepared for this.
    #
    accepted_exit_values => [-1, 0, 1],
  });
}

sub construct_command_line {
  my ($self, $command, $stdout, $stderr) = @_; 
  
  if(!$command){
    throw("cannot create qsub if nothing to submit to it : $!\n");
  }
  my $qsub_options = "-V";
   $qsub_options .= " -q ".$self->queue    if $self->queue;
   
   # Maximal length of string allowed for -N is 15 characters, so trunctating
   # here.
   $qsub_options .= " -N ". substr($self->jobname, -15)  if $self->jobname;
   $qsub_options .= " ".$self->parameters." "  if defined $self->parameters;
   
  if($stdout){
    $command .= " >${stdout}.\${PBS_ARRAY_INDEX} ";
  } elsif ($self->stdout_file) {
    $command .= " >".$self->stdout_file.".\${PBS_ARRAY_INDEX} ";
  }
  if($stderr){
    $command .= " 2>${stderr}.\${PBS_ARRAY_INDEX} ";
  } elsif ($self->stderr_file) {
    $command .= " 2>".$self->stderr_file.".\${PBS_ARRAY_INDEX} ";
  }  

  use File::Path qw( mkpath );

  my $current_job_array_dir = $self->_get_current_array_directory_name;
  
  info("Working directory for the current job array is: $current_job_array_dir");
  
  my $current_job_array_file = File::Spec->catfile($current_job_array_dir, $testrunner_command_file_basename);
    
  if ( ! -d $current_job_array_dir ) {   
    
    info("The directory doesn't exist, so creating $current_job_array_dir");
    
    mkpath($current_job_array_dir);
    $self->_save_as_job_array_directory_created($current_job_array_dir);
    
    # Create job feeder script immediately. When it is run, it will submit 
    # the job array, regardless of what state it is in.
    #
    my $job_feeder_script = $self->_create_job_feeder_script({
      work_dir     => $current_job_array_dir,
      command_file => $current_job_array_file,
    });
    
    my $job_feeder_file_name = File::Spec->catfile($current_job_array_dir, "job_feeder.bash");
       
    my $current_job_array_feeder_file = File::Spec->catfile($current_job_array_dir, "job_feeder.bash");
    
    open OUT, ">$current_job_array_feeder_file";
    print OUT $job_feeder_script;
    close OUT;
    
    info("The job feeder has been written to $current_job_array_feeder_file.");

    my $qsub_cmd = <<QSUB_FILE

. /etc/pbs.conf

# Avoid qsub wrapper on barrine, because it doesn't return exit codes.
#
QSUB="\$PBS_EXEC/bin/qsub"


command_file=$current_job_array_file

num_lines_in_command_file=`wc -l \$command_file | cut -f 1 -d " "`

# Only create a job array, if there is more than one command in the file. 
# Otherwise we get "-J 1-1" which makes qsub throw an error.
#
if [ \$num_lines_in_command_file -eq 1 ]
then
  job_array_parameter=""
else
  job_array_parameter="-J 1-\$num_lines_in_command_file"
fi

\$QSUB $qsub_options -o $current_job_array_dir/stdout.txt -e $current_job_array_dir/stderr.txt \$job_array_parameter $current_job_array_feeder_file

exit_code=\$?

# Make sure a failed qsub is noticed
exit \$exit_code

QSUB_FILE
;
    
    my $qsub_file = File::Spec->catfile($current_job_array_dir, "submit_job_array.bash");
    
    open OUT, ">$qsub_file";
    print OUT $qsub_cmd;
    print OUT "\n";
    close OUT;
    
    info("The qsub command $qsub_cmd has been written to $qsub_file");
    
    use System::ShellRunner;
    System::ShellRunner::run_cmd("chmod u+x $qsub_file");
  }
  
  info("Current job array command file: $current_job_array_file");
  info("Adding the the command: $command");
  
  open OUT, ">>$current_job_array_file";
  print OUT $command;
  print OUT "\n";
  close OUT;
  
  my $number_of_jobs_in_current_job_array = `cat $current_job_array_file | wc -l`;
  chomp $number_of_jobs_in_current_job_array;
  
  $LAST_KNOWN_NUMBER_OF_JOBS_IN_JOB_ARRAY = $number_of_jobs_in_current_job_array;
  
  info("There are $number_of_jobs_in_current_job_array commands in the file now.");
  
  if ($number_of_jobs_in_current_job_array>=$max_number_of_jobs_in_current_job_array) {
    
    if ($run_job_arrays_when_ready) {
      #$self->_submit_job_array($self->_get_current_array_directory_name);
      $self->_submit_job_array($current_job_array_dir);
    }
  }
}

sub _submit_job_array {

  my $self = shift;
  my $array_dir = shift;
  
  my $qsub_file = File::Spec->catfile($array_dir, "submit_job_array.bash");
  
  print("Submitting jobarray from $qsub_file");

  my $run_this = "timeout.pl \"$qsub_file 2>&1\"";

  print "\n\nTrying to submit by running\n$run_this\n";
    
  my $stdout = $self->_run_with_retries({
    max_tries => $default_max_tries,
    num_tries => $default_num_tries,
    sleep_time_between_tries => $default_sleep_time_between_tries,
    run_cmd   => $run_this,
  });
  
  print "Result: $stdout\n\n";
    
  $self->_save_as_job_array_directory_submitted($array_dir);
  $self->_increment_job_array_number();
    
  #my $stdout = System::ShellRunner::run_cmd($qsub_file);
  # 1182030[].paroo3
  # Warning : Job array will run for 0 days.
  #
  # The last line will only appear, if you are using the qsub wrapper.
  # If you are using the qsub from PBS, you will get only the first line.

  my $job_array_id_found = $stdout =~ /^(\d+)/;

  if ($job_array_id_found) {

    chomp($stdout);

    #my $job_array_id = $1;
    my $job_array_id = $stdout;
    $self->id($job_array_id);
    
  } else {
    
    print "Could not find job id from pbs. qsub returned: $stdout\n";
    $self->id("Job id not returned by qsub. Instead I got: $stdout");

  }
}

# For the poor souls who can't spell "check_existence"
sub check_existance {
  my $self= shift;
  $self->check_existence(@_);
}

sub _last_used_array_number_fh_read {

  my $self = shift;
  
  my $last_used_array_number_file = $self->last_used_array_number_file;
  
  if (! -e $last_used_array_number_file) {
  
    my $last_used_array_number = 0;
  
    use File::Basename;
    my $dirname = dirname($last_used_array_number_file);
    
    if (! -d $dirname) {
      use File::Path qw( mkpath );
      mkpath($dirname);
    }
  
    my $OUT = $self->_last_used_array_number_fh_append;
    
    print $OUT $last_used_array_number;
    print $OUT "\n";
    close $OUT;
  }
  my $IN;
  open $IN, $last_used_array_number_file;
  return $IN;  
}

sub _last_used_array_number_fh_append {

  my $self = shift;
  
  my $last_used_array_number_file = $self->last_used_array_number_file;

  my $open_success = open my $OUT, ">>$last_used_array_number_file";

  if (!$open_success) {
    use Carp;
    confess("Unable to open $last_used_array_number_file for appending!");
  }
  return $OUT;
}

sub _get_last_used_array_number {

  my $self = shift;
  
  my $last_used_array_number;
  my $IN = shift;
  
#   print "\n------------------------------\n";
#   print $IN;
#   print "\n------------------------------\n";
  
  if (! $IN) {
    $IN = $self->_last_used_array_number_fh_read;
  }

  while (my $line = <$IN>) {
    if ($line) {
      $last_used_array_number = $line;
    }
  }
  close $IN; 
  return $last_used_array_number;

}

=head2 _get_current_job_array_number

  In the job_array_dir every subdirectory is an integer and has all files for
  running a job array of pipeline jobs.
  
  This will return the number (=name of the subdirectory) to which the next 
  commands should be added. If the command file of the latest directory is 
  full, it will be incremented by one and return that number. In that case, 
  a new command file will have to be created there.

=cut
sub _get_current_job_array_number {

  my $self = shift;
  
  my $last_used_array_number = $self->_get_last_used_array_number;  
  info("last_used_array_number: $last_used_array_number");
  
  my $testrunner_command_file = File::Spec->catfile(
    $self->_get_last_known_array_directory_name, 
    $testrunner_command_file_basename
  );

  my $cmds_in_file;
  if (-e $testrunner_command_file) {
    $cmds_in_file = `cat $testrunner_command_file | wc -l`;
  } else {
    $cmds_in_file = 0;
  }
  
  info("cmds_in_file: $cmds_in_file");
  print("cmds_in_file $testrunner_command_file: $cmds_in_file");
  
  if ($cmds_in_file>=$max_number_of_jobs_in_current_job_array) {
  
    $self->_increment_job_array_number();
  
  }
  return $last_used_array_number;
}

sub _increment_job_array_number {

  my $self = shift;

  my $last_used_array_number = $self->_get_last_used_array_number;  
  my $new_job_array_number = $last_used_array_number+1;  
  
  my $OUT = $self->_last_used_array_number_fh_append;
  
  print "Updating last_used_array_number " . $self->last_used_array_number_file . " from  $last_used_array_number to $new_job_array_number\n";
  
  print $OUT $new_job_array_number;
  print $OUT "\n";
  close $OUT;
  
  return $new_job_array_number;
}

=head2 _create_job_feeder_script

  Creates and returns the contents of the bash script that is submitted.

=cut
sub _create_job_feeder_script {

  my $self  = shift;
  my $param = shift;
  
  my $work_dir     = $param->{work_dir};
  my $command_file = $param->{command_file};  
  
  my $work_dir_full_path     = `readlink -f $work_dir`;
  my $command_file_full_path = `readlink -f $command_file`;
  
  my $stagger_time = $max_number_of_jobs_in_current_job_array * 4;

my $job_feeder_file = <<EOF
#!/bin/bash
# using bash allows the use of the module framework

cd $work_dir_full_path

PARAMFILE=$command_file_full_path

# no need to use /usr/bin/perl if module is loaded
#module load perl/5.15.8

#export PERL5LIB=$ENV{PERL5LIB}

# delay execution for a random period of time to stagger job starts
#sleep `expr \$RANDOM % $stagger_time`

# get the jobid at line PBS_ARRAY_INDEX in parameters.txt

if [ -n "\${PBS_ARRAY_INDEX}" ]
then
  echo Running line \${PBS_ARRAY_INDEX} of the job array
  jobid=`cat \$PARAMFILE | tail -n +\${PBS_ARRAY_INDEX} | head -1`
  echo \$jobid | bash
else
  # If there is no line to choose and run, execute all commands in the file.
  # This is most likely to happen, if there is only one command in the file
  # and the job was submitted as a regular job instead of a job array.
  #
  chmod u+x \$PARAMFILE
  \$PARAMFILE
fi

EOF
;
  return $job_feeder_file;
}

sub get_pending_jobs {
  my($self, %args) = @_;

  my ($user)  = $args{'-user'}  || $args{'-USER'}  || undef;
  my ($queue) = $args{'-queue'} || $args{'-QUEUE'} || undef;

  my $cmd = "qstat";
  $cmd .= " -u $user"  if $user;
  $cmd .= "  | grep \" Q \"";

  print STDERR "$cmd\n" if $args{'-debug'};

  my @pending_jobs;
  if( my $pid = open (my $fh, '-|') ) {
      eval{
	  local $SIG{ALRM} = sub { kill 9, $pid; };
	  alarm(60);
	  while(my $current_line = <$fh>){
	      chomp;
	      push @pending_jobs, $current_line;
	  }
	  close $fh;
	  alarm 0;
      }
  } else {
      exec( $cmd );
      die q{Something went wrong here $!: } . $! . "\n";
      exit;
  }
  print STDERR "FOUND " . scalar @pending_jobs . " jobs pending\n" if $args{'-debug'};
  return @pending_jobs;
}

sub open_command_line {
    my ($self, $verbose)= @_;
    
    info("open_command_line called, but deactivated this for now.");
    return;
}

sub temp_filename{
  my ($self) = @_;

  $self->{'pbs_jobfilename'} = $ENV{'LSB_JOBFILENAME'};
  return $self->{'pbs_jobfilename'};
}

sub job_stats {
    my ( $self, $verbose ) = @_;    
    return $self->fetch_job_ids_in_queue;
}

sub memstring_to_resource {
    return '';
}
sub resource {
    return '';
}

=head2 is_db_overloaded
=cut
sub is_db_overloaded {
  my $self = shift;
  return $self->is_queue_overloaded(@_);
}

sub is_queue_overloaded {
  my $self = shift;
  
  if (
    defined $LAST_KNOWN_NUMBER_OF_JOBS_IN_JOB_ARRAY 
    && 
    $LAST_KNOWN_NUMBER_OF_JOBS_IN_JOB_ARRAY<$max_number_of_jobs_in_current_job_array
  ) {
    return;
  }
  
  print "Checking, if queue is overloaded:";
  
    my $output = $self->_run_with_retries({
      max_tries => $default_max_tries,
      num_tries => $default_num_tries,
      sleep_time_between_tries => $default_sleep_time_between_tries,
      run_cmd   => qq(qstat -wu $ENV{USER} | cut -f 1 -d " " | grep -P "^\\d" | cat),
      #
      # grep returns 1, if nothing was found, so must be done manually later
      # or perhaps pipe to cat
      #
      #run_cmd   => qq(qstat -wu $ENV{USER} | cut -f 1 -d " "),
    });

  my @lines = split "\n", $output;
  my $number_of_job_arrays = @lines;
  
  print " $number_of_job_arrays job arrays (max: $max_number_of_jobs_in_current_job_array)";
  
  if ($number_of_job_arrays>$max_job_arrays) {
    print " The queue is overloaded.\n";
    return 1;
  }
  
  my %existing_ids = %{$self->fetch_job_ids_in_queue};
  
  my $current_no_of_jobs_running = keys %existing_ids;
  
  print " having a total of $current_no_of_jobs_running subjobs (max: $max_number_of_jobs_allowed_in_queue) running.";
  
  my $is_queue_overloaded = $current_no_of_jobs_running > $max_number_of_jobs_allowed_in_queue;
  
  if ($is_queue_overloaded) {
    print " Queue is overloaded!\n";
  } else {
    print " More job arrays can be run.\n";
  }
  
  return $is_queue_overloaded;
}


1;
