#!/usr/bin/env python3
"""
Address Sorter Script

This script reads all JSON files from the current directory (common/addresses),
sorts the data alphabetically by key, and overwrites the files with sorted data.
It also sorts nested deployment JSONs (chain -> name -> address):
  - silo-core/deploy/silo/_siloDeployments.json
  - silo-oracles/deploy/_oraclesDeployments.json

Usage:
    python3 common/addresses/sort_addresses.py
    python3 common/addresses/sort_addresses.py --only-common-addresses

The script will:
1. Find all .json files in common/addresses
2. Add the nested deployment files above if present
3. Sort each file alphabetically by key (nested files: chains and each chain's entries)
4. Write the sorted data back to the same file
5. Preserve the original formatting (indentation, etc.)
"""

import argparse
import json
import os
import glob
def sort_json_file(file_path: str) -> bool:
    """
    Sort a JSON file alphabetically by key and save it back.
    
    Args:
        file_path: Path to the JSON file
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        # Read the JSON file
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Sort the data alphabetically by key
        sorted_data = dict(sorted(data.items()))
        
        # Write the sorted data back to the file with proper formatting.
        # ensure_ascii=False keeps UTF-8 characters (e.g. ₮) instead of \u-escapes.
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(sorted_data, f, indent=4, separators=(',', ': '), ensure_ascii=False)
            f.write('\n')  # Add newline at the end
        
        print(f"✅ Sorted: {os.path.basename(file_path)}")
        return True
        
    except json.JSONDecodeError as e:
        print(f"❌ JSON decode error in {file_path}: {e}")
        return False
    except Exception as e:
        print(f"❌ Error processing {file_path}: {e}")
        return False


def sort_silo_deployments_file(file_path: str) -> bool:
    """
    Sort nested deployment JSON (chain -> entry_name -> address).
    Used for _siloDeployments.json and _oraclesDeployments.json.
    Sorts top-level keys (chains) and each chain's entries by key.

    Args:
        file_path: Path to the deployments JSON file

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        sorted_data = {}
        for chain in sorted(data.keys()):
            sorted_data[chain] = dict(sorted(data[chain].items()))
        
        # ensure_ascii=False keeps UTF-8 characters (e.g. ₮) instead of \u-escapes.
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(sorted_data, f, indent=2, separators=(',', ': '), ensure_ascii=False)
            f.write('\n')
        
        print(f"✅ Sorted: {os.path.basename(file_path)}")
        return True
    except json.JSONDecodeError as e:
        print(f"❌ JSON decode error in {file_path}: {e}")
        return False
    except Exception as e:
        print(f"❌ Error processing {file_path}: {e}")
        return False

# Paths relative to repo root (nested: chain -> name -> address)
SILO_DEPLOYMENTS_JSON = "silo-core/deploy/silo/_siloDeployments.json"
ORACLES_DEPLOYMENTS_JSON = "silo-oracles/deploy/_oraclesDeployments.json"


def main():
    """Sort common/addresses JSON files and optional nested deployment manifests."""
    parser = argparse.ArgumentParser(description="Sort address JSON files alphabetically by key.")
    parser.add_argument(
        "--only-common-addresses",
        action="store_true",
        help="Only sort common/addresses/*.json (skip _siloDeployments.json and _oraclesDeployments.json).",
    )
    args = parser.parse_args()

    print("🔄 Starting address sorting process...")
    print("=" * 50)
    
    # Get current directory (common/addresses) and repo root
    current_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(os.path.dirname(current_dir))
    
    # Find all JSON files in the current directory
    json_files = glob.glob(os.path.join(current_dir, "*.json"))
    
    silo_deployments_path = os.path.join(repo_root, SILO_DEPLOYMENTS_JSON)
    oracles_deployments_path = os.path.join(repo_root, ORACLES_DEPLOYMENTS_JSON)
    nested_deployment_paths = frozenset({silo_deployments_path, oracles_deployments_path})

    if not args.only_common_addresses:
        for path in nested_deployment_paths:
            if os.path.isfile(path):
                json_files.append(path)
    
    if not json_files:
        print("❌ No JSON files found in the current directory")
        return
    
    print(f"📁 Found {len(json_files)} JSON files to process:")
    for file_path in json_files:
        print(f"   - {os.path.relpath(file_path, repo_root)}")
    
    print("\n🔄 Processing files...")
    print("-" * 50)
    
    successful = 0
    failed = 0
    
    for file_path in json_files:
        if file_path in nested_deployment_paths:
            if sort_silo_deployments_file(file_path):
                successful += 1
            else:
                failed += 1
        else:
            if sort_json_file(file_path):
                successful += 1
            else:
                failed += 1
    
    print("-" * 50)
    print(f"✅ Successfully sorted: {successful} files")
    if failed > 0:
        print(f"❌ Failed to sort: {failed} files")
    
    print("🎉 Address sorting completed!")

if __name__ == "__main__":
    main()
