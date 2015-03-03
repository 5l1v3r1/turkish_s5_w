#!/bin/bash

# Copyright 2013   (Authors: Daniel Povey, Bagher BabaAli)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# Call this script from one level above, e.g. from the s3/ directory.  It puts
# its output in data/local/.

# The parts of the output of this that will be needed are
# [in data/local/dict/ ]
# lexicon.txt
# extra_questions.txt
# nonsilence_phones.txt
# optional_silence.txt
# silence_phones.txt

# run this from ../

# Amit
# This script creates the following files: 
# 1) In data/local/dict:
# 		phones.txt (full list of phones)
# 		lexicon.txt   (word expanded to phone sequence) 
# 		(Note: For monophones, lexicon is just the identity mapping. phone "aa" is mapped to word "aa", b b, k k, etc)
# 		extra_questions.txt, 
# 		nonsilence_phones.txt
#		silence_phones.txt
# 		optional_silence.txt 	    
# 2) In data/local/data:
#		lm_train.txt		 
#       (Note: lm_train.txt must be in this format: <s> word1 word2 ... wordN </s>)
# 3) In data/local/lm_tmp:
#		lm_phone_bg.ilm.gz   (This is the intermediate monophone bigram LM file)
# 4) In data/local/nist_lm
#		lm_phone_bg.arpa.gz  (This is the final, compiled monophone bigram LM file in ARPA format)
#
# Change History
# Date		Author		Description
# 12/01		ad			Adapt timit_prepare_dict.sh to prepare turkish dict
#


if [ $# -ne 2 ]; then
   echo "Argument should be a) Turkish directory of WAV files, and b) extension of transcript files, see ../run.sh for example."
   exit 1;
fi

[ -f path.sh ] && . ./path.sh

trans_dir=$(echo $1| sed -e 's:^\(.*/\)\(.*\):\1alignments:')
extn=$2;
# $extn can be either WRD or PHN
[ "$extn" = "WRD" ] || [ "$extn" = "PHN" ] || { echo "Error: Extension can be either WRD or PHN."; exit 1; }

srcdir=data/local/data
dir=data/local/dict
lmdir=data/local/nist_lm
tmpdir=data/local/lm_tmp
utils=`pwd`/utils

rm -rf $dir $lmdir $tmpdir;
mkdir -p $dir $lmdir $tmpdir

[ -f path.sh ] && . ./path.sh

#(1) Dictionary preparation...
if [ "$extn" = "WRD" ]; then
# Create dict from the transcripts (train + test)
perl $utils/metudict2world.pl D $trans_dir $dir/lexicon_metu.txt 
# Convert the dict to WORLDBET format
perl $utils/metudict2world.pl T $dir/lexicon_metu.txt $utils/phonemap/metu2worldmap.txt $dir/lexicon_world.txt
sort -k1,1 $dir/lexicon_world.txt -o $dir/lexicon_world.txt
cp $dir/lexicon_world.txt $dir/lexicon.txt
else
# Create the lexicon, which is just an identity mapping
cut -d' ' -f2- $srcdir/train.txt | tr ' ' '\n' | sort -u > $dir/phones.txt
paste $dir/phones.txt $dir/phones.txt > $dir/lexicon.txt || exit 1;
#grep -v -F -f dir/silence_phones.txt $dir/phones.txt > $dir/nonsilence_phones.txt 
fi

# Make phones symbol-table (adding in silence and verbal and non-verbal noises at this point).
# We are adding suffixes _B, _E, _S for beginning, ending, and singleton phones.

# (2) Get phone lists...
grep -v -w sil $dir/lexicon.txt | \
  awk '{for(n=2;n<=NF;n++) { p[$n]=1; }} END{for(x in p) {print x}}' | sort > $dir/nonsilence_phones.txt
echo sil > data/local/dict/silence_phones.txt
echo sil > data/local/dict/optional_silence.txt
touch data/local/dict/extra_questions.txt # no extra questions, as we have no stress or tone markers.

# nonsilence phones; on each line is a list of phones that correspond
# really to the same base phone.

# Create the lexicon, which is just an identity mapping
# cut -d' ' -f2- $srcdir/train.text | tr ' ' '\n' | sort -u > $dir/phones.txt
# paste $dir/phones.txt $dir/phones.txt > $dir/lexicon.txt || exit 1;
# grep -v -F -f $dir/silence_phones.txt $dir/phones.txt > $dir/nonsilence_phones.txt 

# A few extra questions that will be added to those obtained by automatically clustering
# the "real" phones.  These ask about stress; there's also one for silence.
# cat $dir/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;
# cat $dir/nonsilence_phones.txt | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
#  $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; } } foreach $l (values %q) {print "$l\n";}' \
# >> $dir/extra_questions.txt || exit 1;

# (3) Create the word bigram LM  
  [ -z "$IRSTLM" ] && \
    echo "LM building won't work without setting the IRSTLM env variable" && exit 1;
  ! which $IRSTLM/bin/build-lm.sh 2>/dev/null  && \
    echo "IRSTLM does not seem to be installed (build-lm.sh not on your path): " && \
    echo "go to <kaldi-root>/tools and try 'make irstlm_tgt'" && exit 1;

  # Amit: Build bigram LM (-n 2: indicates bigram, lm_train.txt must be in this format: <s> word1 ... wordN </s>)
  # First generate an LM file in ARPA format using build-lm.sh. Then,
  # using compile-lm, convert LM in ARPA format to IRST format.
  if [ "$extn" = "WRD" ]; then
	cut -f2- $srcdir/train.txt | sed -e 's:^:<s> :' -e 's:$: </s>:' \
    > $srcdir/lm_train.txt
  else
	cut -d' ' -f2- $srcdir/train.txt | sed -e 's:^:<s> :' -e 's:$: </s>:' \
		> $srcdir/lm_train.txt
  fi
  $IRSTLM/bin/build-lm.sh -i $srcdir/lm_train.txt -n 2 -o $tmpdir/lm_phone_bg.ilm.gz  
  
  $IRSTLM/bin/compile-lm $tmpdir/lm_phone_bg.ilm.gz -t=yes /dev/stdout | \
  grep -v unk | gzip -c > $lmdir/lm_phone_bg.arpa.gz 

echo "Dictionary & language model preparation succeeded"
