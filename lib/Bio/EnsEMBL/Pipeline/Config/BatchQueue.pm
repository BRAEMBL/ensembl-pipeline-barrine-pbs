=head1 LICENSE

# Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

    Bio::EnsEMBL::Pipeline::Config::BatchQueue

=head1 SYNOPSIS

    use Bio::EnsEMBL::Pipeline::Config::BatchQueue;
    use Bio::EnsEMBL::Pipeline::Config::BatchQueue qw();

=head1 DESCRIPTION

    Configuration for pipeline batch queues. Specifies per-analysis
    resources and configuration, e.g. so that certain jobs are run only
    on certain nodes.

    It imports and sets a number of standard global variables into the
    calling package. Without arguments all the standard variables are
    set, and with a list, only those variables whose names are provided
    are set. The module will die if a variable which doesn't appear in
    its C<%Config> hash is asked to be set.

    The variables can also be references to arrays or hashes.

    Edit C<%Config> to add or alter variables.

    All the variables are in capitals, so that they resemble environment
    variables.

    To run a job only on a certain host, you have to add specific
    resource-requirements. This can be useful if you have special
    memory-requirements, for example if you like to run the job only
    on linux 64bit machines or if you want to run the job only on a
    specific host group. The commands bmgroup and lsinfo show you
    information about certain host-types / host-groups.

    Here are some example resource-statements / sub_args statements:

        sub_args => '-m bc_hosts',  # only use hosts of host-group 'bc_hosts'
                                    # (see bmgroup)
        sub_args => '-m bc1_1',     # only use hosts of host-group 'bc1_1'

        resource => 'select[type==X86_64]',     # use Linux 64 bit machines only
        resource => 'select[model==X86_64]',    # only run on X86_64 hosts

        resource => 'alpha',    # only run on DEC alpha
        resource => 'linux',    # run on any machine capable of running
                                # 32-bit X86 Linux apps

        # Note: On the Sanger farm, all machines are X86_64 Linux hosts.

=head2 Database throttling

    Do to find tokens for your MySQL servers 
    bhosts -s | grep tok

    This runs a job on a linux host, throttles genebuild2:3306 to not have
    more than 2000 active connections, 10 connections per job in the
    duration of the first 10 minutes when the job is running (means 200
    hosts * 10 connections = 2000 connections):

      resource => 'select[linux] rusage[myens_build2tok=10:duration=10]',

    Running on 'linux' hosts with not more than 2000 active connections
    for genebuild3 and genebuild7, 10 connections per job to each db-instance
    for the first 10 minutes:

      resource => 'select[linux] rusage[myens_build3tok=10:myens_build7tok=10:duration=10]',

    Running on hosts of model 'X86_64' hosts with not more than 200
    active connections to genebuild3, 10 connections per job for the first
    10 minutes:

      resource => 'select[model==X86_64] rusage[myens_build3tok=10:duration=10]',

    Running on hosts of host_group bc_hosts with not more than 200
    active connections to genebuild3, 10 connections per job for the first
    10 minutes:

      resource => 'rusage[myens_build3tok=10:duration=10]',

      sub_args =>'-m bc_hosts',

=head2 Memory requirements

    There are three ways of specifying LSF memory requirements.
    
=head3 Full resource string

    To allocate 4Gb of memory:

      resource  => 'select[mem>4000] rusage[mem=4000]',
      sub_args  => '-M 4000'

=head3 Short memory specification string

    To allocate 4Gb of memory, all of the below settings means the same
    thing (the case of the unit specification is ignored):

      memory => '4Gb'

      memory => '4000Mb'

      memory => '4000000Kb'

    Also see the section on memory arrays when using retries. 
      
=head2 Retrying on failure

    When a job fails due to insufficient memory, or due to run-time
    constraints, it may be retried.  The number of retries and the
    settings to use when retrying may be specified in two different
    ways.

    The maximum number of retries is set with the 'retries' option:

      retries => 3 # Run the job a maximum of four times (three retries).

=head3 Using 'retry_'

    When retrying, the pipeline submission code will look for options
    prefixed with 'retry_' and use these.  For example:

      memory        => '500Mb',     # Use 500 Mb for first run
      retry_memory  => '1Gb'        # Use 1 Gb for the retries

    The options that may be prefixed in this way are:

      queue,
      sub_args,
      resource,
      memory

