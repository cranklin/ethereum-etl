#!/usr/bin/env bash

# MIT License
#
# Copyright (c) 2018 Evgeny Medvedev, evge.medvedev@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


export_blocks_batch_size=100
export_erc20_batch_size=100
output_dir=.

current_time() { echo `date '+%Y-%m-%d %H:%M:%S'`; }

log() { echo "$(current_time) ${1}"; }

quit_if_returned_error() {
    ret_val=$?
    if [ ${ret_val} -ne 0 ]; then
        log "An error occurred. Quitting."
        exit ${ret_val}
    fi
}

usage() { echo "Usage: $0 -s <start_block> -e <end_block> -b <batch_size> -p <provider_uri> [-o <output_dir>]" 1>&2; exit 1; }

while getopts ":s:e:b:p:o:" opt; do
    case "${opt}" in
        s)
            start_block=${OPTARG}
            ;;
        e)
            end_block=${OPTARG}
            ;;
        b)
            batch_size=${OPTARG}
            ;;
        p)
            provider_uri=${OPTARG}
            ;;
        o)
            output_dir=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${start_block}" ] || [ -z "${end_block}" ] || [ -z "${batch_size}" ] || [ -z "${provider_uri}" ]; then
    usage
fi

for (( batch_start_block=$start_block; batch_start_block <= $end_block; batch_start_block+=$batch_size )); do
    start_time=$(date +%s)
    batch_end_block=$((batch_start_block + batch_size - 1))
    batch_end_block=$((batch_end_block > end_block ? end_block : batch_end_block))

    padded_batch_start_block=`printf "%08d" ${batch_start_block}`
    padded_batch_end_block=`printf "%08d" ${batch_end_block}`
    block_range=${padded_batch_start_block}-${padded_batch_end_block}
    file_name_suffix=${padded_batch_start_block}_${padded_batch_end_block}
    # Hive style partitioning
    partition_dir=/start_block=${padded_batch_start_block}/end_block=${padded_batch_end_block}

    blocks_output_dir=${output_dir}/blocks${partition_dir}
    mkdir -p ${blocks_output_dir};

    transactions_output_dir=${output_dir}/transactions${partition_dir}
    mkdir -p ${transactions_output_dir};

    blocks_file=${blocks_output_dir}/blocks_${file_name_suffix}.csv
    transactions_file=${transactions_output_dir}/transactions_${file_name_suffix}.csv
    log "Exporting blocks ${block_range} to ${blocks_file}"
    log "Exporting transactions from blocks ${block_range} to ${transactions_file}"
    python3 export_blocks_and_transactions.py --start-block=${batch_start_block} --end-block=${batch_end_block} --provider-uri="${provider_uri}" --batch-size=${export_blocks_batch_size} --blocks-output=${blocks_file} --transactions-output=${transactions_file}
    quit_if_returned_error

    erc20_transfers_output_dir=${output_dir}/erc20_transfers${partition_dir}
    mkdir -p ${erc20_transfers_output_dir};

    erc20_transfers_file=${erc20_transfers_output_dir}/erc20_transfers_${file_name_suffix}.csv
    log "Exporting ERC20 transfers from blocks ${block_range} to ${erc20_transfers_file}"
    python3 export_erc20_transfers.py --start-block=${batch_start_block} --end-block=${batch_end_block} --provider-uri="${provider_uri}" --batch-size=${export_erc20_batch_size} --output=${erc20_transfers_file}
    quit_if_returned_error

    tx_hashes_output_dir=${output_dir}/tx_hashes${partision_dir}
    mkdir -p ${tx_hashes_output_dir};
    
    tx_hashes_file=${tx_hashes_output_dir}/tx_hases_${file_name_suffix}.csv
    log "Extracting tx_hash column from transaction file ${transactions_file}"
    python3 extract_csv_column.py --input ${transactions_file} --output ${tx_hashes_file} --column "tx_hash"
    quit_if_returned_error

    receipts_output_dir=${output_dir}/receipts${partition_dir}
    mkdir -p ${receipts_output_dir};

    logs_output_dir=${output_dir}/logs${partition_dir}
    mkdir -p ${logs_output_dir};

    receipts_file=${receipts_output_dir}/receipts_${file_name_suffix}.csv
    logs_file=${logs_output_dir}/logs_${file_name_suffix}.csv
    log "Exporting receipts and logs from blocks ${block_range} to ${receipts_file} and ${logs_file}"
    python3 export_receipts_and_logs.py --tx-hashes ${tx_hashes_file} --provider-uri="${provider_uri}"  --receipts-output=${receipts_file} --logs-output=${logs_file}
    quit_if_returned_error
    
    contract_addresses_output_dir=${output_dir}/contract_addresses${partition_dir}
    mkdir -p ${contract_addresses_output_dir}
    
    contract_addresses_file=${contract_addresses_output_dir}/contract_addresses_${file_name_suffix}.csv
    log "Extracting receipt_contract_address from receipt file ${receipts_file}"
    python3 extract_csv_column.py --input ${receipts_file} --column receipt_contract_address --output ${contract_addresses_file}
    quit_if_returned_error

    contracts_output_dir=${output_dir}/contracts${partition_dir}
    mkdir -p ${contracts_output_dir};
    
    contracts_file=${contracts_output_dir}/contracts_${file_name_suffix}.csv
    log "Exporting contracts from blocks ${block_range} to ${contracts_file}"
    python3 export_contracts.py --contract-addresses ${contract_addresses_file} --provider-uri="${provider_uri}" --output=${contracts_file}
    quit_if_returned_error

    erc20_token_addresses_output_dir=${output_dir}/erc20_token_addresses${partition_dir}
    mkdir -p ${erc20_token_addresses_output_dir}
    
    erc20_token_addresses_file=${erc20_token_addresses_output_dir}/erc20_token_addresses_${file_name_suffix}
    log "Extracting erc20_token_address from erc20_token_transfers file ${erc20_transfers_file}"
    python3 extract_csv_column.py -i ${erc20_transfers_file} -c erc20_token -o - | sort | uniq > ${erc20_token_addresses_file}
    quit_if_returned_error
    
    erc20_tokens_output_dir=${output_dir}/erc20_tokens${partition_dir}
    mkdir -p ${erc20_tokens_output_dir}
    
    erc20_tokens_file=${erc20_tokens_output_dir}/erc20_tokens_${file_name_suffix}.csv
    log "Exporting erc20_tokens from blocks ${block_range} to ${erc20_tokens_file}"
    python3 export_erc20_tokens.py --token-addresses ${erc20_token_addresses_file} --provider-uri="${provider_uri}" --output ${erc20_tokens_file}
    quit_if_returned_error

    end_time=$(date +%s)
    time_diff=$((end_time-start_time))

    log "Exporting blocks ${block_range} took ${time_diff} seconds"
done
