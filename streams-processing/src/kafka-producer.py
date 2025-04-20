from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
import random
import uuid
from datetime import datetime
from faker import Faker
import asyncio
import time
from kafka import KafkaProducer
import json

app = FastAPI()
fake = Faker()

# Kafka Producer Setup
producer = KafkaProducer(
    bootstrap_servers='fashion-kafka-kafka-bootstrap.fashion-analytics.svc:9092',  # Update with your Kafka broker's address
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),  # Serialize JSON messages
    api_version=(3, 9, 0)
)

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
        color=fake.color(),
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
        customer_name=fake.name(),
        customer_id=str(uuid.uuid4()),
        customer_state=fake.state()
    )
    return order

# Send message to Kafka topic
def send_to_kafka(topic: str, message: dict):
    producer.send(topic, message)
    producer.flush()  # Ensure message is sent immediately

# Function to simulate the background task
async def generate_orders_and_products():
    while True:
        # Generate and send product and order every 10 seconds
        product = generate_product()
        order = generate_order()

        # Print generated product and order (for testing purposes)
        print(f"Generated Product: {product}")
        print(f"Generated Order: {order}")

        # Send to Kafka topics
        send_to_kafka('fashion-products', product.dict())  # Send product data to 'fashion-products' topic
        send_to_kafka('fashion-orders', order.dict())      # Send order data to 'fashion-orders' topic

        await asyncio.sleep(10)  # Wait for 10 seconds

# FastAPI route to start the background task
@app.on_event("startup")
async def startup_event():
    # Start the background task to generate orders and products
    asyncio.create_task(generate_orders_and_products())

@app.get("/generate_order", response_model=Order)
def get_order():
    return generate_order()

@app.get("/generate_product", response_model=Product)
def get_product():
    return generate_product()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000, log_level="info")
