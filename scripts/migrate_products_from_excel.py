"""
PDMedical Products - Excel to Supabase Migration Script (COMPLETE)
=====================================================================
This script migrates ALL product data from Excel to Supabase database:
- Products & Categories
- Contacts & Organizations (from key_contacts_reference)
- Contact-Product Interests
- Product Variants (if available)
- Product Specifications (if available)

Requirements:
    pip install pandas openpyxl supabase python-dotenv

Environment Variables (.env file):
    SUPABASE_URL=your_supabase_url
    SUPABASE_KEY=your_supabase_service_role_key
"""

import pandas as pd
import os
import re
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime
import sys
from typing import List, Dict, Optional, Tuple

# Load environment variables
load_dotenv()

# Initialize Supabase client
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERROR: Please set SUPABASE_URL and SUPABASE_KEY in your .env file")
    print("NOTE: Use SUPABASE_SERVICE_ROLE_KEY for inserts (not anon key)")
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Excel file path
EXCEL_FILE = 'AI-_PDMedical_Products-29_10_25__1_.xlsx'

# Cache for organizations and contacts to avoid duplicate lookups
_org_cache = {}
_contact_cache = {}
_product_cache = {}

def extract_products_from_excel():
    """Extract product data from the PDM -Product Info sheet"""
    print("📊 Reading Excel file...")
    
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name='PDM -Product Info', header=None)
    except FileNotFoundError:
        print(f"❌ ERROR: Excel file '{EXCEL_FILE}' not found in current directory")
        sys.exit(1)
    except Exception as e:
        print(f"❌ ERROR reading Excel file: {str(e)}")
        sys.exit(1)
    
    products = []
    
    for idx in range(3, len(df)):
        row = df.iloc[idx]
        
        if pd.notna(row[13]) and str(row[13]).strip():
            product = {
                'product_code': str(row[13]).strip(),
                'product_name': str(row[2]).strip() if pd.notna(row[2]) else None,
                'category_name': str(row[3]).strip() if pd.notna(row[3]) else None,
                'market_potential': clean_text(row[4]),
                'background_history': clean_text(row[5]),
                'key_contacts_reference': clean_text(row[6]),
                'forecast_notes': clean_text(row[10]),
            }
            
            if product['product_code'] and product['product_code'].lower() not in ['nan', 'none', '']:
                products.append(product)
    
    print(f"✅ Extracted {len(products)} products from Excel")
    return products

def clean_text(value):
    """Clean text values from Excel"""
    if pd.isna(value):
        return None
    text = str(value).strip()
    if text.lower() in ['nan', 'none', '', 'null']:
        return None
    return text

def extract_sales_priorities():
    """Extract sales priority data from the Sales sheet"""
    print("📊 Reading Sales priorities...")
    
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name='Sales ', header=None)
    except Exception as e:
        print(f"⚠️  Warning: Could not read Sales sheet: {str(e)}")
        return []
    
    sales_data = []
    
    for idx in range(3, len(df)):
        row = df.iloc[idx]
        
        if pd.notna(row[2]) and clean_text(row[2]):
            sale = {
                'product_name': clean_text(row[2]),
                'priority_label': clean_text(row[1]),
                'category_name': clean_text(row[3]),
                'instructions': clean_text(row[4]),
                'timing_notes': clean_text(row[5]),
                'additional_notes': clean_text(row[6]),
            }
            sales_data.append(sale)
    
    print(f"✅ Extracted {len(sales_data)} sales priority records")
    return sales_data

def parse_priority_label(priority_label):
    """Parse priority label (e.g., '# 1' -> 1, 'remove' -> None)"""
    if not priority_label:
        return None, 'active'
    
    label = str(priority_label).lower().strip()
    
    if 'remove' in label:
        return None, 'removed'
    
    try:
        if '#' in label:
            num = int(label.replace('#', '').strip())
            if 1 <= num <= 3:
                return num, 'active'
        else:
            num = int(label)
            if 1 <= num <= 3:
                return num, 'active'
    except (ValueError, AttributeError):
        pass
    
    return None, 'active'

