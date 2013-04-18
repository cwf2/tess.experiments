#! /usr/bin/perl

#
# batch.prepare.pl - prepare a systematic set of tesserae searches
#
#   for Neil B.

=head1 NAME

batch.prepare.pl - prepare a systematic set of tesserae searches

=head1 SYNOPSIS

batch.prepare.pl [options]

=head1 DESCRIPTION

This script accepts tesserae search parameters specifying multiple values per parameter.
It then generates every combination of these parameters and spits them out in a list.
The idea is that you would then feed this list into batch.run.pl, which would run the
searches.

=head1 OPTIONS AND ARGUMENTS

=head2 Command-line mode (default)

The simplest way to use this script is to specify search parameters just as for
read_table.pl, namely:

=over

=item B<--source>

the source text

=item B<--target>

the target text

=item B<--unit>

unit to search: "line" or "phrase"

=item B<--feature>

feature to search on: "word", "stem", "syn", or "3gr"

=item B<--stop>

number of stop words

=item B<--stbasis>

stoplist basis: "corpus", "source", "target", or "both"

=item B<--dist>

max distance (in words) between matching words

=item B<--dibasis>

metric used to calculate distance: "freq", "freq-target", "freq-source", "span", 
"span-target", or "span-source"

=back

But here, unlike with read_table.pl, you can specify multiple values.  This can be done in
a couple of ways.  First, you can separate different values with a comma (but no space).
Second, for names of texts only, you can use the wildcard character '*' to match several
names at once.  Third, for numeric parameters only, you can specify a range by giving the
start and end values separated by a dash (but no space); optionally, you can append a 
"step" value, separated from the range by a colon (but no space), e.g. '1-10' or 
'10-20:2'. The default step is 1.

=head2 Other modes

=over

=item B<--interactive>

This flag initiates "interactive" mode.  The script will ask you what values or ranges 
you want for each of the available parameters.  Still under construction.

=item B<--file> I<FILE>

This will attempt to read parameters from a separate text file.  The file should be
arranged as follows.  Values for a given search parameter should be grouped together,
one per line, under a header in square brackets giving the name of the parameter.
Text names can use the wildcard as above.  Numeric ranges can be specified as above,
and in this case whitespace around the "-" or ":" chars is okay.  Alternately, you can
specify a range verbosely using one of the forms
	range(from=I; to=J)
or
	range(from=I; to=J; step=K)
where I, J, and K are integers.


=back

=head2 General options

=over
	
=item B<--parallel> I<N>

Allow I<N> processes to run simultaneously.  Since this script doesn't run the search,
this won't really do anything, but it can be used to calculate a more accurate ETA for 
your results.

=item B<--quiet>

Less output to STDERR.

=item B<--help>

Print usage and exit.

=back

To see some examples, try running 'perldoc batch.prepare.pl'.

=head1 EXAMPLES

Examples of command-line options:

  batch.prepare.pl  --target lucan.bellum_civile,statius.thebaid   \
                    --source vergil.aeneid.part.*                  \
                    --stop 5-10                                    \
                    --dist 4-20:4

Sample file for B<--batch> mode:

  # my batch file
  # -- comments beginning with '#' are ignored

  [source]
  vergil.aeneid.part.*
	
  [target]
  lucan.bellum_civile.part.*
  statius.thebaid.part.*
  silius_italicus.punica.part.*

  [stop]
  10 - 20 : 5		# range can have spaces

  [stbasis]
  both			# single values work too
	
  [dist]
  range(from=8; to=16; step=4)  # verbose range


=head1 KNOWN BUGS

"Interactive" mode doesn't work yet for setting anything other than source and target.

I don't think --quiet does anything right now.

Nothing has really been tested much.

=head1 SEE ALSO

batch.run.pl

=head1 COPYRIGHT

University at Buffalo Public License Version 1.0.
The contents of this file are subject to the University at Buffalo Public License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://tesserae.caset.buffalo.edu/license.txt.

Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.

The Original Code is batch.prepare.pl.

The Initial Developer of the Original Code is Research Foundation of State University of New York, on behalf of University at Buffalo.

Portions created by the Initial Developer are Copyright (C) 2007 Research Foundation of State University of New York, on behalf of University at Buffalo. All Rights Reserved.

Contributor(s): Chris Forstall, Xia Lu, Neil Bernstein

