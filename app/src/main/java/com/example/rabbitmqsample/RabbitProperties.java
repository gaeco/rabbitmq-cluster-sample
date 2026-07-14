package com.example.rabbitmqsample;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Binds the {@code app.rabbitmq.*} settings from application.yml.
 */
@ConfigurationProperties(prefix = "app.rabbitmq")
public record RabbitProperties(String exchange, String queue, String routingKey) {
}
