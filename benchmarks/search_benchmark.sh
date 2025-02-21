ServerUrl=${EAS_URL}/v1/chat/completions
AccessToken=${EAS_URL}
ClientName=qwen214b #测试名称
Backend=openai-chat # bladellm 服务后端，bladellm适用于压测bladellm、pai-rag等服务

HfModel=Qwen/Qwen2.5-14B-Instruct #下载tokenizer
ModelName=Qwen2.5-14B-Instruct

DatasetPath=data/sharegpt_zh_38K_converted.json
OutputLength=30 #overwrite 输出长度
ConcurrencyList=(20 40 60 80 100) #测试并发数
NumPrompts=500 #每轮测试发送的请求数


PYTHON=python3
Endpoint=/v1/chat/completions
Now=$(date +"%Y%m%d_%H%M%S")
echo "Current Time: ${Now}"
IgnoreEos=false
RequestRate=inf  # Set to a specific number if you want to test QPS performance

Dir=$(realpath $(dirname -- "${BASH_SOURCE[0]}"))
BenchmarkDir=$(dirname ${Dir})
ResultDir=${BenchmarkDir}/result/${ClientName}/${Now}
echo "Result Directory: ${ResultDir}"

ModelPath=default

if [ ! -d ${ResultDir} ]; then
    mkdir -p ${ResultDir}
fi

export PYTHONPATH=./
echo "Access Token: ${AccessToken}"
LogDir=${ResultDir}/log/${ClientName}
CSVFile=${ResultDir}/log/${ClientName}/summary.csv
if [ ! -d ${LogDir} ]; then
    mkdir -p ${LogDir}
fi

#
all_results=()

# Iterate over all concurrency values
for Concurrency in "${ConcurrencyList[@]}"; do
    echo "Concurrency: ${Concurrency}"

    # Generate unique log file names
    temp_file="${LogDir}/temp_output_concurrency_${Concurrency}.txt"
    result_file="${LogDir}/result_concurrency_${Concurrency}.json"

    echo "Running benchmark with prompts:${NumPrompts}, concurrency:${Concurrency}, request_rate:${RequestRate}"
    echo "Temporary File: ${temp_file}"
    echo "Result File: ${result_file}"
    export OPENAI_API_KEY=${AccessToken}

    # Run the benchmark and capture the output
    ${PYTHON} benchmark_serving.py \
        --base-url ${ServerUrl} \
        --endpoint ${Endpoint} \
        --backend ${Backend} \
        --model ${HfModel} \
        --served-model-name ${ModelName} \
        --dataset-name sharegpt \
        --sharegpt-output-len ${OutputLength} \
        --dataset-path ${DatasetPath} \
        --max-concurrency ${Concurrency} \
        --num-prompts ${NumPrompts} > ${temp_file}

    if [ -f ${temp_file} ]; then
        echo "Temporary file found: ${temp_file}"

        #save the results
        ${PYTHON} -c "
import json
import sys

with open('${temp_file}', 'r') as f:
    lines = f.readlines()
    data = {}
    for line in lines:
        try:
            key, value = line.strip().split(': ')
            data[key] = value
        except ValueError:
            print(f'Warning: Invalid line: {line.strip()}')
            continue  # Skip invalid lines

    with open('${result_file}', 'w') as out_f:
        json.dump(data, out_f)
"

        # Read the JSON file and append to all_results
        all_results+=("${result_file}")
    fi
done

# Merge all JSON results into a single CSV file
${PYTHON} -c "
import json
import csv

# Define the CSV file path
csv_file_path = '${CSVFile}'

# Convert the shell array to a Python list
all_results = \"${all_results[*]}\".split()
all_results = [result.strip('\"') for result in all_results]

# Define the headers based on the first JSON file
with open(all_results[0], 'r') as f:
    headers = json.load(f).keys()

# Write the headers to the CSV file
with open(csv_file_path, 'w', newline='') as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=headers)
    writer.writeheader()

    # Write the data rows to the CSV file
    for result_file in all_results:
        with open(result_file, 'r') as f:
            data = json.load(f)
            writer.writerow(data)
"
