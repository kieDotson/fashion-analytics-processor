from kafka import KafkaConsumer
import json
import logging
from datetime import datetime
import time
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('fashion-analytics-consumer')

# Consumer configuration
KAFKA_BOOTSTRAP_SERVERS = 'fashion-kafka-kafka-bootstrap.fashion-analytics.svc:9092'
CONSUMER_GROUP_ID = 'fashion-analytics-processor'
AUTO_OFFSET_RESET = 'earliest'  # Start from the beginning if no committed offsets exist

# Topics to consume
TOPICS = {
    'orders': 'fashion-orders',
    'products': 'fashion-products',
    'trends': 'fashion-trends',
    'recommendations': 'fashion-recommendations'
}

def process_order(order_data):
    """Process order data from the fashion-orders topic"""
    try:
        logger.info(f"Processing order: {order_data['order_id']}")
        # Add your order processing logic here
        # For example:
        # - Calculate sales metrics
        # - Update customer purchase history
        # - Generate order analytics
        
        # Simulate processing time
        time.sleep(0.1)
        
        logger.info(f"Successfully processed order: {order_data['order_id']}")
    except Exception as e:
        logger.error(f"Error processing order {order_data.get('order_id', 'unknown')}: {str(e)}")

def process_product(product_data):
    """Process product data from the fashion-products topic"""
    try:
        logger.info(f"Processing product: {product_data['id']}")
        # Add your product processing logic here
        # For example:
        # - Update product inventory
        # - Track product popularity
        # - Calculate product metrics
        
        # Simulate processing time
        time.sleep(0.1)
        
        logger.info(f"Successfully processed product: {product_data['id']}")
    except Exception as e:
        logger.error(f"Error processing product {product_data.get('id', 'unknown')}: {str(e)}")

def create_consumer(topic, group_id_suffix, process_func):
    """Create a Kafka consumer for a specific topic"""
    full_group_id = f"{CONSUMER_GROUP_ID}-{group_id_suffix}"
    
    consumer = KafkaConsumer(
        topic,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        group_id=full_group_id,
        auto_offset_reset=AUTO_OFFSET_RESET,
        value_deserializer=lambda x: json.loads(x.decode('utf-8')),
        enable_auto_commit=True,
        auto_commit_interval_ms=5000,  # Commit offsets every 5 seconds
    )
    
    logger.info(f"Created consumer for topic {topic} with group ID {full_group_id}")
    return consumer

def consume_topic(topic, group_id_suffix, process_func):
    """Consume messages from a topic and process them"""
    consumer = create_consumer(topic, group_id_suffix, process_func)
    
    logger.info(f"Starting to consume from topic: {topic}")
    try:
        for message in consumer:
            try:
                data = message.value
                process_func(data)
                
                # Uncomment to see message metadata:
                # logger.debug(f"Consumed message: topic={message.topic}, partition={message.partition}, offset={message.offset}")
                
            except Exception as e:
                logger.error(f"Error processing message from {topic}: {str(e)}")
    except Exception as e:
        logger.error(f"Consumer error for topic {topic}: {str(e)}")
    finally:
        consumer.close()
        logger.info(f"Consumer for topic {topic} closed")

def start_consumer_threads():
    """Start consumer threads for all topics"""
    threads = []
    
    # Create thread for orders topic
    order_thread = threading.Thread(
        target=consume_topic,
        args=(TOPICS['orders'], 'orders', process_order),
        daemon=True
    )
    threads.append(order_thread)
    
    # Create thread for products topic
    product_thread = threading.Thread(
        target=consume_topic,
        args=(TOPICS['products'], 'products', process_product),
        daemon=True
    )
    threads.append(product_thread)
    
    # Start all threads
    for thread in threads:
        thread.start()
    
    logger.info(f"Started {len(threads)} consumer threads")
    return threads

def main():
    """Main function to start the Kafka consumers"""
    logger.info("Starting Fashion Analytics Kafka Consumer Application")
    
    threads = start_consumer_threads()
    
    # Keep the main thread running
    try:
        while True:
            time.sleep(1)
            # Check if all threads are still alive
            all_alive = all(thread.is_alive() for thread in threads)
            if not all_alive:
                logger.error("One or more consumer threads died. Exiting.")
                break
    except KeyboardInterrupt:
        logger.info("Received shutdown signal. Closing consumers...")
    
    logger.info("Fashion Analytics Kafka Consumer Application stopped")

if __name__ == "__main__":
    main()