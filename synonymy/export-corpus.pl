#!/usr/bin/env perl

=head1 NAME

export-corpus.pl - export parsed dictionaries to a text file.

=head1 SYNOPSIS

export-corpus.pl [-s] [LANG]

=head1 OPTIONS AND ARGUMENTS

=item LANG

Can be 'la' or 'grc'. Others are ignored. Default is both.

=item -s --stem

Run English definitions through a stemmer.

=head1 DETAILS

export-corpus.pl converts the binary short definition files
stored by read-lexicon.pl to a text file, 'dict/dict.flat.txt'.
If both languages are specified, greek and latin will be
concatenated in a single file.

If you want to use the stemmer, you also need Lingua::Stem.

=head1 SEE ALSO

=over

=item read-lexicon.pl

- parse the dictionaries and save as binaries 

=back

See README.txt for details.

=cut

use strict;
use warnings;

use File::Path qw(make_path remove_tree);
use File::Spec::Functions;
use Storable qw(nstore retrieve);
use Getopt::Long;
use Pod::Usage;

use Tesserae::Mini;
use Tesserae::ProgressBar;

binmode STDERR, ":utf8";

# optional stemmer for English words

my $use_lingua = 0;
my $stemmer;

# display help?

my $help;

GetOptions(
	"stem!" => \$use_lingua,
	"help|?" => \$help);
	
if ($help) { pod2usage({-verbose => 1}) }

if ($use_lingua) {

	require Lingua::Stem;

	$stemmer = Lingua::Stem->new({-locale => 'en-uk'});
}

# languages to read

my @lang;

if (grep {/grc/i} @ARGV) { push @lang, 'grc'}
if (grep {/la/i}  @ARGV) { push @lang, 'la'}

unless (@lang) { @lang = qw/la grc/ }

#
# initialize some variables
#

my %term_count;

#
# part 1: 
#  - read dictionaries
#  - calculate tf scores
#  - index heads by terms for df scores

for my $lang (@lang) {

	# load cache

	my $file_dict = catfile('data', "$lang.short-def.cache");

	print STDERR "loading dictionary $file_dict\n";

	my %def = %{retrieve($file_dict)};
	
	my $n_heads = scalar(keys %def);

	print STDERR "$n_heads headwords\n";

	#
	# process each headword
	# 
	
	print STDERR "converting to bag of words\n";
	
	my $pr = ProgressBar->new($n_heads);

	while (my ($head, $aref) = each %def) {
		
		$pr->advance;
				
		my @def = @$aref;
		
		my $indexed = 0;
		
		# convert defs to a bag of words
	
		for my $def (@def) {
		
			my @words = split(/$non_word{en}/, $def);
			
			$stemmer->stem_in_place(@words) if $use_lingua;
			
			for my $term (@words) {
						
				$term = standardize('en', $term);
			
				next if $term eq "";
				
				$indexed = 1;
				$term_count{$term}{$head}++;
			}
		}
		
		delete $def{$head} unless $indexed;
	}
	
	$pr->finish;
	
	print STDERR scalar(keys %def) . " successfully indexed\n";
}

#
# part 2:
#  - rebuild a consolidated dictionary out of
#    the index of headwords by terms
#  - don't include terms that aren't common to
#    at least two headwords

# this holds the reconstructed, bag of words short defs

my %def;

{
	print STDERR "consolidating lexica, eliminating hapax legomena\n";
				
	#
	# loop over all english terms,
	#
	
	my $pr = ProgressBar->new(scalar keys %term_count);
	
	while (my ($term, $href) = each %term_count) {
	
		$pr->advance;
		
		# get the list of headwords containing this term;
		# flatten any duplicate headwords
				
		my @heads = keys %$href;
		
		# unless the term appears in defs for at least
		# two headwords, we don't need it.
		
		if (scalar(@heads) < 2) {
		
			delete $term_count{$term};
			next;
		}
		
		# add the term to the defs for its headwords
		#  - once for each time it appeared in the 
		#    original lexicon entry
		
		for (@heads) {
				
			push @{$def{$_}}, ($term)x($term_count{$term}{$_});
		}
	}
	
	$pr->finish;
}

#
# step 3
#  - write the dictionary to a file

{
	# the new dictionary file
	
	my $file_flat = catfile("dict", "dict.flat.txt");
		
	open (FH, ">:utf8", $file_flat) or die "can't write to $file_flat: $!";

	print STDERR "writing dictionary to $file_flat\n";
	
	# headwords are the keys to %def
	
	my $pr = ProgressBar->new(scalar(keys %def));
	
	while (my ($head, $aref) = each %def) {
	
		$pr->advance;
	
		print FH $head . "\t" . join(" ", @$aref) . "\n";
	}
	
	$pr->finish;
	
	close FH;
}

#
# and another thing
#  - write text-only definitions to file
#

my $file_corpus = catfile("dict", 'full-defs.flat.txt');

print STDERR "writing corpus to $file_corpus\n";

open (FH, ">:utf8", $file_corpus) or die "can't write to $file_corpus";

for my $lang (@lang) {

	my $file_dict = catfile('data', "$lang.full-def.cache");
	
	print STDERR "loading full defs from $file_dict\n";
	
	my %def = %{retrieve($file_dict)};
	
	print STDERR "exporting\n";
		
	# progress bar
	
	my $pr = ProgressBar->new(scalar keys %def);
	
	while (my ($head, $aref) = each %def) {
	
		$pr->advance();
		
		# write all defs to the file
		
		my $def = join(" ", @$aref);
		
		$def =~ s/\n/ /g;
		$def =~ s/\r/ /g;
		$def =~ s/<[^>]*lang="greek"[^>]*>([^>]+)<\/.+?>/&beta_to_uni($1)/eg;
		$def =~ s/<.+?>//g;
		$def =~ s/(?:^|\s)[[:punct:]]+(?=\s)//g;
		$def =~ s/\s+/ /g;
		
		print FH "$head\t$def\n";
	}
	$pr->finish();
}

close FH;
