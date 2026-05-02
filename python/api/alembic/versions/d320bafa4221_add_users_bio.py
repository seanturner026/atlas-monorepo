"""add users bio

Revision ID: d320bafa4221
Revises: a393d4108f45
Create Date: 2026-05-02 17:24:39.283765

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd320bafa4221'
down_revision: Union[str, Sequence[str], None] = 'a393d4108f45'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('users', sa.Column('bio', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('users', 'bio')
