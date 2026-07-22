"""
db_connection.py
Marketplace Analytics Platform

Centralised SQLAlchemy engine factory.  All ETL scripts and notebooks
import from here so connection config lives in exactly one place.

Connection parameters are read from environment variables with safe
localhost defaults — set them in your shell or a .env file:

    export OLIST_DB_HOST=localhost
    export OLIST_DB_PORT=5432
    export OLIST_DB_NAME=Marketplace-Analytics-Platform
    export OLIST_DB_USER=postgres
    export OLIST_DB_PASSWORD=your_password
"""

import os
from sqlalchemy import create_engine, Engine


def _build_url() -> str:
    host     = os.getenv('OLIST_DB_HOST',     'localhost')
    port     = os.getenv('OLIST_DB_PORT',     '5432')
    dbname   = os.getenv('OLIST_DB_NAME',     'Marketplace-Analytics-Platform')
    user     = os.getenv('OLIST_DB_USER',     'postgres')
    password = os.getenv('OLIST_DB_PASSWORD', '')
    return f'postgresql+psycopg2://{user}:{password}@{host}:{port}/{dbname}'


def get_engine() -> Engine:
    """
    Returns an engine with no default schema override.
    Use this for cross-schema queries (e.g. staging.* and warehouse.*).
    """
    return create_engine(_build_url(), future=True)


def get_staging_engine() -> Engine:
    """Returns an engine with search_path set to the staging schema."""
    return create_engine(
        _build_url(),
        connect_args={'options': '-csearch_path=staging'},
        future=True,
    )


def get_warehouse_engine() -> Engine:
    """Returns an engine with search_path set to the warehouse schema."""
    return create_engine(
        _build_url(),
        connect_args={'options': '-csearch_path=warehouse'},
        future=True,
    )
