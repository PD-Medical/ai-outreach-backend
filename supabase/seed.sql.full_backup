SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

-- \restrict x4p7mgiEourKA88oBFGeznyITIJm4Swx8SiJHBMbm7zngI8edFj5QQ8a8EMidUq

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: audit_log_entries; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

INSERT INTO "auth"."audit_log_entries" ("instance_id", "id", "payload", "created_at", "ip_address") VALUES
	('00000000-0000-0000-0000-000000000000', '6943e81d-8aed-4b0c-bfd5-3fcbd8fb8605', '{"action":"user_signedup","actor_id":"00000000-0000-0000-0000-000000000000","actor_username":"service_role","actor_via_sso":false,"log_type":"team","traits":{"provider":"email","user_email":"moinsaj@gmail.com","user_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","user_phone":""}}', '2025-12-02 08:27:28.313645+00', ''),
	('00000000-0000-0000-0000-000000000000', '3f43bc60-8a13-4952-8c6f-3cebd5b8529c', '{"action":"login","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"account","traits":{"provider":"email"}}', '2025-12-02 08:28:15.147917+00', ''),
	('00000000-0000-0000-0000-000000000000', '4a3640e0-b7fb-4931-8608-2ed291d19912', '{"action":"token_refreshed","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 10:20:40.938072+00', ''),
	('00000000-0000-0000-0000-000000000000', '7894d34a-6e96-484a-aa7d-f0e7ed452628', '{"action":"token_revoked","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 10:20:40.951329+00', ''),
	('00000000-0000-0000-0000-000000000000', 'b5c7ecf2-ef02-406a-927e-9cfc84e572f0', '{"action":"token_refreshed","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 13:54:20.61477+00', ''),
	('00000000-0000-0000-0000-000000000000', '84b6647e-d183-4f52-b3a4-adcfa01d482f', '{"action":"token_revoked","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 13:54:20.61932+00', ''),
	('00000000-0000-0000-0000-000000000000', '2515e8aa-eb44-4d34-813a-c404d2514f1c', '{"action":"token_refreshed","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 14:58:26.693578+00', ''),
	('00000000-0000-0000-0000-000000000000', 'ea1a8de0-79f7-4413-bcd7-d9b2e85da8b5', '{"action":"token_revoked","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 14:58:26.697201+00', ''),
	('00000000-0000-0000-0000-000000000000', '6a9f5bcc-afec-427b-affb-eb1573978edc', '{"action":"token_refreshed","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 15:56:48.577172+00', ''),
	('00000000-0000-0000-0000-000000000000', 'a59c44eb-4982-471e-8678-70f3d674c5b8', '{"action":"token_revoked","actor_id":"4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1","actor_username":"moinsaj@gmail.com","actor_via_sso":false,"log_type":"token"}', '2025-12-02 15:56:48.580811+00', '');