=head3 Using arrays

    Instead of using the 'retry_' prefix, the original option may
    instead hold an array, like this:

      # Use 0.5Gb for the first run, 1Gb for the second, and 1.5Gb for
      # the third (and any later) run:
      memory => ['500Mb', '1Gb', '1500Mb']

    If the 'retries' value is larger than the length of the array, the
    last value of the array will be re-used.

=cut


package Bio::EnsEMBL::Pipeline::Config::BatchQueue;

use strict;
use vars qw(%Config);

my $output_directory_base = '/ebi/bscratch/' . $ENV{USER} . '/genebuild_temp_files';
#my $output_directory_base = '/home/uqmnuhn/development/ensembl_genebuild/mouse/output';
#my $output_directory_base = '/home/uqmnuhn/development/ensembl_genebuild/pogona/output';

=head3 default_group

  The group that will be set in the "-A" parameter when submitting a job to 
  PBS. The qsubaccounts.sh returns the groups that you can use for this 
  purpose. The first one will be used.

=cut
#my $default_group = find_users_default_group();
my $default_group_cached;

#
#my $default_group_hardcoded = 'x';
my $default_group_hardcoded;

sub default_group {

  if ($default_group_hardcoded) {
    return $default_group_hardcoded;
  }
  
  if ($default_group_cached) {
    return $default_group_cached;
  }

  $default_group_cached = find_users_default_group();
  
  return $default_group_cached;
}

sub new {
    my ( $class, @args ) = @_;
    my $self = $class->SUPER::new(@args);
    return $self;
}

sub find_users_default_group {

  my @all_groups = find_users_groups();
  use Carp;
  confess('Cant find group for user') unless(@all_groups);
  
  return $all_groups[0];
}

sub find_users_groups {

  use System::ShellRunner;
  my $stdout;
  
  my $cmd = 'qsubaccounts.sh';
  
  eval {
    $stdout = System::ShellRunner::run_cmd('qsubaccounts.sh');
  };
  if ($@) {
    use Carp;
    confess(
      "\nError in BatchQueue: This module is trying to automatically find the groups you belong to so it can set the account string when generating qsub commands. However, it was not successful and will therefore terminate here. Please make sure you can either\n"
      . " - run the command $cmd on the command line or\n"
      . " - set \$default_group_hardcoded in Bio::EnsEMBL::Pipeline::Config::BatchQueue to what you want your default group to be or\n"
      . " - set the group explicitly in the analyses configured in the Bio::EnsEMBL::Pipeline::Config::BatchQueue module\n"
      . "\n\n"
      .
      $@
    );
  }

  #use Data::Dumper; print "------------->A ".Dumper($stdout)." \n";
  
  my @group = split /\s/, $stdout;

  return @group;
}

my $default_perl = `which perl`;
# Has a carraige return at the end.
chomp($default_perl);

