#! /usr/bin/python
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

by_word  = dict()
corpus   = []
by_id    = []
index    = []
full_def = dict()

def main():
	
	#
	# check for options
	#
	
	parser = argparse.ArgumentParser(
				description='Query the headword similarities matrix', 
				epilog='See README.txt for details.')
	parser.add_argument('-n', '--results', default=25, type=int)
	parser.add_argument('-b', '--batch')
	
	opt = parser.parse_args()
	
	quiet = 0
	
	if opt.batch is not None:
		quiet = 1

	#
	# read the text-only defs
	#
	
	file_dict = 'dict/full-defs.flat.txt'
	
	if not quiet:
		print 'Reading ' + file_dict
	
	f = codecs.open(file_dict, encoding='utf_8')
		
	# store the defs
	
	global full_def

	# a progress counter
	
	size  = 0
	prog  = 0
	total = os.stat(file_dict).st_size
	
	for line in f:
	
		# show progress
	
		if not quiet:
			size += len(line.encode('utf-8'))
			
			if (100 * size / total > prog):
			
				print '\r{0:3d}% done'.format(100 * size / total),
				prog = 100 * size / total
	
		# split the line into headword, def
	
		head, def_ = line.split('\t')
		
		# force to combining form
		
		head = unicodedata.normalize('NFC', head)
		
		# give the head an id in the lookup
		
		full_def[head] = def_
				
	f.close()

	if not quiet:
		print

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
	
	file_corpus = 'data/gensim.corpus.mm'
	
	corpus = corpora.MmCorpus(file_corpus)

	# the similarities index
	
	global index
	
	file_index = 'data/gensim.index'

	if not quiet:		
		print 'Loading similarity index ' + file_index
	
	index = similarities.Similarity.load(file_index)
 
 	if not quiet:
		print 'Ready for queries.'
		print '  To quit, enter an empty query'

	#
	# accept headword queries
	#
	
	# from file, if given
	
	if opt.batch is not None:
		try: 
			f = codecs.open(opt.batch, encoding='utf_8')
		except IOError as err:
			print "can't read {0}: {1}".format(file_batch, str(err))
		
		for line in f:
			q = line.split()[0]			
			q = unicodedata.normalize('NFC', q)

			get_results(q, opt.results)


	# otherwise from stdin

	else:
		while 1:		
			try:
				q = raw_input('headword: ')
			except EOFError:
				break
				
			if q == '':
				break 
			
			try:	
				q = q.decode(sys.stdin.encoding)
			except:
				try:
					q = q.decode('utf8')
				except:
					continue

			q = unicodedata.normalize('NFC', q)
			
			get_results(q, opt.results)
		
		
def get_results(q, n):
	"""test query q against the similarity matrix"""

	# decompose any precombined chars into separated
	# letters + combining diacritics

	if (q in by_word):
	
		q_id = by_word[q]
		
		print 'query = ' + q.encode('utf8')
		
		# query the similarity matrix
		
		sims = index[corpus[q_id]]
		sims = sorted(enumerate(sims), key=lambda item: -item[1])
		
		# only return n results
		
		if n > len(sims): 
			n = len(sims)
		
		sims = sims[0:n]
		
		# display each result, its score, and text-only def
		
		for pair in sims:
			
			r_id, score = pair
			
			r = by_id[r_id]
						
			print '{0}\t{1:.3f}  {2}'.format(
				r.encode('utf8'), 
				float(score), 
				full_def[r].encode('utf8'))
	else:	
		
		print q.encode('utf8') + ' is not indexed.'

	print
	print


if __name__ == '__main__':
    main()
