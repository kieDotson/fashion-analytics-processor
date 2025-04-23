package flink;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.functions.ReduceFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.api.java.tuple.Tuple3;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.time.Duration;
import java.time.Instant;

public class FashionAnalyticsProcessor {
    
    private static final String BOOTSTRAP_SERVERS = "fashion-kafka-kafka-bootstrap.fashion-analytics.svc:9092";
    private static final String ORDER_TOPIC = "fashion-orders";
    private static final String PRODUCT_TOPIC = "fashion-products";
    private static final String TRENDS_TOPIC = "fashion-trends";
    private static final String RECOMMENDATIONS_TOPIC = "fashion-recommendations";
    
    private static final ObjectMapper objectMapper = new ObjectMapper();
    
    public static void main(String[] args) throws Exception {
        // Set up the streaming execution environment
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Configure Kafka order source
        KafkaSource<String> orderSource = KafkaSource.<String>builder()
                .setBootstrapServers(BOOTSTRAP_SERVERS)
                .setTopics(ORDER_TOPIC)
                .setGroupId("flink-fashion-analytics-processor")
                .setStartingOffsets(OffsetsInitializer.earliest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();
                
        // Configure Kafka product source
        KafkaSource<String> productSource = KafkaSource.<String>builder()
                .setBootstrapServers(BOOTSTRAP_SERVERS)
                .setTopics(PRODUCT_TOPIC)
                .setGroupId("flink-fashion-analytics-processor")
                .setStartingOffsets(OffsetsInitializer.earliest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();
        
        // Configure Kafka trend sink
        KafkaSink<String> trendSink = KafkaSink.<String>builder()
                .setBootstrapServers(BOOTSTRAP_SERVERS)
                .setRecordSerializer(
                    KafkaRecordSerializationSchema.<String>builder()
                        .setTopic(TRENDS_TOPIC)
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build()
                )
                .build();
                
        // Configure Kafka recommendation sink
        KafkaSink<String> recommendationSink = KafkaSink.<String>builder()
                .setBootstrapServers(BOOTSTRAP_SERVERS)
                .setRecordSerializer(
                    KafkaRecordSerializationSchema.<String>builder()
                        .setTopic(RECOMMENDATIONS_TOPIC)
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build()
                )
                .build();
        
        // Process order stream
        DataStream<String> orders = env.fromSource(
                orderSource,
                WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofSeconds(5)),
                "Kafka Orders Source");
                
        // Process product stream
        DataStream<String> products = env.fromSource(
                productSource,
                WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofSeconds(5)),
                "Kafka Products Source");
        
        // Parse orders to extract category information
        DataStream<Tuple3<String, String, Double>> categoryOrders = orders
            .map(new MapFunction<String, Tuple3<String, String, Double>>() {
                @Override
                public Tuple3<String, String, Double> map(String orderJson) throws Exception {
                    JsonNode order = objectMapper.readTree(orderJson);
                    String timestamp = order.get("timestamp").asText();
                    String category = order.get("category").asText();
                    Double price = order.get("price").asDouble();
                    return new Tuple3<>(timestamp, category, price);
                }
            })
            .returns(Types.TUPLE(Types.STRING, Types.STRING, Types.DOUBLE));
            
        // Compute trending categories based on order volume within time windows
        DataStream<String> trends = categoryOrders
            // Group by category
            .keyBy(value -> value.f1) 
            // Use 10-minute tumbling windows
            .window(TumblingProcessingTimeWindows.of(Time.minutes(10)))
            // Count orders and sum prices per category in each window
            .reduce(new ReduceFunction<Tuple3<String, String, Double>>() {
                @Override
                public Tuple3<String, String, Double> reduce(
                        Tuple3<String, String, Double> value1, 
                        Tuple3<String, String, Double> value2) {
                    // Keep category name and sum up the prices
                    return new Tuple3<>(value1.f0, value1.f1, value1.f2 + value2.f2);
                }
            })
            // Format as JSON
            .map(new MapFunction<Tuple3<String, String, Double>, String>() {
                @Override
                public String map(Tuple3<String, String, Double> value) throws Exception {
                    ObjectNode trendNode = objectMapper.createObjectNode();
                    trendNode.put("timestamp", Instant.now().toString());
                    trendNode.put("category", value.f1);
                    trendNode.put("total_sales", value.f2);
                    trendNode.put("trend_window_minutes", 10);
                    return objectMapper.writeValueAsString(trendNode);
                }
            });
        
        // Generate simple product recommendations based on trending categories
        DataStream<String> recommendations = trends
            .map(new MapFunction<String, String>() {
                @Override
                public String map(String trendJson) throws Exception {
                    JsonNode trend = objectMapper.readTree(trendJson);
                    String category = trend.get("category").asText();
                    
                    ObjectNode recommendationNode = objectMapper.createObjectNode();
                    recommendationNode.put("timestamp", Instant.now().toString());
                    recommendationNode.put("category", category);
                    recommendationNode.put("recommendation_reason", "Trending category");
                    recommendationNode.put("confidence_score", 0.85);
                    
                    return objectMapper.writeValueAsString(recommendationNode);
                }
            });
        
        // Send processed data to output Kafka topics
        trends.sinkTo(trendSink);
        recommendations.sinkTo(recommendationSink);
        
        // Execute the Flink job
        env.execute("Fashion Analytics Processor");
    }
}
