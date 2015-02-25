#!/usr/bin/env perl
=head1 timout.pl

=head2 Usage

  color()(set -o pipefail;"$@" 2>&1>&3|sed $'s,.*,\e[31m&\e[m,'>&2)3>&1
  color ./scripts/timeout.pl

=head2 Description

  This script is used by the ensembl genebuild pipeline to run external programs like qstat or qsub that may hang for a long time or not return at all.
  
  This script can be prefixed to any command. The command will be run. If execution of the command takes longer as than the user has specified, the process is killed.
  
  If the command returned a non-zero exit code, the script returns 1. Otherwise 0. Ideally the script would return the exact exit code received from the command, but perl doesn't seem to support this.

=head2 Note
  
  There is a timeout program already installed by default on Linux machines. Maybe this should have been used instead. I'm sticking with this script for now, because it prints nice status updates when waiting for too long.

=head2 Parameters

=head3 num_secs_to_timeout

  The number of seconds the command gets to do its job before it is killed. Default is 30 seconds.

=head3 initial_waiting_period

  The number of seconds, before timout.pl starts printing a message that the command might be hanging and printing a countdown.

=head3 update_user_interval

  How often the user will be updated about the time remaining until the command is killed.
  
=cut

use strict;
use Data::Dumper;

my $num_secs_to_timeout    = 30;
my $initial_waiting_period =  1;
my $update_user_interval   =  1;

my $cmd = join " ", @ARGV;

$|=1;

my $exit_code = run_cmd_with_timeout(
  $cmd,
  undef,
  {
    num_secs_to_timeout    => $num_secs_to_timeout,
    initial_waiting_period => $initial_waiting_period,
    update_user_interval   => $update_user_interval,
  }
);

# There seem to be problems returning arbitrary exit codes. When using exit($exit_code):
# 
# scripts/timeout.pl askldjhgsldfkjgh
# echo $?
#
# returns 0, although it failed.
#
if ($exit_code) {
  exit(1);
}
exit(0);

sub run_cmd_with_timeout {

    my $cmd              = shift;
    my $test_for_success = shift;
    my $timeout_params   = shift;

    my $param_ok = (!defined $test_for_success) || (ref $test_for_success eq 'ARRAY'); 
    
    my $num_secs_to_timeout;
    my $initial_waiting_period;
    my $update_user_interval;
    
    if (ref $timeout_params eq 'HASH') {
      $num_secs_to_timeout    = $timeout_params->{num_secs_to_timeout};
      $initial_waiting_period = $timeout_params->{initial_waiting_period};
      $update_user_interval   = $timeout_params->{update_user_interval};
      
    } else {
      confess("Unfortunatley timeout parameters are mandatory at the moment.");
    }

    confess("Parameter error! If test_for_success is set, it must be an array of hashes!") 
      unless ($param_ok);
    
    my $stdout;
    my $exit_code;
    
    # See
    # http://docstore.mik.ua/orelly/perl/cookbook/ch16_11.htm
    # on how to use pipes for inter process communication.
    #
    use IO::Handle;
    pipe(READER, WRITER);
    WRITER->autoflush(1);

    my $pid = fork;
    if ($pid > 0) {
	# Parent process
	close (WRITER);
	my $pid_2;
	eval{
	    
	    local $SIG{ALRM} = sub { 
	      kill -9, $pid; 
	      # If we kill it, set exit code explicitly to fail.
	      $exit_code = -1;
	      confess("The command\n\n$cmd\n\ntimed out after $num_secs_to_timeout seconds.");
	    };
	    alarm $num_secs_to_timeout;
	    
	    $pid_2 = fork;
	    if ($pid_2 > 0) {
	    
	      waitpid($pid, 0);	
	      $exit_code = $?;
	      
	    } elsif ($pid_2==0) {
	    
	      my $start_line_printed;

	      local $SIG{HUP} = sub {
		print STDERR "\n_____________________________________________________\n"
		  if ($start_line_printed);
		  exit(0);
	      };

	      setpgrp(0,0);
	      
	      sleep($initial_waiting_period);
	      print STDERR "\n_____________________________________________________\n";
	      $start_line_printed = 1;
	      print STDERR "The command:\n\n$cmd\n\nseems to be hanging. If it doesn't respond in ".($num_secs_to_timeout - $initial_waiting_period)." seconds, it will be terminated.\n";
	      
	      # Get ahead one interval so we count to zero.
	      my $total_time_waited = $initial_waiting_period + $update_user_interval;
	      
	      while ($total_time_waited<=$num_secs_to_timeout) {
		print STDERR "" . ($num_secs_to_timeout - $total_time_waited) . " ";
		sleep($update_user_interval); 
		$total_time_waited+=$update_user_interval;		
	      }
	      print STDERR "Process timed out and should be killed now.\n";
	    }
	    alarm 0;
	};
	
	# If all has gone well so far, set the exit code to what the child 
	# process returned as the exit code of the program run:
	#
	if ($exit_code == 0) {
	  my $returned = <READER>;
	  $exit_code = $returned;
	}

	kill 'HUP', $pid_2;
	waitpid($pid_2, 0);
	
	# http://perldoc.perl.org/functions/waitpid.html
	#  The status is returned in $?
	if ($@) {
	  use Carp;	  
	  confess($@);
	}
    }
    elsif ($pid == 0) {
    
	# Child process	
	close (READER);
	setpgrp(0,0);
	
	my $stdout;
	my $exit_code = 0;
	
	eval {	
	  use System::ShellRunner;
	  ($stdout, $exit_code) = System::ShellRunner::run_cmd($cmd);
	};
	
	print $stdout;
	
	if ($@) {
	  print "The command\n\n$cmd\n\nhas failed.\n";
	  print "The problem was: $@\n";
	  
	  # Should not be necessary, but it seems that the exit code does not get returned properly.
	  $exit_code = 1;
	}

	# Forward the exit code
	WRITER->print($exit_code);
	WRITER->close();
	exit($exit_code);
# 	$stdout = `$cmd`;	
# 	print $stdout;
# 	
# 	# Forward the exit code
# 	WRITER->print($?);
# 	WRITER->close();
# 	exit($?);
    }
    
    return $exit_code;
}