%Config = (

  # Depending on the job-submission-system you're using, use LSF, you
  # can also use 'Local'.
  #
  # For more info look into:
  # /ensembl-pipeline/modules/Bio/EnsEMBL/Pipeline/BatchSubmission

  QUEUE_MANAGER => 'BraemblPBS', 

  DEFAULT_BATCH_SIZE  => 11,
  DEFAULT_RETRIES     => 2,
  DEFAULT_BATCH_QUEUE => 'workq',  # Put in the queue of your choice, e.g. 'normal'
  DEFAULT_RESOURCE    => 'rusage[myens_build1tok=10,myens_build2tok=10,myens_build3tok=10,myens_build4tok=10,myens_build5tok=10,myens_build6tok=10,myens_build7tok=10,myens_build8tok=10]',
  DEFAULT_SUB_ARGS    => '',
  DEFAULT_OUTPUT_DIR  => $output_directory_base . '/default',
  DEFAULT_CLEANUP     => 'no',
  DEFAULT_VERBOSITY   => 'WARNING',


#   DEFAULT_LSF_PRE_EXEC_PERL =>'/sw/perlbrew/perls/perl-5.15.8/bin/perl',
#   DEFAULT_LSF_PERL =>'/sw/perlbrew/perls/perl-5.15.8/bin/perl',

  # Set this to whatever perl we are using anyway:
  #
  DEFAULT_LSF_PRE_EXEC_PERL => $default_perl,
  DEFAULT_LSF_PERL => $default_perl,
  lsf_pre_exec_perl => $default_perl,


  # SANGER farm: Don't forget to source source
  # /software/intel_cce_80/bin/iccvars.csh for big mem jobs.

  # At <this number of jobs> RuleManager will sleep for a certain period
  # of time.  If you effectively want this never to run set the value
  # to something very high, e.g. 100000.  This is important for queue
  # managers which cannot cope with large numbers of pending jobs (e.g.
  # early LSF versions and SGE).
  JOB_LIMIT => 100000000,

  JOB_STATUSES_TO_COUNT => ['PEND'],    # These are the jobs which will
                                        # be counted. valid statuses
                                        # for this array are RUN, PEND,
                                        # SSUSP, EXIT, DONE ; use 'qw'
                                        # for Sun Grid Engine

  MARK_AWOL_JOBS => 0,
  MAX_JOB_SLEEP  => 3600,   # The maximun time to sleep for when job limit
                            # reached
  MIN_JOB_SLEEP => 120, # The minimum time to sleep for when job limit reached
  SLEEP_PER_JOB => 30,  # The amount of time to sleep per job when job limit
                        # reached

  DEFAULT_RUNNABLEDB_PATH => 'Bio/EnsEMBL/Analysis/RunnableDB',

  DEFAULT_RUNNER         => '',
  #DEFAULT_RETRY_QUEUE    => 'long',
  DEFAULT_RETRY_QUEUE    => '',
  DEFAULT_RETRY_SUB_ARGS => '',
  #DEFAULT_RETRY_RESOURCE => 'select[myens_build1tok>2000 && myens_build2tok>2000 && myens_build3tok>2000 && myens_build4tok>2000 && myens_build5tok>2000 && myens_build6tok>2000 && myens_build7tok>2000 && myens_build8tok>2000]  rusage[myens_build1tok=10:myens_build2tok=10:myens_build3tok=10:myens_build4tok=10:myens_build5tok=10:myens_build6tok=10:myens_build7tok=10:myens_build8tok=10]',
  DEFAULT_RETRY_RESOURCE    => 'rusage[myens_build1tok=10,myens_build2tok=10,myens_build3tok=10,myens_build4tok=10,myens_build5tok=10,myens_build6tok=10,myens_build7tok=10,myens_build8tok=10]',

  QUEUE_CONFIG => [
    { logic_name      => 'RepeatMask',
      batch_size      => 1,
      retries         => 3,
      runner          => '',
      # See 
      # http://www.rcc.uq.edu.au/hpc/guides/index.html?secure/New_Users_Guide.html#Queues
      # for possible queues.
      #
      queue           => 'workq',
      
      # http://www.rcc.uq.edu.au/hpc/guides/index.html?secure/New_Users_Guide.html#scratch
      #
      output_dir      => $output_directory_base . '/repeatmask',
      #output_dir      => '/scratch/'.$ENV{USER}.'/repeatmask',
      
      verbosity       => 'INFO',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',

      # Most RepeatMasker jobs need not more than 500MB.
      #resource => 'select[mem>500] rusage[mem=500]',
      resource => 'mem=500M:ncpus=1:NODETYPE=any:select=1',
      sub_args => '-A '. &default_group .' -l walltime=168:0:0',

      # Some jobs might fail (unlikely with 1M slices), but they will
      # defintely pass with 2GB.
      retry_resource => 'mem=500M:ncpus=1:NODETYPE=any:select=1',
      retry_sub_args => '-A '. &default_group .' -l walltime=168:0:0',

      retry_queue      => '',
      retry_batch_size => 1,
    },
    { logic_name      => 'Pmatch',
      batch_size      => 3,
      retries         => 10,
      runner          => '',
      # See 
      # http://www.rcc.uq.edu.au/hpc/guides/index.html?secure/New_Users_Guide.html#Queues
      # for possible queues.
      #
      queue           => 'workq',
      
      # http://www.rcc.uq.edu.au/hpc/guides/index.html?secure/New_Users_Guide.html#scratch
      #
      output_dir      => $output_directory_base . '/pmatch',
      
      verbosity       => 'INFO',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',

      # Due to a bug in PBS configuration on barrine, the -l parameters are 
      # mandatory:
      #
      # https://desk.gotoassist.com/incidents/3648
      #
      sub_args => '-A '. &default_group .' -l select=1:ncpus=1:mem=3g:NodeType=medium -l walltime=24:0:0',

      # Some jobs might fail (unlikely with 1M slices), but they will
      # defintely pass with 2GB.
      #retry_resource => 'mem=500M:ncpus=1:NODETYPE=any:select=1',
      # Pmatch seems to be using a lot of memory, so if it fails, it might be due to insufficient memory.
      retry_sub_args => '-A '. &default_group .' -l select=1:ncpus=1:mem=4g:NodeType=medium -l walltime=168:0:0',

      retry_queue      => 'workq',
      retry_batch_size => 7,
    },
    {
      logic_name       => 'uniprot',
      batch_size       => 800,      # uniprot takes a long itme
      retry_batch_size => 800,
      #sub_args         => '-A '. &default_group .' -l select=1:ncpus=3:mem=1g:NodeType=medium -l walltime=4:0:0',
      sub_args         => '-A '. &default_group .' -l select=1:ncpus=3:mem=50g:NodeType=any -l walltime=168:0:0',
      retry_sub_args   => '-A '. &default_group .' -l select=1:ncpus=3:mem=50g:NodeType=any -l walltime=168:0:0',
      
      #resource       => 'rusage[myens_build1tok=25]  span[hosts=1]',
      #sub_args       => '-n 3',
      #retry_resource       => 'rusage[myens_build1tok=25]  span[hosts=1]',
      #retry_sub_args       => '-n 3',
      #memory         => ['300MB','1GB','3GB'],
      queue          => 'workq',
    },
    {
      logic_name     => 'genscan',
      batch_size     => 500, # generally we use the default for this which is 120.
      retry_batch_size => 500,
      #resource       => 'rusage[myens_build1tok=10]',
      sub_args         => '-A '. &default_group .' -l select=1:ncpus=3:mem=4g:NodeType=any -l walltime=48:0:0',
      retry_sub_args   => '-A '. &default_group .' -l select=1:ncpus=3:mem=8g:NodeType=any -l walltime=168:0:0',
      #memory         => ['300MB','1GB','3GB'],
    },
    {
      logic_name => 'trnascan',
      batch_size => 2000,
      resource   => 'rusage[myens_build1tok=10]',
      resource   => 'mem=500M:ncpus=1:NODETYPE=any:select=1',
      #memory     => ['200MB', '1GB'],
      queue      => 'workq',
    },
    {
      logic_name     => 'firstef',
      batch_size     => 2000,
      resource       => 'rusage[myens_build1tok=10]',
      memory         => ['200MB', '1GB'],
    },
    { logic_name => 'job_using_more_than_4_gig_of_memory',
      batch_size => 10,
      retries    => 3,
      runner     => '',

      resource => '',
      sub_args => '',

      retry_resource => '',
      retry_sub_args => '',
      retry_queue    => '',
    },
   {
    # this example uses the new 'memory' options which is an alternative to specifying memory
    # in the resource requirements. Each time a job is retried, the next element in the memory array will be used
      logic_name     => 'dust',
      batch_size     => 500, # calculate as approx. num toplevel slice / 20
      memory   => ['700MB', '1500MB'],
      rerty_batch_size     => 1, # assuming there are only a few, eg. less than 10 jobs
      retries         => 3,
    },
    { logic_name  => 'trf',
      batch_size  => 2000,
      retries     => 3,
      runner      => '',
      retry_queue => '',

      # trf is a borderline case for the 100MB limit, give it 200MB.
      resource => 'select[mem>200] rusage[mem=200]',
      sub_args => '-M 200',

      # For really big things, it might need more, give it 1GB
      retry_resource => 'select[mem>1000] rusage[mem=1000]',
      retry_sub_args => '-M 1000',
    },
  {
    logic_name     => 'cpg',                                                  
    batch_size     => 500,
    resource       => 'rusage[myens_build1tok=10]', 
    queue          => 'normal',
  },
  {
    logic_name => 'eponine',
    batch_size => 2000, 
    resource   => 'rusage[myens_build1tok=10]',
    memory     => ['300MB','1GB','2GB'],
    queue      => 'normal',
    verbosity  => 'INFO',
  },
  {
    logic_name => 'unigene',
    batch_size     =>  100, 
    resource       => 'rusage[myens_build1tok=10]',
    memory         => ['300MB','1GB','3GB'],
    queue          => 'normal',
  },
  {
    logic_name => 'vertrna',
    batch_size     => 25,
    resource       => 'rusage[myens_build1tok=10]',
    memory         => ['300MB','1GB','3GB'],
   }, 
    {
      logic_name => 'sim_consensus',
      batch_size => 200,
      resource       => 'select[mem>2000] rusage[mem=2000]',
      retries        => 3,
      sub_args       => '-M 2000',
      runner         => '',
      retry_queue    => '',
      retry_resource => '',
      retry_sub_args => '',
    },
    {
      logic_name => 'utr_addition',
      batch_size => 100,
      resource       => 'select[mem>1500] rusage[mem=1500]',
      retries        => 3,
      sub_args       => '-M 1500',
      runner         => '',
      retry_queue    => '',
      retry_resource => '',
      retry_sub_args => '',
    },
    {
      logic_name => 'LayerAnnotation',
      batch_size => 100,
      resource       => 'select[mem>1500] rusage[mem=1500]',
      retries        => 3,
      sub_args       => '-M 1500',
      runner         => '',
      retry_queue    => '',
      retry_resource => '',
      retry_sub_args => '',
    },
    {
      logic_name => 'ensembl',
      batch_size => 100,
      resource       => 'select[mem>1000] rusage[mem=1000]',
      retries        => 3,
      sub_args       => '-M 1000',
      runner         => '',
      retry_queue    => '',
      retry_resource => '',
      retry_sub_args => '',
    },

#####
# Batchqueue for the protein annotation pipeline
# chunk size was 100/file, around 200 input_ids
    {
      logic_name => 'prints',
      batch_size => 10,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['1000MB', '2000MB'],
    },
    {
      logic_name => 'tmhmm',
      batch_size => 110,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'ncoils',
      batch_size => 110,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'signalp',
      batch_size => 110,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'seg',
      batch_size => 1,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'pirsf',
      batch_size => 10,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['2000MB'],
    },
    {
      logic_name => 'smart',
      batch_size => 10,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'superfamily',
      batch_size => 1,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'tigrfam',
      batch_size => 10,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'pfam',
      batch_size => 1,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
    {
      logic_name => 'pfscan',
      batch_size => 10,
      queue => 'normal',
      retries => 1,
      resource => 'rusage[myens_build8tok=20]',
      memory        => ['500MB'],
    },
#
#####


#####
# Batchqueue for the ncRNA pipeline
    {
      logic_name => 'BlastmiRNA',
      batch_size => 500,
      resource   => 'select[mem>500] rusage[mem=500]',
      retries    => 1,
      sub_args   => '-M500',
      queue      => 'normal',
    },
    {
      logic_name => 'RfamBlast',
      batch_size => 300,
      resource   => 'select[mem>1500] rusage[mem=1500]',
      retries    => 1,
      sub_args   => '-M1500',
      queue      => 'normal',
    },
    {
      logic_name => 'miRNA',
      batch_size => 1,
      retries    => 1,
      resource   => 'select[mem>1000] rusage[mem=1000]',
      sub_args   => '-M1000',
      queue      => 'normal',
    }, 
       {
      logic_name => 'ncRNA',
      batch_size => 500,
      retries    => 1,
      resource   => 'select[mem>500] rusage[mem=500]',
      sub_args   => '-M500',
      queue      => 'normal',
    }, 
    {
      logic_name => 'BlastWait',
      batch_size => 1,
      resource   => 'linux',
      retries    => 0,
      queue => 'normal',
    },
#
#####


  ]
);

sub import {
  my ($callpack) = caller(0);    # Name of the calling package
  my $pack = shift;              # Need to move package off @_

  # Get list of variables supplied, or else all
  my @vars = @_ ? @_ : keys(%Config);
  if ( !@vars ) { return }

  # Predeclare global variables in calling package
  eval "package $callpack; use vars qw(" .
    join( ' ', map { '$' . $_ } @vars ) . ")";
  if ($@) { die $@ }

  foreach (@vars) {
    if ( defined( $Config{$_} ) ) {
      no strict 'refs';
      # Exporter does a similar job to the following
      # statement, but for function names, not
      # scalar variables
      *{"${callpack}::$_"} = \$Config{$_};
    }
    else {
      die("Error: Config: $_ not known\n");
    }
  }
} ## end sub import

1;