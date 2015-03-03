Construction of scripts under turkish/s5_w/ 	("s5_w" means s5 for words)
============================================================================
path.sh						cp timit/path.sh
cmd.sh						cp timit/cmd.sh

run_turkish_words.sh				everything after mfcc generation is based on rm/run.sh except the following:
						a) comment utils/mkgraph.sh data/lang_ug * *
						b) change steps/decode.sh --nj 20 -->  steps/decode.sh --nj 5 (since nj should be less than #testspks)



conf/
------
conf/dev_spk.list				<new file, based on turkish corpus>			
conf/test_spk.list				<new file, based on turkish corpus>	
metu2worldmap.txt				<new file, based on turkish corpus>

conf/decode.config				cp rm/conf/decode.config
conf/decode_dnn.config				cp rm/conf/decode_dnn.config
conf/fbank.conf					cp rm/conf/fbank.conf
conf/mfcc.conf					cp rm/conf/mfcc.conf
conf/online_cmvn.conf				cp rm/conf/online_cmvn.conf
conf/pitch.conf					cp rm/conf/pitch.conf
conf/pitch_process.conf				cp rm/conf/pitch_process.conf
conf/plp.conf					cp rm/conf/plp.conf
conf/topo.proto					cp rm/conf/topo.proto


local/
------
local/turkish_data_prep.sh			<new file, based on timit/local/timit_data_prep.sh>	
local/turkish_format_data.sh			<new file, based on timit/local/timit_format_data.sh>	
local/turkish_prepare_dict.sh			<new file, based on timit/local/timit_prepare_dict.sh>	

local/nnet					cp rm/local/nnet
local/nnet2					cp rm/local/nnet2
local/online					cp rm/local/online
local/run_dnn_convert_nnet2.sh			cp rm/local/run_dnn_convert_nnet2.sh
local/run_nnet2.sh				cp rm/local/run_nnet2.sh
local/run_pitch.sh				cp rm/local/run_pitch.sh
local/run_raw_fmllr.sh				cp rm/local/run_raw_fmllr.sh
local/run_sgmm2.sh				cp rm/local/run_sgmm2.sh
local/run_sgmm2x.sh				cp rm/local/run_sgmm2x.sh
local/run_sgmm_multiling.sh			cp rm/local/run_sgmm_multiling.sh
local/run_sgmm.sh				cp rm/local/run_sgmm.sh
local/run_vtln2.sh				cp rm/local/run_vtln2.sh
local/run_vtln.sh				cp rm/local/run_vtln.sh
local/score.sh					cp rm/local/score.sh
local/test_decoders.sh				cp rm/local/test_decoders.sh







