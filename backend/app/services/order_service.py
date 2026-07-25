import logging

from app.models import Order, OrderHistory

logger = logging.getLogger(__name__)

ALLOWED_TRANSITIONS = {
    "available": ["taken", "cancelled"],
    "taken": ["in_transit", "cancelled"],
    "in_transit": ["delivered", "cancelled"],
    "delivered": [],
    "cancelled": [],
}


def can_transition(current: str, next: str) -> bool:
    return next in ALLOWED_TRANSITIONS.get(current, [])


async def transition_order(order: Order, new_status: str, db):
    if not can_transition(order.status, new_status):
        logger.warning(
            "Invalid transition: order %d from %s to %s",
            order.id, order.status, new_status,
        )
        raise ValueError(
            f"Invalid transition from {order.status} to {new_status}"
        )
    order.status = new_status
    if new_status == "cancelled":
        order.courier_id = None

    history = OrderHistory(order_id=order.id, status=new_status)
    db.add(history)
    await db.commit()