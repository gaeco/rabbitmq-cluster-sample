package com.example.rabbitmqsample;

import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

/**
 * Unit test — no broker required. Verifies the producer publishes to the
 * configured exchange/routing key with the expected payload.
 */
class MessageProducerTest {

    @Test
    void sendPublishesToConfiguredExchangeAndRoutingKey() {
        RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
        RabbitProperties properties = new RabbitProperties("sample.exchange", "sample.queue", "sample.key");
        MessageProducer producer = new MessageProducer(rabbitTemplate, properties);

        SampleMessage sent = producer.send("hello");

        assertThat(sent.content()).isEqualTo("hello");
        verify(rabbitTemplate).convertAndSend(eq("sample.exchange"), eq("sample.key"), eq(sent));
    }
}
