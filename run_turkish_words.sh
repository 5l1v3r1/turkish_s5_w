#!/bin/bash

. cmd.sh
set -e # exit on error
# Acoustic model parameters
numLeavesTri1=1500 #was 1800
numGaussTri1=7500  #was 9000
numLeavesMLLT=1500 #was 1800
numGaussMLLT=7500  #was 9000
numLeavesSAT=1500
numGaussSAT=7500

# call the next line with the directory where the RM data is
# (the argument below is just an example).  This should contain
# subdirectories named as follows:
#    rm1_audio1  rm1_audio2	rm2_audio
#local/rm_data_prep.sh /mnt/matylda2/data/RM
#local/rm_data_prep.sh /home/dpovey/data/LDC93S3A/rm_comp

# Directory where wav files are present
TURKROOT=/media/data/workspace/corpus/turkish/data/speech-text
# Enter either "WRD" (to measure WER) or "PHN" (to measure PER)
extn="WRD"
stage=$1
# If you want to train on a subset of trn data, enter a number. Otherwise, leave it empty (which means train on full set)
num_trn_utt=$2

# [[ $num_trn_utt =~ ^[0-9]+$ ]] returns true if $num_trn_utt is a number
[[ $num_trn_utt =~ ^[0-9]+$ ]] && echo "Will train acoustic models on $num_trn_utt utterances" \
	|| echo "Will train acoustic models on all utterances"

if [[ $stage -eq 1 ]]; then
# If $num_trn_utt is empty (train full set), then run the data prep and feat generation part.
local/turkish_data_prep.sh  $TURKROOT $extn

local/turkish_prepare_dict.sh $TURKROOT $extn

echo "Preparing lang models for type $extn ...";
if [ "$extn" = "PHN" ]; then  
utils/prepare_lang.sh --position-dependent-phones false --num-sil-states 3 \
 data/local/dict 'sil' data/local/lang data/lang
else 
utils/prepare_lang.sh data/local/dict 'SIL' data/local/lang data/lang
fi

local/turkish_format_data.sh
fi

if [[ $stage -eq 2 ]]; then
# mfccdir should be some place with a largish disk where you
# want to store MFCC features.   You can make a soft link if you want.
# Generate features for the full train dev test set even if you chose to train on subsets
featdir=mfcc

for x in train dev test; do
  [ -s  data/$x/spk2utt ] && \
  { steps/make_mfcc.sh --nj 8 --cmd "run.pl" data/$x exp/make_feat/$x $featdir
    #steps/make_plp.sh --nj 8 --cmd "run.pl" data/$x exp/make_feat/$x $featdir
    steps/compute_cmvn_stats.sh data/$x exp/make_feat/$x $featdir
  }
done

# Make a combined data dir where the data from all the test sets goes-- we do
# all our testing on this averaged set.  This is just less hassle.  We
# regenerate the CMVN stats as one of the speakers appears in two of the
# test sets; otherwise tools complain as the archive has 2 entries.

#utils/combine_data.sh data/test data/test_{mar87,oct87,feb89,oct89,feb91,sep92}
#steps/compute_cmvn_stats.sh data/test exp/make_feat/test $featdir
fi

# Amit: Everything below this is same as rm/run.sh for word models and 
# timit/run.sh for phn models
train=train${num_trn_utt}
mono=mono${num_trn_utt}
mono_ali=mono_ali${num_trn_utt}
tri1=tri1${num_trn_utt}
tri1_ali=tri1_ali${num_trn_utt}
tri2a=tri2a${num_trn_utt}
tri2b=tri2b${num_trn_utt}
tri2b_ali=tri2b_ali${num_trn_utt}
tri3b=tri3b${num_trn_utt}
tri3b_ali=tri3b_ali${num_trn_utt}

utils/subset_data_dir.sh data/train ${num_trn_utt:-1000} data/train${num_trn_utt:-.1k}

if [[ $stage -eq 3 ]]; then
steps/train_mono.sh --nj 4 --cmd "$train_cmd" data/train${num_trn_utt:-.1k} data/lang exp/$mono

#show-transitions data/lang/phones.txt exp/tri2a/final.mdl  exp/tri2a/final.occs | perl -e 'while(<>) { if (m/ sil /) { $l = <>; $l =~ m/pdf = (\d+)/|| die "bad line $l";  $tot += $1; }} print "Total silence count $tot\n";'

utils/mkgraph.sh --mono data/lang exp/$mono exp/$mono/graph

steps/decode.sh --config conf/decode.config --nj 5 --cmd "$decode_cmd" \
  exp/$mono/graph data/test exp/$mono/decode

# Get alignments from monophone system.
steps/align_si.sh --nj 8 --cmd "$train_cmd" \
  data/$train data/lang exp/$mono exp/${mono_ali}
fi

