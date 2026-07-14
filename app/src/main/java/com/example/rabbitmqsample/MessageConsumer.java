package com.example.rabbitmqsample;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * Consumes messages from the sample queue and logs them.
 */
@Component
public class MessageConsumer {

    private static final Logger log = LoggerFactory.getLogger(MessageConsumer.class);

    @RabbitListener(queues = "${app.rabbitmq.queue}")
    public void receive(SampleMessage message) {
        log.info("Received message: content='{}', sentAtEpochMs={}",
                message.content(), message.sentAtEpochMs());
    }
}
