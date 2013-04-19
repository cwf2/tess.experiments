#! /usr/bin/perl

#
# batch.run.pl
#

=head1 NAME

batch.run.pl - run a batch of Tesserae searches and digest results

=head1 SYNOPSIS

batch.run.pl [options] FILE

=head1 DESCRIPTION

This script is meant to run a long list of Tesserae searches generated ahead of time by
'batch.prepare.pl'.  It will write the results to a temporary directory, but the main 
product is a digest containing only the number of results for each integer score, for
use in Xia's visualizations.

=head1 OPTIONS AND ARGUMENTS

=over

=item I<FILE>

The file of searches to perform.  This is created by batch.prepare.pl.

=item B<--parallel> I<N>

Allow I<N> processes to run in parallel for faster results. 
Requires Parallel::ForkManager.

=item B<--quiet>

Less output to STDERR.

=item B<--help>

Print usage and exit.

=back

=head1 KNOWN BUGS

=head1 SEE ALSO

=head1 COPYRIGHT

University at Buffalo Public License Version 1.0.
The contents of this file are subject to the University at Buffalo Public License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://tesserae.caset.buffalo.edu/license.txt.

Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.

The Original Code is batch.run.pl.

The Initial Developer of the Original Code is Research Foundation of State University of New York, on behalf of University at Buffalo.

Portions created by the Initial Developer are Copyright (C) 2007 Research Foundation of State University of New York, on behalf of University at Buffalo. All Rights Reserved.

Contributor(s): Chris Forstall

Alternatively, the contents of this file may be used under the terms of either the GNU General Public License Version 2 (the "GPL"), or the GNU Lesser General Public License Version 2.1 (the "LGPL"), in which case the provisions of the GPL or the LGPL are applicable instead of those above. If you wish to allow use of your version of this file only under the terms of either the GPL or the LGPL, and not to allow others to use your version of this file under the terms of the UBPL, indicate your decision by deleting the provisions above and replace them with the notice and other provisions required by the GPL or the LGPL. If you do not delete the provisions above, a recipient may use your version of this file under the terms of any one of the UBPL, the GPL or the LGPL.

=cut

use strict;
use warnings;

# modules necessary to look for config

use Cwd qw/abs_path/;
use FindBin qw/$Bin/;
use File::Spec::Functions;

# load configuration file

my $tesslib;

BEGIN {
	
	my $dir  = $Bin;
	my $prev = "";
			
	while (-d $dir and $dir ne $prev) {

		my $pointer = catfile($dir, '.tesserae.conf');

		if (-s $pointer) {
		
			open (FH, $pointer) or die "can't open $pointer: $!";
			
			$tesslib = <FH>;
			
			chomp $tesslib;
			
			last;
		}
		
		$dir = abs_path(catdir($dir, '..'));
	}
	
	unless ($tesslib) {
	
		die "can't find .tesserae.conf!";
	}
}

# load Tesserae-specific modules

use lib $tesslib;

use TessSystemVars;
use EasyProgressBar;

# modules to read cmd-line options and print usage

use Getopt::Long;
use Pod::Usage;

# load additional modules necessary for this script

use DBI;
use File::Temp qw/tempdir/;
use Storable;

# initialize some variables

my $help     = 0;
my $quiet    = 0;
my $verbose  = 0;
my $parallel = 0;
my $cleanup  = 0;
my $parentdir;
my $dbname;

my @param_names = qw/
	source
	target
	unit
	feature
	stop
	stbasis
	dist
	dibasis/;

# get user options

GetOptions(
	'cleanup'    => \$cleanup,
	'dbname'     => \$dbname,
	'help'       => \$help,	
	'parallel=i' => \$parallel,
	'quiet'      => \$quiet,
	'verbose'    => \$verbose,
	'working=s'  => \$parentdir
	);

# print usage if the user needs help
#
# you could also use perldoc name.pl
	
if ($help) {

	pod2usage(1);
}

# if verbose and quiet, verbose wins

$quiet = 0 if $verbose;

# try to load Parallel::ForkManager
#  if requested.

($parallel, my $pm) = init_parallel($parallel);


# choose a database name if necessary
	
$dbname = check_dbname($dbname);

#
# get file to read from command line
#

my $file = shift(@ARGV);

unless ($file) { pod2usage(1) }

my @run = @{parse_file($file)};


#
# create database
#

($dbname, my ($datadir, $done)) = init_db($dbname, $parentdir);


#
# main loop
#

my $pr = ProgressBar->new(scalar(@run), $quiet);

for (my $i = 0; $i <= $#run; $i++) {

	$pr->advance();
	
	# fork
	
	if ($parallel) {
	
		$pm->start and next;
	}

	# modify arguments a little
	
	my $cmd = $run[$i];
	
	my $bin;
	
	$cmd =~ s/--bin\s+(\S+)/"--bin " . ($bin = catfile($datadir, $1))/e;
	$cmd .= ' --quiet' unless $verbose;
	
	# run tesserae, note how long it took

	my $time = exec_run($cmd, $verbose);
	
	# extract search params, score tallies
	# from the results files
	
	my ($params, $scores) = parse_results($bin);
	
	#
	# connect to database
	#
	
	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "");
	
	# add records to the database
	
	add_scores($dbh, $i, $scores);
	
	# add run info
	
	add_run($dbh, $i, $params, $time);
	
	$pm->finish if $parallel;
}

$pm->wait_all_children if $parallel;

#
# subroutines
#

#
# initialize parallel processing
#

