package com.example.rabbitmqsample;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Trigger a publish for manual testing:
 *   curl -X POST 'http://localhost:8080/messages?content=hello'
 * The consumer logs whatever is delivered by the cluster.
 */
@RestController
public class MessageController {

    private final MessageProducer producer;

    public MessageController(MessageProducer producer) {
        this.producer = producer;
    }

    @PostMapping("/messages")
    public SampleMessage publish(@RequestParam(defaultValue = "hello from spring boot") String content) {
        return producer.send(content);
    }
}