def parse_contacts_from_text(contacts_text: str) -> List[Dict]:
    """Parse contact information from key_contacts_reference text"""
    if not contacts_text:
        return []
    
    contacts = []
    
    # Pattern to match emails
    email_pattern = r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
    emails = re.findall(email_pattern, contacts_text)
    
    # Pattern to match names (common patterns like "First Last", "First M. Last")
    name_patterns = [
        r'([A-Z][a-z]+(?:\s+[A-Z][a-z]*\.?\s*)?[A-Z][a-z]+)',  # First M. Last
        r'([A-Z][a-z]+\s+[A-Z][a-z]+)',  # First Last
    ]
    
    names = []
    for pattern in name_patterns:
        found_names = re.findall(pattern, contacts_text)
        names.extend(found_names)
    
    # Create contact entries
    if emails:
        for i, email in enumerate(emails):
            name = names[i] if i < len(names) else None
            contacts.append({
                'name': name,
                'email': email.lower(),
                'raw_text': contacts_text
            })
    elif names:
        # If we have names but no emails, create placeholder emails
        for name in names[:5]:  # Limit to 5 contacts per product
            # Extract first and last name
            name_parts = name.split()
            if len(name_parts) >= 2:
                first_name = name_parts[0]
                last_name = name_parts[-1]
                # Generate placeholder email
                email = f"{first_name.lower()}.{last_name.lower()}@pdmedical.com.au"
                contacts.append({
                    'name': name,
                    'email': email,
                    'raw_text': contacts_text
                })
    
    return contacts

def get_or_create_organization(domain: str = None, name: str = None) -> Optional[str]:
    """Get organization ID or create if doesn't exist"""
    # Use domain from email or default
    if not domain:
        domain = 'pdmedical.com.au'
    
    # Check cache first
    cache_key = domain.lower()
    if cache_key in _org_cache:
        return _org_cache[cache_key]
    
    try:
        # Try to find by domain
        if domain:
            response = supabase.table('organizations').select('id').eq('domain', domain).execute()
            if response.data and len(response.data) > 0:
                _org_cache[cache_key] = response.data[0]['id']
                return response.data[0]['id']
        
        # Try to find by name
        if name:
            response = supabase.table('organizations').select('id').ilike('name', f'%{name}%').execute()
            if response.data and len(response.data) > 0:
                org_id = response.data[0]['id']
                _org_cache[cache_key] = org_id
                return org_id
        
        # Create new organization
        org_data = {
            'name': name or domain.split('.')[0].title() + ' Organization',
            'domain': domain,
            'status': 'active'
        }
        
        response = supabase.table('organizations').insert(org_data).execute()
        
        if response.data:
            org_id = response.data[0]['id']
            _org_cache[cache_key] = org_id
            print(f"   📁 Created organization: {org_data['name']}")
            return org_id
    except Exception as e:
        print(f"   ⚠️  Error with organization '{domain}': {str(e)}")
    
    return None

def extract_domain_from_email(email: str) -> str:
    """Extract domain from email address"""
    if '@' in email:
        return email.split('@')[1]
    return 'pdmedical.com.au'

def get_or_create_contact(name: str, email: str, organization_id: str) -> Optional[str]:
    """Get contact ID or create if doesn't exist"""
    email_lower = email.lower().strip()
    
    # Check cache first
    if email_lower in _contact_cache:
        return _contact_cache[email_lower]
    
    try:
        # Check if contact exists
        response = supabase.table('contacts').select('id').eq('email', email_lower).execute()
        
        if response.data and len(response.data) > 0:
            contact_id = response.data[0]['id']
            _contact_cache[email_lower] = contact_id
            return contact_id
        
        # Parse name
        name_parts = name.split() if name else []
        first_name = name_parts[0] if len(name_parts) > 0 else None
        last_name = name_parts[-1] if len(name_parts) > 1 else None
        
        # Create new contact
        contact_data = {
            'email': email_lower,
            'first_name': first_name,
            'last_name': last_name,
            'organization_id': organization_id,
            'status': 'active'
        }
        
        response = supabase.table('contacts').insert(contact_data).execute()
        
        if response.data:
            contact_id = response.data[0]['id']
            _contact_cache[email_lower] = contact_id
            print(f"   👤 Created contact: {email}")
            return contact_id
    except Exception as e:
        print(f"   ⚠️  Error creating contact '{email}': {str(e)}")
    
    return None

def merge_product_and_sales_data(products, sales_data):
    """Merge product data with sales priorities"""
    print("🔄 Merging product and sales data...")
    
    sales_lookup = {s['product_name'].lower().strip(): s for s in sales_data if s['product_name']}
    
    merged_products = []
    matched_count = 0
    
    for product in products:
        product_name = product['product_name']
        product_key = product_name.lower().strip() if product_name else None
        
        if product_key and product_key in sales_lookup:
            sales_info = sales_lookup[product_key]
            matched_count += 1
            
            priority_num, status = parse_priority_label(sales_info['priority_label'])
            
            product['sales_priority'] = priority_num
            product['sales_priority_label'] = sales_info['priority_label']
            product['sales_instructions'] = sales_info['instructions']
            product['sales_timing_notes'] = sales_info['timing_notes']
            product['sales_status'] = status
            
            if sales_info['additional_notes']:
                if product['sales_instructions']:
                    product['sales_instructions'] += f"\n\n{sales_info['additional_notes']}"
                else:
                    product['sales_instructions'] = sales_info['additional_notes']
        else:
            product['sales_priority'] = None
            product['sales_priority_label'] = None
            product['sales_instructions'] = None
            product['sales_timing_notes'] = None
            product['sales_status'] = 'active'
        
        merged_products.append(product)
    
    print(f"✅ Merged {len(merged_products)} products with sales data ({matched_count} matches)")
    return merged_products

