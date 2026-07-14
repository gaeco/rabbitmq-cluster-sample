package com.example.rabbitmqsample;

/**
 * Payload exchanged over RabbitMQ. Serialized as JSON.
 */
public record SampleMessage(String content, long sentAtEpochMs) {
}
