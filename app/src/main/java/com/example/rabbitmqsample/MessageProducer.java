package com.example.rabbitmqsample;

import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;

/**
 * Publishes messages to the topic exchange.
 */
@Component
public class MessageProducer {

    private final RabbitTemplate rabbitTemplate;
    private final RabbitProperties properties;

    public MessageProducer(RabbitTemplate rabbitTemplate, RabbitProperties properties) {
        this.rabbitTemplate = rabbitTemplate;
        this.properties = properties;
    }

    public SampleMessage send(String content) {
        SampleMessage message = new SampleMessage(content, System.currentTimeMillis());
        rabbitTemplate.convertAndSend(properties.exchange(), properties.routingKey(), message);
        return message;
    }
}
