package com.example.todoservice.controller;

import com.example.todoservice.dto.CreateTodoRequest;
import com.example.todoservice.dto.TodoResponse;
import com.example.todoservice.dto.UpdateTodoRequest;
import com.example.todoservice.service.TodoService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@RestController
@RequestMapping("/api/todos")
@RequiredArgsConstructor
public class TodoController {

    private final TodoService todoService;

    @GetMapping
    public List<TodoResponse> getAll(@RequestParam Optional<Boolean> completed) {
        return todoService.findAll(completed);
    }

    @GetMapping("/{id}")
    public TodoResponse getById(@PathVariable UUID id) {
        return todoService.findById(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TodoResponse create(@Valid @RequestBody CreateTodoRequest request) {
        return todoService.create(request);
    }

    @PutMapping("/{id}")
    public TodoResponse update(@PathVariable UUID id, @Valid @RequestBody UpdateTodoRequest request) {
        return todoService.update(id, request);
    }

    @PatchMapping("/{id}/complete")
    public TodoResponse complete(@PathVariable UUID id) {
        return todoService.complete(id);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public ResponseEntity<Void> delete(@PathVariable UUID id) {
        todoService.delete(id);
        return ResponseEntity.noContent().build();
    }
}
