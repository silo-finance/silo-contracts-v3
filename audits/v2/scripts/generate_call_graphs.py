#!/usr/bin/env python3
"""
Script to generate call graph PNG files from Slither analysis.

Usage:
./audits/scripts/generate_call_graphs.py <path>
Example:
./audits/scripts/generate_call_graphs.py ./silo-core/contracts/hooks/SiloHookV2.sol


This script:
1. Runs slither with --print call-graph on the specified path
2. Finds all generated .dot files
3. Converts each .dot file to PNG using Graphviz's dot command
4. Saves PNGs to audits/scripts/out/call-graph/
5. Deletes all .dot files
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def run_command(cmd, description):
    """Run a shell command and handle errors."""
    print(f"Running: {description}")
    print(f"Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {description} failed", file=sys.stderr)
        print(f"stdout: {result.stdout}", file=sys.stderr)
        print(f"stderr: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result


def find_dot_files(path):
    """Find all .dot files in the specified path directory."""
    path_obj = Path(path)
    
    # If path is a file, get its parent directory
    if path_obj.is_file():
        search_dir = path_obj.parent
    elif path_obj.is_dir():
        search_dir = path_obj
    else:
        print(f"Error: Path '{path}' does not exist", file=sys.stderr)
        sys.exit(1)
    
    # Find all .dot files in the directory
    dot_files = list(search_dir.glob("*.dot"))
    return dot_files


def main():
    parser = argparse.ArgumentParser(
        description="Generate call graph PNG files from Slither analysis"
    )
    parser.add_argument(
        "path",
        type=str,
        help="Path to analyze (can be a file or directory)"
    )
    
    args = parser.parse_args()
    
    # Get the script directory to determine output path
    script_dir = Path(__file__).parent.resolve()
    output_dir = script_dir / "out" / "call-graph"
    
    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {output_dir}")
    
    # Step 1: Run slither
    print(f"\nStep 1: Running slither on '{args.path}'...")
    slither_cmd = ["slither", args.path, "--print", "call-graph"]
    run_command(slither_cmd, "slither call-graph generation")
    
    # Step 2: Find all .dot files
    print(f"\nStep 2: Finding .dot files...")
    dot_files = find_dot_files(args.path)
    
    if not dot_files:
        print("No .dot files found. Exiting.")
        sys.exit(0)
    
    print(f"Found {len(dot_files)} .dot file(s):")
    for dot_file in dot_files:
        print(f"  - {dot_file}")
    
    # Step 3: Convert each .dot file to PNG
    print(f"\nStep 3: Converting .dot files to PNG...")
    for dot_file in dot_files:
        png_filename = dot_file.stem + ".png"
        png_path = output_dir / png_filename
        
        dot_cmd = ["dot", str(dot_file), "-Tpng", "-o", str(png_path)]
        run_command(dot_cmd, f"Converting {dot_file.name} to PNG")
        print(f"  Generated: {png_path}")
    
    # Step 4: Delete all .dot files
    print(f"\nStep 4: Deleting .dot files...")
    for dot_file in dot_files:
        dot_file.unlink()
        print(f"  Deleted: {dot_file}")
    
    print(f"\nDone! Generated {len(dot_files)} PNG file(s) in {output_dir}")


if __name__ == "__main__":
    main()