if [[ $stage -eq 4 ]]; then
# train tri1 [first triphone pass]
steps/train_deltas.sh --cmd "$train_cmd" \
 $numLeavesTri1 $numGaussTri1 data/$train data/lang exp/${mono_ali} exp/$tri1
 
# decode tri1
utils/mkgraph.sh data/lang exp/$tri1 exp/$tri1/graph
steps/decode.sh --config conf/decode.config --nj 5 --cmd "$decode_cmd" \
  exp/$tri1/graph data/test exp/$tri1/decode

local/test_decoders.sh exp/$tri1/decode/tmp # This is a test program that we run only in the
											# RM setup, it does some comparison tests on decoders
											# to help validate the code.
#draw-tree data/lang/phones.txt exp/tri1/tree | dot -Tps -Gsize=8,10.5 | ps2pdf - tree.pdf

# align tri1
steps/align_si.sh --nj 8 --cmd "$train_cmd" \
  --use-graphs true data/$train data/lang exp/$tri1 exp/${tri1_ali}

# train tri2a [delta+delta-deltas]
steps/train_deltas.sh --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
 data/$train data/lang exp/${tri1_ali} exp/$tri2a

# decode tri2a
utils/mkgraph.sh data/lang exp/$tri2a exp/$tri2a/graph
steps/decode.sh --config conf/decode.config --nj 5 --cmd "$decode_cmd" \
  exp/$tri2a/graph data/test exp/$tri2a/decode
fi

if [[ $stage -eq 5 ]]; then
# train and decode tri2b [LDA+MLLT]
steps/train_lda_mllt.sh --cmd "$train_cmd" \
  --splice-opts "--left-context=3 --right-context=3" \
 $numLeavesMLLT $numGaussMLLT data/$train data/lang exp/${tri1_ali} exp/$tri2b
utils/mkgraph.sh data/lang exp/$tri2b exp/$tri2b/graph

steps/decode.sh --config conf/decode.config --nj 5 --cmd "$decode_cmd" \
   exp/$tri2b/graph data/test exp/$tri2b/decode

# you could run these scripts at this point, that use VTLN.
# local/run_vtln.sh
# local/run_vtln2.sh

# Align all data with LDA+MLLT system (tri2b)
steps/align_si.sh --nj 8 --cmd "$train_cmd" --use-graphs true \
   data/$train data/lang exp/$tri2b exp/${tri2b_ali}
fi

if [[ $stage -eq 6 ]]; then   
#  Do MMI on top of LDA+MLLT.
steps/make_denlats.sh --nj 8 --cmd "$train_cmd" \
  data/train data/lang exp/tri2b exp/tri2b_denlats
steps/train_mmi.sh data/train data/lang exp/tri2b_ali exp/tri2b_denlats exp/tri2b_mmi
steps/decode.sh --config conf/decode.config --iter 4 --nj 20 --cmd "$decode_cmd" \
   exp/tri2b/graph data/test exp/tri2b_mmi/decode_it4
steps/decode.sh --config conf/decode.config --iter 3 --nj 20 --cmd "$decode_cmd" \
   exp/tri2b/graph data/test exp/tri2b_mmi/decode_it3

# Do the same with boosting.
steps/train_mmi.sh --boost 0.05 data/train data/lang \
   exp/tri2b_ali exp/tri2b_denlats exp/tri2b_mmi_b0.05
steps/decode.sh --config conf/decode.config --iter 4 --nj 20 --cmd "$decode_cmd" \
   exp/tri2b/graph data/test exp/tri2b_mmi_b0.05/decode_it4
steps/decode.sh --config conf/decode.config --iter 3 --nj 20 --cmd "$decode_cmd" \
   exp/tri2b/graph data/test exp/tri2b_mmi_b0.05/decode_it3

# Do MPE.
steps/train_mpe.sh data/train data/lang exp/tri2b_ali exp/tri2b_denlats exp/tri2b_mpe
steps/decode.sh --config conf/decode.config --iter 4 --nj 20 --cmd "$decode_cmd" \
   exp/tri2b/graph data/test exp/tri2b_mpe/decode_it4
steps/decode.sh --config conf/decode.config --iter 3 --nj 20 --cmd "$decode_cmd" \
   exp/tri2b/graph data/test exp/tri2b_mpe/decode_it3
fi

if [[ $stage -eq 7 ]]; then
## Do LDA+MLLT+SAT, and decode.
steps/train_sat.sh $numLeavesSAT $numGaussSAT data/$train data/lang exp/${tri2b_ali} exp/$tri3b
utils/mkgraph.sh data/lang exp/$tri3b exp/$tri3b/graph
steps/decode_fmllr.sh --config conf/decode.config --nj 5 --cmd "$decode_cmd" \
  exp/$tri3b/graph data/test exp/$tri3b/decode

