#!/usr/bin/env python
"""
Return the top similarity hits for query headwords

Prompts the user for query words.  The top n hits 
from the similarity matrix are returned to STDOUT.

Requires package 'gensim'.

See README.txt for workflow details.
"""

import pickle
import os
import sys
import codecs
import unicodedata
import argparse
from gensim import corpora, models, similarities

from Tesserae import progressbar

by_word  = dict()
corpus   = []
by_id    = []
index    = []
full_def = dict()


def get_results(q, n, file, filter):
	"""test query q against the similarity matrix"""
		
	row = [q]
		
	if (q in by_word):
		q_id = by_word[q]
				
		# query the similarity matrix
		
		sims = index[corpus[q_id]]
		sims = sorted(enumerate(sims), key=lambda item: -item[1])
				
		# display each result, its score, and text-only def
		
		for pair in sims:	
			r_id, score = pair
			
			r = by_id[r_id]
			
			if filter and is_greek(r) != (filter - 1):
				continue
			
			row.append(r)
					
			if len(row) > n:
				break
		
		if file is not None:
			file.write(u','.join(row) + '\n')
		else:
			print u','.join(row)


def is_greek(form):
	'''try to guess whether a word is greek'''
	
	for c in form:
		if ord(c) > 255:
			return 1
	
	return 0


def main():
	
	#
	# check for options
	#
	
	parser = argparse.ArgumentParser(
			description='Query the headword similarities matrix')
	parser.add_argument('-n', '--results', metavar='N', default=2, type=int,
			help = 'Display top N results')
	parser.add_argument('-t', '--translate', metavar='MODE', default=0, type=int,
			help = 'Translation mode: 1=Latin to Greek; 2=Greek to Latin')
	parser.add_argument('-l', '--lsi', action='store_const', const=1,
			help = 'Use LSI to reduce dimensionality')
	
	opt = parser.parse_args()
	
	if opt.translate not in [1, 2]:
		opt.translate = 0
	
	quiet = 0
		
	#
	# read the text-only defs
	#
	
	file_dict = 'data/full_defs.pickle'
	
	if not quiet:
		print 'Reading ' + file_dict

	f = open(file_dict, 'r')
	
	# store the defs
	
	global full_def
	
	full_def = pickle.load(f)
	
	f.close()
	
	#
	# load data created by calc-matrix.py
	#
		
	# the index by word
	
	global by_word
	
	file_lookup_word = 'data/lookup_word.pickle'
	
	if not quiet:
		print 'Loading index ' + file_lookup_word
	
	f = open(file_lookup_word, 'r')
	by_word = pickle.load(f)
	f.close()
	
	# the index by id
	
	global by_id
	
	file_lookup_id = 'data/lookup_id.pickle'
	
	if not quiet:
		print 'Loading index ' + file_lookup_id
	
	f = open(file_lookup_id, 'r')
	by_id = pickle.load(f)
	f.close()
	
	# the corpus
	
	global corpus
	
	if opt.lsi is None:
		file_corpus = 'data/gensim.corpus_tfidf.mm'
	else:
		file_corpus = 'data/gensim.corpus_lsi.mm'
	
	corpus = corpora.MmCorpus(file_corpus)
	
	# the similarities index
	
	global index
	
	file_index = 'data/gensim.index'
	
	if not quiet:		
		print 'Loading similarity index ' + file_index
	
	index = similarities.Similarity.load(file_index)
	
 	if not quiet:
		print 'Exporting dictionary'
	
	file_output = codecs.open('trans2.csv', 'w', encoding='utf_8')
	
	pr = progressbar.ProgressBar(len(by_word), quiet)
	
	# take each headword in turn as a query
	
	for q in by_word:
		pr.advance()
		
		q = unicodedata.normalize('NFC', q)
			
		if opt.translate and is_greek(q) == (opt.translate - 1):
			continue

		get_results(q, opt.results, file_output, opt.translate)


if __name__ == '__main__':
    main()
