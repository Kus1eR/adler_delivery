"""unique courier location

Revision ID: f5a9c81d2047
Revises: 8c7b7e0d6a21
Create Date: 2026-07-25
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f5a9c81d2047"
down_revision: Union[str, None] = "8c7b7e0d6a21"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        sa.text(
            "DELETE FROM courier_locations AS old "
            "WHERE EXISTS ("
            "SELECT 1 FROM courier_locations AS newer "
            "WHERE newer.courier_id = old.courier_id "
            "AND (newer.updated_at > old.updated_at "
            "OR (newer.updated_at = old.updated_at AND newer.id > old.id))"
            ")"
        )
    )
    with op.batch_alter_table("courier_locations") as batch_op:
        batch_op.create_unique_constraint(
            "uq_courier_locations_courier_id", ["courier_id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("courier_locations") as batch_op:
        batch_op.drop_constraint(
            "uq_courier_locations_courier_id", type_="unique"
        )