#(
# utils/mkgraph.sh data/lang_ug exp/tri3b exp/tri3b/graph_ug
# steps/decode_fmllr.sh --config conf/decode.config --nj 20 --cmd "$decode_cmd" \
#   exp/tri3b/graph_ug data/test exp/tri3b/decode_ug
#)


# Align all data with LDA+MLLT+SAT system (tri3b)
steps/align_fmllr.sh --nj 8 --cmd "$train_cmd" --use-graphs true \
  data/$train data/lang exp/$tri3b exp/${tri3b_ali}
fi

# I don't need most of what is below. Proceed directly to Karel's DNN recipe.
if [[ $stage -eq 8 ]]; then
# # We have now added a script that will help you find portions of your data that
# # has bad transcripts, so you can filter it out.  Below we demonstrate how to
# # run this script.
# steps/cleanup/find_bad_utts.sh --nj 20 --cmd "$train_cmd" data/train data/lang \
#   exp/tri3b_ali exp/tri3b_cleanup 
# # The following command will show you some of the hardest-to-align utterances in the data.
# head  exp/tri3b_cleanup/all_info.sorted.txt 

## MMI on top of tri3b (i.e. LDA+MLLT+SAT+MMI)
steps/make_denlats.sh --config conf/decode.config \
   --nj 8 --cmd "$train_cmd" --transform-dir exp/tri3b_ali \
  data/train data/lang exp/tri3b exp/tri3b_denlats
steps/train_mmi.sh data/train data/lang exp/tri3b_ali exp/tri3b_denlats exp/tri3b_mmi

steps/decode_fmllr.sh --config conf/decode.config --nj 20 --cmd "$decode_cmd" \
  --alignment-model exp/tri3b/final.alimdl --adapt-model exp/tri3b/final.mdl \
   exp/tri3b/graph data/test exp/tri3b_mmi/decode

# Do a decoding that uses the exp/tri3b/decode directory to get transforms from.
steps/decode.sh --config conf/decode.config --nj 20 --cmd "$decode_cmd" \
  --transform-dir exp/tri3b/decode  exp/tri3b/graph data/test exp/tri3b_mmi/decode2

# demonstration scripts for online decoding.
# local/online/run_gmm.sh
# local/online/run_nnet2.sh
# local/online/run_baseline.sh
# Note: for online decoding with pitch, look at local/run_pitch.sh, 
# which calls local/online/run_gmm_pitch.sh

#
# local/run_nnet2.sh
# local/online/run_nnet2_baseline.sh



#first, train UBM for fMMI experiments.
steps/train_diag_ubm.sh --silence-weight 0.5 --nj 8 --cmd "$train_cmd" \
  250 data/train data/lang exp/tri3b_ali exp/dubm3b

# Next, various fMMI+MMI configurations.
steps/train_mmi_fmmi.sh --learning-rate 0.0025 \
  --boost 0.1 --cmd "$train_cmd" data/train data/lang exp/tri3b_ali exp/dubm3b exp/tri3b_denlats \
  exp/tri3b_fmmi_b

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj 20 --config conf/decode.config --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3b/decode  exp/tri3b/graph data/test exp/tri3b_fmmi_b/decode_it$iter &
done

steps/train_mmi_fmmi.sh --learning-rate 0.001 \
  --boost 0.1 --cmd "$train_cmd" data/train data/lang exp/tri3b_ali exp/dubm3b exp/tri3b_denlats \
  exp/tri3b_fmmi_c

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj 20 --config conf/decode.config --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3b/decode  exp/tri3b/graph data/test exp/tri3b_fmmi_c/decode_it$iter &
done

# for indirect one, use twice the learning rate.
steps/train_mmi_fmmi_indirect.sh --learning-rate 0.01 --schedule "fmmi fmmi fmmi fmmi mmi mmi mmi mmi" \
  --boost 0.1 --cmd "$train_cmd" data/train data/lang exp/tri3b_ali exp/dubm3b exp/tri3b_denlats \
  exp/tri3b_fmmi_d

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj 20 --config conf/decode.config --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3b/decode  exp/tri3b/graph data/test exp/tri3b_fmmi_d/decode_it$iter &
done

# Demo of "raw fMLLR"
local/run_raw_fmllr.sh


# You don't have to run all 3 of the below, e.g. you can just run the run_sgmm2.sh
#local/run_sgmm.sh
local/run_sgmm2.sh
#local/run_sgmm2x.sh

# The following script depends on local/run_raw_fmllr.sh having been run.
#
local/run_nnet2.sh
fi

if [[ $stage -eq 9 ]]; then
# Karel's neural net recipe.                                                                                                                                        
local/nnet/run_dnn.sh                                                                                                                                                  

# Karel's CNN recipe.
# local/nnet/run_cnn.sh
fi
