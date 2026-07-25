"""add multi-admin fields

Revision ID: 8c7b7e0d6a21
Revises: d2e8fdbb4a50
Create Date: 2026-07-25
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "8c7b7e0d6a21"
down_revision: Union[str, None] = "d2e8fdbb4a50"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("admins", sa.Column("display_name", sa.String(200), nullable=True))
    op.add_column(
        "admins",
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
    )
    op.add_column(
        "admins",
        sa.Column(
            "is_superadmin", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
    )
    op.create_index("ix_admins_username", "admins", ["username"], unique=True)
    admins = sa.table(
        "admins",
        sa.column("username", sa.String()),
        sa.column("is_active", sa.Boolean()),
        sa.column("is_superadmin", sa.Boolean()),
    )
    op.execute(
        sa.update(admins)
        .where(admins.c.username == "admin")
        .values(is_active=True, is_superadmin=True)
    )


def downgrade() -> None:
    op.drop_index("ix_admins_username", table_name="admins")
    op.drop_column("admins", "is_superadmin")
    op.drop_column("admins", "is_active")
    op.drop_column("admins", "display_name")
