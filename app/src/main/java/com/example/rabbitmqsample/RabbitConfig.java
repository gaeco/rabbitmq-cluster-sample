package com.example.rabbitmqsample;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Declares the exchange/queue/binding and wires JSON message conversion.
 * The queue is durable so it survives node restarts; on a cluster its
 * definition is replicated to every node via the shared schema.
 */
@Configuration
@EnableConfigurationProperties(RabbitProperties.class)
public class RabbitConfig {

    private final RabbitProperties properties;

    public RabbitConfig(RabbitProperties properties) {
        this.properties = properties;
    }

    @Bean
    public TopicExchange exchange() {
        return new TopicExchange(properties.exchange(), true, false);
    }

    @Bean
    public Queue queue() {
        return QueueBuilder.durable(properties.queue()).build();
    }

    @Bean
    public Binding binding(Queue queue, TopicExchange exchange) {
        return BindingBuilder.bind(queue).to(exchange).with(properties.routingKey());
    }

    @Bean
    public MessageConverter jsonMessageConverter(ObjectMapper objectMapper) {
        return new Jackson2JsonMessageConverter(objectMapper);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory, MessageConverter converter) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(converter);
        return template;
    }
}
