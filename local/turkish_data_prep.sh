#!/bin/bash

# Copyright 2013   (Authors: Bagher BabaAli, Daniel Povey, Arnab Ghoshal)
#           2014   Brno University of Technology (Author: Karel Vesely)
# Apache 2.0.
#
# Amit
# This script creates the following 9 files in s5/data/local/data:
# x.spk2gender, x.spk2utt, x.utt2spk
# x.trans, x.txt, x.uttids
# x_sph.flist, x_sph.scp, x_wav.scp 
# where x = train, dev, test
#
# Change History
# Date		Author		Description
# 10/27		ad			Adapt timit_data_prep.sh to prepare turkish data
#


if [ $# -ne 2 ]; then
   echo "Argument should be a) Turkish directory of WAV files, and b) extension of transcript files, see ../run.sh for example."
   exit 1;
fi
wavdir=$1;
extn=$2;

# $extn can be either WRD or PHN
[ "$extn" = "WRD" ] || [ "$extn" = "PHN" ] || { echo "Error: Extension can be either WRD or PHN."; exit 1; }

dir=`pwd`/data/local/data
local=`pwd`/local
utils=`pwd`/utils
conf=`pwd`/conf

#delete everything under data/ except the subsets train.1k/ train100/ ...
find `pwd`/data -mindepth 1 -maxdepth 1 -type d  -not -iname "train[^ ]*" 2>/dev/null|xargs rm -rf  
mkdir -p $dir; 

# Get the transcription directory from the wav directory 
# This is done by replacing "speech-text" with "alignments" in the wav dir 
# /blah/blah/Turkish/data/speech-text
trans_dir=$(echo ${wavdir}| sed -e 's:^\(.*/\)\(.*\):\1alignments:')

. ./path.sh # Needed for KALDI_ROOT
#export PATH=$PATH:$KALDI_ROOT/tools/irstlm/bin
#sph2pipe=$KALDI_ROOT/tools/sph2pipe_v2.5/sph2pipe
#if [ ! -x $sph2pipe ]; then
#   echo "Could not find (or execute) the sph2pipe program at $sph2pipe";
#   exit 1;
#fi

#[ -f $conf/test_spk.list ] || error_exit "$PROG: Eval-set speaker list not found.";
#[ -f $conf/dev_spk.list ] || error_exit "$PROG: dev-set speaker list not found.";
[ -f $conf/test_spk.list ] || { echo "$PROG: Eval-set speaker list not found."; exit 1; }
[ -f $conf/dev_spk.list ] ||  { echo "$PROG: dev-set speaker list not found." ; exit 1; }

# First check if the train & test directories exist (these can either be upper-
# or lower-cased
if [ ! -d $wavdir/TRAIN -o ! -d $wavdir/TEST ] && [ ! -d $wavdir/train -o ! -d $wavdir/test ]; then
  echo "turkish_data_prep.sh: Spot check of command line argument failed"
  echo "Command line argument must be absolute pathname to Turkish directory of WAV files"
  echo "with name like /media/data/workspace/corpus/turkish/data/speech-text"
  exit 1;
fi

# Now check what case the directory structure is
uppercased=false
train_dir=train
test_dir=test
if [ -d $wavdir/TRAIN ]; then
  uppercased=true
  train_dir=TRAIN
  test_dir=TEST
fi

tmpdir=$dir/tmp; mkdir -p $tmpdir; 
#tmpdir=$(mktemp -d);
#trap 'rm -rf "$tmpdir"' EXIT

# Get the list of speakers. The list of speakers in the 5-speaker core test 
# set and the 14-speaker development set must be supplied to the script. All
# speakers in the 'train' directory are used for training.
if $uppercased; then
  tr '[:lower:]' '[:upper:]' < $conf/dev_spk.list > $tmpdir/dev_spk
  tr '[:lower:]' '[:upper:]' < $conf/test_spk.list > $tmpdir/test_spk
  ls -d "$wavdir"/TRAIN/s* | sed -e "s:^.*/::" > $tmpdir/train_spk
else
  tr '[:upper:]' '[:lower:]' < $conf/dev_spk.list > $tmpdir/dev_spk
  tr '[:upper:]' '[:lower:]' < $conf/test_spk.list > $tmpdir/test_spk
  ls -d "$wavdir"/train/s* | sed -e "s:^.*/::" > $tmpdir/train_spk
fi

cd $dir
for x in train dev test; do
  # First, find the list of audio files (all except s1012*.wav, s1054-012.wav, s1026-030.wav).
  # Transcriptions for a) train/s1012* are invalid, b) train/s1054-012 do not exist. 
  # c) gmm-align-compiled fails decoding s1026-030 unless very high beam width is used
  # Hence, exclude corresponding wav files.
  # Note: train & test sets are under different directories, but doing find on 
  # both and grepping for the speakers will work correctly.

  find $wavdir/{$train_dir,$test_dir} -not \( -iname 's1012*' \) -iname '*.WAV' \
    | grep -f $tmpdir/${x}_spk > $tmpdir/${x}_sph.flist    
  
  grep -v 's1054-012\|s1026-030' $tmpdir/${x}_sph.flist > ${x}_sph.flist   

  sed -e 's:.*/\(.*\)/\(.*\).WAV$:\1_\2:i' ${x}_sph.flist \
    > $tmpdir/${x}_sph.uttids
      
  paste $tmpdir/${x}_sph.uttids ${x}_sph.flist \
    | sort -k1,1 > ${x}_sph.scp     
    
  cat ${x}_sph.scp | awk '{print $1}' > ${x}.uttids

  # Now, Convert the transcripts into our format (no normalization yet)
  # Get the transcripts: each line of the output contains an utterance 
  # ID followed by the transcript.
  find $trans_dir/{$train_dir,$test_dir} -not \( -iname 's1012*' \) -iname "*.$extn"  \
	| grep -v 's1026-030' \
    | grep -f $tmpdir/${x}_spk > $tmpdir/${x}_phn.flist
  sed -e 's:.*/\(.*\)/\(.*\).'"$extn"'$:\1_\2:i' $tmpdir/${x}_phn.flist \
    > $tmpdir/${x}_phn.uttids    
  while read line; do    
    [ -f $line ] || { echo "Cannot find transcription file '$line'" ; exit 1; }
    cut -f3 -d' ' "$line" | tr '\n' ' ' | sed -e 's: *$:\n:'
  done < $tmpdir/${x}_phn.flist > $tmpdir/${x}_phn.trans
  paste $tmpdir/${x}_phn.uttids $tmpdir/${x}_phn.trans \
    | sort -k1,1 > ${x}.trans
  # Do normalization steps (e.g. reduce phoneme set) for the transcripts. Note we are not normalizing the lexicon here. 
  # Convert un-normalized trans ($x.trans) to  normalized trans ($x.txt)
  # cat ${x}.trans | $local/timit_norm_trans.pl -i - -m $conf/phones.60-48-39.map -to 48 | sort > $x.text || exit 1;  
  # Amit: Normalization of transcripts is done only if the transcripts contain phonemes. If the transcripts contains words, 
  # we do not normalize the transcripts. Simply create a corresponding .txt file since Kaldi looks for transcripts in 
  # .txt files.
  if [ "$extn" = "PHN" ]; then  
    perl $utils/transnorm.pl -map-from-col 1 -map-to-col 2 -trans-start-col 2  ${x}.trans $utils/phonemap/metu2worldmap.txt | sort > ${x}.txt || exit 1;     
  else
	cp ${x}.trans ${x}.txt	
  fi

  # Create wav.scp
  #awk '{printf("%s '$sph2pipe' -f wav %s |\n", $1, $2);}' < ${x}_sph.scp > ${x}_wav.scp
  cp ${x}_sph.scp ${x}_wav.scp

  # Make the utt2spk and spk2utt files.
  cut -f1 -d'_'  $x.uttids | paste -d' ' $x.uttids - > $x.utt2spk 
  cat $x.utt2spk | $utils/utt2spk_to_spk2utt.pl > $x.spk2utt || exit 1; 

  # Prepare gender mapping  
  while read spk; do
	if [ "$x" = "train" ]; then  
		spkinfofile=${wavdir}/${train_dir}/${spk}/${spk}.txt	
	else
		spkinfofile=${wavdir}/${test_dir}/${spk}/${spk}.txt	
	fi	    
    [ -f $spkinfofile ] || { echo "Cannot find spk info file '$spkinfofile'" ; exit 1; }
    # Now get the gender info from spkinfofile. dos2unix removes ^M  present at the end of line
    gender=$(grep -i "gender:" $spkinfofile | dos2unix |tr '[:upper:]' '[:lower:]'| awk '{print $2}')  
    echo "${spk}	${gender}"
  done < $tmpdir/${x}_spk > $x.spk2gender  
  dos2unix $x.spk2gender  
done

echo "Data preparation succeeded"
