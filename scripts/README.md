# PDMedical Products Migration Script (COMPLETE)

This script migrates **ALL** product-related data from Excel to Supabase:
- ✅ Products & Categories
- ✅ Contacts (parsed from key_contacts_reference)
- ✅ Organizations (created from email domains)
- ✅ Contact-Product Interests (links contacts to products)

## Setup

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Create a `.env` file** in the scripts directory (or root directory):
   ```
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_KEY=your_service_role_key
   ```

   **Important:** Use the `service_role` key (not `anon` key) for inserts. You can find it in:
   - Supabase Dashboard → Project Settings → API → `service_role` secret

3. **Place the Excel file** in the same directory as the script:
   - File name: `AI-_PDMedical_Products-29_10_25__1_.xlsx`
   - Or update `EXCEL_FILE` variable in the script

## Usage

```bash
cd scripts
python migrate_products_from_excel.py
```

## What it does

1. ✅ Reads product data from "PDM -Product Info" sheet
2. ✅ Reads sales priorities from "Sales " sheet
3. ✅ Merges product and sales data
4. ✅ Creates categories automatically if they don't exist
5. ✅ Imports products to Supabase
6. ✅ **Parses contacts from key_contacts_reference column** (extracts names & emails)
7. ✅ **Creates organizations** based on email domains
8. ✅ **Creates contacts** if they don't exist
9. ✅ **Links contacts to products** via contact_product_interests table
10. ✅ **Sets lead_score_contribution** (10 points for key contacts)
11. ✅ Skips products that already exist (by product_code)
12. ✅ Verifies the import and shows statistics

## Excel Sheet Structure

### PDM -Product Info Sheet
- Row 4+: Data rows
- Column 2 (B): Product Name
- Column 3 (C): Category
- Column 4 (D): Market Potential
- Column 5 (E): Background History
- Column 6 (F): Key Contacts
- Column 10 (J): Forecast Notes
- Column 13 (M): Product Code

### Sales Sheet
- Row 4+: Data rows
- Column 1 (A): Priority Label (# 1, # 2, # 3, or "remove")
- Column 2 (B): Product Name
- Column 3 (C): Category
- Column 4 (D): Instructions
- Column 5 (E): Timing Notes
- Column 6 (F): Additional Notes

## Contact Parsing

The script automatically extracts contact information from the `key_contacts_reference` column:

- **Email extraction**: Finds all email addresses in the text
- **Name extraction**: Finds names (First Last, First M. Last patterns)
- **Organization creation**: Creates organizations based on email domain
- **Contact linking**: Links contacts to products with `interest_level='high'` and `lead_score_contribution=10`

Example `key_contacts_reference` text:
```
Jennifer Fredman (jennifer@hospital.com.au), Dr. Smith (smith@clinic.com)
```

Will create:
- Organization: `hospital.com.au` (if doesn't exist)
- Contact: Jennifer Fredman (jennifer@hospital.com.au)
- Organization: `clinic.com` (if doesn't exist)
- Contact: Dr. Smith (smith@clinic.com)
- Contact-Product Interest links for both contacts

## Output

The script will show:
- Progress for each product imported
- Contacts and organizations created
- Contact-product interest links created
- Summary with success/error counts
- Verification statistics (products, contacts, interests, organizations, by category, priority)

## Error Handling

- Skips products that already exist (by product_code)
- Shows errors for failed imports
- Continues processing even if some products fail

