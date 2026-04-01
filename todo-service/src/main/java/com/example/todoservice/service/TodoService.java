package com.example.todoservice.service;

import com.example.todoservice.dto.CreateTodoRequest;
import com.example.todoservice.dto.TodoResponse;
import com.example.todoservice.dto.UpdateTodoRequest;
import com.example.todoservice.exception.TodoNotFoundException;
import com.example.todoservice.model.Todo;
import com.example.todoservice.repository.TodoRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class TodoService {

    private final TodoRepository todoRepository;

    public List<TodoResponse> findAll(Optional<Boolean> completed) {
        List<Todo> todos = completed
                .map(todoRepository::findByCompleted)
                .orElseGet(todoRepository::findAll);
        return todos.stream().map(TodoResponse::from).toList();
    }

    public TodoResponse findById(UUID id) {
        return todoRepository.findById(id)
                .map(TodoResponse::from)
                .orElseThrow(() -> new TodoNotFoundException(id));
    }

    @Transactional
    public TodoResponse create(CreateTodoRequest request) {
        Todo todo = new Todo(request.title(), request.description());
        return TodoResponse.from(todoRepository.save(todo));
    }

    @Transactional
    public TodoResponse update(UUID id, UpdateTodoRequest request) {
        Todo todo = todoRepository.findById(id)
                .orElseThrow(() -> new TodoNotFoundException(id));

        if (request.title() != null && !request.title().isBlank()) {
            todo.setTitle(request.title());
        }
        if (request.description() != null) {
            todo.setDescription(request.description());
        }
        if (request.completed() != null) {
            todo.setCompleted(request.completed());
        }

        return TodoResponse.from(todoRepository.save(todo));
    }

    @Transactional
    public TodoResponse complete(UUID id) {
        Todo todo = todoRepository.findById(id)
                .orElseThrow(() -> new TodoNotFoundException(id));
        todo.setCompleted(true);
        return TodoResponse.from(todoRepository.save(todo));
    }

    @Transactional
    public void delete(UUID id) {
        if (!todoRepository.existsById(id)) {
            throw new TodoNotFoundException(id);
        }
        todoRepository.deleteById(id);
    }
}
