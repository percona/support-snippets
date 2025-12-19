import java.io.*;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * A simple Java application for load testing MySQL databases.
 * Version 0.0.2
 * 
 * Usage: java MySQLTester <host> <user> <password> <port> <poolSize> <threadCount> <queriesInput> [<duration> [<executions> [<pause>]]]
 * 
 * - host: MySQL server host (e.g., 192.168.56.16)
 * - user: MySQL username
 * - password: MySQL password
 * - port: MySQL port (e.g., 6446)
 * - poolSize: Number of total connections to open
 * - threadCount: Number of concurrent threads executing queries
 * - queriesInput: Either a file path containing SQL queries (one per line), "-" to read from stdin,
 *                 or a semicolon-separated string of SQL queries
 * - duration: Duration of each test run in seconds (default: 30)
 * - executions: Number of test runs (default: 1)
 * - pause: Pause between test runs in seconds (default: 0)
 * 
 * Requirements:
 * - MySQL Connector/J JDBC driver (mysql-connector-j-*.jar) in classpath.
 *   Download from: https://dev.mysql.com/downloads/connector/j/
 *   Run example: java -cp .:/usr/share/java/mysql-connector-j-8.2.0.jar MySQLTester 192.168.1.100 appuser 'pass' 3306 100 8 queries.sql 30 10 5
 * 
 * Behavior:
 * - Creates a connection pool of size <poolSize>, kept open across all test runs and pauses.
 * - Runs <executions> tests, each lasting <duration> seconds with <threadCount> threads executing random queries.
 * - Pauses for <pause> seconds between tests.
 * - Prints total queries executed, runtime, and queries per second (QPS) per test, plus overall totals.
 * - Supports DML and SELECT queries (results discarded for performance).
 * - Connects without specifying a database; include "USE database;" in queries if needed.
 * - URL options: ?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
 * 
 * Note: Uses only standard Java libraries (java.sql.*, java.util.concurrent.*) and no third-party frameworks.
 */
public class MySQLTester {
    private static final int DEFAULT_DURATION_SECONDS = 30;
    private static final int DEFAULT_EXECUTIONS = 1;
    private static final int DEFAULT_PAUSE_SECONDS = 0;
    private static final String JDBC_DRIVER = "com.mysql.cj.jdbc.Driver";
    private static final String URL_TEMPLATE = "jdbc:mysql://%s:%d?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC";

