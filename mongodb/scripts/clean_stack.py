## clean_stack.py
#################
## How to use
## python3 clean_stack.py mongo.log
#################

import json
import sys

def extract_symbols(log_file_path):
    symbols = []
    with open(log_file_path, 'r') as file:
        for line in file:
            try:
                log_entry = json.loads(line)
                symbol = log_entry.get("attr", {}).get("frame", {}).get("s")
                if symbol:
                    symbols.append(symbol)
            except json.JSONDecodeError:
                pass  # Ignore lines that are not valid JSON
    return symbols

if len(sys.argv) != 2:
    print("Usage: python clean_stack.py <log_file_path>")
    sys.exit(1)

log_file_path = sys.argv[1]
extracted_symbols = extract_symbols(log_file_path)
for symbol in extracted_symbols:
    print(symbol)