Alternatively, the contents of this file may be used under the terms of either the GNU General Public License Version 2 (the "GPL"), or the GNU Lesser General Public License Version 2.1 (the "LGPL"), in which case the provisions of the GPL or the LGPL are applicable instead of those above. If you wish to allow use of your version of this file only under the terms of either the GPL or the LGPL, and not to allow others to use your version of this file under the terms of the UBPL, indicate your decision by deleting the provisions above and replace them with the notice and other provisions required by the GPL or the LGPL. If you do not delete the provisions above, a recipient may use your version of this file under the terms of any one of the UBPL, the GPL or the LGPL.

=cut


use strict;
use warnings;

use File::Copy;
use File::Spec::Functions;
use Pod::Usage;
use Term::UI;
use Term::ReadLine;
use Getopt::Long;

use Data::Dumper;

use lib '/var/www/tesserae/perl';
use TessSystemVars;
use EasyProgressBar;

#
# initialize variables
#

my $lang = 'la';

my @params = qw/source
	target
	unit
	feature
	stop
	stbasis
	dist
	dibasis/;

my $interactive = 0;
my $parallel    = 0;
my $quiet       = 0;
my $file_batch;
my $help;

my %par;
my %opt;

# user options

for (@params) { 

	$par{$_} = undef;
	$opt{"$_=s"} = \$par{$_};
}

GetOptions(%opt,
		'parallel=i'  => \$parallel,
		'help'        => \$help,
		'interactive' => \$interactive,
		'file=s'      => \$file_batch
	);
	
if    ($help)        { pod2usage(1) }

if    ($file_batch)  { parse_file($file_batch) }

elsif ($interactive) { interactive() }

unless ($par{source} and $par{target}) {

	print STDERR "Source or target unspecified.  Try using --interactive.\n";
	exit;
}

# parse user input for ranges, multi values

parse_params();

#
# initialize parallel processing
#

my $prmanager;

if ($parallel) {

	require Parallel::ForkManager;

	$prmanager = Parallel::ForkManager->new($parallel);
	
	$quiet = 1;
}

#
# calculate all combinations
#

my @combi = ([]);

for my $pname (@params) {

	next unless defined $par{$pname};
	
	my @combi_ = @combi;
	@combi = ();
	
	for my $cref (@combi_) {
	
		for my $val (@{$par{$pname}}) {
		
			push @combi, [@{$cref}, "--$pname" => $val];
		}
	}
}

#
# print all combinations
#

my $n = scalar @combi; 

print STDERR "Generates $n combinations.\n";
print STDERR "If each run takes 10 seconds, this batch will take ";
print STDERR parse_time($n * 10) . "\n";

if ($parallel) {

	print STDERR "With parallel processing, it could take as little as ";
	print STDERR parse_time($n * 10 / $parallel) . "\n";
}

