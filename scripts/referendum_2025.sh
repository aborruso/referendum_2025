#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${folder}"/../data/output
mkdir -p "${folder}"/../data/processing
mkdir -p "${folder}"/../data/processing/PR
mkdir -p "${folder}"/../data/processing/RE
mkdir -p "${folder}"/../data/processing/CM

# crea un subfolder da 01 a 05 in "${folder}"/../data/processing/RE
for i in $(seq -f "%02g" 1 5); do
  mkdir -p "${folder}"/../data/processing/RE/"${i}"
done

for i in $(seq -f "%02g" 1 5); do
  mkdir -p "${folder}"/../data/processing/PR/"${i}"
done

for i in $(seq -f "%02g" 1 5); do
  mkdir -p "${folder}"/../data/processing/CM/"${i}"
done

# clean anagrafica
sed -r 's/=*"//g' "${folder}"/../resources/codici-comuni.csv >"${folder}"/../data/codici-comuni.csv

duckdb --csv -c "SELECT * FROM read_csv('${folder}/../data/codici-comuni.csv',normalize_names=true)" >"${folder}"/../data/tmp.csv

mv "${folder}"/../data/tmp.csv "${folder}"/../data/codici-comuni.csv

duckdb --csv -c "
SELECT
  *,
  substring(CAST(codice_elettorale AS VARCHAR), 7, 4) AS CM,  -- caratteri 7‑10
  substring(CAST(codice_elettorale AS VARCHAR), 4, 3) AS PR   -- caratteri 4‑6
FROM read_csv('${folder}/../data/codici-comuni.csv');
" >"${folder}"/../data/tmp.csv

mv "${folder}"/../data/tmp.csv "${folder}"/../data/codici-comuni.csv

mlr -S --icsv --ojsonl cat "${folder}"/../data/codici-comuni.csv >"${folder}"/../data/codici-comuni.jsonl

mlr -S --jsonl cut -f PR then uniq -a then sort -f PR "${folder}"/../data/codici-comuni.jsonl >"${folder}"/../data/codici-pr.jsonl

# Loop through regions 01-20
for region in $(seq -f "%02g" 1 20); do
  # Loop through time points 1-5
  for ref in $(seq -f "%02g" 1 5); do

    # se "${folder}"/../data/processing/RE/"${ref}"/"${region}".json esiste, salta
    if [[ -f "${folder}"/../data/processing/RE/"${ref}"/"${region}".json ]]; then
      echo "File for RE ${ref} and region ${region} already exists, skipping..."
      continue
    fi

    # Fetch data from API
    curl 'https://eleapi.interno.gov.it/siel/PX/votantiFI/DE/20250608/TE/09/SK/'"${ref}"'/RE/'"${region}"'' \
      -H 'accept: application/json, text/plain, */*' \
      -H 'accept-language: it,en-US;q=0.9,en;q=0.8' \
      -H 'cache-control: no-cache' \
      -H 'origin: https://elezioni.interno.gov.it' \
      -H 'pragma: no-cache' \
      -H 'priority: u=1, i' \
      -H 'referer: https://elezioni.interno.gov.it/' \
      -H 'sec-ch-ua: "Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"' \
      -H 'sec-ch-ua-mobile: ?0' \
      -H 'sec-ch-ua-platform: "Windows"' \
      -H 'sec-fetch-dest: empty' \
      -H 'sec-fetch-mode: cors' \
      -H 'sec-fetch-site: same-site' \
      -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36' >"${folder}"/../data/processing/RE/"${ref}"/"${region}".json
  done
done

# unisci i file regionali

find "${folder}"/../data/processing/RE -type f -name '*.json' -print0 |
  xargs -0 jq -s '.' \
    >"${folder}"/../data/processing/RE/regioni.json

flatterer --force "${folder}"/../data/processing/RE/regioni.json "${folder}"/../data/output/regioni

mlr -S --icsv --ojsonl cut -f cod then uniq -a then sort -t cod "${folder}"/../data/output/regioni/csv/enti_enti_f.csv >"${folder}"/../data/codici-province.jsonl

# per ogni PR, scarica i dati
cat "${folder}"/../data/codici-province.jsonl | while read -r line; do

  PR=$(echo "${line}" | jq -r '.cod')
  # porta a doppio zero padded PR
  PR=$(printf "%03d" "${PR}")

  for ref in $(seq -f "%02g" 1 5); do

    # se "${folder}"/../data/processing/PR/"${PR}".json esiste, salta
    if [[ -f "${folder}"/../data/processing/PR/"${ref}"/"${PR}".json ]]; then
      echo "File for PR ${PR} already exists, skipping..."
      continue
    fi

    curl 'https://eleapi.interno.gov.it/siel/PX/votantiFI/DE/20250608/TE/09/SK/'"${ref}"'/PR/'"${PR}"'' \
      -H 'accept: application/json, text/plain, */*' \
      -H 'accept-language: it,en-US;q=0.9,en;q=0.8' \
      -H 'cache-control: no-cache' \
      -H 'origin: https://elezioni.interno.gov.it' \
      -H 'pragma: no-cache' \
      -H 'priority: u=1, i' \
      -H 'referer: https://elezioni.interno.gov.it/' \
      -H 'sec-ch-ua: "Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"' \
      -H 'sec-ch-ua-mobile: ?0' \
      -H 'sec-ch-ua-platform: "Windows"' \
      -H 'sec-fetch-dest: empty' \
      -H 'sec-fetch-mode: cors' \
      -H 'sec-fetch-site: same-site' \
      -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36' >"${folder}"/../data/processing/PR/"${ref}"/"${PR}".json
  done

done

mlr -S --icsv --ojsonl cat then filter '$tipo_tras=="SZ"' "${folder}"/../resources/comuni_prov.csv >"${folder}"/../resources/comuni_prov.jsonl

cat "${folder}"/../resources/comuni_prov.jsonl | while read -r line; do

  PR=$(echo "${line}" | jq -r '.enti_ente_p_cod')
  PR=$(printf "%03d" "${PR}")
  CM=$(echo "${line}" | jq -r '.cod')
  CM=$(printf "%04d" "${CM}")

  for ref in $(seq -f "%02g" 1 5); do

  mkdir -p "${folder}"/../data/processing/CM/"${ref}"/"${PR}"

    curl 'https://eleapi.interno.gov.it/siel/PX/votantiFIZ/DE/20250608/TE/09/SK/'"${ref}"'/PR/'"${PR}"'/CM/'"${CM}"'' \
      -H 'accept: application/json, text/plain, */*' \
      -H 'accept-language: it,en-US;q=0.9,en;q=0.8' \
      -H 'cache-control: no-cache' \
      -H 'origin: https://elezioni.interno.gov.it' \
      -H 'pragma: no-cache' \
      -H 'priority: u=1, i' \
      -H 'referer: https://elezioni.interno.gov.it/' \
      -H 'sec-ch-ua: "Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"' \
      -H 'sec-ch-ua-mobile: ?0' \
      -H 'sec-ch-ua-platform: "Windows"' \
      -H 'sec-fetch-dest: empty' \
      -H 'sec-fetch-mode: cors' \
      -H 'sec-fetch-site: same-site' \
      -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36' >"${folder}"/../data/processing/CM/"${ref}"/"${PR}"/"${CM}".json

  done
done
