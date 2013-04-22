#! /usr/bin/perl

=head1 NAME

read-lexicon.pl - Parse the big XML dictionaries from Perseus

=head1 SYNOPSIS

read-lexicon.pl [LANG]

=head1 ARGUMENTS

LANG may be 'la' or 'grc'. Others are ignored. Default is both.

=head1 DETAILS

Looks for the XML dictionaries at dict/LANG.lexicon.xml.

Parses dictionaries and creates the following binary files:

=over 1

	data/LANG.short-def.cache
	data/LANG.full-def.cache
	data/LANG.head.map

=back

These binary files are then exported to text files to
be read by the python scripts that calculate relatedness.
The reason we bother creating these binaries at all is
that in the future I hope to add some further scripts
that continue to process the entries, following redirection
in the XML to find definitions for headwords that don't
have their own.

=head1 SEE ALSO

install-dictionaries.sh - get dictionaries from Tesserae site
export-corpus.pl        - export binary files to plain text

See README.txt for workflow details.

=cut

use strict;
use warnings;

use utf8;

use File::Path qw(make_path remove_tree);
use File::Spec::Functions;
use Storable qw(nstore retrieve);
use Pod::Usage;
use Getopt::Long;

# requires HTML::Entities from CPAN;

use HTML::Entities;

# these are included included;
# if '.' is in @INC they should be visible
# from the directory containing the scripts

use Tesserae::ProgressBar;
use Tesserae::Mini;

#
# get user options
#

my $help;

GetOptions(
	'help|?' => \$help
	);
	
if ($help) { pod2usage({-verbose => 1}) }

#
# set languages from cmd line arguments
#

my @lang;

for (@ARGV) {

	if (/(la|grc)/i) { push @lang, lc($1) }
}

unless (@lang) { @lang = qw/la grc/ }

#
# some other params
#

# elements to delete from entries

my @del = qw/cit bibl orth etym itype pos number gen mood case tns per pron date usg gramGrp/;

# elements containing short def material

my %defpattern = (

	la  => qr'<hi [^>]*rend="ital"[^>]*>.+?<\/hi>',
	grc => qr'<tr\b.+?</tr>' );

#
# these hold parsed entries
#

our %short_def;
our %full_def;
our %redirect;
	
#
# process one language at a time
#

for my $lang (@lang) {

	my $file = catfile('dict', $lang . '.lexicon.xml');
	
	#
	# step 1: parse the file
	#

	# open the file

	open (FH, "<:utf8", $file) or die "can't open $file: $!";

	# parse

	local %short_def;
	local %full_def;
	local %redirect;

	print STDERR "parsing $file\n";

	my $pr = ProgressBar->new(-s $file);

	while (my $line = <FH>) {

		$pr->advance(length($line));
	
		next unless $line =~ /(<entryFree.+?\/entryFree>)/;
		
		parseEntry($lang, $1);
	}

	# close the file

	close (FH);

	$pr->finish();

	print STDERR "done\n";

	#
	# save the results
	#
	
	# create data dir
	
	make_path("data");
	
	# save results
	
	my $file_short = catfile("data", "$lang.short-def.cache");
	print "saving $file_short\n";
	nstore \%short_def, $file_short;
	
	my $file_full = catfile("data", "$lang.full-def.cache");
	print "saving $file_full\n";
	nstore \%full_def, $file_full;
	
	my $file_index = catfile("data", "$lang.head.map");
	print "saving $file_index\n";
	nstore \%redirect, $file_index;
}
	
	
#
# subroutines
#
	
sub parseEntry {

	my ($lang, $entry) = @_;
	
	# save the attributes of the entry
	
	$entry =~ /<entryFree(.+?)>(.+?)<\/entryFree>/;
	
	my $ent_attr = $1;
	$entry = $2;
	
	# get the headword
	
	$ent_attr =~ /key="(.+?)"/;
	
	my $key = $1;
	
	# standardize orthography
	
	my $head = standardize($lang, $key);
	
	if ($lang eq 'grc') {
	
		$head = beta_to_uni($head)
	}
	
	unless ($head =~ /[[:alpha:]]/) {
	
		return;
	}
	
	$redirect{$key} = $head;
		
	#
	# strip some unhelpful material from the entry
	#
	
	for (@del) {
		
		$entry =~ s/<$_\b.+?<\/$_>//g;
	}
	
	#
	# convert beta code, xml named entities to unicode
	#
	
 	$entry =~ s/<foreign lang="greek">(.+?)<\/foreign>/&greekWords($1)/eg;
	$entry = decode_entities($entry);
			
	#
	# save what remains
	#
	
	push @{$full_def{$head}}, $entry;
	
	#
	# now try to pare it down to just the defs
	#
	
	my @def = ($entry =~ /$defpattern{$lang}/g);
		
	# remove any xml tags remaining
	
	for (@def) {
	
		s/<.+?>//g;
	}
	
	push @{$short_def{$head}}, @def;
	
}

sub greekWords {

	my $string = shift;
	
	$string =~ s/($is_word{'grc'})/&beta_to_uni(&standardize('grc', $1))/eg;

	return $string;	
}

