"""
Excel Structure Analyzer
This script analyzes the Excel file and shows all columns and sample data
"""

import pandas as pd
import sys
import os

EXCEL_FILE = os.path.join(os.path.dirname(__file__), 'AI- PDMedical_Products-29 10 25 (1).xlsx')

if not os.path.exists(EXCEL_FILE):
    print(f"❌ Excel file not found: {EXCEL_FILE}")
    print(f"Current directory: {os.getcwd()}")
    sys.exit(1)

print("="*80)
print("📊 EXCEL FILE STRUCTURE ANALYSIS")
print("="*80)

try:
    # Get all sheet names
    xl_file = pd.ExcelFile(EXCEL_FILE)
    print(f"\n📄 Found {len(xl_file.sheet_names)} sheet(s):")
    for sheet in xl_file.sheet_names:
        print(f"   - {sheet}")
    
    # Analyze each sheet
    for sheet_name in xl_file.sheet_names:
        print(f"\n{'='*80}")
        print(f"SHEET: {sheet_name}")
        print(f"{'='*80}")
        
        df = pd.read_excel(EXCEL_FILE, sheet_name=sheet_name, header=None)
        
        print(f"\nTotal rows: {len(df)}")
        print(f"Total columns: {len(df.columns)}")
        
        # Show first 5 rows with column indices
        print(f"\n📋 First 5 rows (with column indices):")
        print("-" * 80)
        
        for row_idx in range(min(5, len(df))):
            print(f"\nRow {row_idx} (Excel row {row_idx + 1}):")
            for col_idx in range(min(20, len(df.columns))):  # Show first 20 columns
                value = df.iloc[row_idx, col_idx]
                if pd.notna(value):
                    value_str = str(value)[:100]  # Truncate long values
                    print(f"   Column {col_idx} (Excel col {chr(65 + col_idx)}): {value_str}")
        
        # Try to detect headers (look for row with most non-null values)
        print(f"\n🔍 Detected header row analysis:")
        print("-" * 80)
        
        non_null_counts = [df.iloc[i].notna().sum() for i in range(min(10, len(df)))]
        header_row_idx = non_null_counts.index(max(non_null_counts)) if non_null_counts else 0
        
        print(f"Most likely header row: {header_row_idx} (Excel row {header_row_idx + 1})")
        print(f"\nColumn headers (if detected):")
        for col_idx in range(min(20, len(df.columns))):
            header_value = df.iloc[header_row_idx, col_idx] if header_row_idx < len(df) else None
            if pd.notna(header_value):
                print(f"   Column {col_idx} ({chr(65 + col_idx)}): {str(header_value)[:50]}")
        
        # Show data distribution
        print(f"\n📊 Data sample (rows after header):")
        print("-" * 80)
        
        start_row = header_row_idx + 1 if header_row_idx < len(df) - 1 else 0
        for row_idx in range(start_row, min(start_row + 3, len(df))):
            print(f"\nData Row {row_idx} (Excel row {row_idx + 1}):")
            row_data = {}
            for col_idx in range(min(20, len(df.columns))):
                value = df.iloc[row_idx, col_idx]
                if pd.notna(value) and str(value).strip():
                    row_data[chr(65 + col_idx)] = str(value)[:80]
            
            if row_data:
                for col, val in row_data.items():
                    print(f"   {col}: {val}")
            else:
                print("   (No data in first 20 columns)")
        
        print(f"\n✅ Sheet '{sheet_name}' analyzed")
    
    print(f"\n{'='*80}")
    print("✅ ANALYSIS COMPLETE")
    print("="*80)
    
except Exception as e:
    print(f"❌ Error analyzing Excel file: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

