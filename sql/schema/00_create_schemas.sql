-- =============================================================================
-- Marketplace Analytics Platform
-- Script: 00_create_schemas.sql
-- Schema: (creates the database and the staging/warehouse schemas)
-- Description: Creates the Marketplace-Analytics-Platform database and its
--              two top-level schemas — staging (raw landing zone) and
--              warehouse (star schema). One-time environment setup step,
--              run before any table-creation script.
-- Run order: Run this script BEFORE 01_create_staging_tables.sql and
--            02_create_warehouse_tables.sql.
-- Usage: Run against the default 'postgres' database, since the target
--        database does not exist yet:
--        psql -U postgres -d postgres -f 00_create_schemas.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Create database
-- One-time step — PostgreSQL's CREATE DATABASE has no IF NOT EXISTS clause.
-- If the database already exists, this line errors ("database already
-- exists") and the script stops here. That's expected, not a failure — it
-- means this step has already been done once. 
-- -----------------------------------------------------------------------------

CREATE DATABASE "Marketplace-Analytics-Platform";


-- -----------------------------------------------------------------------------
-- Reconnect into the newly created database
-- -----------------------------------------------------------------------------

\c "Marketplace-Analytics-Platform"


-- -----------------------------------------------------------------------------
-- Drop existing schemas if they exist (safe re-run)
-- CASCADE removes any tables already created inside them. 01_create_staging_tables.sql
-- and 02_create_warehouse_tables.sql will simply recreate those tables the next
-- time they're run against a clean schema.
-- -----------------------------------------------------------------------------

DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS warehouse CASCADE;


-- -----------------------------------------------------------------------------
-- Create schemas
-- staging   — raw landing zone, no keys or constraints (01_create_staging_tables.sql)
-- warehouse — star schema, surrogate keys and foreign keys (02_create_warehouse_tables.sql)
-- -----------------------------------------------------------------------------

CREATE SCHEMA staging;
CREATE SCHEMA warehouse;


-- =============================================================================
-- End of script