my $maxlen = length($#combi);
my $format = "%0${maxlen}i";

for (my $i = 0; $i <= $#combi; $i++) {

	my @opt = @{$combi[$i]};
	
	push @opt, ('--bin' => sprintf($format, $i));
	
	print join(" ",	catfile($fs_cgi, "read_table.pl"), @opt) . "\n";
}


#
# subroutines
#

#
# parse command-line options 
# for multiple values, ranges
#

sub parse_params {

	for (@params) {

		next unless defined $par{$_};
		
		my @val;
		my @working = $par{$_};
			
		if ($par{$_} =~ /,/) {
	
			@working = split(/,/, $par{$_});
		}
		
		for (@working) {

			if (/(\d+)-(\d+)(?::(\d+))?/) {
	
				my $low  = $1;
				my $high = $2;
				my $step = $3 || 1;
		
				if ($low > $high) { ($low, $high) = ($high, $low) }
			
				for (my $i = $low; $i <= $high; $i += $step) {
	
					push @val, $i;
				}
			}
			else {
				push @val, $_;
			}
		}

		$par{$_} = \@val;
	}
	
	# expand text names for source, target
		
	for (qw/source target/) {
	
		my @list;
		my @all = @{get_all_texts($lang)};

		for my $spec (@{$par{$_}}) {
		
			$spec =~ s/\./\\./g;
			$spec =~ s/\*/.*/g;
			$spec = "^$spec\$";
			
			push @list, (grep { /$spec/ } @all);
		}
		
		@list = sort {text_sort($a, $b)} @{TessSystemVars::uniq(\@list)};
		
		$par{$_} = \@list;
	}
}

#
# get the list of all texts installed
#

sub get_all_texts {

	my $lang = shift;
	
	my @texts;
	
	my $dir = catdir($fs_data, 'v3', $lang);

	opendir (DH, $dir);

	push @texts, (grep {!/^\./ and -d catdir($dir, $_)} readdir DH);

	closedir (DH);
		
	return \@texts;
}

#
# turn seconds into nice time
#

sub parse_time {

	my %name  = ('d' => 'day',
				 'h' => 'hour',
				 'm' => 'minute',
				 's' => 'second');
				
	my %count = ('d' => 0,
				 'h' => 0,
				 'm' => 0,
				 's' => 0);
	
	$count{'s'} = shift;
	
	if ($count{'s'} > 59) {
	
		$count{'m'} = int($count{'s'} / 60);
		$count{'s'} -= ($count{'m'} * 60);
	}
	if ($count{'m'} > 59) {
	
		$count{'h'} = int($count{'m'} / 60);
		$count{'m'} -= ($count{'h'} * 60);		
	}
	if ($count{'h'} > 23) {
	
		$count{'d'} = int($count{'h'} / 24);
		$count{'d'} -= ($count{'h'} * 24);
	}
	
	my @string = ();
	
	for (qw/d h m s/) {
	
		next unless $count{$_};
		
		push @string, $count{$_} . " " . $name{$_};
		
		$string[-1] .= 's' if $count{$_} > 1;
	}
	
	my $sep = " ";
	
	if (scalar @string > 1) {
			
		$string[-1] = 'and ' . $string[-1];
		
		$sep = ', ' if scalar @string > 2;
	}
	
	return join ($sep, @string);
}

#
# prompt for options interactively
#

sub interactive {

	#
	# set up terminal interface
	#

	my $term = Term::ReadLine->new('myterm');

	my @all = @{get_all_texts($lang)};
	
	# prompt for source, target
	
	for my $dest (qw/source target/) {
	
		my $message = 'Choose source texts:';
		my $prompt  = 'Select one or more texts by number: ';
		
		my %selected;
		
		for (@all) { $selected{$_} = 0 };
		
		my $done = 0;
		
		until ($done) {

			my @choices;
			
			for my $text (@all) {
			
				push @choices, ($selected{$text} ? '* ' : '') . $text;
			}
			
			push @choices, 'Done';
			
			my @reply = $term->get_reply(
					prompt   => $prompt,
					print_me => $message,
					choices  => \@choices,
					default  => 'Done',
					multi    => 1);
			
			for (@reply) {
			
				if (/^Done$/) {
				
					$done = 1;
				}
				else {
				
					s/^\*\s//;
					
					$selected{$_} = ! $selected{$_};
				}
			}
		}
		
		$par{$dest} = join(',', grep { $selected{$_} } @all);
	}	
}

#
# sort parts in right order
#

sub text_sort {

	my ($l, $r) = @_;

	unless ($l =~ /(.+)\.part\.(.*)/) {
	
		return ($l cmp $r);
	}
	
	my ($lbase, $lpart) = ($1, $2);
	
	unless ($r =~ /(.+)\.part\.(.*)/) {
	
		return ($l cmp $r);
	}
	
	my ($rbase, $rpart) = ($1, $2);	
	
	unless ($lbase eq $rbase) {
	
		return ($l cmp $r)
	}

	if ($lpart =~ /\D/ or $rpart =~ /\D/) {
	
		return ($l cmp $r)
	}
	
	return ($lpart <=> $rpart);
}

#
# parse a config file for parameters
#

sub parse_file {

	my $file = shift;
	
	open (FH, "<", $file) || die "can't open $file: $!";
	
	my $text;
	
	while (my $line = <FH>) {
	
		$text .= $line;
	}
	
	close FH;
	
	$text =~ s/[\x12\x15]+/\n/sg;
	
	my %section;
	
	my $pname = "";
	
	my @line = split(/\n+/, $text);
	
	my @all = @{get_all_texts($lang)};
	
	for my $l (@line) {
		
		if ($l =~ /\[\s*(\S.+).*\]/) {
		
			$pname = lc($1);
			next;
		}	

		$l =~ s/#.*//;
		
		if ($l =~ /range\s*\(from\D*(\d+)\b.*?to\D*(\d+)(.*)/) {
		
			my ($from, $to, $tail) = ($1, $2, $3);
			
			my $step = 1;
			
			if (defined $tail and $tail =~ /step\D*(\d+)/) {
			
				$step = $1;
			}
			
			$l = "$from-$to:$step";
		}
		elsif ($l =~ /(\d+)\s*-\s*(\d+)(.*)/) {
		
			my ($from, $to, $tail) = ($1, $2, $3);
			
			my $step = 1;
			
			if (defined $tail and $tail =~ /:\s*(\d+)/) {
			
				$step = $1;
			}
			
			$l = "$from-$to:$step";
		}

		push @{$section{$pname}}, $l;
	}
	
	for (keys %section) {
	
		$par{$_} = join(',', @{$section{$_}});
	}
}