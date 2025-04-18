from fastapi import FastAPI
from pydantic import BaseModel
import random
import uuid
from datetime import datetime
from faker import Faker
import time

app = FastAPI()
fake = Faker()

# Define Pydantic models for validation
class Product(BaseModel):
    id: str
    name: str
    category: str
    price: float
    color: str

class Order(BaseModel):
    order_id: str
    product_id: str
    product_name: str
    category: str
    price: float
    timestamp: str
    customer_id: str
    customer_name: str
    customer_state: str

# Generate a random product
def generate_product() -> Product:
    return Product(
        id=str(uuid.uuid4()),
        name=fake.word().capitalize() + " " + fake.word().capitalize(),
        category=random.choice(["Dresses", "Denim", "Shoes", "Accessories", "Tops", "Bottoms", "Jackets"]),
        color = fake.color.human()
        price=round(random.uniform(20, 200), 2)
    )

# Generate a random order
def generate_order() -> Order:
    product = generate_product()
    order = Order(
        order_id=str(uuid.uuid4()),
        product_id=product.id,
        product_name=product.name,
        category=product.category,
        price=product.price,
        timestamp=datetime.utcnow().isoformat(),
        customer_name=fake.person.fullName(),
        customer_id=str(uuid.uuid4()),
        customer_state=fake.location.state()
    )
    return order

@app.get("/generate_order", response_model=Order)
def get_order():
    return generate_order()

@app.get("/generate_product", response_model=Product)
def get_product():
    return generate_product()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000, log_level="info")
