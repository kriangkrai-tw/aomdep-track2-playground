package com.example.userservice.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/users")
public class UserController {

    @GetMapping("/{id}")
    public ResponseEntity<?> getUser(@PathVariable int id) {
        if (id == 1) {
            return ResponseEntity.ok(Map.of(
                    "id", 1,
                    "name", "Alice",
                    "email", "alice@example.com"
            ));
        }
        else if (id == 2) {
            return ResponseEntity.ok(Map.of(
                    "id", 2,
                    "name", "Cho",
                    "email", "cho@example.com"
            ));
        }
        
        return ResponseEntity.notFound().build();
    }
}