sub init_parallel {

	my $parallel = shift;
	
	my $pm;
	
	if ($parallel) {

		eval {
		
			require Parallel::ForkManager;
		};
	
		if ($@) {
		
			print STDERR "can't load Parallel::ForkManager: $@\n";
			
			print STDERR "continuing with --parallel 0\n";
			
			$parallel = 0;
		}
	
		else {
		
			$pm = Parallel::ForkManager->new($parallel);
		}
	}
	
	return ($parallel, $pm);
}

#
# choose a database name if none given
#

sub check_dbname {

	my $dbname = shift;

	unless ($dbname) {
	
		opendir (my $dh, curdir) or die "can't read current directory: $!";
		
		my @existing = sort (grep {/^tesbatch\.\d+\.db$/} readdir $dh);
		
		my $i = 0;
		
		if (@existing) {
		
			$existing[-1] =~ /\.(\d+)\.db/;
			$i = $1 + 1;
		}
	
		$dbname = sprintf("tesbatch.%03i.db", $i);
		$dbname = abs_path(catfile(curdir, $dbname));
	}
	
	return $dbname;
}

#
# parse the input file
#

sub parse_file {

	my $file = shift;
	
	my @run;
	
	open(my $fh, "<", $file) or die "can't read $file: $!";
	
	print STDERR "reading $file\n" unless $quiet;
	
	while (my $l = <$fh>) {
	
		chomp $l;
		push @run, $l if $l =~ /[a-z]/i
	}
	
	close $fh;
	
	return \@run;
}


#
# create a new database
#
#   NOTE: - if it exists already, do something else?
#

sub init_db {

	my ($dbname, $parentdir) = @_;
	

	#	
	# open / create the database file
	#
	
	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "");
		
	my $done = check_resume($dbh);
	

	#
	# create a temp directory for all the results
	#
	
	my %options = (CLEANUP => $cleanup);
	if ($parentdir) { $options{DIR} = $parentdir }
	
	my $tempdir = tempdir(%options);
	
	return ($dbname, $tempdir, $done);
}


# check database tables to see whether
# an aborted run must be resumed (and where)

sub check_resume {

	my $dbh = shift;
	
	my %done;
	
	my $sth = $dbh->prepare(
		'select name from sqlite_master 
			where type="table";');
			
	$sth->execute;
	
	my %exists;
	foreach(@{$sth->fetchall_arrayref()}) {
		$exists{$_} = 1;
	}
	
	# if both tables are present, figure out 
	# how much has already been done
		
	if ($exists{runs} and $exists{scores}) {
		
		my $sth = $dbh->prepare ('select run_id from runs;');
		$sth->execute;
		
		foreach(@{$sth->fetchall_arrayref()}) {
			$done{$_} = 1;
		}
	}

	# otherwise create them;
	#   - if only one exists, delete it and start over.

	else {
		
		if ($exists{runs}) {
		
			my $sth = $dbh->prepare('drop table runs;');
			$sth->execute;
		}
		elsif ($exists{scores}) {
			my $sth = $dbh->prepare('drop table scores;');
			$sth->execute;
		}
	
		my $sth;
		my $cols;
		
		# create table runs
		
		$cols = join(', ', 
			'run_id  int',
			'source  varchar(80)',
			'target  varchar(80)',
			'unit    char(6)',
			'feature char(4)',
			'stop    int',
			'stbasis char(7)',
			'dist    int',
			'dibasis char(11)',
			'time    int');

		$sth = $dbh->prepare(
			"create table runs ($cols);"
		);
		
		$sth->execute;
		
		# create table scores
		
		$cols = join(', ', 
			'run_id int',
			'score  int',
			'count  int'
		);	
	
		$sth = $dbh->prepare(
			"create table scores ($cols);"
		);	
		
		$sth->execute;
	}
	
	return \%done;
}


#
# extract parameters from string
#

sub params_from_string {

	my $cmd = shift;
	my %par;
	
	$cmd =~ s/.*read_table.pl\s+//;
	
	while ($cmd =~ /--(\S+)\s+([^-]\S*)/g) {
	
		$par{$1} = $2;
	}
	
	return \%par;
}


#
# execute a run, return benchmark data
#

sub exec_run {

	my ($cmd, $echo) = @_;
	
	print STDERR $cmd . "\n" if $echo;
	
	my $bmtext = `$cmd`;
	
	$bmtext =~ /total>>(\d+)/;
	
	return $1;
}


#
# parse results files
#

sub parse_results {

	my $bin = shift;
	
	# get parameters
	
	my $file_meta = catfile($bin, 'match.meta');
	
	my %meta = %{retrieve($file_meta)};
	
	my @params = @meta{map {uc($_)} @param_names};
	
	# get score tallies

	my @scores;
	
	my $file_score = catfile($bin, 'match.score');
	
	my %score = %{retrieve($file_score)};

	for my $unit_id_target (keys %score) {
	
		for my $unit_id_source (keys %{$score{$unit_id_target}}) {
		
			$scores[$score{$unit_id_target}{$unit_id_source}]++;
		}
	}
	
	return (\@params, \@scores);
}

#
# add scores to database
#

sub add_scores {

	my ($dbh, $i, $scoresref) = @_;
	
	my @scores = @$scoresref;
	
	my $sth = $dbh->prepare(
		"insert into scores values($i, ?, ?);"
	);
	
	while (my ($score, $count) = each @scores) {
	
		$sth->execute($score, ($count || 0));
	}
}


#
# add run info to database
#

sub add_run {

	my ($dbh, $i, $paramsref, $time) = @_;
	
	my @params = @$paramsref;
	
	my $values = join(', ', add_quotes(
		$i, 
		@params, 
		$time
	));
		
	my $sth = $dbh->prepare("insert into runs values ($values);");
	
	$sth->execute;
}

sub add_quotes {

	for (@_) {
	
		$_ = "'$_'" if /[a-z]/i;
	}
	
	return @_;
}