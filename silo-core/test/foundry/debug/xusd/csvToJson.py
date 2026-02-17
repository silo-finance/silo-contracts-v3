#!/usr/bin/env python3
"""
Script to convert CSV file to JSON format.
Reads CSV file and uses first line as headers/keys for JSON objects.

python3 silo-core/test/foundry/debug/xusd/csvToJson.py
"""

import csv
import json
import os

# Hardcoded path (relative to project root)
CSV_FILE_PATH = "silo-core/test/foundry/data/xusd/stream_markets_positions.csv"

# Fields that should be converted to numbers
NUMERIC_FIELDS = {'network_id', 'assets', 'block_number'}
# Fields that should be converted to booleans
BOOLEAN_FIELDS = {'is_contract'}

def convert_row_types(row):
    """Convert row values to appropriate types (numbers, booleans)."""
    converted_row = {}
    for key, value in row.items():
        if key in NUMERIC_FIELDS:
            # Convert to integer
            try:
                converted_row[key] = int(value)
            except (ValueError, TypeError):
                converted_row[key] = value
        elif key in BOOLEAN_FIELDS:
            # Convert "True"/"False" strings to boolean
            if value == "True":
                converted_row[key] = True
            elif value == "False":
                converted_row[key] = False
            else:
                converted_row[key] = value
        else:
            converted_row[key] = value
    return converted_row

def csv_to_json():
    """Convert CSV file to JSON format."""
    # Get project root (assuming script is in silo-core/test/foundry/debug/xusd/)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, "..", "..", "..", "..", ".."))
    
    csv_path = os.path.join(project_root, CSV_FILE_PATH)
    # Generate JSON file path by replacing .csv extension with .json
    json_file_path = os.path.splitext(CSV_FILE_PATH)[0] + ".json"
    json_path = os.path.join(project_root, json_file_path)
    
    # Read CSV and convert to JSON
    data = []
    with open(csv_path, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            converted_row = convert_row_types(row)
            data.append(converted_row)
    
    # Write JSON file
    with open(json_path, 'w', encoding='utf-8') as jsonfile:
        json.dump(data, jsonfile, indent=2, ensure_ascii=False)
    
    print(f"Successfully converted {len(data)} rows from CSV to JSON")
    print(f"CSV file: {csv_path}")
    print(f"JSON file: {json_path}")

if __name__ == "__main__":
    csv_to_json()

