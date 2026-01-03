package com.training.containers;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;

import jakarta.annotation.PostConstruct;

@SpringBootApplication
@EnableScheduling
public class ContainersApplication {

	private static final Logger log = LoggerFactory.getLogger(ContainersApplication.class);

	public static void main(String[] args) {
		SpringApplication.run(ContainersApplication.class, args);
	}

    /**
     * It executes once the application has started. After spring context is ready.
     */
    @PostConstruct
    public void initialGreeting() {
        log.info("🚀 Spring Boot application started successfully, hello there!");
    }

    /**
     * It executes every minute to show that the application is still running.
     */
    @Scheduled(fixedRate = 60_000)
    public void stillAlive() {
        log.info("💓 I am alive and still running...");
    }

}
