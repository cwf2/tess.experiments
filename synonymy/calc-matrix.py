#!/usr/bin/env python
"""
use gensim to calculate headword similarities

This script reads the text file 'dict/dict.flat.txt', produced by
export-corpus.pl.  It uses the package 'gensim' to calculate 
vectors for all the headwords based on the tf-idf scores of the 
English terms in the headwords definitions.

See README.txt for workflow details.
"""

def main():

	import pickle
	import os
	import tempfile
	import codecs
	import unicodedata
	
	# needs non-core module gensim
	
	from gensim import corpora, models, similarities
	
	# open the dicitonary file
	
	file_dict = os.path.join('dict', 'dict.flat.txt')
	
	print 'reading ' + file_dict
	
	f = codecs.open(file_dict, encoding='utf8')
	
	# this will be our corpus
	
	corpus = []
	
	# this is an index, giving the id in the corpus
	# of each dictionary headword
	
	by_word = dict()
	
	# a progress counter
	
	size = 0
	prog  = 0
	total = os.stat(file_dict).st_size
	
	for i, line in enumerate(f):
	
		# show progress
	
		size += len(line.encode('utf-8'))
		
		if (100 * size / total > prog):
		
			print '\r{0:3d}% done'.format(100 * size / total),
			prog = 100 * size / total
	
		# split the line into headword, def
	
		head, short_def = line.split('\t')
		
		# force to combining form
		
		head = unicodedata.normalize('NFC', head)
		
		# give the head an id in the lookup
		
		by_word[head] = i
		
		# split the def into words;
		# add to corpus
		
		corpus.extend([short_def.split()])
		
	f.close()
	print
	

	#
	# create array to lookup headword by id
	#
	
	print 'creating reverse index'
	
	by_id = [''] * len(by_word)
	
	for k,v in by_word.iteritems():
		by_id[v] = k
	
	# save the lookup table
	
	file_lookup_word = os.path.join('data', 'lookup_word.pickle')
	
	print 'saving index ' + file_lookup_word
	
	f = open(file_lookup_word, "w")
	pickle.dump(by_word, f)
	f.close()
	
	# save the id lookup
	
	file_lookup_id = os.path.join('data', 'lookup_id.pickle')
	
	print 'saving index ' + file_lookup_id
	
	f = open(file_lookup_id, "w")
	pickle.dump(by_id, f)
	f.close()
	
	#
	# use gensim
	#
	
	# create dictionary
		
	print 'creating dictionary ' + file_dict
	
	dictionary = corpora.Dictionary(corpus)
	
	# convert each sample to a bag of words
	
	print 'converting each doc to bag-of-words'
	
	corpus = [dictionary.doc2bow(doc) for doc in corpus]
		
	# calculate tf-idf scores
	
	print 'creating tfidf model'
	
	tfidf = models.TfidfModel(corpus)
		
	print 'transforming the corpus to tfidf'
	
	corpus_tfidf = tfidf[corpus]
	
	# save corpus in market matrix format
	
	file_corpus = os.path.join('data', 'gensim.corpus.mm')
	
	print 'saving corpus as matrix ' + file_corpus
	
	corpora.MmCorpus.serialize(file_corpus, corpus_tfidf)

	# calculate similarities
	
	print 'calculating similarities (please be patient)'
	
	temp_dir = os.path.join(tempfile.gettempdir(), 'sims')
	
	index = similarities.Similarity(temp_dir, corpus_tfidf, len(corpus_tfidf))
	
	file_index = os.path.join('data', 'gensim.index')
	
	print 'saving similarity index ' + file_index
	
	index.save(file_index)


if __name__ == '__main__':
    main()
    
