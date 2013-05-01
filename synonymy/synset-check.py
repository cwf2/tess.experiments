#!/usr/bin/env python
"""
Return the top similarity hits for query headwords

Prompts the user for query words.  The top n hits 
from the similarity matrix are returned to STDOUT.

Requires package 'gensim'.

See README for workflow details.

 -- For Harry Diakoff.
"""

import pickle
import os
import sys
import re
import codecs
import unicodedata
import argparse
from gensim import corpora, models, similarities
from Tesserae import progressbar


class SynPair:
	"""store information about a pair of words purported to be synonyms"""
	def __init__(self, synsets=None, sim=None, ranka=None, rankb=None):
		
		self.synsets = synsets;
		self.sim     = sim;
		self.ranka   = ranka;
		self.rankb   = rankb;


class LexQuery:
	"""translate queries between strings and ids"""
	
	_by_word = {}
	_by_id   = []
	
	@classmethod	
	def load_by_word(self, file, quiet=0):
		"""load word->id dictionary"""
		
		if not quiet:
			print 'Loading index ' + file
		
		f = open(file, 'r')
		LexQuery._by_word = pickle.load(f)
		f.close()
	
	@classmethod
	def load_by_id(self, file, quiet=0):
		"""load id->word list"""
		
		# the index by id	
		
		if not quiet:
			print 'Loading index ' + file
		
		f = open(file, 'r')
		LexQuery._by_id = pickle.load(f)
		f.close()
		
	@classmethod	
	def LookupByWord(self, word):
		"""look up a word, return id"""
		
		id = None
		
		if word in LexQuery._by_word:
			id = LexQuery._by_word[word] 
		
		return id
	
	@classmethod
	def LookupById(self, id):
		"""look up an id, return word"""
		
		word = None
		
		if len(LexQuery._by_id) >= id:
			word = LexQuery._by_id[id] 
		
		return word
		
	def __init__(self, byword=None, byid=None):
		"""new query object"""
				
		if byword is not None:
			self.word = unicodedata.normalize('NFC', byword.decode('utf8'))
			self.id   = LexQuery.LookupByWord(self.word)
			
		elif byid is not None:
			self.id   = int(byid)
			self.word = LexQuery.LookupById(self.id)
			
		else:
			self.word = None
			self.id   = None
			

class SimsDB:
	"""a class to keep all the precomputed gensim data in"""
	
	def __init__(self, file_corpus, file_index, quiet=0):
		
		self.load_corpus(file_corpus, quiet)
		self.load_index(file_index, quiet)
	
	def load_corpus(self, file_corpus, quiet=0):
		"""load the corpus"""
		
		if not quiet:
			print 'Loading corpus ' + file_corpus
		
		self.corpus = corpora.MmCorpus(file_corpus)
	
	def load_index(self, file_index, quiet=0):
		"""load the similarities index"""
		
		if not quiet:		
			print 'Loading similarity index ' + file_index
		
		self.index = similarities.Similarity.load(file_index)
	
	def get_sims(self, query):
		"""test query against the similarity matrix"""
		
		sims = None
		
		# query the similarity matrix
		
		sims = self.index[self.corpus[query.id]]
		sims = sorted(enumerate(sims), key=lambda item: -item[1])
				
		return sims


def parse_synsets(file, quiet):
	"""parse a file of synsets"""
	
	if not quiet:
		print 'Reading synsets from {0}'.format(file)
	
	# a progress counter
	
	pr = progressbar.ProgressBar(os.stat(file).st_size)
	
	try: 
		f = codecs.open(file, encoding='utf_8')
	except IOError as err:
		print "can't read {0}: {1}".format(file, str(err))
		return None
		
	# this dictionary holds links between heads
	
	links = dict()
	
	# each line should be a separate record
	
	for line in f:
		
		# show progress
		
		pr.advance(len(line.encode('utf-8')))
		
		# check for synset id
		
		m = re.match('<synset no="(\d+)">', line)
		
		# skip lines that don't match synset format
		
		if m is None:
			continue
		
		n = int(m.group(1))
		
		# get the list of greek words in this set
		
		nodes = re.findall('<grcword>(.+?)</grcword>', line)
		
		nodes = [unicodedata.normalize('NFC', node) for node in nodes]
		nodes = [node.encode('utf8') for node in nodes]
		
		# create a link for every possible pair
		
		for i in range(len(nodes)-1):
			for j in range(i+1, len(nodes)):
				
				keypair = '{0}->{1}'.format(*sorted([nodes[i],nodes[j]]))
				
				# create a SynPair instance if one doesn't exist
				
				if keypair not in links:
					links[keypair] = SynPair()
				
				# note that the two nodes are joined by this synset
	
				if links[keypair].synsets is None:
					links[keypair].synsets = set([n])
				else:
					links[keypair].synsets.add(n)
	
	return links		


def recip_lookup(pair, link, simsdb, f):
	"""lookup syn pair in sim database, add info"""
	
	query_a, query_b = [LexQuery(byword=word) for word in pair.split('->')]
		
	if query_a.id is not None and query_b.id is not None:
				
		hits_a = simsdb.get_sims(query_a)
			
		for i in range(len(hits_a)):
						
			if hits_a[i][0] == query_b.id:
				
				link.sim   = hits_a[i][1]
				link.ranka = i
					
				break
				
		hits_b = simsdb.get_sims(query_b)
			
		for i in range(len(hits_b)):
						
			if hits_b[i][0] == query_a.id:
				
				link.rankb = i
				
				break


def main():
				
	#
	# check for options
	#
	
	parser = argparse.ArgumentParser(
				description='Check synsets against similarities matrix', 
				epilog='See README.txt for details.')
	parser.add_argument('file', metavar='FILE', type=str,
				help='synset file')
	parser.add_argument('-q', '--quiet', action='store_const', const=1,
				help='print less info')

	
	opt = parser.parse_args()
		
	#
	# load data created by calc-matrix.py
	#
	
	LexQuery.load_by_word(file='data/lookup_word.pickle', quiet=opt.quiet)
	LexQuery.load_by_id(file='data/lookup_id.pickle', quiet=opt.quiet)
	
	#
	# load the gensim corpus & similarities
	#
		
	simsdb = SimsDB(file_corpus = 'data/gensim.corpus.mm',
					file_index  = 'data/gensim.index',
					quiet       = opt.quiet)
 
	#
	# load synset data from input file
	#
	
	links = parse_synsets(file=opt.file, quiet=opt.quiet)

	#
	# check all synpairs 
	#
	
	f = open('test.results', 'w')
	
	print 'cross-referencing synsets'
	
	pr = progressbar.ProgressBar(len(links), quiet=1)
	
	for pair, link in links.iteritems():
	
		pr.advance()
		sys.stderr.write('\r{0}/{1}'.format(pr._current, pr._total))
		
		recip_lookup(pair, link, simsdb, f)
		f.write('{0}\t{1}\t{2}\t{3}\t{4}\n'.format(
			pair, 
			link.sim, 
			link.ranka, 
			link.rankb,
			';'.join([str(synset) for synset in link.synsets])
		))
		f.flush()
		
	f.close()	


# call function main as default action

if __name__ == '__main__':
    main()
