package com.example.todoservice.dto;

import com.example.todoservice.model.Todo;

import java.time.LocalDateTime;
import java.util.UUID;

public record TodoResponse(
        UUID id,
        String title,
        String description,
        boolean completed,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
    public static TodoResponse from(Todo todo) {
        return new TodoResponse(
                todo.getId(),
                todo.getTitle(),
                todo.getDescription(),
                todo.isCompleted(),
                todo.getCreatedAt(),
                todo.getUpdatedAt()
        );
    }
}