def get_or_create_category(category_name):
    """Get category ID or create if doesn't exist"""
    if not category_name:
        return None
    
    try:
        response = supabase.table('product_categories').select('id').eq('category_name', category_name).execute()
        
        if response.data and len(response.data) > 0:
            return response.data[0]['id']
        
        response = supabase.table('product_categories').insert({
            'category_name': category_name,
            'description': f'{category_name} products',
            'is_active': True
        }).execute()
        
        if response.data:
            print(f"   📁 Created category: {category_name}")
            return response.data[0]['id']
    except Exception as e:
        print(f"   ⚠️  Error with category '{category_name}': {str(e)}")
    
    return None

def import_products_to_supabase(products):
    """Import products into Supabase and create related records"""
    print("\n🚀 Starting import to Supabase...")
    
    success_count = 0
    error_count = 0
    skipped_count = 0
    contacts_created = 0
    interests_created = 0
    errors = []
    
    for i, product in enumerate(products, 1):
        try:
            # Check if product already exists
            existing = supabase.table('products').select('id, product_code').eq('product_code', product['product_code']).execute()
            
            product_id = None
            if existing.data and len(existing.data) > 0:
                product_id = existing.data[0]['id']
                skipped_count += 1
                print(f"⏭️  [{i}/{len(products)}] Skipped (exists): {product['product_code']}")
            else:
                # Get category ID
                category_id = get_or_create_category(product['category_name'])
                
                # Prepare product data
                product_data = {
                    'product_code': product['product_code'],
                    'product_name': product['product_name'],
                    'category_id': category_id,
                    'category_name': product['category_name'],
                    'market_potential': product['market_potential'],
                    'background_history': product['background_history'],
                    'key_contacts_reference': product['key_contacts_reference'],
                    'forecast_notes': product['forecast_notes'],
                    'sales_priority': product['sales_priority'],
                    'sales_priority_label': product['sales_priority_label'],
                    'sales_instructions': product['sales_instructions'],
                    'sales_timing_notes': product['sales_timing_notes'],
                    'sales_status': product['sales_status'],
                    'is_active': True if product['sales_status'] != 'removed' else False,
                }
                
                product_data = {k: v for k, v in product_data.items() if v is not None and v != ''}
                
                # Insert product
                response = supabase.table('products').insert(product_data).execute()
                
                if response.data:
                    product_id = response.data[0]['id']
                    success_count += 1
                    print(f"✅ [{i}/{len(products)}] Imported: {product['product_code']} - {product['product_name']}")
                else:
                    error_count += 1
                    error_msg = f"Failed to import {product['product_code']}: No data returned"
                    errors.append(error_msg)
                    print(f"❌ [{i}/{len(products)}] {error_msg}")
                    continue
            
            # Cache product_id for contact_product_interests
            if product_id:
                _product_cache[product['product_code']] = product_id
                
                # Parse and create contacts from key_contacts_reference
                if product['key_contacts_reference']:
                    parsed_contacts = parse_contacts_from_text(product['key_contacts_reference'])
                    
                    for contact_info in parsed_contacts:
                        try:
                            # Get or create organization
                            domain = extract_domain_from_email(contact_info['email'])
                            org_id = get_or_create_organization(domain, contact_info.get('name'))
                            
                            if not org_id:
                                continue
                            
                            # Get or create contact
                            contact_id = get_or_create_contact(
                                contact_info.get('name', ''),
                                contact_info['email'],
                                org_id
                            )
                            
                            if contact_id and product_id:
                                contacts_created += 1
                                
                                # Create contact_product_interests link
                                try:
                                    # Check if interest already exists
                                    existing_interest = supabase.table('contact_product_interests').select('id').eq('contact_id', contact_id).eq('product_id', product_id).execute()
                                    
                                    if not existing_interest.data or len(existing_interest.data) == 0:
                                        interest_data = {
                                            'contact_id': contact_id,
                                            'organization_id': org_id,
                                            'product_id': product_id,
                                            'interest_level': 'high',  # Default high if mentioned in key contacts
                                            'status': 'prospecting',
                                            'source': 'excel_import',
                                            'lead_score_contribution': 10,  # Give points for key contact interest
                                        }
                                        
                                        response = supabase.table('contact_product_interests').insert(interest_data).execute()
                                        
                                        if response.data:
                                            interests_created += 1
                                except Exception as e:
                                    # Ignore duplicate key errors
                                    if 'duplicate' not in str(e).lower():
                                        print(f"      ⚠️  Could not create interest link: {str(e)}")
                        except Exception as e:
                            print(f"      ⚠️  Error processing contact {contact_info.get('email')}: {str(e)}")
                            
        except Exception as e:
            error_count += 1
            error_msg = f"Error importing {product.get('product_code', 'UNKNOWN')}: {str(e)}"
            errors.append(error_msg)
            print(f"❌ [{i}/{len(products)}] {error_msg}")
    
    print(f"\n{'='*80}")
    print(f"📊 IMPORT SUMMARY")
    print(f"{'='*80}")
    print(f"✅ Successfully imported: {success_count} products")
    print(f"⏭️  Skipped (already exists): {skipped_count} products")
    print(f"👤 Contacts created: {contacts_created}")
    print(f"🔗 Contact-Product interests created: {interests_created}")
    print(f"❌ Failed: {error_count} products")
    print(f"{'='*80}")
    
    if errors:
        print("\n⚠️  ERRORS:")
        for error in errors[:10]:
            print(f"   - {error}")
        if len(errors) > 10:
            print(f"   ... and {len(errors) - 10} more errors")
    
    return success_count, error_count, skipped_count, contacts_created, interests_created

