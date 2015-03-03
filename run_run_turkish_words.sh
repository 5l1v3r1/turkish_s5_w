#! /bin/bash

tests="3 4 5 7"
# 1 = data prep
# 2 = feat prep
# 3 = monophone 
# 4 = triphone (deltas and deltas+deltas)
# 5 = LDA + MLLT 
# 6 = LDA + MLLT + MMI
# 7 = LDA+MLLT+SAT, decode
# 8 = MMI + SGMM + Dan's nnet2
# 9 = Karel's nnet

subsets="100 200 500"


# train with the full training set
#for i in $tests
#do
	#bash run_turkish_words.sh $i 
#done

# train with a subset of $n utts from training set
for n in $subsets
do
	for i in $tests
	do
		bash run_turkish_words.sh $i $n
	done
done

