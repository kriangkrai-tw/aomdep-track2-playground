package com.example.todoservice.dto;

import jakarta.validation.constraints.Size;

public record UpdateTodoRequest(
        @Size(max = 255, message = "Title must not exceed 255 characters")
        String title,

        String description,

        Boolean completed
) {}