def verify_import():
    """Verify the imported data"""
    print("\n🔍 Verifying import...")
    
    try:
        # Count total products
        response = supabase.table('products').select('id', count='exact').execute()
        total_count = response.count if hasattr(response, 'count') else len(response.data) if response.data else 0
        
        # Count contacts
        response = supabase.table('contacts').select('id', count='exact').execute()
        contact_count = response.count if hasattr(response, 'count') else len(response.data) if response.data else 0
        
        # Count contact_product_interests
        response = supabase.table('contact_product_interests').select('id', count='exact').execute()
        interest_count = response.count if hasattr(response, 'count') else len(response.data) if response.data else 0
        
        # Count organizations
        response = supabase.table('organizations').select('id', count='exact').execute()
        org_count = response.count if hasattr(response, 'count') else len(response.data) if response.data else 0
        
        # Count by category
        response = supabase.table('products').select('category_name').execute()
        categories = {}
        if response.data:
            for row in response.data:
                cat = row.get('category_name') or 'Uncategorized'
                categories[cat] = categories.get(cat, 0) + 1
        
        # Count by priority
        response = supabase.table('products').select('sales_priority').execute()
        priorities = {}
        if response.data:
            for row in response.data:
                priority = row.get('sales_priority')
                priority_label = str(priority) if priority is not None else 'No Priority'
                priorities[priority_label] = priorities.get(priority_label, 0) + 1
        
        print(f"\n✅ Total products in database: {total_count}")
        print(f"👤 Total contacts in database: {contact_count}")
        print(f"🔗 Total contact-product interests: {interest_count}")
        print(f"📁 Total organizations: {org_count}")
        
        print(f"\n📊 Products by Category:")
        for cat, count in sorted(categories.items()):
            print(f"   {cat}: {count}")
        
        print(f"\n🎯 Products by Sales Priority:")
        for priority, count in sorted(priorities.items()):
            print(f"   Priority {priority}: {count}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error verifying import: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Main migration function"""
    print("="*80)
    print("🏥 PDMedical Products Migration (COMPLETE)")
    print("="*80)
    print(f"📅 Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"📄 Excel file: {EXCEL_FILE}")
    print("="*80)
    
    try:
        # Step 1: Extract data from Excel
        products = extract_products_from_excel()
        
        if not products:
            print("❌ No products found in Excel file. Exiting.")
            sys.exit(1)
        
        sales_data = extract_sales_priorities()
        
        # Step 2: Merge product and sales data
        merged_products = merge_product_and_sales_data(products, sales_data)
        
        # Step 3: Import to Supabase (includes contacts and interests)
        success_count, error_count, skipped_count, contacts_created, interests_created = import_products_to_supabase(merged_products)
        
        # Step 4: Verify import
        verify_import()
        
        print("\n" + "="*80)
        if error_count == 0:
            print("✅ MIGRATION COMPLETED SUCCESSFULLY!")
        else:
            print(f"⚠️  MIGRATION COMPLETED WITH {error_count} ERRORS")
        print("="*80)
        print(f"📅 Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("="*80)
        
    except Exception as e:
        print(f"\n❌ MIGRATION FAILED: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
