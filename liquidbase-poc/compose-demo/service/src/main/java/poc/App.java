package poc;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@SpringBootApplication
@RestController
public class App {

    private final JdbcTemplate jdbc;

    public App(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public static void main(String[] args) {
        SpringApplication.run(App.class, args);
    }

    @GetMapping("/users")
    public List<Map<String, Object>> users() {
        return jdbc.queryForList("SELECT id, email, status, created_at FROM users ORDER BY id");
    }

    @GetMapping("/changelog")
    public List<Map<String, Object>> changelog() {
        return jdbc.queryForList("SELECT id, author, filename, dateexecuted, orderexecuted, exectype FROM DATABASECHANGELOG ORDER BY orderexecuted");
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Integer one = jdbc.queryForObject("SELECT 1", Integer.class);
        return Map.of("db", one != null && one == 1 ? "up" : "down");
    }
}