    public static void main(String[] args) {
        if (args.length < 7 || args.length > 10) {
            System.err.println("Usage: java MySQLTester <host> <user> <password> <port> <poolSize> <threadCount> <queriesInput> [<duration> [<executions> [<pause>]]]");
            System.exit(1);
        }

        String host = args[0];
        String user = args[1];
        String password = args[2];
        int port;
        int poolSize;
        int threadCount;
        String queriesInput = args[6];
        int duration = DEFAULT_DURATION_SECONDS;
        int executions = DEFAULT_EXECUTIONS;
        int pause = DEFAULT_PAUSE_SECONDS;

        try {
            port = Integer.parseInt(args[3]);
            poolSize = Integer.parseInt(args[4]);
            threadCount = Integer.parseInt(args[5]);
            if (args.length >= 8) {
                duration = Integer.parseInt(args[7]);
            }
            if (args.length >= 9) {
                executions = Integer.parseInt(args[8]);
            }
            if (args.length == 10) {
                pause = Integer.parseInt(args[9]);
            }
        } catch (NumberFormatException e) {
            System.err.println("Invalid numeric parameter: " + e.getMessage());
            System.exit(1);
            return;
        }

        if (poolSize <= 0 || threadCount <= 0 || duration <= 0 || executions <= 0 || pause < 0) {
            System.err.println("poolSize, threadCount, duration, and executions must be positive; pause must be non-negative.");
            System.exit(1);
            return;
        }

        // Load JDBC driver
        try {
            Class.forName(JDBC_DRIVER);
        } catch (ClassNotFoundException e) {
            System.err.println("MySQL JDBC Driver (" + JDBC_DRIVER + ") not found in classpath.");
            System.exit(1);
            return;
        }

        String url = String.format(URL_TEMPLATE, host, port);

        // Read queries
        List<String> queries = readQueries(queriesInput);
        if (queries.isEmpty()) {
            System.err.println("No valid queries provided.");
            System.exit(1);
            return;
        }
        System.out.println("Loaded " + queries.size() + " queries.");

        // Create connection pool
        SimpleConnectionPool pool;
        try {
            pool = new SimpleConnectionPool(poolSize, url, user, password);
        } catch (SQLException e) {
            System.err.println("Failed to create connection pool: " + e.getMessage());
            System.exit(1);
            return;
        }

        // Run test executions
        long overallStartTime = System.currentTimeMillis();
        int overallQueries = 0;
        List<Double> runTimes = new ArrayList<>();
        List<Integer> runQueries = new ArrayList<>();
        Random random = new Random();

        for (int run = 1; run <= executions; run++) {
            System.out.printf("Starting test run %d of %d...%n", run, executions);
            final int finalDuration = duration; // Ensure duration is effectively final for lambda

            // Execute concurrent queries
            AtomicInteger totalExecuted = new AtomicInteger(0);
            ExecutorService executor = Executors.newFixedThreadPool(threadCount);
            CountDownLatch latch = new CountDownLatch(threadCount);
            long startTime = System.currentTimeMillis();

            for (int i = 0; i < threadCount; i++) {
                executor.submit(() -> {
                    try {
                        long threadStart = System.currentTimeMillis();
                        int count = 0;
                        while (System.currentTimeMillis() - threadStart < finalDuration * 1000L) {
                            String query = queries.get(random.nextInt(queries.size()));
                            try {
                                Connection conn = pool.borrow();
                                try (PreparedStatement stmt = conn.prepareStatement(query)) {
                                    boolean hasResultSet = stmt.execute();
                                    if (hasResultSet) {
                                        try (ResultSet rs = stmt.getResultSet()) {
                                            while (rs.next()) {
                                                // Discard results for performance testing
                                            }
                                        }
                                    }
                                    count++;
                                } catch (SQLException e) {
                                    System.err.println("Query execution error: " + e.getMessage());
                                    // Continue to next query
                                } finally {
                                    pool.release(conn);
                                }
                            } catch (InterruptedException e) {
                                Thread.currentThread().interrupt();
                                System.err.println("Thread interrupted during borrow: " + e.getMessage());
                                break;
                            }
                        }
                        totalExecuted.addAndGet(count);
                    } finally {
                        latch.countDown();
                    }
                });
            }

            try {
                latch.await();
            } catch (InterruptedException e) {
                System.err.println("Test interrupted.");
                Thread.currentThread().interrupt();
            }

            long endTime = System.currentTimeMillis();
            executor.shutdownNow();

            double runtimeSeconds = (endTime - startTime) / 1000.0;
            int totalQueries = totalExecuted.get();
            double qps = totalQueries / runtimeSeconds;

            System.out.printf("Test run %d completed in %.2f seconds.%n", run, runtimeSeconds);
            System.out.printf("Test run %d queries executed: %d%n", run, totalQueries);
            System.out.printf("Test run %d throughput: %.2f QPS%n", run, qps);

            overallQueries += totalQueries;
            runTimes.add(runtimeSeconds);
            runQueries.add(totalQueries);

            // Pause between runs (if not the last run)
            if (run < executions && pause > 0) {
                System.out.printf("Pausing for %d seconds...%n", pause);
                try {
                    Thread.sleep(pause * 1000L);
                } catch (InterruptedException e) {
                    System.err.println("Pause interrupted: " + e.getMessage());
                    Thread.currentThread().interrupt();
                }
            }
        }

        // Close pool
        pool.close();

        // Print overall statistics
        double totalRuntime = (System.currentTimeMillis() - overallStartTime) / 1000.0;
        double averageQPS = overallQueries / runTimes.stream().mapToDouble(Double::doubleValue).sum();
        System.out.printf("%nOverall Statistics:%n");
        System.out.printf("Total test runs: %d%n", executions);
        System.out.printf("Total queries executed: %d%n", overallQueries);
        System.out.printf("Total runtime (including pauses): %.2f seconds%n", totalRuntime);
        System.out.printf("Average throughput: %.2f QPS%n", averageQPS);
    }

    private static List<String> readQueries(String input) {
        List<String> queries = new ArrayList<>();
        if ("-".equals(input)) {
            // Read from stdin
            try (BufferedReader br = new BufferedReader(new InputStreamReader(System.in))) {
                String line;
                while ((line = br.readLine()) != null) {
                    String trimmed = line.trim();
                    if (!trimmed.isEmpty()) {
                        queries.add(trimmed);
                    }
                }
            } catch (IOException e) {
                System.err.println("Error reading from stdin: " + e.getMessage());
            }
        } else {
            File file = new File(input);
            if (file.exists() && file.isFile()) {
                // Read from file (one query per line)
                try (BufferedReader br = new BufferedReader(new FileReader(file))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        String trimmed = line.trim();
                        if (!trimmed.isEmpty()) {
                            queries.add(trimmed);
                        }
                    }
                } catch (IOException e) {
                    System.err.println("Error reading file '" + input + "': " + e.getMessage());
                }
            } else {
                // Treat as semicolon-separated string
                String[] parts = input.split(";");
                for (String part : parts) {
                    String trimmed = part.trim();
                    if (!trimmed.isEmpty()) {
                        queries.add(trimmed);
                    }
                }
            }
        }
        return queries;
    }

    // Simple blocking connection pool implementation
    private static class SimpleConnectionPool {
        private final BlockingQueue<Connection> pool;
        private final String url;
        private final String user;
        private final String password;

        public SimpleConnectionPool(int size, String url, String user, String password) throws SQLException {
            this.url = url;
            this.user = user;
            this.password = password;
            this.pool = new LinkedBlockingQueue<>(size);
            for (int i = 0; i < size; i++) {
                Connection conn = DriverManager.getConnection(url, user, password);
                pool.offer(conn);
            }
        }

        public Connection borrow() throws InterruptedException {
            return pool.take();
        }

        public void release(Connection conn) {
            pool.offer(conn);
        }

        public void close() {
            Connection conn;
            while ((conn = pool.poll()) != null) {
                try {
                    conn.close();
                } catch (SQLException e) {
                    System.err.println("Error closing connection: " + e.getMessage());
                }
            }
        }
    }
}