--
-- Data for Name: flow_state; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at", "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token", "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at", "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin", "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change", "phone_change_token", "phone_change_sent_at", "email_change_token_current", "email_change_confirm_status", "banned_until", "reauthentication_token", "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous") VALUES
	('00000000-0000-0000-0000-000000000000', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', 'authenticated', 'authenticated', 'moinsaj@gmail.com', '$2a$10$XOKU2iRtMbEihJXXXYbXKu8rkOWK6PitmnFUWUmLMaIi3D24Fp7Au', '2025-12-02 08:27:28.315047+00', NULL, '', NULL, '', NULL, '', '', NULL, '2025-12-02 08:28:15.149654+00', '{"provider": "email", "providers": ["email"]}', '{"email_verified": true}', NULL, '2025-12-02 08:27:28.307796+00', '2025-12-02 15:56:48.584568+00', NULL, NULL, '', '', NULL, '', 0, NULL, '', NULL, false, NULL, false);


--
-- Data for Name: identities; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at", "updated_at", "id") VALUES
	('4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '{"sub": "4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1", "email": "moinsaj@gmail.com", "email_verified": false, "phone_verified": false}', 'email', '2025-12-02 08:27:28.312019+00', '2025-12-02 08:27:28.312049+00', '2025-12-02 08:27:28.312049+00', 'c6d45e7d-41e2-42fc-9e8d-692b3dac4bde');


--
-- Data for Name: instances; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: oauth_clients; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: sessions; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

INSERT INTO "auth"."sessions" ("id", "user_id", "created_at", "updated_at", "factor_id", "aal", "not_after", "refreshed_at", "user_agent", "ip", "tag", "oauth_client_id", "refresh_token_hmac_key", "refresh_token_counter") VALUES
	('e3cd05f5-cd20-40fa-b15e-e674bec0dbfb', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '2025-12-02 08:28:15.149766+00', '2025-12-02 15:56:48.586993+00', NULL, 'aal1', NULL, '2025-12-02 15:56:48.586947', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36', '192.168.65.1', NULL, NULL, NULL, NULL);


--
-- Data for Name: mfa_amr_claims; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

INSERT INTO "auth"."mfa_amr_claims" ("session_id", "created_at", "updated_at", "authentication_method", "id") VALUES
	('e3cd05f5-cd20-40fa-b15e-e674bec0dbfb', '2025-12-02 08:28:15.155434+00', '2025-12-02 08:28:15.155434+00', 'password', '873b024c-8179-4eda-8f7e-9b6d3a5d19d1');


--
-- Data for Name: mfa_factors; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: mfa_challenges; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: oauth_authorizations; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: oauth_consents; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: one_time_tokens; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

INSERT INTO "auth"."refresh_tokens" ("instance_id", "id", "token", "user_id", "revoked", "created_at", "updated_at", "parent", "session_id") VALUES
	('00000000-0000-0000-0000-000000000000', 1, '3hwpb5v2ppqx', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', true, '2025-12-02 08:28:15.152989+00', '2025-12-02 10:20:40.95254+00', NULL, 'e3cd05f5-cd20-40fa-b15e-e674bec0dbfb'),
	('00000000-0000-0000-0000-000000000000', 2, 'ew23zsp4beer', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', true, '2025-12-02 10:20:40.955424+00', '2025-12-02 13:54:20.619785+00', '3hwpb5v2ppqx', 'e3cd05f5-cd20-40fa-b15e-e674bec0dbfb'),
	('00000000-0000-0000-0000-000000000000', 3, 'mblvwqnfcbo6', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', true, '2025-12-02 13:54:20.622416+00', '2025-12-02 14:58:26.69787+00', 'ew23zsp4beer', 'e3cd05f5-cd20-40fa-b15e-e674bec0dbfb'),
	('00000000-0000-0000-0000-000000000000', 4, '3tly2ab3emhz', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', true, '2025-12-02 14:58:26.699841+00', '2025-12-02 15:56:48.581227+00', 'mblvwqnfcbo6', 'e3cd05f5-cd20-40fa-b15e-e674bec0dbfb'),
	('00000000-0000-0000-0000-000000000000', 5, 'b3h4eadxdq2c', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', false, '2025-12-02 15:56:48.5832+00', '2025-12-02 15:56:48.5832+00', '3tly2ab3emhz', 'e3cd05f5-cd20-40fa-b15e-e674bec0dbfb');


--
-- Data for Name: sso_providers; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: saml_providers; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: saml_relay_states; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: sso_domains; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--



--
-- Data for Name: mailboxes; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."mailboxes" ("id", "email", "name", "type", "imap_host", "imap_port", "imap_username", "is_active", "last_synced_at", "last_synced_uid", "sync_status", "sync_settings", "created_at", "updated_at", "persona_description", "signature_html", "signature_images") VALUES
	('75e149a5-f136-48d0-85f6-f05d47180dd3', 'chris@pdmedical.com.au', 'Chris', 'personal', 'mail.pdmedical.com.au', 993, NULL, true, NULL, '{}', '{}', '{"password_configured": true, "password_updated_at": "2025-12-02 15:44:05.600216+00"}', '2025-12-02 15:44:05.600216+00', '2025-12-02 15:52:52.551008+00', 'You are a friendly Managing Director at PD Medical, who keeps a casual tone and signs off with Cheers, Chris', '<p><span style="color: rgb(0, 112, 192); font-size: 14px;"><strong>Chris Deliopoulos</strong></span></p><p><span style="color: rgb(0, 112, 192); font-size: 14px;"><strong>PDMedical Pty Ltd</strong></span></p><p><span style="color: rgb(0, 112, 192); font-size: 14px;">80-84 Arkwright Drive</span></p><p><span style="color: rgb(0, 112, 192); font-size: 14px;">Dandenong South VIC 3175</span></p><p><span style="color: rgb(0, 112, 192); font-size: 14px;">&nbsp;</span></p><p><span style="color: rgb(0, 112, 192); font-size: 14px;">Office: (03)&nbsp; 9708 9708</span></p><p><span style="color: rgb(0, 112, 192); font-size: 14px;">Website: </span><a target="_blank" rel="noopener noreferrer" href="http://www.pdmedical.com.au"><span style="color: blue; font-size: 14px;"><u>www.pdmedical.com.au</u></span></a><span style="color: rgb(0, 112, 192); font-size: 14px;">&nbsp;</span></p><p><span style="font-size: 14px;"><img src="blob:http://localhost:8080/ee31316f-c954-4245-8b52-66299a227ae0" alt="pdmedical_icon.jpg"></span></p><p><span style="color: black; font-size: 14px;">&nbsp;Manufacturers and Distributors</span></p><p><span style="color: black; font-size: 14px;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; of Medical Products</span></p><p><span style="color: rgb(112, 48, 160); font-size: 14px;">&nbsp;Innovative : Helpful : Trusted</span></p><p></p>', '[{"cid": "pdmedical_icon_jpg_1764690188441_68njxa", "filename": "pdmedical_icon.jpg", "content_type": "image/jpeg", "storage_path": "signatures/75e149a5-f136-48d0-85f6-f05d47180dd3/pdmedical_icon_jpg_1764690188441_68njxa.jpg"}, {"cid": "pdmedical_icon_jpg_1764690760230_emmjwa", "filename": "pdmedical_icon.jpg", "content_type": "image/jpeg", "storage_path": "signatures/75e149a5-f136-48d0-85f6-f05d47180dd3/pdmedical_icon_jpg_1764690760230_emmjwa.jpg"}]');


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."profiles" ("auth_user_id", "full_name", "role", "created_at", "updated_at", "profile_id") VALUES
	('4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', 'Moinuddin Syed', 'admin', '2025-12-02 08:28:07.875402+00', '2025-12-02 08:28:07.875402+00', '3ee9d143-8935-4afc-9d18-c4c7fa2a0756');


--
-- Data for Name: campaign_sequences; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: organization_types; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: organizations; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: campaign_enrollments; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: conversations; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: emails; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: workflows; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: workflow_executions; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: action_items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: ai_enrichment_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: email_templates; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: email_drafts; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: approval_queue; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."products" ("id", "product_code", "product_name", "main_category", "subcategory", "industry_category", "unit_price", "hsv_price", "qty_per_box", "moq", "currency", "sales_priority", "sales_priority_label", "market_potential", "background_history", "key_contacts_reference", "forecast_notes", "sales_instructions", "sales_timing_notes", "sales_status", "is_active", "created_at", "updated_at", "product_type", "description", "website_url") VALUES
	('963a3f64-8adf-4f00-8a27-7626b2fda3ae', 'MA139', 'Midogas Analgesic Unit', 'MIDOGAS Products', 'MIDOGAS UNIT', 'Birthing/Biomed', 12950.00, NULL, 1, 1, 'AUD', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'The Gold Standard for administering variable analgesic gas mixture of Nitrous Oxide & Oxygen. Demand inhalation unit for pain relief. Manufactured, serviced and repaired locally. Highly effective, durable and popular over many decades.', 'https://pdmedical.com.au/midogas/'),
	('5c7103dd-438e-4226-8f35-48a5ffd2e8f7', 'EOL-C', 'Suco Sensor Board (end-of-line resistor board)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 14.80, NULL, 50, 50, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'End-of-line sensor boards for medical gas pressure systems. Connect to alarm switches with voltage-free contacts. Available for Suco and generic pressure switches. Compatible with PDMedical, BOC and ASCON gas alarm systems.', 'https://pdmedical.com.au/gas-alarm-panel-2/'),
	('adb5f5da-a5e5-460e-9a7a-173a29aa61c7', 'EOL-GP', 'Generic Sensor Board (Square)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 16.85, NULL, 25, 50, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'End-of-line sensor boards for medical gas pressure systems. Connect to alarm switches with voltage-free contacts. Available for Suco and generic pressure switches. Compatible with PDMedical, BOC and ASCON gas alarm systems.', 'https://pdmedical.com.au/gas-alarm-panel-2/'),
	('97fe9c4b-3770-4dab-95df-c109b4af23d2', '707820', 'Midogas Knob Master Control', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 42.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('627d3eec-5d9d-4222-939f-5d7b70f5ee69', 'PPE-C', 'PPE Caddy', 'PPE Products', 'PPE Caddy', 'Infection Control', 135.50, NULL, 3, 3, 'AUD', 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Holds all PPE for normal, airborne, contact and droplet precautions. Simple, clean, intuitive, instructive. Minimizes pathogen transmission. Provides consistent, clean, professional layout. Developed with IC nurses in Australian hospitals.', 'https://pdmedical.com.au/ppe-caddy-wall-and-mobile/'),
	('f708541e-c11f-4ea5-966a-3b943f0758f3', 'PPE-C1', 'PPE Caddy-C1 (clipboard + clean-up caddy)', 'PPE Products', 'PPE Caddy', 'Infection Control', 171.50, NULL, 3, 3, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Holds all PPE for normal, airborne, contact and droplet precautions. Simple, clean, intuitive, instructive. Minimizes pathogen transmission. Provides consistent, clean, professional layout. Developed with IC nurses in Australian hospitals.', 'https://pdmedical.com.au/ppe-caddy-wall-and-mobile/'),
	('3f4136ab-2e2b-4b4a-b41d-f9aa87aefda4', 'SC-100P-STV', 'Sharps Caddy Small Pink', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 48.95, 56.00, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('39e819fd-5db9-4781-887b-a6ce46816a52', 'BAR_PAN_P', 'Bariatric Pan Pink', 'Miscellaneous Products', 'Miscellaneous', 'General', 52.30, NULL, 20, 20, 'AUD', 3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'For bariatric wheelchairs and commodes including Broda. Easy fit, easy use, easy clean. Stable, durable, autoclavable. Low profile design, easy to place. Accommodates bariatric and obstetric patients.', 'https://pdmedical.com.au/bariatric-commode-pan/'),
	('5f727d29-9242-41ac-8317-972bf566593e', 'BAR_PAN_G', 'Bariatric Pan Green', 'Miscellaneous Products', 'Miscellaneous', 'General', 52.30, NULL, 20, 20, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'For bariatric wheelchairs and commodes including Broda. Easy fit, easy use, easy clean. Stable, durable, autoclavable. Low profile design, easy to place. Accommodates bariatric and obstetric patients.', 'https://pdmedical.com.au/bariatric-commode-pan/'),
	('df3183ca-7058-40bd-8313-fbafd47e589f', 'MA142-M', 'Midogas Mobile Stand (Two-Way Handle Only)', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1465.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('7fe55b8b-7b09-4d30-b82c-d306934b67b6', 'MA142-MB', 'Midogas Mobile Stand with Basket', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1560.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('aedbb06f-8441-4274-9eab-d4fc57b76bb9', 'MA142-MG', 'Midogas Mobile Stand with Gas Bottle Holders', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1655.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('4da8cd52-0ed8-4b10-9972-5eb8feca0c60', 'MA142-MBG', 'Midogas Mobile Stand with Basket and Gas Bottle Holders', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1740.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('97f32636-67f6-49ec-9977-177c4e31349e', 'MA139MSH', 'Two Way Handle', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 140.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('da9346d3-f0a2-43d9-afc5-6ffbe3d1d7cc', 'MA139MSB', 'Basket', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 125.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('0e865f44-8316-4630-bf08-8ba58dce93aa', 'GBH-C2SP', '2xC Gas Bottle Holder (Std + Scavenge)', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('701c7122-3e38-4519-98a8-176917ff0fc5', 'GBH-C2P-D', '2xD Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('440aa0ca-c0d9-4930-9674-26dd6b3dbe6c', 'GBH-C1P25', 'IV25 - 1xC Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('274192eb-bc6d-4419-a7e9-6063a18ab69f', 'GBH-C1P38', 'IV38 - 1xC Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('ce40a486-2833-4837-ad4b-2409ff215501', 'MA139 SERV', 'Midogas Std Service', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', 1250.00, NULL, NULL, 1, 'AUD', 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'service', 'Service and repair of Midogas units. Quick service and ongoing support.', 'https://pdmedical.com.au/midogas-service-and-repairs/'),
	('7e6f842b-e949-4be6-8e57-aa6f5abe3830', 'MA139-S+R', 'Midogas Service and Repair', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', NULL, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'service', 'Service and repair of Midogas units. Quick service and ongoing support.', 'https://pdmedical.com.au/midogas-service-and-repairs/'),
	('334d2252-2236-4188-91ac-7424b66c9e4d', '512071', 'Midogas Service Kit', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', 475.50, NULL, NULL, NULL, 'AUD', 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'kit', 'Service and repair of Midogas units. Quick service and ongoing support.', 'https://pdmedical.com.au/midogas-service-and-repairs/'),
	('ab6223be-bde2-497d-8a8f-c0955383bfed', 'DM493', 'Midogas Label Master Control (ON/OFF)', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 48.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('3ac9b0a8-9cd3-4f1b-a6f7-87055caefa7b', 'GBH-C2P', '2xC Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Low gravity design with heavy base for stability and ease of use. Can incorporate the Gas Scavenge Unit. For use with Midogas system.', 'https://pdmedical.com.au/midogas/'),
	('7e7aa2ea-93b5-42e1-a5c0-2e8780f778ca', 'PPE-ASS', 'PPE Clipboard (Single Sided)', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 12.00, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'PPE accessory for infection control. High quality, practical design.', NULL),
	('c78a6b04-0ac9-4d96-9bbf-90b4687cbb17', 'PPE-DFS', 'Frame Face Shield', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 3.65, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Full face shields provide comfortable protection against contamination of eyes, nose & mouth. Optically clear, anti-glare and latex free. Accommodates eyeglasses and face masks. Disposable glasses are lightweight and comfortable.', 'https://pdmedical.com.au/ppe-face-eyes-shields/'),
	('0f23cce7-d750-4e89-aa83-2dc412122cbf', 'PPE-C3', 'PPE Caddy-C3 (clipboard + clean-up + basket)', 'PPE Products', 'PPE Caddy', 'Infection Control', 265.60, NULL, 3, 3, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Holds all PPE for normal, airborne, contact and droplet precautions. Simple, clean, intuitive, instructive. Minimizes pathogen transmission. Provides consistent, clean, professional layout. Developed with IC nurses in Australian hospitals.', 'https://pdmedical.com.au/ppe-caddy-wall-and-mobile/'),
	('0b85dc17-600b-48a2-bc1a-42a6e5c0d588', 'PPE-CH', 'PPE Caddy Wall Hanger', 'PPE Products', 'PPE Caddy', 'Infection Control', 30.00, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Holds all PPE for normal, airborne, contact and droplet precautions. Simple, clean, intuitive, instructive. Minimizes pathogen transmission. Provides consistent, clean, professional layout. Developed with IC nurses in Australian hospitals.', 'https://pdmedical.com.au/ppe-caddy-wall-and-mobile/'),
	('95598e9e-8f67-4b29-9dfb-5d87a3dee32e', 'PPE-MC', 'PPE Mobile Caddy', 'PPE Products', 'PPE Caddy', 'Infection Control', 1450.00, NULL, 1, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Holds all PPE for normal, airborne, contact and droplet precautions. Simple, clean, intuitive, instructive. Minimizes pathogen transmission. Provides consistent, clean, professional layout. Developed with IC nurses in Australian hospitals.', 'https://pdmedical.com.au/ppe-caddy-wall-and-mobile/'),
	('50d12f72-6111-4022-81b8-b6a3a68ff0ef', 'PPE-ADS', 'PPE Clipboard (Double Sided)', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 15.00, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'PPE accessory for infection control. High quality, practical design.', NULL),
	('7770582e-3eff-4e34-83ea-91a3a366be28', 'PPE-DG', 'Disposable Glasses', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 2.10, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Full face shields provide comfortable protection against contamination of eyes, nose & mouth. Optically clear, anti-glare and latex free. Accommodates eyeglasses and face masks. Disposable glasses are lightweight and comfortable.', 'https://pdmedical.com.au/ppe-face-eyes-shields/'),
	('a67d6f51-15ab-448b-a95d-b2da85e2a909', 'PPE-DGF', 'Disposable Glasses Frame', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 0.60, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Full face shields provide comfortable protection against contamination of eyes, nose & mouth. Optically clear, anti-glare and latex free. Accommodates eyeglasses and face masks. Disposable glasses are lightweight and comfortable.', 'https://pdmedical.com.au/ppe-face-eyes-shields/'),
	('6bf0fcdc-1b7d-4e27-bdd2-a40b6c2ac3ed', 'PPE-DGL', 'Disposable Glasses Lens', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 1.50, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Full face shields provide comfortable protection against contamination of eyes, nose & mouth. Optically clear, anti-glare and latex free. Accommodates eyeglasses and face masks. Disposable glasses are lightweight and comfortable.', 'https://pdmedical.com.au/ppe-face-eyes-shields/'),
	('f251865c-d9c4-4946-abaf-6f7053c34697', 'PPE-FFS', 'Full Face Shield', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 4.65, NULL, 150, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Full face shields provide comfortable protection against contamination of eyes, nose & mouth. Optically clear, anti-glare and latex free. Accommodates eyeglasses and face masks. Disposable glasses are lightweight and comfortable.', 'https://pdmedical.com.au/ppe-face-eyes-shields/'),
	('c263b846-0502-4a1a-a0b9-0b819bcb3c15', 'PPE-S', 'PPE Signs', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 6.00, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'PPE accessory for infection control. High quality, practical design.', NULL),
	('49369e4e-a71a-4ff2-9c1b-a2f9e1259aa7', 'PPE-V', 'Clean-up Caddy', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 55.60, NULL, 5, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'PPE accessory for infection control. High quality, practical design.', NULL),
	('27be2a27-9e76-49c7-9835-f3e863d08b6c', 'PPE-GG', 'PPE Glove Box Holder', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 18.50, NULL, 1, 1, 'AUD', 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'PPE accessory for infection control. High quality, practical design.', NULL),
	('f5ad8c07-bb56-4b10-bb8a-33bbb1199dfd', 'SC-100B-STV', 'Sharps Caddy Small Blue', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 48.95, 56.00, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('777deed6-ba60-43fc-8cb6-57963885828b', 'SC-AT-200B', 'AT Sharps Caddy Large Blue', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 53.35, 62.50, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('df9b0052-9c3c-4465-8db3-0e9c8cfc9eff', 'SC-AT-200P', 'AT Sharps Caddy Large Pink', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 53.35, 62.50, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('08b5de99-fada-4a76-aa26-bfe5ffe6799f', 'SC-INS-200P', 'Sharps Caddy Insert Pink', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 6.95, NULL, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('610fa41d-81d7-4609-9cf2-98e42e2aaf03', 'SC-100PP-STV', 'Sharps Caddy Small Purple', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 48.95, 56.00, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('1285cbca-793c-480f-aa8d-ddfcf1449ecc', 'SC-INS-200B', 'Sharps Caddy Insert Blue', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 6.95, NULL, 4, 4, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('38e2f1ed-6014-4b60-8607-dde8398fc735', 'SC-CONT-1.4L', 'Sharps Container 1.4L (Yellow)', 'Safe Sharps Handling', 'Sharps Container', 'Infection Control', 4.53, 4.87, 30, 60, 'AUD', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', '1.4L container for sharps disposal', 'https://pdmedical.com.au/sharps-caddy/'),
	('163d1402-7f06-4bf3-9ded-e286fce31b98', 'SBR1', 'Scalpel Blade Remover - STERILE', 'Safe Sharps Handling', 'Scalpel Blade Remover', 'Infection Control', 3.65, NULL, 50, NULL, 'AUD', 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Safe and easy way to remove scalpel blades during operations. Works with any handle, any blade. Easy to hold, intuitive, comfortable and stable in operation. Minimizes injury risk and infection transmission (hepatitis, HIV/AIDS).', 'https://pdmedical.com.au/scalpel-blade-remover/'),
	('10398155-938b-4801-978d-f1b4a227d2f2', 'SBR2', 'Scalpel Blade Remover - NON-STERILE', 'Safe Sharps Handling', 'Scalpel Blade Remover', 'Infection Control', 2.20, NULL, 50, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Safe and easy way to remove scalpel blades during operations. Works with any handle, any blade. Easy to hold, intuitive, comfortable and stable in operation. Minimizes injury risk and infection transmission (hepatitis, HIV/AIDS).', 'https://pdmedical.com.au/scalpel-blade-remover/'),
	('b12beb78-4af0-4483-a6b2-524366be09b4', 'ST_G1-NH_B', 'Tray General Purpose No Hole Bulk', 'Safe Sharps Handling', 'Instrument Trays', 'Infection Control', 2.25, NULL, 100, 2700, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', '3 types for holding, transferring and managing sharps safely. Safe, comfortable to hold, easy to maneuver. Designed for the most dangerous phase of operations (suturing).', 'https://pdmedical.com.au/operating-theatre-transfer-trays/'),
	('1f1b23cb-939f-4366-ae2e-12b13cff591d', 'ST_S1-NH_B', 'Tray Scalpel/Syringe No Hole Bulk', 'Safe Sharps Handling', 'Instrument Trays', 'Infection Control', 2.25, NULL, 100, 2700, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', '3 types for holding, transferring and managing sharps safely. Safe, comfortable to hold, easy to maneuver. Designed for the most dangerous phase of operations (suturing).', 'https://pdmedical.com.au/operating-theatre-transfer-trays/'),
	('98fb6d44-bcbb-4729-8ed9-04e46ee7daf3', 'SC-WM', 'Sharps Caddy Wall Mount', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 12.50, NULL, 1, 1, 'AUD', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Protects nurses from sharps and needle injuries. Dispose contaminated sharps at point of use. Developed with IC nurses at St Vincents Private Hospital, Melbourne. Promotes 5 steps of hand hygiene.', 'https://pdmedical.com.au/sharps-caddy/'),
	('c4dc3913-490b-4ba0-8854-6539b5d8c457', 'TC1014PP-S', 'Tube Connector: Large 10-14mm OD x 8mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('b200693e-6dc5-4044-822f-357a7866152d', 'TA37PP-S', 'Tube Adaptor: X-small/Medium 3-5mm/7-10mm OD x 2mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('84b56cd6-3f9d-4ace-b598-953866361dca', 'TA47PP-S', 'Tube Adaptor: Small/Medium 4-7mm/7-10mm OD x 3mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('0c4e0bea-e750-4435-b35c-875d065fb589', 'YC810PP-S', 'Y-Tube Connector: Medium 8-10mm OD x 6mm ID. STERILE', 'Tube Connectors', 'Y-Tube Connectors', 'General', 2.75, 2.86, 100, 100, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('fbe5349d-cb27-4e21-ac29-e46c472d437f', 'SP10PP-S', 'Spigot 10mm: 0-10mm OD x 49mm long. STERILE', 'Tube Connectors', 'Spigots', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('099cb4cb-de50-4c1d-b2a1-df542d339571', 'TC47PP-S', 'Tube Connector: Small 4-7mm OD x 3mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('fead3008-c438-4370-8017-bbf42e83b435', 'TC1014PP', 'Tube Connector: Large 10-14mm OD x 8mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, NULL, 1, 1, 'AUD', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('230a690d-0917-4a5d-a1ed-6d9338171a71', 'TC37PP-S', 'Tube Connector: X-Small 3-7mm OD x 2mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, NULL, 1, 1, 'AUD', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('94eb0d85-7eaa-4cc4-9a47-e4fa9e2dac52', 'TC37PP', 'Tube Connector: X-Small 3-7mm OD x 2mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, NULL, 1, 1, 'AUD', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('6a2bf704-363b-4ae1-ab70-625786b591ff', 'DM476', 'Oxygen Button Sub-Assembly', 'Devices and Components', 'Sub-Assemblies', 'General', 1350.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('fc0b2b93-23af-4809-ab14-db2458a21641', 'DM534', 'Warning Device Sub-Assembly', 'Devices and Components', 'Sub-Assemblies', 'General', 1680.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('4a19b84b-078b-49c9-aa40-d0af65a8784d', '512444', 'N2O Tube Nylon 5/16"', 'Devices and Components', 'Components', 'General', 16.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('70d1cc6d-8bb9-4745-a4d4-1e7fcedf63cc', '512445', 'O2 Tube Nylon 1/4"', 'Devices and Components', 'Components', 'General', 16.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('7fa05e69-1db0-4faf-9236-7ba237297ef9', '512446', 'O2 Tube Nylon 1/4" plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('07b57324-5fba-4ccf-bc9d-f2dd34a334a0', '512447P', 'O2 Nylon Warning Device Tube plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('16e7f6e8-1321-476c-a161-a1e5da31712c', '512449P', 'O2 Button Nylon Tube plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('379edfde-9894-4f58-886c-65739467fdb0', '512434', 'Regulator Inlet Elbow O2 (1/8" - 1/4")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('b5dd4e20-2f14-4628-acaa-88a98f254820', '512460', 'Regulator Inlet Elbow N2O (1/8" - 5/16")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('cd1fa7d9-4a10-45ea-9651-e52aff831916', '512443', 'Master Valve Elbow O2 (1/4" - 1/4")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('48143aa2-f108-4ce4-a226-be734403d867', 'ZP1156', 'SLEEVE OXY OUTLET', 'Devices and Components', 'Components', 'General', 85.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('e510c558-cd8e-46d5-aec1-30cb39c29fbd', 'DAVM633', 'Linkettes', 'Miscellaneous Products', 'Miscellaneous', 'General', 6.35, 6.12, 400, 400, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Medical connectors and linkettes for various applications.', NULL),
	('d67a7372-6833-4903-b9e1-bb39f1414347', 'DM547', 'Master Valve Assembly for Midogas', 'Devices and Components', 'Sub-Assemblies', 'General', 1753.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('899b1536-0f2f-4884-8614-45424bc64b7a', 'MGHA-Suctn', 'MGHA-Suction', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('554dbaf4-b265-44f8-b22d-65b352e5202a', 'MGHA-OXY', 'MGHA-Medical Oxygen', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('f6a4cdf0-9da7-45f0-83b6-05df619e7b39', 'MGHA-N2O', 'MGHA-Nitrous Oxide', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('184a4590-f553-4f87-b24d-2717b3c10c36', 'MGHA-Scav', 'MGHA-Scavenge', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('cfeee004-263a-40ab-be6a-d56af91ca9f0', 'MGHA-MedAir', 'MGHA-Medical Air', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('dcd65010-afe3-40f4-9c2e-79c9cc63d49b', 'MGHA-Ent', 'MGHA-Entonox', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('aa304b4e-4819-4a13-b69c-dc0f3dbdc666', 'MGHA-SurgToolAir', 'MGHA-Surgical Tool Air', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Medical gas hose assemblies for hospital gas delivery systems. High quality construction, reliable connections.', NULL),
	('4a0469e0-27dd-4e29-b69a-b2e3d746006f', '512258', 'Norgren Regulators (not included in service kit)', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 217.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('be6ae05e-54f7-4581-918f-3de2d615a272', '512448P', 'N2O Nylon Warning Device Tube plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('f1c4555e-74b6-4052-a074-b5f5f5812127', '512456', 'Master Valve Elbow N2O (1/4" - 5/16")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('b5061578-ba8c-4464-ac1c-83ee104e7498', 'ZP1157', 'SLEEVE N2O OUTLET', 'Devices and Components', 'Components', 'General', 85.00, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('ffa6d2d5-18a4-41be-8194-2bd5a301051b', 'DM489', 'Midogas Console', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 850.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('4655db00-55bc-4d82-9716-17f4a82b6153', 'DM492', 'Midogas Percentage Scale', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 165.00, NULL, NULL, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'spare_part', 'Spare part/component for Midogas and medical gas systems. High quality, reliable performance.', NULL),
	('6f35b8ed-8f2c-4567-a907-1614ea83e57d', 'PPE-B', 'PPE Basket', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 48.50, NULL, 5, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'PPE accessory for infection control. High quality, practical design.', NULL),
	('8ab92d72-bea8-4651-9e65-d4bf1360c779', 'PPE-C2', 'PPE Caddy-C2 (clipboard + basket)', 'PPE Products', 'PPE Caddy', 'Infection Control', 210.00, NULL, 3, 3, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Holds all PPE for normal, airborne, contact and droplet precautions. Simple, clean, intuitive, instructive. Minimizes pathogen transmission. Provides consistent, clean, professional layout. Developed with IC nurses in Australian hospitals.', 'https://pdmedical.com.au/ppe-caddy-wall-and-mobile/'),
	('397b2b04-202c-4cc5-81ea-33e370ca2793', 'CC-CONT-1.3L', 'Cytotoxic Container 1.3L (Purple)', 'Safe Sharps Handling', 'Sharps Container', 'Infection Control', 4.85, NULL, 30, 30, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', '1.4L container for cytotoxic waste disposal', 'https://pdmedical.com.au/sharps-caddy/'),
	('fb1e7362-c334-46ba-ab07-ea5f01215b23', 'MA141M-9', 'Gas Scavenge Unit 915mm for Midogas', 'Devices and Components', 'Scavenge Unit', 'General', 1785.00, NULL, 1, 1, 'AUD', 3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'accessory', 'Clears the room of nitrous oxide. Extracts expired analgesic gases and protects nurses from overexposure. Can be wall-fitted or incorporated in MIDOGAS mobile stand.', 'https://pdmedical.com.au/scavenge-unit/'),
	('6be95082-3d29-440d-a281-fcbe710293bb', 'MA143-ST', 'Breathing Circuit - Scavenge Tube', 'Devices and Components', 'Breathing Circuits', 'General', 6.68, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Manufactured from high quality plastic. Suits a variety of uses. Can be purchased off-the-shelf or customized. High quality, always available. Easy grip, comfortable.', 'https://pdmedical.com.au/breathing-circuits/'),
	('b4e6f9df-9027-4246-8870-fdc373296854', 'MA143-PBCS', 'Breathing Circuit Pediatric with Scavenge', 'Devices and Components', 'Breathing Circuits', 'General', 9.85, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Manufactured from high quality plastic. Suits a variety of uses. Can be purchased off-the-shelf or customized. High quality, always available. Easy grip, comfortable.', 'https://pdmedical.com.au/breathing-circuits/'),
	('f71031bf-d8ca-4fee-b967-49729161451a', 'WARRANTY', 'Midogas Extra 12 Month Warranty', 'MIDOGAS Products', 'MIDOGAS UNIT', 'Birthing/Biomed', 1278.00, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Extended 12-month warranty coverage for Midogas Analgesic Unit. Additional peace of mind and support.', 'https://pdmedical.com.au/midogas/'),
	('349bfa2d-de5d-4063-a55f-3fb99897b886', 'DM524', 'Wall Bracket', 'MIDOGAS Products', 'MIDOGAS UNIT', 'Birthing/Biomed', 285.00, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Wall mounting bracket for Midogas Analgesic Unit. Secure and stable wall installation.', 'https://pdmedical.com.au/midogas/'),
	('0a9a3322-2c9e-4637-8d3e-931fdb27eeed', 'MA143-BCS', 'Breathing Circuit with Scavenge Tube and Mouthpiece', 'Devices and Components', 'Breathing Circuits', 'General', 8.85, 9.43, 1, 1, 'AUD', 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Manufactured from high quality plastic. Suits a variety of uses. Can be purchased off-the-shelf or customized. High quality, always available. Easy grip, comfortable.', 'https://pdmedical.com.au/breathing-circuits/'),
	('a2d2ed62-17df-47f8-a7fa-d0f175e65a7d', 'MA143-BC', 'Breathing Circuit - Single Hose', 'Devices and Components', 'Breathing Circuits', 'General', 7.26, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Manufactured from high quality plastic. Suits a variety of uses. Can be purchased off-the-shelf or customized. High quality, always available. Easy grip, comfortable.', 'https://pdmedical.com.au/breathing-circuits/'),
	('d89ddcac-b741-48a5-9fce-c1fe36413f54', 'MA143-ESC', 'Breathing Circuit - Entonox', 'Devices and Components', 'Breathing Circuits', 'General', 6.84, 7.65, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'Manufactured from high quality plastic. Suits a variety of uses. Can be purchased off-the-shelf or customized. High quality, always available. Easy grip, comfortable.', 'https://pdmedical.com.au/breathing-circuits/'),
	('8150c2b3-1575-4117-b662-b075fe91f3d6', 'GAP-16SP', 'Gas Alarm System (16 Sensor Ports)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 1385.00, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Medical gas alarm system with 4.3" TFT colour graphic display. Engineered for easy installation with web page configuration. Designed to meet AS2896 requirements for monitoring medical gas supplies in Australian hospitals.', 'https://pdmedical.com.au/gas-alarm-panel/'),
	('ddbd3f54-db27-426f-bb65-f46119b7c92d', 'GAP', 'Gas Alarm System (Mobile Messaging)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 1650.00, NULL, 1, 1, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'main_unit', 'Medical gas alarm system with 4.3" TFT colour graphic display. Engineered for easy installation with web page configuration. Designed to meet AS2896 requirements for monitoring medical gas supplies in Australian hospitals.', 'https://pdmedical.com.au/gas-alarm-panel/'),
	('e588ebd4-b1b9-4e60-89c5-f1f5f8304e3c', 'MA139-LN', 'Midogas Loan Unit', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', NULL, NULL, NULL, NULL, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'service', 'Service and repair of Midogas units. Quick service and ongoing support.', 'https://pdmedical.com.au/midogas-service-and-repairs/'),
	('8fcb87af-d9b0-4b6f-8c79-7c68d324e6d7', 'TC710PP-S', 'Tube Connector: Medium 7-10mm OD x 6mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('16041fa6-c09e-4aaf-bf08-bd71ffb76029', 'TC47PP', 'Tube Connector: Small 4-7mm OD x 3mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, NULL, 100, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('0fb6369c-8177-484b-96e8-9a6c860a5826', 'TC710PP', 'Tube Connector: Medium 7-10mm OD x 6mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, NULL, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('b7baccee-33ab-4ed3-88a1-e0895b4f4ee5', 'TA410PP-S', 'Tube Adaptor: Small/Large 4-7mm/10-14mm OD x 3mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('f88ac0a6-c2d8-4649-8be9-0eab6bf5ca69', 'TA710PP-S', 'Tube Adaptor: Medium/Large 7-10mm/10-14mm OD x 6mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('e8f24ece-9f0e-4354-b6c6-bfae8ed04c48', 'YC58PP-S', 'Y-Tube Connector: Small 5-8mm OD x 4mm ID. STERILE', 'Tube Connectors', 'Y-Tube Connectors', 'General', 2.75, 2.86, 100, 100, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('61486f88-05a2-4b4b-8f70-5192196846b1', 'YC1214PP-S', 'Y-Tube Connector: Large 12-14mm OD x 10mm ID. STERILE', 'Tube Connectors', 'Y-Tube Connectors', 'General', 2.75, 2.86, 100, 100, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/'),
	('44b96868-677c-4bc9-b65a-bfae20ad8613', 'SP13PP-S', 'Spigot 13mm: 0-13mm OD x 52mm long. STERILE', 'Tube Connectors', 'Spigots', 'General', 1.86, 2.06, 200, 200, 'AUD', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'active', true, '2025-11-25 12:36:34.962094', '2025-11-25 12:36:34.962094', 'consumable', 'High quality, wide range of sizes. Manufactured and distributed locally, always available. Custom options available on request.', 'https://pdmedical.com.au/tube-connectors-adaptors-spigots/');


--
-- Data for Name: campaigns; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: campaign_contact_summary; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: campaign_events; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: contact_product_interests; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: email_import_errors; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: product_contact_engagement; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: product_documents; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."product_documents" ("id", "product_id", "document_type", "storage_path", "file_name", "file_size_bytes", "mime_type", "description", "is_primary", "created_at", "updated_at") VALUES
	('0b6027c5-3d89-4522-944b-ff79b2b0efaa', '5f727d29-9242-41ac-8317-972bf566593e', 'brochure', 'PDM - Product Brochures & Info/Bariatric Commode Pan/Brochure/Bariatric Commode Pan_Brochure _BV1R.pdf', 'Bariatric Commode Pan_Brochure _BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('bda7fa86-9b36-464d-8d80-cdb7ce96bcc5', '39e819fd-5db9-4781-887b-a6ce46816a52', 'brochure', 'PDM - Product Brochures & Info/Bariatric Commode Pan/Brochure/Bariatric Commode Pan_Brochure _BV1R.pdf', 'Bariatric Commode Pan_Brochure _BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('baf8fbaa-3c46-4398-9f29-47b97f89898f', '6be95082-3d29-440d-a281-fcbe710293bb', 'brochure', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure/PDMedical_Breathing Circuits_NW24.pdf', 'PDMedical_Breathing Circuits_NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('776f8854-f852-436d-8118-dace6c3754df', 'b4e6f9df-9027-4246-8870-fdc373296854', 'brochure', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure/PDMedical_Breathing Circuits_NW24.pdf', 'PDMedical_Breathing Circuits_NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('fb5657b8-e9f1-4709-a2e3-c8fbd337d442', '0a9a3322-2c9e-4637-8d3e-931fdb27eeed', 'brochure', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure/PDMedical_Breathing Circuits_NW24.pdf', 'PDMedical_Breathing Circuits_NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('a37cdca5-1a33-47af-9f8c-7d73c2e337bb', 'a2d2ed62-17df-47f8-a7fa-d0f175e65a7d', 'brochure', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure/PDMedical_Breathing Circuits_NW24.pdf', 'PDMedical_Breathing Circuits_NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('a4354237-5535-40b5-9949-2e10262df7ab', 'd89ddcac-b741-48a5-9fce-c1fe36413f54', 'brochure', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure/PDMedical_Breathing Circuits_NW24.pdf', 'PDMedical_Breathing Circuits_NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('c0725e8e-1595-4ac7-ab12-5be3a9b1ec0a', '7770582e-3eff-4e34-83ea-91a3a366be28', 'brochure', 'PDM - Product Brochures & Info/Face Shield/Brochure/PDMedical_Eyes&Face Shield Brochure_V4.pdf', 'PDMedical_Eyes&Face Shield Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('0105a596-33f7-46a7-bb97-554d2a83fd87', '6bf0fcdc-1b7d-4e27-bdd2-a40b6c2ac3ed', 'brochure', 'PDM - Product Brochures & Info/Face Shield/Brochure/PDMedical_Eyes&Face Shield Brochure_V4.pdf', 'PDMedical_Eyes&Face Shield Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('fa16e0ac-99c2-4209-94a8-f29887c6f59d', 'f251865c-d9c4-4946-abaf-6f7053c34697', 'brochure', 'PDM - Product Brochures & Info/Face Shield/Brochure/PDMedical_Eyes&Face Shield Brochure_V4.pdf', 'PDMedical_Eyes&Face Shield Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('af4db22b-a806-4ada-948e-85e084526d9f', 'c78a6b04-0ac9-4d96-9bbf-90b4687cbb17', 'brochure', 'PDM - Product Brochures & Info/Face Shield/Brochure/PDMedical_Eyes&Face Shield Brochure_V4.pdf', 'PDMedical_Eyes&Face Shield Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('d0eba0e5-90cd-47f6-960b-6cc452393011', 'a67d6f51-15ab-448b-a95d-b2da85e2a909', 'brochure', 'PDM - Product Brochures & Info/Face Shield/Brochure/PDMedical_Eyes&Face Shield Brochure_V4.pdf', 'PDMedical_Eyes&Face Shield Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('309e6dc9-9e02-424a-aef0-e8daaafd2da2', 'fb1e7362-c334-46ba-ab07-ea5f01215b23', 'brochure', 'PDM - Product Brochures & Info/Gas Scavenge Unit/Brochure/Gas Scavenge Unit for MIDOGAS.pdf', 'Gas Scavenge Unit for MIDOGAS.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('96246d17-03e8-4f25-9af1-359814a57645', '184a4590-f553-4f87-b24d-2717b3c10c36', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('7b1cc670-4336-462a-9088-b74036a5ba76', '899b1536-0f2f-4884-8614-45424bc64b7a', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('d4c7bcae-424e-4451-bf2a-b196744ca605', 'cfeee004-263a-40ab-be6a-d56af91ca9f0', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('2f005366-e623-434a-9799-a52e68367068', 'f6a4cdf0-9da7-45f0-83b6-05df619e7b39', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('71e57203-43b9-4d89-afd0-493924e76cc8', '554dbaf4-b265-44f8-b22d-65b352e5202a', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('c4eed25f-bf1e-4c85-a65c-403aaf186cbd', 'dcd65010-afe3-40f4-9c2e-79c9cc63d49b', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('5a60d63e-f363-4803-a17c-d6ab93c6a262', 'aa304b4e-4819-4a13-b69c-dc0f3dbdc666', 'brochure', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', 'Medical Gas Hose Assemblies_BV1R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('88ec81de-edcc-47da-92c3-937155834359', '963a3f64-8adf-4f00-8a27-7626b2fda3ae', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('fc84df39-92bf-4561-9c2b-250f1f678b5a', '349bfa2d-de5d-4063-a55f-3fb99897b886', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('a28d37d7-69a0-4928-a8a3-510d6aa12eae', 'f71031bf-d8ca-4fee-b967-49729161451a', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('7283f37f-9237-421e-ad75-5bacb79c6532', 'aedbb06f-8441-4274-9eab-d4fc57b76bb9', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('cead75e9-2fcb-476f-b7c8-4966427b42ea', '7fe55b8b-7b09-4d30-b82c-d306934b67b6', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('d9e36fa3-1d05-4f37-bd22-6d9d87e3f8a5', 'df3183ca-7058-40bd-8313-fbafd47e589f', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('585556e6-5930-4db3-a347-99d8fa9b2bfc', '4da8cd52-0ed8-4b10-9972-5eb8feca0c60', 'brochure', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', 'Midogas_BV3R.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('a8948a18-942d-4845-b933-517d2cf184c7', '627d3eec-5d9d-4222-939f-5d7b70f5ee69', 'brochure', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', 'PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('32afa519-06dd-407d-a592-4e92afe59907', 'f708541e-c11f-4ea5-966a-3b943f0758f3', 'brochure', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', 'PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('396beec9-0880-4568-b169-5a86f6bdd2e5', '0f23cce7-d750-4e89-aa83-2dc412122cbf', 'brochure', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', 'PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('15fc71a3-d26a-4f75-8fb6-5350c26d9eb9', '0b85dc17-600b-48a2-bc1a-42a6e5c0d588', 'brochure', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', 'PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('f560f8cc-33f2-420b-9612-a2571770e31f', '8ab92d72-bea8-4651-9e65-d4bf1360c779', 'brochure', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', 'PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('2f49e46f-788d-4c1c-be2f-051168299534', '95598e9e-8f67-4b29-9dfb-5d87a3dee32e', 'brochure', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', 'PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('44017454-13da-4d92-934c-6b745a62149e', '163d1402-7f06-4bf3-9ded-e286fce31b98', 'brochure', 'PDM - Product Brochures & Info/Scalpel Blade Remover/Brochure/PDMedical_Scalpel Blade Remover Brochure_V4.pdf', 'PDMedical_Scalpel Blade Remover Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('8abbb640-0ce3-48b4-b6bf-2691d3551c56', '10398155-938b-4801-978d-f1b4a227d2f2', 'brochure', 'PDM - Product Brochures & Info/Scalpel Blade Remover/Brochure/PDMedical_Scalpel Blade Remover Brochure_V4.pdf', 'PDMedical_Scalpel Blade Remover Brochure_V4.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('719cda1c-17aa-4a71-bfea-91b2d9039381', 'ddbd3f54-db27-426f-bb65-f46119b7c92d', 'brochure', 'PDM - Product Brochures & Info/Sensor Boards/Brochure/Gas Pressure Switch Sensor Boards_BV1.pdf', 'Gas Pressure Switch Sensor Boards_BV1.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('a38d12dd-3e47-4600-b910-965c14b07368', '8150c2b3-1575-4117-b662-b075fe91f3d6', 'brochure', 'PDM - Product Brochures & Info/Sensor Boards/Brochure/Gas Pressure Switch Sensor Boards_BV1.pdf', 'Gas Pressure Switch Sensor Boards_BV1.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('32fbe29d-33a7-4e48-afec-878b20418adb', '5c7103dd-438e-4226-8f35-48a5ffd2e8f7', 'brochure', 'PDM - Product Brochures & Info/Sensor Boards/Brochure/Gas Pressure Switch Sensor Boards_BV1.pdf', 'Gas Pressure Switch Sensor Boards_BV1.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('080a58db-223b-4ce8-a4fa-0111a9717227', 'adb5f5da-a5e5-460e-9a7a-173a29aa61c7', 'brochure', 'PDM - Product Brochures & Info/Sensor Boards/Brochure/Gas Pressure Switch Sensor Boards_BV1.pdf', 'Gas Pressure Switch Sensor Boards_BV1.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('d9e464a3-64a2-4a06-a601-47e4ef076947', '1285cbca-793c-480f-aa8d-ddfcf1449ecc', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('86decbab-13c9-4b0f-80b6-e35d4dcffac2', '08b5de99-fada-4a76-aa26-bfe5ffe6799f', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('cf03ad24-0b75-47d4-811e-ad067ef0bf61', 'df9b0052-9c3c-4465-8db3-0e9c8cfc9eff', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('743ae4ba-0bf3-49ea-b137-db7e00743037', '3f4136ab-2e2b-4b4a-b41d-f9aa87aefda4', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('2b8a8f45-411a-48f2-b5d2-d6600c2c0acf', '610fa41d-81d7-4609-9cf2-98e42e2aaf03', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('651024bc-d219-45c7-bc71-19a223e113f6', 'f5ad8c07-bb56-4b10-bb8a-33bbb1199dfd', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('e790ed1e-aff6-4b29-825c-e29df33a13ca', '777deed6-ba60-43fc-8cb6-57963885828b', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('e4a5dd5d-5591-4cf5-acce-73694d50d68a', '98fb6d44-bcbb-4729-8ed9-04e46ee7daf3', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('5785085b-1137-40e1-b968-89a5022bbd3f', '38e2f1ed-6014-4b60-8607-dde8398fc735', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('fd7c2e6f-3ed1-4ad5-b782-8fef7df6b180', '397b2b04-202c-4cc5-81ea-33e370ca2793', 'brochure', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', 'Sharps Caddy_Brochure 2025.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('54dc7a13-9bcd-45b3-b0dc-62dc2c763555', '1f1b23cb-939f-4366-ae2e-12b13cff591d', 'brochure', 'PDM - Product Brochures & Info/Sharps Transfer Trays/Brochure/PDMedical_Operating Theatre Transfer Trays NW24.pdf', 'PDMedical_Operating Theatre Transfer Trays NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('3137d5b4-83c3-407a-8616-a94c0c81aede', 'b12beb78-4af0-4483-a6b2-524366be09b4', 'brochure', 'PDM - Product Brochures & Info/Sharps Transfer Trays/Brochure/PDMedical_Operating Theatre Transfer Trays NW24.pdf', 'PDMedical_Operating Theatre Transfer Trays NW24.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('6259e311-48dc-411a-becb-7190d1692dee', '84b56cd6-3f9d-4ace-b598-953866361dca', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('805df440-f6b7-431d-a8f2-89db22f41fec', '099cb4cb-de50-4c1d-b2a1-df542d339571', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('65d02b47-f68d-41ba-9371-e9f9b36f0f41', '0c4e0bea-e750-4435-b35c-875d065fb589', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('611b825c-1737-4736-9e50-5c88ea2df112', 'c4dc3913-490b-4ba0-8854-6539b5d8c457', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('1f8c4cef-dffc-4222-984e-be64f092c3db', 'b200693e-6dc5-4044-822f-357a7866152d', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('57dbd9b3-3507-4575-bd3b-468c8b30aa11', 'fbe5349d-cb27-4e21-ac29-e46c472d437f', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('fcd95c54-778a-4bdd-99a7-13ec3e3ea776', '61486f88-05a2-4b4b-8f70-5192196846b1', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('894e52d5-2c13-4743-a26c-e64a0d17661d', '0fb6369c-8177-484b-96e8-9a6c860a5826', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('8f438dec-14cd-4485-a881-5a2d9c1075d3', 'e8f24ece-9f0e-4354-b6c6-bfae8ed04c48', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('c848e029-9c6b-441c-8848-1c4f1f50534f', '44b96868-677c-4bc9-b65a-bfae20ad8613', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('fb0ccb51-ee17-4ffe-b3a5-5623e057e892', '16041fa6-c09e-4aaf-bf08-bd71ffb76029', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('1f5bb534-5d10-487a-85b5-66823e06b749', 'f88ac0a6-c2d8-4649-8be9-0eab6bf5ca69', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('2d77cb5a-cb8f-4315-8687-7b5d078c6454', 'b7baccee-33ab-4ed3-88a1-e0895b4f4ee5', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('405b0798-5402-42c9-853c-9bbaa58c9524', '8fcb87af-d9b0-4b6f-8c79-7c68d324e6d7', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('ad01ec8b-efa2-4bc5-b7d5-7cc2615b8ffa', 'fead3008-c438-4370-8017-bbf42e83b435', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('3ff4107d-6979-4005-b700-9aa109b0f8b0', '230a690d-0917-4a5d-a1ed-6d9338171a71', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00'),
	('2789c5b8-a910-4a60-8834-abd79700443d', '94eb0d85-7eaa-4cc4-9a47-e4fa9e2dac52', 'brochure', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', 'PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, 'application/pdf', NULL, true, '2025-12-02 15:02:36.885388+00', '2025-12-02 15:02:36.885388+00');


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."role_permissions" ("role", "view_users", "manage_users", "view_contacts", "manage_contacts", "view_campaigns", "manage_campaigns", "approve_campaigns", "view_analytics", "manage_approvals", "updated_at", "view_workflows", "view_emails", "view_products", "manage_products") VALUES
	('admin', true, true, true, true, true, true, true, true, true, '2025-12-02 15:02:36.885388+00', true, true, true, true),
	('sales', false, false, true, true, true, true, false, true, false, '2025-12-02 15:02:36.885388+00', true, true, true, true),
	('accounts', false, false, true, true, true, false, true, true, true, '2025-12-02 15:02:36.885388+00', true, true, true, false),
	('management', false, false, true, false, true, false, true, true, true, '2025-12-02 15:02:36.885388+00', true, true, true, false);


--
-- Data for Name: system_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."system_config" ("key", "value", "description", "updated_at") VALUES
	('workflow_matcher_url', '"http://host.docker.internal:3001/workflow-matcher"', 'URL for workflow-matcher Lambda function', '2025-11-23 07:05:09.9592'),
	('campaign_scheduler_url', '"http://host.docker.internal:3001/campaign-scheduler"', 'URL for campaign-scheduler Lambda function (pg_cron)', '2025-12-01 00:00:00'),
	('campaign_executor_url', '"http://host.docker.internal:3001/campaign-executor"', 'URL for campaign-executor Lambda function (pg_cron)', '2025-12-01 00:00:00');


--
-- Data for Name: user_permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

INSERT INTO "storage"."buckets" ("id", "name", "owner", "created_at", "updated_at", "public", "avif_autodetection", "file_size_limit", "allowed_mime_types", "owner_id", "type") VALUES
	('ai-outreach', 'ai-outreach', NULL, '2025-12-02 08:22:48.086505+00', '2025-12-02 08:22:48.086505+00', false, false, NULL, NULL, NULL, 'STANDARD'),
	('internal', 'internal', NULL, '2025-12-02 16:31:18.466739+00', '2025-12-02 16:31:18.466739+00', false, false, NULL, NULL, NULL, 'STANDARD');


--
-- Data for Name: buckets_analytics; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: buckets_vectors; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: iceberg_namespaces; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: iceberg_tables; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: objects; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

INSERT INTO "storage"."objects" ("id", "bucket_id", "name", "owner", "created_at", "updated_at", "last_accessed_at", "metadata", "version", "owner_id", "user_metadata", "level") VALUES
	('6b2a455f-fc47-4a72-905c-a099b3de774c', 'ai-outreach', 'PDM - Product Brochures & Info/Midogas mini/MIDOGAS-mini _  Spec Sheet & Unique Features.pdf', NULL, '2025-12-02 08:22:52.198917+00', '2025-12-02 08:22:52.198917+00', '2025-12-02 08:22:52.198917+00', '{"eTag": "\"7583db91c50e0152f0ed8afe8dd83ee6\"", "size": 131453, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.138Z", "contentLength": 131453, "httpStatusCode": 200}', 'f0aa8bfc-da3d-4b22-9740-c899661c6dae', NULL, NULL, 3),
	('cd4ae4c6-45fd-46ba-8204-36c33c052fa2', 'ai-outreach', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors/PDMedical_Connectors_ Adaptors_Spigots_Jul2023.pdf', NULL, '2025-12-02 08:22:52.200643+00', '2025-12-02 08:22:52.200643+00', '2025-12-02 08:22:52.200643+00', '{"eTag": "\"127ba48d4fbf748101fa86f40d06c990\"", "size": 206353, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.138Z", "contentLength": 206353, "httpStatusCode": 200}', '800c2356-d11e-41fa-995f-fddfcd48555d', NULL, NULL, 3),
	('0f53e323-7c00-4c7d-8552-3759368a04e1', 'ai-outreach', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure/PDMedical_Breathing Circuits_NW24.pdf', NULL, '2025-12-02 08:22:52.224589+00', '2025-12-02 08:22:52.224589+00', '2025-12-02 08:22:52.224589+00', '{"eTag": "\"e9e8c9fda765130b75224b568aca3a8d\"", "size": 550238, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.138Z", "contentLength": 550238, "httpStatusCode": 200}', '12eff0a7-3331-4dd4-98fa-52ce5b8c0c7d', NULL, NULL, 4),
	('cb782e1d-c20b-475a-a518-05e0a0a7050c', 'ai-outreach', 'PDM - Product Brochures & Info/Bariatric Commode Pan/Brochure/Bariatric Commode Pan_Brochure _BV1R.pdf', NULL, '2025-12-02 08:22:52.243762+00', '2025-12-02 08:22:52.243762+00', '2025-12-02 08:22:52.243762+00', '{"eTag": "\"7c7cf6af9d108e186135b0ee8a6f0e1f\"", "size": 706012, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.139Z", "contentLength": 706012, "httpStatusCode": 200}', '1bc69800-d3a2-47c8-921d-f217700277c0', NULL, NULL, 4),
	('049a7630-3e59-4e28-8e43-187bddceda08', 'ai-outreach', 'PDM - Product Brochures & Info/PPE Caddy/Brochure/PPE Caddy Brochure - PDMedical V1_lr.pdf', NULL, '2025-12-02 08:22:52.299004+00', '2025-12-02 08:22:52.299004+00', '2025-12-02 08:22:52.299004+00', '{"eTag": "\"2d8675367e5accfe6215b08fa1f23e3b\"", "size": 887820, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.151Z", "contentLength": 887820, "httpStatusCode": 200}', '605a3513-4888-41e2-8792-277e4e592d70', NULL, NULL, 4),
	('2041c190-f8fe-4ca0-8680-fa38a9ec9803', 'ai-outreach', 'PDM - Product Brochures & Info/Gas Scavenge Unit/Brochure/Gas Scavenge Unit for MIDOGAS.pdf', NULL, '2025-12-02 08:22:52.377617+00', '2025-12-02 08:22:52.377617+00', '2025-12-02 08:22:52.377617+00', '{"eTag": "\"0d1cd42e4e61e8978a649b51ffaa1882\"", "size": 652803, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.250Z", "contentLength": 652803, "httpStatusCode": 200}', 'c3057141-b7f1-4496-bd7c-84a57b0d45b4', NULL, NULL, 4),
	('05e7a9b4-ab82-4b8a-b778-1c6b30619ff0', 'ai-outreach', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure/Sharps Caddy_Brochure 2025.pdf', NULL, '2025-12-02 08:22:52.524318+00', '2025-12-02 08:22:52.524318+00', '2025-12-02 08:22:52.524318+00', '{"eTag": "\"14bb04566151bf1e31e08861b151d91c\"", "size": 1023908, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.449Z", "contentLength": 1023908, "httpStatusCode": 200}', 'f8da4377-cb31-46e8-ab09-0dcc02c397ca', NULL, NULL, 4),
	('7326d69a-8fc1-46c8-abce-014f46814c33', 'ai-outreach', 'PDM - Product Brochures & Info/Sharps Transfer Trays/Brochure/PDMedical_Operating Theatre Transfer Trays NW24.pdf', NULL, '2025-12-02 08:22:52.527183+00', '2025-12-02 08:22:52.527183+00', '2025-12-02 08:22:52.527183+00', '{"eTag": "\"eb73ded1aee4e8b68641d21137c61fc9\"", "size": 1702518, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.361Z", "contentLength": 1702518, "httpStatusCode": 200}', 'fc927189-75e7-4eca-b8fa-e5d6e7fcdebc', NULL, NULL, 4),
	('91ca9147-4c25-47e7-b2d2-731e03f96bfe', 'ai-outreach', 'PDM - Product Brochures & Info/Sensor Boards/Brochure/Gas Pressure Switch Sensor Boards_BV1.pdf', NULL, '2025-12-02 08:22:52.549942+00', '2025-12-02 08:22:52.549942+00', '2025-12-02 08:22:52.549942+00', '{"eTag": "\"841b92ddbe6e75369876caacb90c3ada\"", "size": 2338191, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.418Z", "contentLength": 2338191, "httpStatusCode": 200}', 'ddad4704-8bcf-4304-b2c3-ac06d5b5744b', NULL, NULL, 4),
	('453c68b3-bdcb-4072-9ffb-f360d5a6da0d', 'ai-outreach', 'PDM - Product Brochures & Info/'' PDM All Products Catalogue/PDMedical Product Catalogue 2022.pdf', NULL, '2025-12-02 08:22:52.60318+00', '2025-12-02 08:22:52.60318+00', '2025-12-02 08:22:52.60318+00', '{"eTag": "\"69b68b382e5e2a81eee376e7db9a286f\"", "size": 6423802, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.138Z", "contentLength": 6423802, "httpStatusCode": 200}', '71b41356-eee1-4ccb-a9b0-f3cb1d4a7d2a', NULL, NULL, 3),
	('63dd793c-f24b-4490-89cf-ab21d8d0bdd4', 'ai-outreach', 'PDM - Product Brochures & Info/Midogas/Brochure/Midogas_BV3R.pdf', NULL, '2025-12-02 08:22:52.668014+00', '2025-12-02 08:22:52.668014+00', '2025-12-02 08:22:52.668014+00', '{"eTag": "\"09be336f8055e9f4eaea25f6e5734af0\"", "size": 206188, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.656Z", "contentLength": 206188, "httpStatusCode": 200}', '957411e7-c16f-4ee5-9b74-3540d36b74ba', NULL, NULL, 4),
	('6ac140df-fa95-456a-8391-5c1356e21f29', 'ai-outreach', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure/Medical Gas Hose Assemblies_BV1R.pdf', NULL, '2025-12-02 08:22:52.678471+00', '2025-12-02 08:22:52.678471+00', '2025-12-02 08:22:52.678471+00', '{"eTag": "\"342b17756db8dc1046d2646bdbe030ab\"", "size": 578938, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.656Z", "contentLength": 578938, "httpStatusCode": 200}', 'e43e979d-7d25-4e4a-8472-5a832c89e635', NULL, NULL, 4),
	('639b20a8-46a3-4522-82ff-9e85776a502d', 'ai-outreach', 'PDM - Product Brochures & Info/Midogas/Brochure/MIDOGAS Analgesic Unit on Mobile Stand.pdf', NULL, '2025-12-02 08:22:52.689309+00', '2025-12-02 08:22:52.689309+00', '2025-12-02 08:22:52.689309+00', '{"eTag": "\"b271b59611f974c263ea3c15a6dc99bf\"", "size": 617640, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.663Z", "contentLength": 617640, "httpStatusCode": 200}', '56cf57c0-78ed-4e86-9fa8-a3237a198092', NULL, NULL, 4),
	('e677e5b8-149d-4c4c-a49e-ec14fed0e2f3', 'ai-outreach', 'PDM - Product Brochures & Info/Scalpel Blade Remover/Brochure/PDMedical_Scalpel Blade Remover Brochure_V4.pdf', NULL, '2025-12-02 08:22:52.704694+00', '2025-12-02 08:22:52.704694+00', '2025-12-02 08:22:52.704694+00', '{"eTag": "\"b6382e8bf22a73ad753de92bfb2e87f6\"", "size": 1205831, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.668Z", "contentLength": 1205831, "httpStatusCode": 200}', '9bf88ec0-cd0b-4676-bc28-735575939cc0', NULL, NULL, 4),
	('3b596e78-1674-4ccb-be5e-1577fc2b3fe3', 'ai-outreach', 'PDM - Product Brochures & Info/Face Shield/Brochure/PDMedical_Eyes&Face Shield Brochure_V4.pdf', NULL, '2025-12-02 08:22:52.682174+00', '2025-12-02 08:22:52.682174+00', '2025-12-02 08:22:52.682174+00', '{"eTag": "\"077ffd015d2887b49015fabfa86cc742\"", "size": 479038, "mimetype": "application/pdf", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T08:22:52.660Z", "contentLength": 479038, "httpStatusCode": 200}', 'cd7e9027-d8a4-4655-829c-5b110e57217a', NULL, NULL, 4),
	('9a93a661-858e-4440-bc3b-6393e23996c4', 'ai-outreach', 'signatures/75e149a5-f136-48d0-85f6-f05d47180dd3/pdmedical_icon_jpg_1764690188441_68njxa.jpg', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '2025-12-02 15:44:05.879729+00', '2025-12-02 15:44:05.879729+00', '2025-12-02 15:44:05.879729+00', '{"eTag": "\"2d6def158dcd9a8c58056b71921a3ff4\"", "size": 2549, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T15:44:05.870Z", "contentLength": 2549, "httpStatusCode": 200}', '0df470e0-8fdf-4ea0-9230-dfdcb1a8feeb', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '{}', 3),
	('1a3eb71a-b751-4482-bb5c-4346e483057f', 'ai-outreach', 'signatures/75e149a5-f136-48d0-85f6-f05d47180dd3/pdmedical_icon_jpg_1764690760230_emmjwa.jpg', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '2025-12-02 15:52:52.378196+00', '2025-12-02 15:52:52.378196+00', '2025-12-02 15:52:52.378196+00', '{"eTag": "\"2d6def158dcd9a8c58056b71921a3ff4\"", "size": 2549, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2025-12-02T15:52:52.372Z", "contentLength": 2549, "httpStatusCode": 200}', '9b5a688b-b58a-4ca8-b603-8c5f73e40cc4', '4e2c9c2a-78f5-4d4b-b3a0-08cc32e1e7d1', '{}', 3);


--
-- Data for Name: prefixes; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

INSERT INTO "storage"."prefixes" ("bucket_id", "name", "created_at", "updated_at") VALUES
	('ai-outreach', 'PDM - Product Brochures & Info', '2025-12-02 08:22:52.198917+00', '2025-12-02 08:22:52.198917+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Midogas mini', '2025-12-02 08:22:52.198917+00', '2025-12-02 08:22:52.198917+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Spigots, Connectors and Adaptors', '2025-12-02 08:22:52.200643+00', '2025-12-02 08:22:52.200643+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Breathing Circuits', '2025-12-02 08:22:52.224589+00', '2025-12-02 08:22:52.224589+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Breathing Circuits/Brochure', '2025-12-02 08:22:52.224589+00', '2025-12-02 08:22:52.224589+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Bariatric Commode Pan', '2025-12-02 08:22:52.243762+00', '2025-12-02 08:22:52.243762+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Bariatric Commode Pan/Brochure', '2025-12-02 08:22:52.243762+00', '2025-12-02 08:22:52.243762+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/PPE Caddy', '2025-12-02 08:22:52.299004+00', '2025-12-02 08:22:52.299004+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/PPE Caddy/Brochure', '2025-12-02 08:22:52.299004+00', '2025-12-02 08:22:52.299004+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Gas Scavenge Unit', '2025-12-02 08:22:52.377617+00', '2025-12-02 08:22:52.377617+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Gas Scavenge Unit/Brochure', '2025-12-02 08:22:52.377617+00', '2025-12-02 08:22:52.377617+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Sharps Caddy', '2025-12-02 08:22:52.524318+00', '2025-12-02 08:22:52.524318+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Sharps Caddy/Brochure', '2025-12-02 08:22:52.524318+00', '2025-12-02 08:22:52.524318+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Sharps Transfer Trays', '2025-12-02 08:22:52.527183+00', '2025-12-02 08:22:52.527183+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Sharps Transfer Trays/Brochure', '2025-12-02 08:22:52.527183+00', '2025-12-02 08:22:52.527183+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Sensor Boards', '2025-12-02 08:22:52.549942+00', '2025-12-02 08:22:52.549942+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Sensor Boards/Brochure', '2025-12-02 08:22:52.549942+00', '2025-12-02 08:22:52.549942+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/'' PDM All Products Catalogue', '2025-12-02 08:22:52.60318+00', '2025-12-02 08:22:52.60318+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Midogas', '2025-12-02 08:22:52.668014+00', '2025-12-02 08:22:52.668014+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Midogas/Brochure', '2025-12-02 08:22:52.668014+00', '2025-12-02 08:22:52.668014+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies', '2025-12-02 08:22:52.678471+00', '2025-12-02 08:22:52.678471+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Medical Gas Hose Assemblies/Brochure', '2025-12-02 08:22:52.678471+00', '2025-12-02 08:22:52.678471+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Face Shield', '2025-12-02 08:22:52.682174+00', '2025-12-02 08:22:52.682174+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Face Shield/Brochure', '2025-12-02 08:22:52.682174+00', '2025-12-02 08:22:52.682174+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Scalpel Blade Remover', '2025-12-02 08:22:52.704694+00', '2025-12-02 08:22:52.704694+00'),
	('ai-outreach', 'PDM - Product Brochures & Info/Scalpel Blade Remover/Brochure', '2025-12-02 08:22:52.704694+00', '2025-12-02 08:22:52.704694+00'),
	('ai-outreach', 'signatures', '2025-12-02 15:44:05.879729+00', '2025-12-02 15:44:05.879729+00'),
	('ai-outreach', 'signatures/75e149a5-f136-48d0-85f6-f05d47180dd3', '2025-12-02 15:44:05.879729+00', '2025-12-02 15:44:05.879729+00');


--
-- Data for Name: s3_multipart_uploads; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: s3_multipart_uploads_parts; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: vector_indexes; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--



--
-- Data for Name: hooks; Type: TABLE DATA; Schema: supabase_functions; Owner: supabase_functions_admin
--



--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE SET; Schema: auth; Owner: supabase_auth_admin
--

SELECT pg_catalog.setval('"auth"."refresh_tokens_id_seq"', 5, true);


--
-- Name: hooks_id_seq; Type: SEQUENCE SET; Schema: supabase_functions; Owner: supabase_functions_admin
--

SELECT pg_catalog.setval('"supabase_functions"."hooks_id_seq"', 1, false);


--
-- PostgreSQL database dump complete
--

-- \unrestrict x4p7mgiEourKA88oBFGeznyITIJm4Swx8SiJHBMbm7zngI8edFj5QQ8a8EMidUq

RESET ALL;
