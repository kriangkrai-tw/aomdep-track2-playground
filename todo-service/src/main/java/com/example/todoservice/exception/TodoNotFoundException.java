package com.example.todoservice.exception;

import java.util.UUID;

public class TodoNotFoundException extends RuntimeException {
    public TodoNotFoundException(UUID id) {
        super("Todo not found with id: " + id);
    }
}
